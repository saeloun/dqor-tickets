package `in`.dqor.staff.nativeapi

import java.net.URI
import java.net.URLEncoder
import java.time.Instant
import java.time.LocalDate
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import org.json.JSONObject

class NativeFailure(val kind: Kind) : Exception(kind.message) {
    enum class Kind(val message: String) {
        DISABLED("Native integration is disabled pending staging approval."),
        SIGN_IN("Staff session expired or revoked. Sign in again."),
        DENIED("Staff capability or event date is not permitted."),
        UNKNOWN("Ticket was not found."), INVALID("Invalid request."),
        RATE_LIMIT("Too many requests. Try again later."),
        NOT_CONFIRMED("Not confirmed. No offline queue. Retry the same ticket IDs and date."),
        OUTCOME("Unsupported or unverified outcome. Do not admit; staff resolution is required."),
        SCHEMA("Invalid server response. Admission is not confirmed."),
        STORAGE("Secure session storage unavailable. Sign in again.")
    }
}
class NativeConfig(val enabled: Boolean = false, origin: String = "") {
    val origin: String = if (!enabled) "" else URI(origin).let {
        require(it.scheme == "https" && !it.host.isNullOrBlank() && it.rawUserInfo == null && it.rawQuery == null && it.rawFragment == null && it.rawPath in listOf("", "/")) { "An approved HTTPS origin is required" }
        it.toString().trimEnd('/')
    }
}
// Never use data-class generated toString for objects containing credentials or QR values.
class NativeRequest(val method: String, val path: String, val bearer: String? = null, val body: String? = null) {
    override fun toString() = "NativeRequest($method, redacted)"
}
class NativeResponse(val status: Int, val body: String = "") { override fun toString() = "NativeResponse($status, redacted)" }
fun interface NativeTransport { suspend fun execute(request: NativeRequest): NativeResponse }
class StoredCredential(val origin: String, val token: String, val expiresAt: Instant) { override fun toString() = "StoredCredential(redacted)" }
interface CredentialStore { suspend fun read(): StoredCredential?; suspend fun write(value: StoredCredential); suspend fun clear() }
data class NativeScope(val event: String, val eventDates: List<String>, val capabilities: Set<String>, val expiresAt: Instant, val maxBatchSize: Int)
data class NativeTicket(val id: Long, val attendeeName: String, val attendeeEmail: String, val ticketType: String, val orderCode: String, val eligible: Boolean, val checkedInAt: String?)
data class NativePreview(val date: String, val ticket: NativeTicket)
data class NativeLookup(val date: String, val moreResults: Boolean, val tickets: List<NativeTicket>)
enum class NativeState { SUCCESS, WARNING, ERROR }
enum class NativeOutcomeCode(val wireValue: String, val state: NativeState) {
    SUCCESS("success", NativeState.SUCCESS), DUPLICATE("duplicate", NativeState.WARNING),
    NOT_FOUND("not_found", NativeState.ERROR), UNCONFIRMED("unconfirmed", NativeState.ERROR),
    WRONG_DATE("wrong_date", NativeState.ERROR), CANCELED("canceled", NativeState.ERROR)
}
data class NativeOutcome(val ticketId: Long, val attendee: String?, val state: NativeState, val code: NativeOutcomeCode, val message: String, val checkedInAt: String?)
data class NativeConfirmation(val date: String, val results: List<NativeOutcome>)
enum class LogoutResult { REVOKED, LOCAL_ONLY }

