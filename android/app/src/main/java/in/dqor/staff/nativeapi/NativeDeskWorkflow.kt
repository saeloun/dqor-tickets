package `in`.dqor.staff.nativeapi

import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class StaffHistoryKind { PREVIEW, LOOKUP, CONFIRMATION }
enum class StaffHistoryStatus(val label: String) { PREVIEW_ONLY("Preview only"), CONFIRMED("Admission confirmed"), ALREADY_ADMITTED("Already admitted"), REJECTED("Not eligible"), UNVERIFIED("Not confirmed"), LOOKUP("Lookup complete") }
data class StaffHistoryEntry(val id: Long, val at: Instant, val event: String, val date: String,
    val kind: StaffHistoryKind, val status: StaffHistoryStatus, val ticketId: Long?, val attendee: String?, val detail: String)

data class ReviewBatch(val event: String, val date: String, val tickets: List<NativeTicket>)
data class NativeDeskState(
    val session: NativeScope? = null, val event: String? = null, val date: String = "",
    val query: String = "", val tickets: List<NativeTicket> = emptyList(), val moreResults: Boolean = false,
    val selected: List<NativeTicket> = emptyList(), val preview: NativePreview? = null,
    val review: ReviewBatch? = null, val results: List<NativeOutcome> = emptyList(),
    val history: List<StaffHistoryEntry> = emptyList(),
    val busy: Boolean = false, val uncertain: Boolean = false,
    val message: String = "Mock transport only. Sign in with a demo identity. No live credentials are needed."
) { val canWrite get() = session?.capabilities?.contains("checkins:write") == true }

/** Shared UI state machine. Only confirmReview can invoke the mutating adapter method.
 * No QR/password is kept in state; reviewed identities survive rotation via the ViewModel. */
