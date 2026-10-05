package `in`.dqor.staff.programme

import java.net.URI
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject

data class PublicEvent(val id: String, val title: String, val startDate: LocalDate, val endDate: LocalDate, val timezone: ZoneId, val venue: String, val publicUrl: String)
data class PublicSession(val id: String, val title: String, val abstract: String?, val startsAt: OffsetDateTime?, val endsAt: OffsetDateTime?, val localDate: LocalDate?, val speakerId: String?, val speakerName: String?, val room: String?) {
    fun timeLabel(zone: ZoneId): String {
        val format=DateTimeFormatter.ofPattern("HH:mm",java.util.Locale.ENGLISH)
        val start=startsAt?.atZoneSameInstant(zone)?.format(format) ?: return "Time to be announced"
        return endsAt?.atZoneSameInstant(zone)?.format(format)?.let {"$start – $it"} ?: "$start · end to be announced"
    }
}
data class PublicSpeaker(val id: String, val name: String, val title: String?, val bio: String?, val profileUrl: String)
data class PublicProgramme(val contentVersion: String, val event: PublicEvent, val sessions: List<PublicSession>, val speakers: List<PublicSpeaker>) {
    companion object {
        fun parse(body: String): PublicProgramme {
            val root=JSONObject(body)
            require(root.get("schema_version") is Int && root.getInt("schema_version")==1)
            val version=root.text("content_version"); require(version.matches(Regex("[a-f0-9]{64}")))
            val e=root.getJSONObject("event")
            val event=PublicEvent(e.text("id"),e.text("title"),LocalDate.parse(e.text("start_date")),LocalDate.parse(e.text("end_date")),ZoneId.of(e.text("timezone")),e.text("venue"),e.url("public_url"))
            require(event.id=="dqor-2026" && event.timezone.id=="Asia/Kolkata" && event.startDate<=event.endDate)
            val sessions=root.getJSONArray("sessions").let {a -> (0 until a.length()).map { i -> val s=a.getJSONObject(i)
                PublicSession(s.text("id"),s.text("title"),s.nullableText("abstract"),s.nullableText("starts_at")?.let(OffsetDateTime::parse),s.nullableText("ends_at")?.let(OffsetDateTime::parse),s.nullableText("local_date")?.let(LocalDate::parse),s.nullableText("speaker_id"),s.nullableText("speaker_name"),s.nullableText("room")).also {
                    require(it.id.matches(Regex("[1-9][0-9]*")))
                    require(it.localDate==it.startsAt?.atZoneSameInstant(event.timezone)?.toLocalDate())
                    require(it.startsAt==null || it.endsAt==null || !it.endsAt.isBefore(it.startsAt))
                }
            }}
            val speakers=root.getJSONArray("speakers").let {a -> (0 until a.length()).map { i -> val s=a.getJSONObject(i)
                PublicSpeaker(s.text("id"),s.text("name"),s.nullableText("title"),s.nullableText("bio"),s.url("profile_url"))
            }}
            require(sessions.map {it.id}.distinct().size==sessions.size && speakers.map {it.id}.distinct().size==speakers.size)
            require(sessions.all {it.speakerId==null || speakers.any {speaker -> speaker.id==it.speakerId}})
            return PublicProgramme(version,event,sessions,speakers)
        }
    }
}
private fun JSONObject.text(key: String): String = get(key).let {require(it is String); it}
private fun JSONObject.nullableText(key: String): String? = get(key).let {if(it===JSONObject.NULL) null else {require(it is String); it}}
private fun JSONObject.url(key: String): String = text(key).also {require(URI(it).isAbsolute)}

