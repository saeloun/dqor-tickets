package `in`.dqor.staff.attendee

import java.net.ServerSocket
import java.net.InetAddress
import java.net.Socket
import java.net.URI
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.net.InetSocketAddress
import java.time.Instant
import java.util.concurrent.CopyOnWriteArrayList

class AttendeeHttpBridgeTest {
    private class Headers {
        val values = mutableListOf<Pair<String,String>>()
        fun getFirst(name: String): String? = values.firstOrNull {it.first.equals(name,true)}?.second
        fun add(name: String,value: String) {values += name to value}
    }
    private class Exchange(private val socket: Socket) {
        val requestMethod: String
        val requestURI: URI
        val requestHeaders=Headers()
        val responseHeaders=Headers()
        val responseBody=ByteArrayOutputStream()
        val requestBody: java.io.InputStream
        private var status=500
        init {
            val input=socket.getInputStream().buffered()
            fun line(): String {
                val output=ByteArrayOutputStream()
                while (true) {val value=input.read(); if(value<0 || value==10) break; if(value!=13) output.write(value); require(output.size()<8192)}
                return output.toString("UTF-8")
            }
            val first=line().split(' '); requestMethod=first[0]; requestURI=URI(first[1])
            while(true) {val row=line(); if(row.isEmpty()) break; val split=row.indexOf(':'); require(split>0); requestHeaders.add(row.substring(0,split),row.substring(split+1).trim())}
            val count=requestHeaders.getFirst("Content-Length")?.toInt() ?: 0; require(count in 0..8192)
            val bytes=ByteArray(count); var read=0; while(read<count) {val n=input.read(bytes,read,count-read); require(n>0); read+=n}
            requestBody=bytes.inputStream()
        }
        fun sendResponseHeaders(code: Int,length: Long) {status=code}
        fun close() {
            val output=socket.getOutputStream()
            val bytes=responseBody.toByteArray()
            val headers=buildString {append("HTTP/1.1 $status Synthetic\r\n"); responseHeaders.values.forEach {(key,value)->append("$key: $value\r\n")}; append("Content-Length: ${bytes.size}\r\nConnection: close\r\n\r\n")}
            try {output.write(headers.toByteArray()); output.write(bytes); output.flush()}
            catch (_: java.io.IOException) { }
            finally {socket.close()}
        }
    }
    private class LocalHttpServer {
        private val socket=ServerSocket(0,50,InetAddress.getByName("127.0.0.1"))
        val address get()=socket.localSocketAddress as InetSocketAddress
        private var handler: ((Exchange)->Unit)?=null
        private var error: Throwable?=null
        private var thread: Thread?=null
        fun createContext(path: String,handler: (Exchange)->Unit) {this.handler=handler}
        fun start() {thread=Thread {
            while(!socket.isClosed) {
                try {val connection=socket.accept(); connection.soTimeout=5000; val exchange=Exchange(connection); try {handler!!(exchange)} catch(failure: Throwable) {error=failure; exchange.sendResponseHeaders(500,0); exchange.close()}}
                catch(failure: Exception) {if(!socket.isClosed) error=failure}
            }
        }.apply {isDaemon=true;start()}}
        fun stop(delay: Int) {socket.close(); thread?.join(1000); error?.let {throw AssertionError("Synthetic HTTP fixture failed",it)}}
    }

    private class LoopbackTransport(origin: String) : AttendeeWireTransport {
        private val origin: String
        private val client = attendeeHttpClient()
        init {
            val uri=runCatching {URI(origin)}.getOrElse {throw AttendeeFailure(AttendeeProblem.INVALID_RESPONSE)}
            if(uri.port !in 1..65535 || origin!="http://127.0.0.1:${uri.port}") throw AttendeeFailure(AttendeeProblem.INVALID_RESPONSE)
            this.origin=origin
        }
        override suspend fun send(request: AttendeeWireRequest): AttendeeWireResponse {
            val local=attendeeRequest(request).newBuilder().url(origin+request.path).build()
            return attendeeWireResponse(client,local)
        }
    }

