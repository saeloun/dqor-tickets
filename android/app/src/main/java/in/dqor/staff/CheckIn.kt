package `in`.dqor.staff

import java.time.Instant

data class Event(val id: String, val name: String, val location: String, val subtitle: String, val dates: List<String>, val theme: String)
enum class Role { DESK, ADMIN, VIEWER }
data class Ticket(val id: Int, val name: String, val email: String, val type: String, val eligible: Boolean = true)
enum class OutcomeState { SUCCESS, DUPLICATE, ERROR }
data class Outcome(val ticketId: Int?, val attendee: String?, val state: OutcomeState, val message: String, val checkedInAt: String? = null)
data class Lookup(val date: String, val tickets: List<Ticket>, val checkedInCount: Int, val moreResults: Boolean, val maxBatchSize: Int = 50)
data class CheckInResponse(val results: List<Outcome>, val checkedInCount: Int)
class NotConfirmed : Exception("Not confirmed. No offline queue. Retry the same tickets and date when connected.")
class SessionExpired : Exception("Staff session expired. Sign in again before continuing.")
/** An approved adapter must enforce authentication on the server, validate response schemas,
 * use returned dates/counts, and preserve each result including HTTP 409/404/422 outcomes. */
interface CheckInService {
    suspend fun lookup(event: Event, date: String, query: String): Lookup
    suspend fun checkIn(event: Event, date: String, ids: List<Int>, confirmed: Boolean): CheckInResponse
    suspend fun scan(event: Event, date: String, secret: String): CheckInResponse
}
/** Demo only: no network, credentials, persistence or real attendance mutations. */
class MockCheckInService : CheckInService {
    var offline = false
    var expired = false
    var role = Role.DESK
    private val attendance = mutableMapOf<Triple<String, String, Int>, String>()
    private val tickets = listOf(Ticket(101,"Asha Rao","asha@example.test","Conference"), Ticket(102,"Grace Shah","grace@example.test","Complimentary"), Ticket(103,"Kabir Desai","kabir@example.test","Workshop"), Ticket(104,"Mira Patel","mira@example.test","Canceled", false))
    private fun guard(event: Event, date: String, mutation: Boolean = false) {
        if (offline) throw NotConfirmed()
        if (expired) throw SessionExpired()
        require(date in event.dates) { "Invalid event date" }
        check(!mutation || role != Role.VIEWER) { "This role cannot check in attendees" }
    }
    private fun count(event: Event, date: String) = attendance.keys.count { it.first == event.id && it.second == date }
    override suspend fun lookup(event: Event, date: String, query: String): Lookup {
        guard(event,date)
        val matches = tickets.filter { it.eligible && (it.name.contains(query,true) || it.email.contains(query,true) || it.id.toString() == query) }
        return Lookup(date,matches.take(20),count(event,date),matches.size > 20)
    }
    override suspend fun checkIn(event: Event, date: String, ids: List<Int>, confirmed: Boolean): CheckInResponse {
        guard(event,date,true)
        require(confirmed && ids.isNotEmpty() && ids.all { it > 0 } && ids.distinct().size <= 50) { "Confirm 1–50 explicit tickets" }
        return CheckInResponse(ids.distinct().map { id ->
            val ticket = tickets.find { it.id == id }
            val key = Triple(event.id,date,id)
            when {
                ticket == null -> Outcome(id,null,OutcomeState.ERROR,"Unknown ticket")
                !ticket.eligible -> Outcome(id,ticket.name,OutcomeState.ERROR,"Ticket is not eligible")
                key in attendance -> Outcome(id,ticket.name,OutcomeState.DUPLICATE,"Already checked in for this date",attendance[key])
                else -> { val time = Instant.now().toString(); attendance[key] = time; Outcome(id,ticket.name,OutcomeState.SUCCESS,"Demo check-in confirmed",time) }
            }
        },count(event,date))
    }
    override suspend fun scan(event: Event, date: String, secret: String): CheckInResponse {
        guard(event,date,true)
        val id = when (secret) { "demo-101" -> 101; "demo-102" -> 102; "demo-103" -> 103; "demo-104" -> 104; else -> null }
        return if (id == null) CheckInResponse(listOf(Outcome(null,null,OutcomeState.ERROR,"Unknown demo QR")),count(event,date)) else checkIn(event,date,listOf(id),true)
    }
}