/** Standalone typed adapter: never wired to the demo's immediate-mutation scanner. */
class NativeStaffClient(private val config: NativeConfig, private val transport: NativeTransport, private val store: CredentialStore, private val now: () -> Instant = Instant::now) {
    private val mutex = Mutex()
    private var scope: NativeScope? = null
    private fun enabled() { if(!config.enabled) throw NativeFailure(NativeFailure.Kind.DISABLED) }
    private suspend fun clear() { scope=null; store.clear() }
    private suspend fun credential(): StoredCredential {
        val value=store.read()
        if(value == null || value.origin != config.origin || !value.expiresAt.isAfter(now())) { clear(); throw NativeFailure(NativeFailure.Kind.SIGN_IN) }
        return value
    }
    private suspend fun request(request: NativeRequest, expected: Int): NativeResponse {
        enabled()
        val response=try { transport.execute(request) } catch(e: CancellationException) { throw e } catch(_: Exception) { throw NativeFailure(NativeFailure.Kind.NOT_CONFIRMED) }
        if(response.status == expected) return response
        throw NativeFailure(when(response.status) {
            401 -> { clear(); NativeFailure.Kind.SIGN_IN }
            403 -> NativeFailure.Kind.DENIED
            404 -> NativeFailure.Kind.UNKNOWN
            422 -> NativeFailure.Kind.INVALID
            429 -> NativeFailure.Kind.RATE_LIMIT
            else -> NativeFailure.Kind.NOT_CONFIRMED
        })
    }
    suspend fun signIn(email: String, password: CharArray): NativeScope {
        try { return mutex.withLock {
            enabled(); clear()
            val body=JSONObject().put("email",email).put("password",String(password)).toString()
            val json=decode { JSONObject(request(NativeRequest("POST","/api/staff/session",body=body),201).body) }
            val fresh=decode { parseScope(json) }
            val token=decode { require(json.string("token_type") == "Bearer"); json.string("access_token").also { require(it.matches(Regex("[A-Za-z0-9_-]{32,512}"))) } }
            try { store.write(StoredCredential(config.origin,token,fresh.expiresAt)) } catch(_: Exception) { clear(); throw NativeFailure(NativeFailure.Kind.STORAGE) }
            scope=fresh; fresh
        } } finally { password.fill('\u0000') }
    }
    suspend fun restoreSession(): NativeScope = mutex.withLock {
        enabled(); scope=null
        val saved=credential()
        val fresh=decode { parseScope(JSONObject(request(NativeRequest("GET","/api/staff/session",saved.token),200).body)) }
        store.write(StoredCredential(config.origin,saved.token,fresh.expiresAt)); scope=fresh; fresh
    }
    suspend fun logout(): LogoutResult = mutex.withLock {
        val saved=store.read()
        // Local logout happens first and is never undone by a failed request.
        clear()
        if(saved == null || !config.enabled || saved.origin != config.origin) return@withLock LogoutResult.LOCAL_ONLY
        try { request(NativeRequest("DELETE","/api/staff/session",saved.token),204); LogoutResult.REVOKED }
        catch(e: CancellationException) { throw e } catch(_: Exception) { LogoutResult.LOCAL_ONLY }
    }
    private suspend fun authorize(event: String, date: String, capability: String): StoredCredential {
        enabled(); val credential=credential(); val active=scope ?: throw NativeFailure(NativeFailure.Kind.SIGN_IN)
        if(!active.expiresAt.isAfter(now())) { clear(); throw NativeFailure(NativeFailure.Kind.SIGN_IN) }
        if(event != active.event || date !in active.eventDates || capability !in active.capabilities) throw NativeFailure(NativeFailure.Kind.DENIED)
        return credential
    }
    suspend fun resolve(event: String, date: String, secret: String): NativePreview = mutex.withLock {
        val auth=authorize(event,date,"tickets:read")
        require(secret.isNotEmpty())
        decode {
            val json=JSONObject(request(NativeRequest("POST","/api/staff/checkins/resolve",auth.token,JSONObject().put("secret",secret).put("date",date).toString()),200).body)
            require(json.string("state") == "resolved" && json.string("date") == date)
            NativePreview(date,ticket(json.getJSONObject("ticket")))
        }
    }
    suspend fun lookup(event: String, date: String, query: String): NativeLookup = mutex.withLock {
        val auth=authorize(event,date,"tickets:read")
        decode {
            val path="/api/staff/checkins?date=${URLEncoder.encode(date,"UTF-8")}&q=${URLEncoder.encode(query,"UTF-8")}"
            val json=JSONObject(request(NativeRequest("GET",path,auth.token),200).body)
            require(json.string("date") == date)
            val tickets=json.getJSONArray("tickets").objects().map(::ticket)
            require(tickets.size<=20 && tickets.map {it.id}.distinct().size==tickets.size)
            NativeLookup(date,json.boolean("more_results"),tickets)
        }
    }
    suspend fun confirm(event: String, date: String, ids: List<Long>, confirmed: Boolean): NativeConfirmation = mutex.withLock {
        val auth=authorize(event,date,"checkins:write")
        val unique=ids.distinct()
        require(confirmed && unique.isNotEmpty() && ids.all {it>0} && unique.size <= scope!!.maxBatchSize)
        decode {
            val body=JSONObject().put("ticket_ids",JSONArray(unique)).put("date",date).put("confirmed",true).toString()
            val json=JSONObject(request(NativeRequest("POST","/api/staff/checkins/confirm",auth.token,body),200).body)
            require(json.string("date")==date)
            val results=json.getJSONArray("results").objects().map { result ->
                val id=result.positiveId("ticket_id") // Rails confirm serializes requested IDs as strings.
                val code=NativeOutcomeCode.entries.find {it.wireValue==result.opt("code")}
                    ?: throw NativeFailure(NativeFailure.Kind.OUTCOME)
                if(result.opt("state")!=code.state.name.lowercase()) throw NativeFailure(NativeFailure.Kind.OUTCOME)
                val state=code.state
                val time=result.optionalString("checked_in_at")?.also { Instant.parse(it) }
                require(state!=NativeState.SUCCESS || time!=null)
                NativeOutcome(id,result.optionalString("attendee"),state,code,result.string("message"),time)
            }
            require(results.map {it.ticketId} == unique)
            NativeConfirmation(date,results)
        }
    }
    private fun parseScope(json: JSONObject): NativeScope {
        val dates=json.getJSONArray("event_dates").strings().onEach {LocalDate.parse(it)}
        val expires=Instant.parse(json.string("expires_at")); val max=json.positiveId("max_batch_size"); require(max in 1..50)
        require(dates.isNotEmpty() && dates.distinct().size==dates.size && expires.isAfter(now()) && max in 1..50)
        return NativeScope(json.string("event"),dates,json.getJSONArray("capabilities").strings().toSet(),expires,max.toInt())
    }
    private fun ticket(json: JSONObject): NativeTicket { require(json.has("checked_in_at")); return NativeTicket(json.positiveId("id"),json.string("attendee_name"),json.string("attendee_email"),json.string("ticket_type"),json.string("order_code"),json.boolean("eligible"),json.optionalString("checked_in_at")?.also {Instant.parse(it)}) }
    private suspend fun <T> decode(block: suspend () -> T): T = try {block()} catch(e: NativeFailure) {throw e} catch(e: CancellationException) {throw e} catch(_: Exception) {throw NativeFailure(NativeFailure.Kind.SCHEMA)}
}
internal fun JSONObject.string(name: String): String = (get(name) as? String) ?: error("string")
internal fun JSONObject.optionalString(name: String): String? = if(!has(name) || isNull(name)) null else string(name)
internal fun JSONObject.boolean(name: String): Boolean = (get(name) as? Boolean) ?: error("boolean")
internal fun JSONObject.positiveId(name: String): Long { val value=get(name); require(value is Int || value is Long || value is String); val raw=value.toString(); require(raw.matches(Regex("[1-9][0-9]*"))); return raw.toLong() }
internal fun JSONArray.strings() = (0 until length()).map { (get(it) as? String) ?: error("string") }
internal fun JSONArray.objects() = (0 until length()).map {getJSONObject(it)}