class NativeDeskWorkflow(private val client: NativeStaffClient, private val now: () -> Instant = Instant::now) {
    private val mutable = MutableStateFlow(NativeDeskState())
    val state = mutable.asStateFlow()
    private var historySequence=0L
    private fun record(kind: StaffHistoryKind, status: StaffHistoryStatus, ticketId: Long?=null, attendee: String?=null, detail: String) {
        val current=mutable.value; val event=current.event ?: return
        val entry=StaffHistoryEntry(++historySequence,now(),event,current.date,kind,status,ticketId,attendee,detail)
        mutable.value=current.copy(history=(listOf(entry)+current.history).take(100))
    }
    private suspend fun perform(mutation: Boolean = false, historyKind: StaffHistoryKind? = null, block: suspend () -> Unit) {
        if(mutable.value.busy) return
        mutable.value=mutable.value.copy(busy=true)
        try {block()} catch(e: CancellationException) {
            mutable.value=mutable.value.copy(message="Request interrupted. Admission is not confirmed.",uncertain=mutable.value.uncertain || (mutation && mutable.value.review!=null))
            historyKind?.let {record(it,StaffHistoryStatus.UNVERIFIED,detail="Request interrupted; admission not confirmed") }
            throw e
        } catch(e: NativeFailure) {
            if(e.kind in setOf(NativeFailure.Kind.SIGN_IN,NativeFailure.Kind.STORAGE)) mutable.value=NativeDeskState(message=if(mutable.value.session==null && e.kind==NativeFailure.Kind.SIGN_IN) "No active demo session. Sign in to continue." else e.message.orEmpty())
            else {
                mutable.value=mutable.value.copy(message=e.message.orEmpty(),uncertain=mutable.value.uncertain || (mutation && mutable.value.review!=null))
                historyKind?.let {record(it,StaffHistoryStatus.UNVERIFIED,detail=e.message.orEmpty())}
            }
        } catch(_: Exception) {
            mutable.value=mutable.value.copy(message="Not confirmed. No offline queue. Retry the same tickets and date.",uncertain=mutable.value.uncertain || (mutation && mutable.value.review!=null))
            historyKind?.let {record(it,StaffHistoryStatus.UNVERIFIED,detail="Response not verified") }
        } finally {mutable.value=mutable.value.copy(busy=false)}
    }
    suspend fun signIn(readOnly: Boolean = false) = perform {
        val session=client.signIn(if(readOnly) "viewer@demo.invalid" else "desk@demo.invalid","demo-only".toCharArray())
        mutable.value=NativeDeskState(session=session,date=session.eventDates.first(),message="Demo session active. Choose your event.",busy=true)
    }
    suspend fun restore() = perform {
        val session=client.restoreSession()
        val old=mutable.value
        val scopeChanged=old.session?.let {it.event!=session.event || it.eventDates!=session.eventDates || it.capabilities!=session.capabilities} ?: true
        mutable.value=if(scopeChanged) NativeDeskState(session=session,date=session.eventDates.first(),message="Session verified. Preview selections were cleared; no attendance inferred.",busy=true)
            else old.copy(session=session)
    }
    suspend fun logout() = perform {
        val result=client.logout()
        mutable.value=NativeDeskState(message=if(result==LogoutResult.REVOKED) "Signed out. Mock server revocation confirmed." else "Signed out locally. Server revocation was not confirmed.",busy=true)
    }
    fun chooseEvent(event: String?) {
        val old=mutable.value
        if(old.busy || old.uncertain || old.session==null || (event!=null && event!=old.session.event)) return
        mutable.value=old.copy(event=event,selected=emptyList(),review=null,preview=null,results=emptyList(),tickets=emptyList(),message="Preview first, then explicitly confirm attendance.")
    }
    fun chooseDate(date: String) {
        val old=mutable.value
        if(old.busy || old.uncertain || date !in old.session?.eventDates.orEmpty()) return
        mutable.value=old.copy(date=date,selected=emptyList(),review=null,preview=null,results=emptyList(),tickets=emptyList(),message="Date changed. Preview selections cleared.")
    }
    fun setQuery(query: String) { if(!mutable.value.busy) mutable.value=mutable.value.copy(query=query) }
    suspend fun search() = perform(historyKind=StaffHistoryKind.LOOKUP) {
        val old=mutable.value; val event=old.event ?: return@perform
        val response=client.lookup(event,old.date,old.query)
        mutable.value=mutable.value.copy(tickets=response.tickets,moreResults=response.moreResults,message="Search returned ${response.tickets.size} visible tickets. No attendance changed.")
        record(StaffHistoryKind.LOOKUP,StaffHistoryStatus.LOOKUP,detail="${response.tickets.size} visible matches; no attendance changed")
    }
    suspend fun resolve(secret: String) = perform(historyKind=StaffHistoryKind.PREVIEW) {
        val old=mutable.value; val event=old.event ?: return@perform
        if(old.review!=null || old.uncertain) return@perform
        val response=client.resolve(event,old.date,secret)
        val ticket=response.ticket
        val selected=if(old.canWrite && ticket.eligible && ticket.checkedInAt==null && old.selected.size < (old.session?.maxBatchSize ?: 0)) (old.selected+ticket).distinctBy {it.id} else old.selected
        val status=when { !ticket.eligible -> "Ineligible. Do not admit."; ticket.checkedInAt!=null -> "Already checked in for this date."; !old.canWrite -> "Read-only role."; else -> "Preview only. Review and confirm to admit." }
        mutable.value=mutable.value.copy(preview=response,selected=selected,results=emptyList(),message="${ticket.attendeeName}, ticket ${ticket.id}. $status")
        record(StaffHistoryKind.PREVIEW,if(!ticket.eligible) StaffHistoryStatus.REJECTED else if(ticket.checkedInAt!=null) StaffHistoryStatus.ALREADY_ADMITTED else StaffHistoryStatus.PREVIEW_ONLY,ticket.id,ticket.attendeeName,status)
    }
    fun toggle(ticket: NativeTicket) {
        val old=mutable.value
        if(old.busy || old.review!=null || old.uncertain || !old.canWrite || !ticket.eligible) return
        if(ticket !in old.tickets && ticket !in old.selected && ticket!=old.preview?.ticket) return
        val selected=if(old.selected.any {it.id==ticket.id}) old.selected.filterNot {it.id==ticket.id}
            else if(old.selected.size < (old.session?.maxBatchSize ?: 0)) old.selected+ticket else old.selected
        mutable.value=old.copy(selected=selected)
    }
    fun reviewSelection() {
        val old=mutable.value
        if(old.busy || old.uncertain || !old.canWrite || old.selected.isEmpty() || old.event==null) return
        mutable.value=old.copy(review=ReviewBatch(old.event,old.date,old.selected.toList()),results=emptyList(),message="Review names, IDs and date. Nothing has been submitted.")
    }
    fun cancelReview() { if(!mutable.value.busy && !mutable.value.uncertain) mutable.value=mutable.value.copy(review=null) }
    fun discardUncertain() {
        if(!mutable.value.busy) mutable.value=mutable.value.copy(review=null,selected=emptyList(),uncertain=false,message="Unconfirmed response dismissed. This does not undo attendance; search the same tickets/date before admitting.")
    }
    suspend fun confirmReview(expected: ReviewBatch) = perform(mutation=true,historyKind=StaffHistoryKind.CONFIRMATION) {
        val old=mutable.value
        if(old.review !== expected || old.event!=expected.event || old.date!=expected.date || !old.canWrite) return@perform
        val response=client.confirm(expected.event,expected.date,expected.tickets.map {it.id},true)
        mutable.value=mutable.value.copy(results=response.results,review=null,selected=emptyList(),preview=null,uncertain=false,
            message=if(response.results.size==1) response.results.single().let {"${it.attendee ?: "Ticket ${it.ticketId}"}: ${it.message}"} else "${response.results.size} results: ${response.results.count {it.state==NativeState.SUCCESS}} confirmed, ${response.results.count {it.state==NativeState.WARNING}} duplicate warnings, ${response.results.count {it.state==NativeState.ERROR}} rejected. Review each outcome below.")
        response.results.forEach {result -> record(StaffHistoryKind.CONFIRMATION,
            when(result.code) {NativeOutcomeCode.SUCCESS -> StaffHistoryStatus.CONFIRMED; NativeOutcomeCode.DUPLICATE -> StaffHistoryStatus.ALREADY_ADMITTED; else -> StaffHistoryStatus.REJECTED},
            result.ticketId,result.attendee,result.message) }
    }
}
