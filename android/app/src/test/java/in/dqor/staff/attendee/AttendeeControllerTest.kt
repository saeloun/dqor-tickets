package `in`.dqor.staff.attendee

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.*
import org.junit.Test
import java.net.URI
import java.net.URLDecoder
import java.time.Instant
import java.time.LocalDate

class AttendeeControllerTest {
    private val base = Instant.parse("2026-10-03T12:00:00Z")
    private var now = base
    private var elapsed = 0L
    private val bridge = FixtureBridge()
    private fun controller(timeout: Long = 20_000L) = AttendeeController(bridge, true, true, { now }, { elapsed }, timeout)
    private fun callback(auth: AttendeeAuthorization, code: String = "nac1_" + "c".repeat(43)) = "${AttendeeIntegration.CALLBACK}?code=$code&state=${auth.state}"
    private suspend fun signedIn(c: AttendeeController) { assertTrue(c.callback(callback(c.begin()!!))) }

    private inner class FixtureBridge : AttendeeBridge {
        var expires = base.plusSeconds(1800)
        var exchanges = 0
        var reads = 0
        var revokes = 0
        var revoked = false
        val revokedTokens = mutableSetOf<String>()
        val receivedTokens = mutableListOf<String>()
        var failure: AttendeeProblem? = null
        var empty = false
        var identity = AttendeeIdentity("8", "Synthetic Attendee", "synthetic@example.invalid")
        var accountIdentity: AttendeeIdentity? = null
        var exchangeWait: CompletableDeferred<Unit>? = null
        var readWait: CompletableDeferred<Unit>? = null
        var accountWait: CompletableDeferred<Unit>? = null
        var expired = false
        var invalidToken = false
        var pageOverride: AttendeePassPage? = null
        var passedVerifier: String? = null
        val observation = base.minusSeconds(5)
        private fun check(credential: AttendeeCredential? = null) { failure?.let { throw AttendeeFailure(it) }; if (revoked || credential?.value in revokedTokens) throw AttendeeFailure(AttendeeProblem.REVOKED) }
        override suspend fun exchange(request: AttendeeExchange): AttendeeLease {
            exchanges++
            val sequence = exchanges
            passedVerifier = request.verifier
            exchangeWait?.await()
            check()
            val token = if (invalidToken) "staff-token" else "na1_" + AttendeePkce.challenge(request.verifier + sequence)
            receivedTokens += token
            return AttendeeLease(AttendeeCredential(token), if (expired) base else expires)
        }
        override suspend fun session(credential: AttendeeCredential): AttendeeSession { reads++; readWait?.await(); check(credential); return AttendeeSession(AttendeeIntegration.CLIENT_ID, setOf("account:read", "passes:read"), expires, base) }
        override suspend fun account(credential: AttendeeCredential): AttendeeAccountResult { reads++; accountWait?.await(); check(credential); return AttendeeAccountResult(accountIdentity ?: identity, observation) }
        override suspend fun passes(credential: AttendeeCredential, cursor: String?): AttendeePassPage {
            reads++; check(credential)
            return pageOverride ?: AttendeePassPage(if (empty) emptyList() else listOf(AttendeePass("21", "3", "Synthetic conference status", PassStatus.CONFIRMED, null, null,
                listOf(AttendeeEntry(LocalDate.parse("2026-10-08"), true, null)))), false, null, observation)
        }
        override suspend fun revoke(credential: AttendeeCredential): AttendeeRevocation { revokes++; check(); revokedTokens += credential.value; return AttendeeRevocation.REVOKED }
    }