/** No origin, cookies, authorization or networking implementation. */
data class ProgrammeRequest(val ifNoneMatch: String? = null) { val path: String get()="/api/public/v1/dqor/programme" }
data class ProgrammeResponse(val status: Int, val etag: String? = null, val body: String = "")
fun interface ProgrammeTransport { suspend fun fetch(request: ProgrammeRequest): ProgrammeResponse }
enum class ProgrammeProblem { OFFLINE, UNAVAILABLE, INVALID_RESPONSE }
data class ProgrammeState(val snapshot: PublicProgramme? = null, val etag: String? = null, val loading: Boolean = false, val problem: ProgrammeProblem? = null) {
    val stale: Boolean get()=snapshot!=null && problem!=null
}
class ProgrammeOfflineException: java.io.IOException()

/** Memory-only cache. Every refresh revalidates; 200 atomically replaces both arrays. */
class PublicProgrammeClient(private val transport: ProgrammeTransport) {
    private val mutable=MutableStateFlow(ProgrammeState())
    val state=mutable.asStateFlow()
    private val mutex=Mutex()
    suspend fun refresh()=mutex.withLock {
        val before=mutable.value
        mutable.value=before.copy(loading=true)
        try {
            val validator=before.etag.takeIf {before.snapshot!=null}
            var response=transport.fetch(ProgrammeRequest(validator))
            var retried=false
            if(response.status==304 && (validator==null || (response.etag!=null && response.etag!=validator))) {
                retried=true
                response=transport.fetch(ProgrammeRequest())
            }
            when(response.status) {
                200 -> {
                    val snapshot=PublicProgramme.parse(response.body)
                    val etag=response.etag?.also {require(it.matches(Regex("(?:W/)?\"[^\"\\r\\n]*\"")))}
                    mutable.value=ProgrammeState(snapshot,etag)
                }
                304 -> {
                    require(!retried && validator!=null && before.snapshot!=null && (response.etag==null || response.etag==validator))
                    mutable.value=before.copy(loading=false,problem=null)
                }
                503 -> {
                    val error=JSONObject(response.body)
                    require(error.get("schema_version") is Int && error.getInt("schema_version")==1 && error.getJSONObject("error").text("code")=="programme_unavailable")
                    mutable.value=before.copy(loading=false,problem=ProgrammeProblem.UNAVAILABLE)
                }
                else -> mutable.value=before.copy(loading=false,problem=ProgrammeProblem.INVALID_RESPONSE)
            }
        } catch(cancelled: CancellationException) {
            mutable.value=before; throw cancelled
        } catch(_: java.io.IOException) {
            mutable.value=before.copy(loading=false,problem=ProgrammeProblem.OFFLINE)
        } catch(_: Exception) {
            mutable.value=before.copy(loading=false,problem=ProgrammeProblem.INVALID_RESPONSE)
        }
    }
}

/** Explicit synthetic scenarios; never delegates to HTTP. */
class DemoProgrammeTransport(private val fixture: String): ProgrammeTransport {
    enum class Scenario { PUBLISHED, UNCHANGED, EMPTY, OFFLINE, UNAVAILABLE }
    var scenario=Scenario.PUBLISHED
    override suspend fun fetch(request: ProgrammeRequest): ProgrammeResponse = when(scenario) {
        Scenario.PUBLISHED -> ProgrammeResponse(200,"W/\"synthetic-v1\"",fixture)
        Scenario.UNCHANGED -> if(request.ifNoneMatch=="W/\"synthetic-v1\"") ProgrammeResponse(304,"W/\"synthetic-v1\"") else ProgrammeResponse(200,"W/\"synthetic-v1\"",fixture)
        Scenario.EMPTY -> ProgrammeResponse(200,"\"synthetic-empty\"",JSONObject(fixture).put("content_version","0".repeat(64)).put("sessions",org.json.JSONArray()).put("speakers",org.json.JSONArray()).toString())
        Scenario.OFFLINE -> throw ProgrammeOfflineException()
        Scenario.UNAVAILABLE -> ProgrammeResponse(503,body="""{"schema_version":1,"error":{"code":"programme_unavailable","message":"Programme temporarily unavailable. Try again later."}}""")
    }
}
