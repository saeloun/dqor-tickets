package `in`.dqor.staff

import `in`.dqor.staff.nativeapi.*
import java.io.IOException
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class NativeStaffClientTest {
    private val now=Instant.parse("2026-10-02T12:00:00Z")
    private val token="synthetic_test_token_not_a_real_credential_12345"
    private val scope="""{"event":"dqor-2026","event_dates":["2026-10-08"],"capabilities":["tickets:read","checkins:write"],"expires_at":"2026-10-02T20:00:00Z","max_batch_size":50}"""
    private val ticket="""{"id":101,"attendee_name":"Grace Shah","attendee_email":"grace@example.test","ticket_type":"Conference","order_code":"TEST-1","eligible":true,"checked_in_at":null}"""
    private class MemoryStore : CredentialStore {
        var value: StoredCredential?=null
        override suspend fun read()=value
        override suspend fun write(value: StoredCredential) {this.value=value}
        override suspend fun clear() {value=null}
    }
    private class FakeTransport : NativeTransport {
        val requests=mutableListOf<NativeRequest>()
        val responses=ArrayDeque<NativeResponse>()
        var fail=false
        override suspend fun execute(request: NativeRequest): NativeResponse {requests+=request; if(fail) throw IOException("synthetic transport failure"); return responses.removeFirst()}
    }
    private inner class Fixture(enabled: Boolean=true) {
        val store=MemoryStore(); val transport=FakeTransport()
        var clock=now
        val client=NativeStaffClient(NativeConfig(enabled,"https://staging.example.test"),transport,store) {clock}
        suspend fun login() {transport.responses+=NativeResponse(201,JSONObject(scope).put("access_token",token).put("token_type","Bearer").toString()); client.signIn("staff@example.test","test-password".toCharArray())}
    }
    private suspend fun failure(kind: NativeFailure.Kind, action: suspend () -> Unit) {try {action(); fail("Expected $kind")} catch(e: NativeFailure) {assertEquals(kind,e.kind)}}
    @Test fun `disabled config makes no request and wipes password`() = runBlocking {
        val f=Fixture(false); val password="synthetic".toCharArray()
        failure(NativeFailure.Kind.DISABLED) {f.client.signIn("staff",password)}
        assertTrue(password.all {it=='\u0000'}); assertTrue(f.transport.requests.isEmpty())
    }
    @Test fun `real transport remains compile time disabled`() {
        try {ApprovedNativeTransport(NativeConfig(true,"https://staging.example.test")); fail("Must remain disabled")} catch(_: IllegalStateException) {}
    }
    @Test fun `origin rejects cleartext credentials and paths`() {
        for(origin in listOf("http://example.test","https://user@example.test","https://example.test/path","https://example.test?x=1","https://example.test#secret")) {
            try {NativeConfig(true,origin); fail(origin)} catch(_: IllegalArgumentException) {}
        }
    }
    @Test fun `sign in stores token but no password and request diagnostics redact`() = runBlocking {
        val f=Fixture(); f.login()
        assertEquals(token,f.store.value!!.token)
        assertFalse(f.store.value.toString().contains(token))
        assertFalse(f.transport.requests.first().toString().contains("test-password"))
        assertNull(f.transport.requests.first().bearer)
    }
    @Test fun `resolve uses read only route and does not confirm`() = runBlocking {
        val f=Fixture(); f.login(); f.transport.responses+=NativeResponse(200,"""{"state":"resolved","date":"2026-10-08","ticket":$ticket}""")
        val preview=f.client.resolve("dqor-2026","2026-10-08","test-qr-secret")
        assertTrue(preview.ticket.eligible)
        val request=f.transport.requests.last()
        assertEquals("/api/staff/checkins/resolve",request.path); assertEquals(token,request.bearer)
        assertFalse(request.path.contains("test-qr-secret")); assertTrue(request.body!!.contains("test-qr-secret"))
        assertEquals(2,f.transport.requests.size)
    }
    @Test fun `confirmation preserves partial outcomes duplicate string ids and ordered result identity`() = runBlocking {
        val f=Fixture(); f.login()
        f.transport.responses+=NativeResponse(200,"""{"date":"2026-10-08","results":[{"ticket_id":"101","attendee":"Grace Shah","state":"success","message":"Checked in","checked_in_at":"2026-10-08T10:00:00Z"},{"ticket_id":"102","state":"warning","message":"Already checked in"},{"ticket_id":"999","state":"error","message":"Not found"}]}""")
        val result=f.client.confirm("dqor-2026","2026-10-08",listOf(101,101,102,999),true)
        assertEquals(listOf(NativeState.SUCCESS,NativeState.WARNING,NativeState.ERROR),result.results.map {it.state})
        assertEquals(3,JSONObject(f.transport.requests.last().body!!).getJSONArray("ticket_ids").length())
    }
    @Test fun `invalid and unconfirmed batches never hit transport`() = runBlocking {
        val f=Fixture(); f.login()
        for(ids in listOf(emptyList(),listOf(-1L),(1L..51L).toList())) {try {f.client.confirm("dqor-2026","2026-10-08",ids,true); fail()} catch(_: IllegalArgumentException) {}}
        try {f.client.confirm("dqor-2026","2026-10-08",listOf(101),false); fail()} catch(_: IllegalArgumentException) {}
        assertEquals(1,f.transport.requests.size)
    }
    @Test fun `expiry clears local credential without network`() = runBlocking {
        val f=Fixture(); f.login(); f.clock=now.plusSeconds(9*3600)
        failure(NativeFailure.Kind.SIGN_IN) {f.client.lookup("dqor-2026","2026-10-08","")}
        assertNull(f.store.value); assertEquals(1,f.transport.requests.size)
    }
    @Test fun `revoked server session clears local token`() = runBlocking {
        val f=Fixture(); f.login(); f.transport.responses+=NativeResponse(401)
        failure(NativeFailure.Kind.SIGN_IN) {f.client.lookup("dqor-2026","2026-10-08","")}
        assertNull(f.store.value)
    }
    @Test fun `restore verifies scope before any attendance operation`() = runBlocking {
        val f=Fixture(); f.login()
        val restored=NativeStaffClient(NativeConfig(true,"https://staging.example.test"),f.transport,f.store) {now}
        failure(NativeFailure.Kind.SIGN_IN) {restored.lookup("dqor-2026","2026-10-08","")}
        f.transport.responses+=NativeResponse(200,scope)
        assertEquals("dqor-2026",restored.restoreSession().event)
        assertEquals("GET",f.transport.requests.last().method)
    }
    @Test fun `wrong origin event and date fail closed`() = runBlocking {
        val f=Fixture(); f.login()
        failure(NativeFailure.Kind.DENIED) {f.client.lookup("other","2026-10-08","")}
        failure(NativeFailure.Kind.DENIED) {f.client.lookup("dqor-2026","2026-10-09","")}
        val other=NativeStaffClient(NativeConfig(true,"https://other.example.test"),f.transport,f.store) {now}
        failure(NativeFailure.Kind.SIGN_IN) {other.restoreSession()}; assertNull(f.store.value)
    }
    @Test fun `reduced server capabilities deny confirmation`() = runBlocking {
        val f=Fixture(); f.login(); f.transport.responses+=NativeResponse(200,scope.replace(",\"checkins:write\"","")); f.client.restoreSession()
        failure(NativeFailure.Kind.DENIED) {f.client.confirm("dqor-2026","2026-10-08",listOf(101),true)}
        assertEquals(2,f.transport.requests.size)
    }
    @Test fun `logout clears token even when server revocation is unconfirmed`() = runBlocking {
        val f=Fixture(); f.login(); f.transport.fail=true
        assertEquals(LogoutResult.LOCAL_ONLY,f.client.logout()); assertNull(f.store.value)
    }
    @Test fun `confirmed logout requires 204`() = runBlocking {
        val f=Fixture(); f.login(); f.transport.responses+=NativeResponse(204)
        assertEquals(LogoutResult.REVOKED,f.client.logout()); assertNull(f.store.value)
        assertEquals("DELETE",f.transport.requests.last().method)
    }
    @Test fun `timeout does not queue or retry mutation`() = runBlocking {
        val f=Fixture(); f.login(); f.transport.fail=true
        failure(NativeFailure.Kind.NOT_CONFIRMED) {f.client.confirm("dqor-2026","2026-10-08",listOf(101),true)}
        assertEquals(2,f.transport.requests.size)
    }
    @Test fun `malformed 200 and mismatched IDs never imply success`() = runBlocking {
        val f=Fixture(); f.login()
        for(body in listOf("{}","""{"date":"2026-10-08","results":[{"ticket_id":"999","state":"success","message":"OK"}]}""","""{"date":"2026-10-09","results":[]}""")) {
            f.transport.responses+=NativeResponse(200,body)
            failure(NativeFailure.Kind.SCHEMA) {f.client.confirm("dqor-2026","2026-10-08",listOf(101),true)}
        }
    }
    @Test fun `HTTP failures are typed without displaying server bodies`() = runBlocking {
        val f=Fixture(); f.login()
        for((status,kind) in mapOf(403 to NativeFailure.Kind.DENIED,404 to NativeFailure.Kind.UNKNOWN,422 to NativeFailure.Kind.INVALID,429 to NativeFailure.Kind.RATE_LIMIT,500 to NativeFailure.Kind.NOT_CONFIRMED,302 to NativeFailure.Kind.NOT_CONFIRMED)) {
            f.transport.responses+=NativeResponse(status,"sensitive response")
            failure(kind) {f.client.resolve("dqor-2026","2026-10-08","fake-secret")}
        }
    }
    @Test fun `lookup encodes search and preserves duplicate names by ID`() = runBlocking {
        val f=Fixture(); f.login(); f.transport.responses+=NativeResponse(200,"""{"date":"2026-10-08","more_results":false,"tickets":[$ticket,${ticket.replace("101","102")}]}""")
        assertEquals(listOf(101L,102L),f.client.lookup("dqor-2026","2026-10-08","Grace & #").tickets.map {it.id})
        assertTrue(f.transport.requests.last().path.contains("Grace+%26+%23"))
    }
}
