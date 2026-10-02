package `in`.dqor.staff.experience

import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import org.json.JSONObject

enum class SessionTrack(val label: String) { TALK("Talks"), WORKSHOP("Workshops"), COMMUNITY("Community") }
data class ProgramSession(val id: String, val eventId: String, val date: String, val startsAt: String, val endsAt: String,
    val title: String, val speaker: String, val venue: String, val track: SessionTrack, val description: String)
enum class AdmissionStatus(val label: String) { NOT_CHECKED_IN("Not checked in"), CHECKED_IN("Checked in"), CANCELED("Canceled"), UNKNOWN("Not verified") }
enum class RedemptionStatus(val label: String) { AVAILABLE("Not redeemed"), REDEEMED("Redeemed"), NOT_INCLUDED("Not included"), UNKNOWN("Not verified") }
enum class EntitlementKind(val label: String) { MEAL("Meal"), PARTY("Party") }
data class DayAdmission(val date: String, val status: AdmissionStatus)
data class PassEntitlement(val id: String, val kind: EntitlementKind, val title: String, val date: String, val status: RedemptionStatus)
data class DemoWalletPass(val id: String, val eventId: String, val attendee: String, val ticketType: String,
    val orderCode: String, val admission: List<DayAdmission>, val entitlements: List<PassEntitlement>) {
    // Deliberately not a staff QR or usable claim token.
    val demoQrPayload get() = "DEMO-ONLY:WALLET:$id:NOT-VALID-FOR-ENTRY"
    fun admissionOn(date: String) = admission.find {it.date==date}?.status ?: AdmissionStatus.UNKNOWN
}

/** Local synthetic content, not inferred network DTOs or attendee authorization. */
class EventExperience(val timeZone: String, private val sessions: List<ProgramSession>, private val passes: List<DemoWalletPass>) {
    fun program(eventId: String, date: String? = null, query: String = "", track: SessionTrack? = null): List<ProgramSession> {
        val term=query.trim()
        return sessions.filter {it.eventId==eventId && (date==null || it.date==date) && (track==null || it.track==track) &&
            (term.isEmpty() || listOf(it.title,it.speaker,it.venue).any {text -> text.contains(term,true)})}
            .sortedWith(compareBy({it.date},{it.startsAt},{it.id}))
    }
    fun wallet(eventId: String) = passes.filter {it.eventId==eventId}
    companion object {
        fun parse(source: String): EventExperience {
            val root=JSONObject(source)
            require(root.getBoolean("demo_only")) {"Only explicitly synthetic fixtures are supported"}
            val zone=root.getString("time_zone"); ZoneId.of(zone)
            val sessions=root.getJSONArray("sessions").let {array -> (0 until array.length()).map {index ->
                val row=array.getJSONObject(index)
                ProgramSession(row.getString("id"),row.getString("event_id"),row.getString("date"),row.getString("starts_at"),row.getString("ends_at"),row.getString("title"),row.getString("speaker"),row.getString("venue"),SessionTrack.valueOf(row.getString("track")),row.getString("description")).also {
                    LocalDate.parse(it.date); require(LocalTime.parse(it.startsAt)<LocalTime.parse(it.endsAt))
                }
            }}
            val passes=root.getJSONArray("passes").let {array -> (0 until array.length()).map {index ->
                val row=array.getJSONObject(index)
                val admission=row.getJSONArray("admission").let {days -> (0 until days.length()).map {i -> days.getJSONObject(i).let {day -> DayAdmission(day.getString("date"),AdmissionStatus.valueOf(day.getString("status"))).also {LocalDate.parse(it.date)} } } }
                val entitlements=row.getJSONArray("entitlements").let {items -> (0 until items.length()).map {i -> items.getJSONObject(i).let {item -> PassEntitlement(item.getString("id"),EntitlementKind.valueOf(item.getString("kind")),item.getString("title"),item.getString("date"),RedemptionStatus.valueOf(item.getString("status"))).also {LocalDate.parse(it.date)} } } }
                require(admission.isNotEmpty())
                require(admission.map {it.date}.distinct().size==admission.size)
                require(entitlements.map {it.id}.distinct().size==entitlements.size)
                DemoWalletPass(row.getString("id"),row.getString("event_id"),row.getString("attendee"),row.getString("ticket_type"),row.getString("order_code"),admission,entitlements)
            }}
            require(sessions.map {it.id}.distinct().size==sessions.size)
            require(passes.map {it.id}.distinct().size==passes.size)
            return EventExperience(zone,sessions,passes)
        }
    }
}