    @Test fun disabledNeverStartsOrExchanges() = runBlocking {
        val c = AttendeeController(bridge, false)
        assertNull(c.begin()); assertFalse(c.callback("${AttendeeIntegration.CALLBACK}?code=c&state=s"))
        assertEquals(0, bridge.exchanges); assertEquals(AttendeeState.Unavailable, c.state.value)
    }
    @Test fun challengeMatchesPublishedRfc7636Vector() {
        assertEquals("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", AttendeePkce.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"))
    }
    @Test fun authorizationHasExactClientCallbackAndRandomIndependentValues() {
        val c = controller(); val auth = c.begin()!!
        val query = URI(auth.url).rawQuery.split('&').associate { part -> part.split('=', limit=2).let { it[0] to URLDecoder.decode(it[1], "UTF-8") } }
        assertEquals("dqor-android", query["client_id"]); assertEquals(AttendeeIntegration.CALLBACK, query["redirect_uri"])
        assertEquals("S256", query["code_challenge_method"]); assertEquals(43, auth.verifier.length); assertEquals(43, auth.state.length)
        assertNotEquals(auth.state, auth.verifier); assertEquals(AttendeePkce.challenge(auth.verifier), query["code_challenge"])
        c.cancel(); assertNotEquals(auth.state, c.begin()!!.state)
    }
    @Test fun repeatedTapOnlyCreatesOnePendingTransaction() { val c=controller(); assertNotNull(c.begin()); assertNull(c.begin()) }
    @Test fun validCallbackExchangesOnlyOnceAndPreservesServerObservationAndNullableDates() = runBlocking {
        val c=controller(); val auth=c.begin()!!; val url=callback(auth)
        assertTrue(c.callback(url)); assertFalse(c.callback(url)); assertEquals(1,bridge.exchanges)
        assertEquals(auth.verifier,bridge.passedVerifier)
        val snapshot=(c.state.value as AttendeeState.Ready).snapshot
        assertEquals(bridge.observation,snapshot.checkedAt); assertNull(snapshot.passes.single().startsOn)
    }
    @Test fun invalidCallbacksDoNotEraseLegitimatePendingTransaction() = runBlocking {
        val c=controller(); val auth=c.begin()!!
        val bad=listOf(callback(auth).replace("https:","http:"),callback(auth).replace("deccanqueenonrails.com","evil.invalid"),
            callback(auth).replace("/android/","/ios/"),callback(auth).replace(".com/",".com:443/"),callback(auth).replace("https://","https://user@"),
            callback(auth)+"#fragment",callback(auth)+"&code=duplicate",callback(auth)+"&state=duplicate",callback(auth)+"&unexpected=yes",
            callback(auth).replace(auth.state,"wrong"),callback(auth).replace("/callback?","/%63allback?"),callback(auth).replace("code=${"nac1_" + "c".repeat(43)}","code=%00"),
            callback(auth).replace("code=${"nac1_" + "c".repeat(43)}","code=%"),callback(auth).replace("code=${"nac1_" + "c".repeat(43)}","code="))
        bad.forEach { assertFalse(it,c.callback(it)) }
        assertEquals(0,bridge.exchanges); assertEquals(AttendeeState.Authorizing,c.state.value); assertTrue(c.callback(callback(auth)))
    }
    @Test fun coldLaunchAndCanceledOldCallbacksFailClosed() = runBlocking {
        val c=controller(); val old=c.begin()!!; c.cancel(); val fresh=c.begin()!!
        assertFalse(c.callback(callback(old))); assertFalse(controller().callback(callback(fresh))); assertTrue(c.callback(callback(fresh)))
    }
    @Test fun pendingClientDeadlineExpiresEvenIfWallClockMovesBackward() = runBlocking {
        val c=controller(); val auth=c.begin()!!; now=base.minusSeconds(86400); elapsed=600_000
        assertFalse(c.callback(callback(auth))); assertEquals(AttendeeState.Failed(AttendeeProblem.EXPIRED),c.state.value)
    }
    @Test fun tokenLeaseRejectsInvalidTokenAndOverlongLifetime() = runBlocking {
        bridge.invalidToken=true; val c=controller(); signedIn(c); assertEquals(AttendeeState.Failed(AttendeeProblem.INVALID_RESPONSE),c.state.value)
        bridge.invalidToken=false; now=base.minusSeconds(1); val c2=controller(); signedIn(c2); assertTrue(c2.state.value is AttendeeState.Ready)
        elapsed=1_800_000; c2.expire(); assertEquals(AttendeeState.Failed(AttendeeProblem.EXPIRED),c2.state.value)
        now=base; elapsed=0; bridge.expires=base.plusSeconds(1801); val c3=controller(); signedIn(c3); assertEquals(AttendeeState.Failed(AttendeeProblem.INVALID_RESPONSE),c3.state.value)
    }
    @Test fun serverExpiryAndMonotonicExpiryClearPrivateData() = runBlocking {
        val c=controller(); signedIn(c); now=base.minusSeconds(86400); elapsed=1_800_000; c.expire()
        assertEquals(AttendeeState.Failed(AttendeeProblem.EXPIRED),c.state.value); assertEquals(3,bridge.reads)
    }
    @Test fun expiredExchangeNeverReadsAccount() = runBlocking {
        bridge.expired=true; val c=controller(); signedIn(c); assertTrue(c.state.value is AttendeeState.Failed); assertEquals(0,bridge.reads)
    }
    @Test fun emailChangeAndAccountSessionMismatchClearPrivateState() = runBlocking {
        val c=controller(); signedIn(c); bridge.identity=bridge.identity.copy(email="changed@example.invalid"); c.refresh()
        assertEquals(AttendeeState.Failed(AttendeeProblem.IDENTITY_CHANGED),c.state.value)
        bridge.accountIdentity=bridge.identity.copy(id="other"); val c2=controller(); signedIn(c2); bridge.accountIdentity=bridge.identity; c2.refresh()
        assertEquals(AttendeeState.Failed(AttendeeProblem.IDENTITY_CHANGED),c2.state.value)
    }
    @Test fun revokedAndOfflineReadClearPrivateData() = runBlocking {
        val c=controller(); signedIn(c); bridge.revoked=true; c.refresh(); assertEquals(AttendeeState.Failed(AttendeeProblem.REVOKED),c.state.value)
        bridge.revoked=false; val c2=controller(); signedIn(c2); bridge.failure=AttendeeProblem.OFFLINE; c2.refresh(); assertEquals(AttendeeState.Failed(AttendeeProblem.OFFLINE),c2.state.value)
    }
    @Test fun onlineLogoutConfirmsAndOfflineLogoutDoesNotClaimRevocation() = runBlocking {
        val c=controller(); signedIn(c); c.logout(); assertEquals(AttendeeState.SignedOutResult(AttendeeRevocation.REVOKED),c.state.value)
        bridge.revoked=false; val c2=controller(); signedIn(c2); bridge.failure=AttendeeProblem.OFFLINE; c2.logout(); assertEquals(AttendeeState.SignedOutResult(null),c2.state.value)
    }
    @Test fun logoutDuringReadPreventsSubsequentAccountAndPassRequests() = runBlocking {
        val c=controller(); signedIn(c); bridge.readWait=CompletableDeferred(); val work=async { c.refresh() }; yield()
        assertEquals(4,bridge.reads); c.logout(); bridge.readWait!!.complete(Unit); work.await()
        assertEquals(4,bridge.reads); assertEquals(AttendeeState.SignedOutResult(AttendeeRevocation.REVOKED),c.state.value)
    }
    @Test fun logoutDuringAccountDoesNotStartPassRequest() = runBlocking {
        val c=controller(); signedIn(c); bridge.accountWait=CompletableDeferred(); val work=async { c.refresh() }; yield()
        assertEquals(5,bridge.reads); c.logout(); bridge.accountWait!!.complete(Unit); work.await(); assertEquals(5,bridge.reads)
    }
    @Test fun canceledLateExchangeIsRevokedAndDoesNotResurrect() = runBlocking {
        val c=controller(); val auth=c.begin()!!; bridge.exchangeWait=CompletableDeferred(); val work=async {c.callback(callback(auth))}; yield()
        c.cancel(); bridge.exchangeWait!!.complete(Unit); work.await(); assertEquals(AttendeeState.SignedOut,c.state.value); assertEquals(1,bridge.revokes); assertEquals(0,bridge.reads)
    }
    @Test fun canceledOldExchangeCleanupDoesNotRevokeOrReplaceNewSession() = runBlocking {
        val c=controller(); val old=c.begin()!!; val pending=CompletableDeferred<Unit>(); bridge.exchangeWait=pending
        val oldWork=async {c.callback(callback(old))}; yield(); c.cancel()
        bridge.exchangeWait=null; val fresh=c.begin()!!; c.callback(callback(fresh))
        val newest=bridge.receivedTokens.single(); assertTrue(c.state.value is AttendeeState.Ready)
        pending.complete(Unit); oldWork.await()
        assertFalse(bridge.revokedTokens.contains(newest)); assertEquals(1,bridge.revokedTokens.size)
        c.refresh(); assertTrue(c.state.value is AttendeeState.Ready)
    }
    @Test fun callbackBackgroundReturnWorksAndPrivateBackgroundReadIsRevalidated() = runBlocking {
        val c=controller(); val auth=c.begin()!!; c.background(); assertTrue(c.callback(callback(auth))); assertEquals(0,bridge.reads)
        c.foreground(); assertTrue(c.state.value is AttendeeState.Ready); c.background(); assertEquals(AttendeeState.Loading,c.state.value)
        c.foreground(); assertEquals(6,bridge.reads)
    }
    @Test fun expiryClearsPrivateDataWithoutMountedAccountOrAnyFurtherAction() = runBlocking {
        bridge.expires=base.plusMillis(150)
        val start=System.nanoTime()
        val c=AttendeeController(bridge,true,true,{base},{(System.nanoTime()-start)/1_000_000L})
        signedIn(c); assertTrue(c.state.value is AttendeeState.Ready)
        delay(300)
        assertEquals(AttendeeState.Failed(AttendeeProblem.EXPIRED),c.state.value)
        c.forget()
    }
    @Test fun emptyAssignedPassListIsAValidReadyState() = runBlocking { bridge.empty=true; val c=controller(); signedIn(c); assertTrue((c.state.value as AttendeeState.Ready).snapshot.passes.isEmpty()) }
    @Test fun malformedCursorAndUnboundedPagesFailClosed() = runBlocking {
        bridge.pageOverride=AttendeePassPage(emptyList(),true,"01",base); val c=controller(); signedIn(c)
        assertEquals(AttendeeState.Failed(AttendeeProblem.INVALID_RESPONSE),c.state.value)
    }
    @Test fun timeoutDoesNotRetryExchange() = runBlocking {
        bridge.exchangeWait=CompletableDeferred(); val c=controller(30); val auth=c.begin()!!; c.callback(callback(auth))
        assertEquals(AttendeeState.Failed(AttendeeProblem.TIMEOUT),c.state.value); assertFalse(c.callback(callback(auth))); assertEquals(1,bridge.exchanges)
    }
    @Test fun credentialsAndTransactionDebugStringsAreRedacted() {
        assertFalse(AttendeeCredential("na1_secret").toString().contains("na1_secret")); assertFalse(AttendeeExchange("secret","verifier").toString().contains("secret"))
        val auth=controller().begin()!!; assertFalse(auth.toString().contains(auth.state)); assertFalse(auth.toString().contains(auth.verifier))
    }
}
