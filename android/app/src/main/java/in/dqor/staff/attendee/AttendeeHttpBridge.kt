package `in`.dqor.staff.attendee

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import java.io.IOException
import okhttp3.CookieJar
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.time.Instant
import java.time.LocalDate
import java.util.concurrent.TimeUnit

internal class AttendeeWireRequest(val method: String, val path: String, val credential: AttendeeCredential?, val json: String?) {
    override fun toString() = "AttendeeWireRequest([redacted])"
}
internal class AttendeeWireResponse(val status: Int, val body: String, val retryAfter: String? = null) {
    override fun toString() = "AttendeeWireResponse([redacted])"
}
internal fun interface AttendeeWireTransport { suspend fun send(request: AttendeeWireRequest): AttendeeWireResponse }

internal fun attendeeHttpClient(): OkHttpClient = OkHttpClient.Builder().cookieJar(CookieJar.NO_COOKIES).cache(null)
    .followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false)
    .connectTimeout(10, TimeUnit.SECONDS).readTimeout(15, TimeUnit.SECONDS).callTimeout(20, TimeUnit.SECONDS).build()

internal fun attendeeRequest(request: AttendeeWireRequest): Request {
    fun invalid(): Nothing = throw AttendeeFailure(AttendeeProblem.INVALID_RESPONSE)
    val path = request.path.substringBefore('?')
    val allowed = setOf("/api/native/attendee/v1/token", "/api/native/attendee/v1/account", "/api/native/attendee/v1/passes", "/api/native/attendee/v1/session")
    if (path !in allowed || request.path.contains('#')) invalid()
    val query = request.path.substringAfter('?', "")
    if (query.isNotEmpty()) {
        val cursor = query.removePrefix("cursor=")
        if (!path.endsWith("/passes") || !query.startsWith("cursor=") || cursor.toLongOrNull()?.let { it > 0 && it.toString() == cursor } != true) invalid()
    } else if ('?' in request.path) invalid()
    val exchange = path.endsWith("/token")
    if (exchange) {
        if (request.method != "POST" || request.credential != null || request.json == null) invalid()
    } else {
        if (request.credential == null || !request.credential.value.matches(Regex("na1_[A-Za-z0-9_-]{43}")) || request.json != null ||
            !(request.method == "GET" || request.method == "DELETE" && path.endsWith("/session"))) invalid()
    }
    val builder = Request.Builder().url(AttendeeIntegration.ORIGIN + request.path)
        .header("Accept", "application/json").header("Cache-Control", "no-store")
    request.credential?.let { builder.header("Authorization", "Bearer ${it.value}") }
    return builder.method(request.method, request.json?.toRequestBody("application/json; charset=utf-8".toMediaType())).build()
}

internal class AttendeeFixedHttpsTransport : AttendeeWireTransport {
    private val client = attendeeHttpClient()
    override suspend fun send(request: AttendeeWireRequest): AttendeeWireResponse {
        if (!AttendeeIntegration.ENABLED) throw AttendeeFailure(AttendeeProblem.UNAVAILABLE)
        return attendeeWireResponse(client, attendeeRequest(request))
    }
}

internal suspend fun attendeeWireResponse(client: OkHttpClient, request: Request): AttendeeWireResponse {
    val call = client.newCall(request)
    return suspendCancellableCoroutine { continuation ->
        continuation.invokeOnCancellation { call.cancel() }
        call.enqueue(object : okhttp3.Callback {
            override fun onFailure(call: okhttp3.Call, error: IOException) {
                if (continuation.isActive) continuation.resumeWithException(AttendeeFailure(AttendeeProblem.OFFLINE))
            }
            override fun onResponse(call: okhttp3.Call, response: okhttp3.Response) {
                try {
                    response.use {
                        val body = it.body
                        if ((body?.contentLength() ?: 0L) > 1_048_576L) throw AttendeeFailure(AttendeeProblem.INVALID_RESPONSE)
                        val output = ByteArrayOutputStream()
                        body?.byteStream()?.use { input ->
                            val buffer = ByteArray(8192)
                            while (true) {
                                val count = input.read(buffer)
                                if (count < 0) break
                                if (output.size() + count > 1_048_576) throw AttendeeFailure(AttendeeProblem.INVALID_RESPONSE)
                                output.write(buffer, 0, count)
                            }
                        }
                        val decoded = try { Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(output.toByteArray())).toString() }
                            catch (_: Exception) { throw AttendeeFailure(AttendeeProblem.INVALID_RESPONSE) }
                        if (continuation.isActive) continuation.resume(AttendeeWireResponse(it.code, decoded, it.headers.values("Retry-After").singleOrNull()))
                    }
                } catch (failure: Exception) {
                    if (continuation.isActive) continuation.resumeWithException(if (failure is AttendeeFailure) failure else AttendeeFailure(AttendeeProblem.OFFLINE))
                }
            }
        })
    }
}