    private val now = Instant.parse("2026-10-03T12:00:00Z")
    private val expires = now.plusSeconds(1800)
    private val token = "na1_" + "t".repeat(43)
    private val code = "nac1_" + "c".repeat(43)
    private val envelope = "\"schema_version\":1,\"event\":\"dqor-2026\",\"checked_at\":\"$now\""
    private val tokenJson = "{\"access_token\":\"$token\",\"token_type\":\"Bearer\",\"expires_at\":\"$expires\",\"event\":\"dqor-2026\",\"capabilities\":[\"account:read\",\"passes:read\"]}"
    private fun error(code: String) = "{\"schema_version\":1,\"error\":{\"code\":\"$code\"}}"
    private fun failure(expected: AttendeeProblem, action: suspend () -> Unit) = runBlocking {
        try { action(); fail("Expected $expected") } catch (failure: AttendeeFailure) { assertEquals(expected, failure.problem) }
    }

    @Test fun realLoopbackHttpPkceExchangeReadLogoutReplayHasIsolatedHeadersAndNoCookies() = runBlocking {
        val server = LocalHttpServer()
        val seen = CopyOnWriteArrayList<String>()
        var expectedChallenge = ""
        var consumed = false
        var revoked = false
        server.createContext("/api/native/attendee/v1/") { exchange ->
            assertNull(exchange.requestHeaders.getFirst("Cookie"))
            assertNull(exchange.requestHeaders.getFirst("If-None-Match"))
            assertEquals("no-store",exchange.requestHeaders.getFirst("Cache-Control"))
            seen += "${exchange.requestMethod} ${exchange.requestURI}"
            var status=200
            val body = if (exchange.requestURI.path.endsWith("/token")) {
                assertEquals("POST",exchange.requestMethod); assertNull(exchange.requestHeaders.getFirst("Authorization"))
                val request = JSONObject(exchange.requestBody.bufferedReader().use { it.readText() })
                assertEquals(setOf("code","code_verifier","client_id","redirect_uri"),request.keys().asSequence().toSet())
                assertEquals(AttendeeIntegration.CLIENT_ID,request.getString("client_id")); assertEquals(AttendeeIntegration.CALLBACK,request.getString("redirect_uri"))
                if (consumed || request.getString("code") != code || AttendeePkce.challenge(request.getString("code_verifier")) != expectedChallenge) {
                    status=401; error("invalid_grant")
                } else { consumed=true; tokenJson }
            } else {
                assertEquals("Bearer $token",exchange.requestHeaders.getFirst("Authorization"))
                if (revoked) { status=401; error("unauthenticated") }
                else when (exchange.requestURI.path.substringAfterLast('/')) {
                    "session" -> if (exchange.requestMethod=="DELETE") {revoked=true; status=204; ""} else "{$envelope,\"client_id\":\"dqor-android\",\"capabilities\":[\"account:read\",\"passes:read\"],\"expires_at\":\"$expires\"}"
                    "account" -> "{$envelope,\"account\":{\"id\":\"8\",\"name\":\"Synthetic HTTP Attendee\",\"email\":\"synthetic@example.invalid\"}}"
                    "passes" -> "{$envelope,\"passes\":[],\"more_results\":false,\"next_cursor\":null}"
                    else -> {status=404; error("not_found")}
                }
            }
            exchange.responseHeaders.add("Content-Type","application/json")
            exchange.responseHeaders.add("Cache-Control","private, no-store")
            exchange.responseHeaders.add("Set-Cookie","must_not_store=synthetic; Path=/")
            exchange.sendResponseHeaders(status, if(status==204) -1 else body.toByteArray().size.toLong())
            if(status!=204) exchange.responseBody.use {it.write(body.toByteArray())}
            exchange.close()
        }
        server.start()
        try {
            val localOrigin="http://127.0.0.1:${server.address.port}"
            val transport=LoopbackTransport(localOrigin)
            val bridge=AttendeeHttpBridge(transport)
            val controller=AttendeeController(bridge,true,true,{now},{0L})
            val attempt=controller.begin()!!; expectedChallenge=AttendeePkce.challenge(attempt.verifier)
            assertTrue(controller.callback("${AttendeeIntegration.CALLBACK}?code=$code&state=${attempt.state}"))
            assertEquals("Synthetic HTTP Attendee",(controller.state.value as AttendeeState.Ready).snapshot.identity.name)
            assertEquals(listOf("POST /api/native/attendee/v1/token","GET /api/native/attendee/v1/session","GET /api/native/attendee/v1/account","GET /api/native/attendee/v1/passes"),seen.toList())
            controller.logout(); assertEquals(AttendeeState.SignedOutResult(AttendeeRevocation.REVOKED),controller.state.value)
            assertEquals(AttendeeRevocation.ALREADY_INVALID,bridge.revoke(AttendeeCredential(token)))
            failure(AttendeeProblem.REVOKED) { bridge.account(AttendeeCredential(token)) }
            failure(AttendeeProblem.REVOKED) { bridge.exchange(AttendeeExchange(code,attempt.verifier)) }
        } finally { server.stop(0) }
    }
    @Test fun revokeDecodes401AwayFromCallerDispatcherAndKeeps204FastPath() {
        val dispatches = java.util.concurrent.atomic.AtomicInteger()
        val executor = java.util.concurrent.Executors.newSingleThreadExecutor()
        val caller = object : kotlinx.coroutines.CoroutineDispatcher() {
            override fun dispatch(context: kotlin.coroutines.CoroutineContext, block: Runnable) {
                dispatches.incrementAndGet()
                executor.execute(block)
            }
        }
        try {
            runBlocking {
                kotlinx.coroutines.withContext(caller) {
                    val bridge = AttendeeHttpBridge { AttendeeWireResponse(401, error("unauthenticated")) }
                    val beforeDecode = dispatches.get()
                    assertEquals(AttendeeRevocation.ALREADY_INVALID, bridge.revoke(AttendeeCredential(token)))
                    assertTrue("401 parsing must resume through the caller dispatcher", dispatches.get() > beforeDecode)
                    val fast = AttendeeHttpBridge { AttendeeWireResponse(204, "") }
                    val beforeFast = dispatches.get()
                    assertEquals(AttendeeRevocation.REVOKED, fast.revoke(AttendeeCredential(token)))
                    assertEquals(beforeFast, dispatches.get())
                }
            }
        } finally {
            executor.shutdownNow()
            assertTrue(executor.awaitTermination(5, java.util.concurrent.TimeUnit.SECONDS))
        }
        failure(AttendeeProblem.INVALID_RESPONSE) { AttendeeHttpBridge { AttendeeWireResponse(401, "{}") }.revoke(AttendeeCredential(token)) }
        failure(AttendeeProblem.UNAVAILABLE) { AttendeeHttpBridge { AttendeeWireResponse(401, error("invalid_grant")) }.revoke(AttendeeCredential(token)) }
    }
    @Test fun actualHttp429PreservesCanonicalRetryAfterAndRejectsMalformedHeadersWithBoundedWait() = runBlocking {
        val server = LocalHttpServer()
        var duplicateHeader = false
        server.createContext("/") { exchange ->
            exchange.responseHeaders.add("Retry-After", "180")
            if (duplicateHeader) exchange.responseHeaders.add("Retry-After", "180")
            val body = error("rate_limited").toByteArray()
            exchange.sendResponseHeaders(429, body.size.toLong()); exchange.responseBody.write(body); exchange.close()
        }
        server.start()
        try {
            val bridge = AttendeeHttpBridge(LoopbackTransport("http://127.0.0.1:${server.address.port}"))
            try { bridge.account(AttendeeCredential(token)); fail("Expected bounded rate limit") }
            catch (failure: AttendeeFailure) { assertEquals(AttendeeProblem.RATE_LIMITED, failure.problem); assertEquals(180, failure.retryAfterSeconds) }
            try { bridge.revoke(AttendeeCredential(token)); fail("Expected bounded logout rate limit") }
            catch (failure: AttendeeFailure) { assertEquals(AttendeeProblem.RATE_LIMITED, failure.problem); assertEquals(180, failure.retryAfterSeconds) }
            duplicateHeader = true
            try { bridge.account(AttendeeCredential(token)); fail("Accepted duplicate Retry-After headers") }
            catch (failure: AttendeeFailure) { assertEquals(AttendeeProblem.INVALID_RESPONSE, failure.problem); assertEquals(180, failure.retryAfterSeconds) }
        } finally { server.stop(0) }
        for (header in listOf(null, "0", "179", "181", "0180", "+180", "180.0", "180, 180", "999999999999999999999", "Sat, 03 Oct 2026 12:03:00 GMT")) {
            val bridge = AttendeeHttpBridge { AttendeeWireResponse(429, error("rate_limited"), header) }
            try { bridge.exchange(AttendeeExchange(code, "v".repeat(43))); fail("Accepted noncanonical Retry-After") }
            catch (failure: AttendeeFailure) { assertEquals(AttendeeProblem.INVALID_RESPONSE, failure.problem); assertEquals(180, failure.retryAfterSeconds) }
        }
        for (body in listOf("{}", error("made_up"), "{\"schema_version\":\"1\",\"error\":{\"code\":\"rate_limited\"}}")) {
            try { AttendeeHttpBridge { AttendeeWireResponse(429, body, "180") }.account(AttendeeCredential(token)); fail("Accepted noncanonical 429 body") }
            catch (failure: AttendeeFailure) { assertEquals(AttendeeProblem.INVALID_RESPONSE, failure.problem); assertEquals(180, failure.retryAfterSeconds) }
        }
    }
    @Test fun productionTransportGateAndRequestAllowlistFailClosed() {
        failure(AttendeeProblem.UNAVAILABLE) { AttendeeFixedHttpsTransport().send(AttendeeWireRequest("GET","/api/native/attendee/v1/account",AttendeeCredential(token),null)) }
        listOf("/api/public/v1/dqor/programme","/api/attendee/v1/account","/api/staff/checkins","/api/native/attendee/v1/session#secret","/api/native/attendee/v1/token?code=x","/api/native/attendee/v1/passes?cursor=01").forEach { path ->
            failure(AttendeeProblem.INVALID_RESPONSE) {attendeeRequest(AttendeeWireRequest("GET",path,AttendeeCredential(token),null))}
        }
        failure(AttendeeProblem.INVALID_RESPONSE) {attendeeRequest(AttendeeWireRequest("DELETE","/api/native/attendee/v1/account",AttendeeCredential(token),null))}
        val client=attendeeHttpClient(); assertFalse(client.followRedirects); assertFalse(client.followSslRedirects); assertFalse(client.retryOnConnectionFailure)
        assertNull(client.cache); assertSame(okhttp3.CookieJar.NO_COOKIES,client.cookieJar); assertEquals(20_000,client.callTimeoutMillis)
        val tokenRequest=attendeeRequest(AttendeeWireRequest("POST","/api/native/attendee/v1/token",null,"{}"))
        assertNull(tokenRequest.header("Authorization")); assertEquals(AttendeeIntegration.ORIGIN,tokenRequest.url.toString().substringBefore("/api/"))
    }
    @Test fun exactTokenAndErrorSchemasRejectWrongTypesScopeSecretExtrasAndDuplicates() {
        val malformed=listOf(tokenJson.replace("Bearer","bearer"),tokenJson.replace("account:read","checkins:write"),tokenJson.replace("dqor-2026","other"),
            tokenJson.dropLast(1)+",\"qr\":\"secret\"}",tokenJson.dropLast(1)+",\"access_token\":\"$token\"}",tokenJson+" trailing",tokenJson.replace("\"expires_at\"","\"schema_version\":1,\"expires_at\""))
        malformed.forEach { body -> failure(AttendeeProblem.INVALID_RESPONSE) {AttendeeHttpBridge {AttendeeWireResponse(200,body)}.exchange(AttendeeExchange(code,"v".repeat(43)))} }
        listOf("{\"schema_version\":\"1\",\"error\":{\"code\":\"unauthenticated\"}}",error("made_up"),"{\"schema_version\":1,\"error\":{\"code\":\"unauthenticated\",\"token\":\"secret\"}}").forEach { body ->
            failure(AttendeeProblem.INVALID_RESPONSE) {AttendeeHttpBridge {AttendeeWireResponse(401,body)}.account(AttendeeCredential(token))}
        }
    }
    @Test fun publishedTypedErrorsAndNullablePassDatesDecodeCorrectly() = runBlocking {
        failure(AttendeeProblem.RATE_LIMITED) {AttendeeHttpBridge {AttendeeWireResponse(429,error("rate_limited"),"180")}.account(AttendeeCredential(token))}
        failure(AttendeeProblem.UNAVAILABLE) {AttendeeHttpBridge {AttendeeWireResponse(503,error("configuration_unavailable"))}.account(AttendeeCredential(token))}
        val pass="{\"id\":\"21\",\"type\":{\"id\":\"3\",\"name\":\"Synthetic pass\"},\"status\":\"confirmed\",\"admission\":{\"starts_on\":null,\"ends_on\":null},\"entry\":[{\"date\":\"2026-10-08\",\"eligible\":true,\"checked_in_at\":null}]}"
        val bridge=AttendeeHttpBridge {AttendeeWireResponse(200,"{$envelope,\"passes\":[$pass],\"more_results\":false,\"next_cursor\":null}")}
        val page=bridge.passes(AttendeeCredential(token),null); assertNull(page.passes.single().startsOn); assertNull(page.passes.single().entry.single().checkedInAt); assertEquals(now,page.checkedAt)
        failure(AttendeeProblem.INVALID_RESPONSE) {bridge.passes(AttendeeCredential(token),"9223372036854775808")}
    }
    @Test fun oversizedBodiesAndRedirectsAreRejectedWithoutFollowing() = runBlocking {
        failure(AttendeeProblem.INVALID_RESPONSE) {AttendeeHttpBridge {AttendeeWireResponse(200," ".repeat(1_048_577))}.account(AttendeeCredential(token))}
        val server=LocalHttpServer(); var requests=0
        server.createContext("/") {exchange -> requests++; exchange.responseHeaders.add("Location","http://127.0.0.1:1/must-not-follow"); exchange.sendResponseHeaders(302,0); exchange.close()}
        server.start()
        try {
            val bridge=AttendeeHttpBridge(LoopbackTransport("http://127.0.0.1:${server.address.port}"))
            failure(AttendeeProblem.INVALID_RESPONSE) {bridge.account(AttendeeCredential(token))}; assertEquals(1,requests)
        } finally {server.stop(0)}
    }
    @Test fun actualAsyncReaderRejectsOversizedResponseAndCancelsSlowLoopbackRequest() = runBlocking {
        val server=LocalHttpServer()
        var oversized=true
        server.createContext("/") {exchange ->
            if (oversized) {exchange.responseBody.write(" ".repeat(1_048_577).toByteArray());exchange.sendResponseHeaders(200,1_048_577)}
            else {Thread.sleep(500);exchange.responseBody.write("{}".toByteArray());exchange.sendResponseHeaders(200,2)}
            exchange.close()
        }
        server.start()
        try {
            val transport=LoopbackTransport("http://127.0.0.1:${server.address.port}")
            val request=AttendeeWireRequest("GET","/api/native/attendee/v1/account",AttendeeCredential(token),null)
            failure(AttendeeProblem.INVALID_RESPONSE) {transport.send(request)}
            oversized=false
            val start=System.nanoTime()
            try {kotlinx.coroutines.withTimeout(50) {transport.send(request)}; fail("Slow call did not cancel")}
            catch (_: kotlinx.coroutines.TimeoutCancellationException) {assertTrue((System.nanoTime()-start)/1_000_000<450)}
            listOf("https://deccanqueenonrails.com","http://localhost:1234","http://127.0.0.1:1234/","http://127.0.0.1:1234?x=1","http://user@127.0.0.1:1234","http://127.0.0.1:65536").forEach {origin ->failure(AttendeeProblem.INVALID_RESPONSE) {LoopbackTransport(origin)}}
        } finally {server.stop(0)}
    }
    @Test fun strictJsonRejectsNonJsonFormsAndDuplicateKeysAtEveryDepth() {
        listOf("{a:1}","{\"a\":01}","{\"a\":NaN}","{\"a\":1,}","{\"a\":1,\"a\":2}","{\"a\":{\"b\":1,\"b\":2}}", "{\"a\":\"bad\\q\"}","{\"a\":1}{}", "{\"a\":/*comment*/1}").forEach { body ->
            failure(AttendeeProblem.INVALID_RESPONSE) {AttendeeJson(body).parse()}
        }
        assertEquals("puné",AttendeeJson("{\"a\":\"pun\\u00e9\"}").parse().getString("a"))
    }
}
