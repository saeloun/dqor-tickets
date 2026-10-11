package `in`.dqor.staff.owned

import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

data class OwnedEvent(val id: String, val title: String, val startsAt: OffsetDateTime, val endsAt: OffsetDateTime, val startDate: LocalDate, val endDate: LocalDate, val timezone: ZoneId, val organizer: String, val organizerSlug: String, val detailsPath: String) {
    val website: String get() = OwnedEventsHttp.ORIGIN + detailsPath
    companion object {
        fun validId(id: String) = id.matches(Regex("hosted-event-[1-9][0-9]{0,18}")) && id.removePrefix("hosted-event-").toLongOrNull() != null
        fun parse(root: JSONObject): OwnedEvent {
            root.keysExactly("id", "ownership", "title", "starts_at", "ends_at", "start_date", "end_date", "timezone", "organizer", "details_path")
            val id = root.text("id"); require(validId(id) && root.text("ownership") == "hosted_event")
            val title = root.text("title"); require(title.isNotBlank() && title.codePointCount(0, title.length) <= 255)
            val organization = root.getJSONObject("organizer"); organization.keysExactly("name", "slug")
            val name = organization.text("name"); require(name.isNotBlank() && name.codePointCount(0, name.length) <= 255)
            val slug = organization.text("slug"); require(slug.matches(Regex("[a-z0-9]+(?:-[a-z0-9]+)*")))
            val path = root.text("details_path"); require(path.matches(Regex("/events/$slug/[a-z0-9]+(?:-[a-z0-9]+)*")))
            val zoneName = root.text("timezone"); require(zoneName in ZoneId.getAvailableZoneIds()); val zone = ZoneId.of(zoneName)
            val start = OffsetDateTime.parse(root.text("starts_at")); val end = OffsetDateTime.parse(root.text("ends_at")); require(!end.toInstant().isBefore(start.toInstant()))
            val first = LocalDate.parse(root.text("start_date")); val last = LocalDate.parse(root.text("end_date"))
            require(start.atZoneSameInstant(zone).toLocalDate() == first && end.atZoneSameInstant(zone).toLocalDate() == last)
            return OwnedEvent(id, title, start, end, first, last, zone, name, slug, path)
        }
    }
}
sealed interface OwnedResource {
    data class Catalog(val page: Int = 1): OwnedResource
    data class Detail(val id: String): OwnedResource
    fun path(): String = when(this) {
        is Catalog -> { require(page in 1..1000); "/api/public/v1/events?page=$page" }
        is Detail -> { require(OwnedEvent.validId(id)); "/api/public/v1/events/$id" }
    }
}
data class OwnedCatalog(val events: List<OwnedEvent>, val page: Int, val total: Long)
data class OwnedResponse(val status: Int, val etag: String? = null, val body: String = "")
fun interface OwnedTransport { suspend fun fetch(resource: OwnedResource, validator: String?): OwnedResponse }
enum class OwnedProblem { UNAVAILABLE, INVALID_RESPONSE, UNSUPPORTED_SCHEMA }
data class OwnedState(val catalog: OwnedCatalog? = null, val event: OwnedEvent? = null, val stale: Boolean = true, val unavailable: Boolean = false, val problem: OwnedProblem? = null)
class OwnedEventsClient(private val transport: OwnedTransport, private val decoder: (OwnedResource, String) -> OwnedState = OwnedSnapshotDecoder::parse) {
    private val lock = Any()
    private val cache = linkedMapOf<OwnedResource, OwnedState>()
    private val validators = mutableMapOf<OwnedResource, String>()
    private val pending = mutableSetOf<OwnedResource>()
    private var generation = 0
    fun state(resource: OwnedResource): OwnedState = synchronized(lock) { cache[resource] ?: OwnedState() }
    fun cancelPending() = synchronized(lock) { generation++; pending.clear() }
    fun clear() = synchronized(lock) { cancelPending(); cache.clear(); validators.clear() }
    fun background() = synchronized(lock) { cancelPending(); cache.replaceAll { _, state -> state.copy(stale = true) } }
    private fun remember(resource: OwnedResource, state: OwnedState) {
        cache.remove(resource); cache[resource] = state
        while(cache.size > 8) { val old = cache.keys.first(); cache.remove(old); validators.remove(old) }
    }
    suspend fun refresh(resource: OwnedResource): OwnedState {
        resource.path()
        val current: Int
        val before: OwnedState
        val validator: String?
        synchronized(lock) {
            check(pending.add(resource))
            current = generation; before = state(resource)
            validator = validators[resource].takeIf { before.catalog != null || before.event != null }
        }
        try {
            var response = transport.fetch(resource, validator)
            synchronized(lock) { if(current != generation) throw CancellationException() }
            if(response.status == 304 && validator == null) {
                response = transport.fetch(resource, null)
                synchronized(lock) { if(current != generation) throw CancellationException() }
            }
            val decoded = if(response.status == 200) withContext(Dispatchers.Default) { decoder(resource, response.body) } else null
            return synchronized(lock) {
                if(current != generation) throw CancellationException()
                when(response.status) {
                    304 -> {
                        require(validator != null && (response.etag == null || response.etag == validator))
                        before.copy(stale = false, problem = null).also { remember(resource, it) }
                    }
                    404 -> {
                        cancelPending()
                        if(resource is OwnedResource.Catalog) { cache.clear(); validators.clear() }
                        else cache.keys.filterIsInstance<OwnedResource.Catalog>().forEach { cache.remove(it); validators.remove(it) }
                        validators.remove(resource)
                        OwnedState(stale = false, unavailable = true).also { remember(resource, it) }
                    }
                    200 -> {
                        val next = requireNotNull(decoded)
                        remember(resource, next)
                        validators.remove(resource)
                        response.etag?.takeIf(::validEtag)?.let { validators[resource] = it }
                        next
                    }
                    503 -> before.copy(stale = true, problem = OwnedProblem.UNAVAILABLE).also { remember(resource, it) }
                    else -> before.copy(stale = true, problem = OwnedProblem.INVALID_RESPONSE).also { remember(resource, it) }
                }
            }
        } catch(cancelled: CancellationException) { throw cancelled }
        catch(error: Exception) {
            return synchronized(lock) {
                if(current != generation) throw CancellationException()
                before.copy(stale = true, problem = if(error is UnsupportedOperationException) OwnedProblem.UNSUPPORTED_SCHEMA else if(error is java.io.IOException) OwnedProblem.UNAVAILABLE else OwnedProblem.INVALID_RESPONSE).also { remember(resource, it) }
            }
        } finally { synchronized(lock) { if(current == generation) pending.remove(resource) } }
    }
    companion object {
        fun validEtag(value: String): Boolean {
            val prefix = if(value.startsWith("W/\"")) 3 else if(value.startsWith("\"")) 1 else return false
            return value.length in (prefix + 2)..256 && value.endsWith('"') && value.substring(prefix, value.length - 1).all { it.code in 33..126 && it != '"' && it != '\\' }
        }
    }
}
internal object OwnedSnapshotDecoder {
    fun parse(resource: OwnedResource, body: String): OwnedState {
        require(body.toByteArray(Charsets.UTF_8).size <= OwnedEventsHttp.MAX_BODY)
        val root = JSONObject(body)
        require(root.get("schema_version") is Int)
        if(root.getInt("schema_version") != 1) throw UnsupportedOperationException()
        require(root.text("content_version").matches(Regex("[a-f0-9]{64}")))
        return when(resource) {
            is OwnedResource.Catalog -> {
                root.keysExactly("schema_version", "content_version", "events", "pagination")
                val pagination = root.getJSONObject("pagination"); pagination.keysExactly("page", "per_page", "total")
                require(pagination.get("page") is Int && pagination.getInt("page") == resource.page && pagination.get("per_page") is Int && pagination.getInt("per_page") == 24)
                require(pagination.get("total") is Int || pagination.get("total") is Long)
                val total = pagination.getLong("total"); require(total >= 0)
                val rows = root.getJSONArray("events"); require(rows.length() <= 24 && rows.length().toLong() <= total)
                val events = (0 until rows.length()).map { OwnedEvent.parse(rows.getJSONObject(it)) }; require(events.map { it.id }.distinct().size == events.size)
                OwnedState(catalog = OwnedCatalog(events, resource.page, total), stale = false)
            }
            is OwnedResource.Detail -> {
                root.keysExactly("schema_version", "content_version", "event")
                val event = OwnedEvent.parse(root.getJSONObject("event")); require(event.id == resource.id)
                OwnedState(event = event, stale = false)
            }
        }
    }
}
private fun JSONObject.text(key: String): String = get(key).let { require(it is String); it }
private fun JSONObject.keysExactly(vararg keys: String) { require(keys().asSequence().toSet() == keys.toSet()) }