internal class AttendeeHttpBridge(private val transport: AttendeeWireTransport) : AttendeeBridge {
    private val capabilities = setOf("account:read", "passes:read")
    private fun invalid(): Nothing = throw AttendeeFailure(AttendeeProblem.INVALID_RESPONSE)
    private suspend fun <T> decode(block: () -> T): T = withContext(Dispatchers.Default) {
        try { block() } catch (failure: AttendeeFailure) { throw failure } catch (_: Exception) { invalid() }
    }
    private suspend fun rateLimited(response: AttendeeWireResponse): Nothing = decode {
        val valid = runCatching {
            if (response.body.toByteArray(Charsets.UTF_8).size > 1_048_576) invalid()
            val data = AttendeeJson(response.body).parse()
            data.exact("schema_version", "error")
            val error = data.getJSONObject("error"); error.exact("code")
            data.get("schema_version") == 1 && error.string("code") == "rate_limited" && response.retryAfter == "180"
        }.getOrDefault(false)
        throw AttendeeFailure(if (valid) AttendeeProblem.RATE_LIMITED else AttendeeProblem.INVALID_RESPONSE, 180)
    }
    private fun JSONObject.exact(vararg keys: String) { if (keys().asSequence().toSet() != keys.toSet()) invalid() }
    private fun JSONObject.string(key: String): String = (get(key) as? String)?.takeIf { it.length <= 4096 } ?: invalid()
    private fun JSONObject.instant(key: String) = runCatching { Instant.parse(string(key)) }.getOrElse { invalid() }
    private fun JSONObject.id(key: String): String = string(key).also { value -> if (value.toLongOrNull()?.let { it > 0 && it.toString() == value } != true) invalid() }
    private fun JSONObject.nullableDate(key: String): LocalDate? = if (isNull(key)) null else runCatching { LocalDate.parse(string(key)) }.getOrElse { invalid() }
    private fun JSONObject.capabilities(): Set<String> {
        val values = getJSONArray("capabilities")
        if (values.length() != 2) invalid()
        return (0 until values.length()).map { values.get(it) as? String ?: invalid() }.toSet().also { if (it != capabilities) invalid() }
    }
    private suspend fun call(method: String, path: String, credential: AttendeeCredential? = null, json: String? = null): JSONObject {
        val response = transport.send(AttendeeWireRequest(method, "/api/native/attendee/v1/$path", credential, json))
        if (response.status == 429) return rateLimited(response)
        return decode {
            if (response.body.toByteArray(Charsets.UTF_8).size > 1_048_576) invalid()
            val data = try { AttendeeJson(response.body).parse() } catch (_: Exception) { invalid() }
            if (response.status !in 200..299) {
                data.exact("schema_version", "error")
                if (data.get("schema_version") != 1) invalid()
                val error = data.getJSONObject("error"); error.exact("code")
                val code = error.string("code")
                val valid = when (response.status) {
                    400 -> code == "invalid_request"
                    401 -> code == if (path == "token") "invalid_grant" else "unauthenticated"
                    403 -> code in setOf("https_required", "invalid_consent")
                    404 -> code == "not_found"
                    409 -> code == "invalid_attempt"
                    422 -> code == "invalid_cursor"
                    429 -> code == "rate_limited"
                    503 -> code in setOf("configuration_unavailable", "temporarily_unavailable")
                    else -> false
                }
                if (!valid) invalid()
                throw AttendeeFailure(when (response.status) { 401 -> AttendeeProblem.REVOKED; 429 -> AttendeeProblem.RATE_LIMITED; 404,503 -> AttendeeProblem.UNAVAILABLE; else -> AttendeeProblem.INVALID_RESPONSE })
            }
            if (response.status != 200) invalid()
            data
        }
    }
    private fun JSONObject.envelope() { if (get("schema_version") != 1 || string("event") != "dqor-2026") invalid() }
    override suspend fun exchange(request: AttendeeExchange): AttendeeLease {
        if (!request.code.matches(Regex("nac1_[A-Za-z0-9_-]{43}")) || !request.verifier.matches(Regex("[A-Za-z0-9._~-]{43,128}"))) invalid()
        val json = JSONObject().put("code", request.code).put("code_verifier", request.verifier).put("client_id", request.clientId).put("redirect_uri", request.redirectUri).toString()
        val data = call("POST", "token", json=json)
        return decode {
            data.exact("access_token", "token_type", "expires_at", "event", "capabilities")
            if (data.string("token_type") != "Bearer" || data.string("event") != "dqor-2026") invalid()
            data.capabilities()
            val token = data.string("access_token")
            if (!token.matches(Regex("na1_[A-Za-z0-9_-]{43}"))) invalid()
            AttendeeLease(AttendeeCredential(token), data.instant("expires_at"))
        }
    }
    override suspend fun session(credential: AttendeeCredential): AttendeeSession {
        val data = call("GET", "session", credential)
        return decode {
            data.exact("schema_version", "event", "client_id", "capabilities", "expires_at", "checked_at"); data.envelope()
            if (data.string("client_id") != AttendeeIntegration.CLIENT_ID) invalid()
            AttendeeSession(data.string("client_id"), data.capabilities(), data.instant("expires_at"), data.instant("checked_at"))
        }
    }
    override suspend fun account(credential: AttendeeCredential): AttendeeAccountResult {
        val data = call("GET", "account", credential)
        return decode {
            data.exact("schema_version", "event", "checked_at", "account"); data.envelope()
            val account = data.getJSONObject("account"); account.exact("id", "name", "email")
            AttendeeAccountResult(AttendeeIdentity(account.id("id"), if (account.isNull("name")) null else account.string("name"), account.string("email")), data.instant("checked_at"))
        }
    }
    override suspend fun passes(credential: AttendeeCredential, cursor: String?): AttendeePassPage {
        if (cursor != null && cursor.toLongOrNull()?.let { it > 0 && it.toString() == cursor } != true) invalid()
        val data = call("GET", "passes" + (cursor?.let { "?cursor=$it" } ?: ""), credential)
        return decode {
            data.exact("schema_version", "event", "checked_at", "passes", "more_results", "next_cursor"); data.envelope()
            val array = data.getJSONArray("passes"); if (array.length() > 20) invalid()
            val passes = (0 until array.length()).map { index ->
                val pass = array.getJSONObject(index); pass.exact("id", "type", "status", "admission", "entry")
                val type = pass.getJSONObject("type"); type.exact("id", "name")
                val admission = pass.getJSONObject("admission"); admission.exact("starts_on", "ends_on")
                val status = when (pass.string("status")) { "confirmed" -> PassStatus.CONFIRMED; "canceled" -> PassStatus.CANCELED; "expired" -> PassStatus.EXPIRED; "pending" -> PassStatus.PENDING; else -> invalid() }
                val rows = pass.getJSONArray("entry"); if (rows.length() > 4) invalid()
                val entry = (0 until rows.length()).map { n ->
                    val row = rows.getJSONObject(n); row.exact("date", "eligible", "checked_in_at")
                    val date = row.nullableDate("date") ?: invalid()
                    if (date < LocalDate.parse("2026-10-08") || date > LocalDate.parse("2026-10-11")) invalid()
                    AttendeeEntry(date, row.get("eligible") as? Boolean ?: invalid(), if (row.isNull("checked_in_at")) null else row.instant("checked_in_at"))
                }
                if (entry.map { it.date }.distinct().size != entry.size) invalid()
                AttendeePass(pass.id("id"), type.id("id"), type.string("name"), status, admission.nullableDate("starts_on"), admission.nullableDate("ends_on"), entry)
            }
            AttendeePassPage(passes, data.get("more_results") as? Boolean ?: invalid(), if (data.isNull("next_cursor")) null else data.id("next_cursor"), data.instant("checked_at"))
        }
    }
    override suspend fun revoke(credential: AttendeeCredential): AttendeeRevocation {
        val response = transport.send(AttendeeWireRequest("DELETE", "/api/native/attendee/v1/session", credential, null))
        if (response.status == 204 && response.body.isEmpty()) return AttendeeRevocation.REVOKED
        if (response.status == 429) return rateLimited(response)
        if (response.status == 401) return decode {
            val data = runCatching { AttendeeJson(response.body).parse() }.getOrElse { invalid() }
            data.exact("schema_version", "error")
            val error = data.getJSONObject("error"); error.exact("code")
            if (data.get("schema_version") == 1 && error.string("code") == "unauthenticated") AttendeeRevocation.ALREADY_INVALID
            else throw AttendeeFailure(AttendeeProblem.UNAVAILABLE)
        }
        throw AttendeeFailure(AttendeeProblem.UNAVAILABLE)
    }
}
