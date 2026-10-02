package `in`.dqor.staff

import `in`.dqor.staff.nativeapi.*
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class NativeDeskWorkflowTest {
    private class MemoryStore : CredentialStore {
        var saved: StoredCredential? = null
        override suspend fun read()=saved
        override suspend fun write(value: StoredCredential) {saved=value}
        override suspend fun clear() {saved=null}
    }
    private class Fixture {
        var now=Instant.parse("2026-10-02T12:00:00Z")
        val store=MemoryStore()
        val server=MockNativeTransport {now}
        val client=NativeStaffClient(NativeConfig(true,"https://mock.invalid"),server,store) {now}
        val flow=NativeDeskWorkflow(client)
        val state get()=flow.state.value
        suspend fun login(readOnly: Boolean=false) {flow.signIn(readOnly); flow.chooseEvent("dqor-2026")}
        suspend fun reviewSample(): ReviewBatch {flow.resolve("demo-101"); flow.reviewSelection(); return state.review!!}
    }
    @Test fun `login restore and logout use adapter session lifecycle`()=runBlocking {
        val f=Fixture(); f.login(); assertNotNull(f.state.session); assertNotNull(f.store.saved)
        f.flow.restore(); assertNotNull(f.state.session)
        f.flow.logout(); assertNull(f.state.session); assertNull(f.store.saved); assertTrue(f.state.message.contains("revocation confirmed"))
    }
    @Test fun `scan select and review never confirm attendance`()=runBlocking {
        val f=Fixture(); f.login(); f.flow.resolve("demo-101")
        assertEquals(1,f.server.resolveCalls); assertEquals(1,f.state.selected.size)
        assertEquals(0,f.server.confirmationCalls); assertEquals(0,f.server.attendanceCount)
        f.flow.reviewSelection(); assertNotNull(f.state.review); assertEquals(0,f.server.confirmationCalls)
        f.flow.cancelReview(); assertEquals(0,f.server.attendanceCount)
    }
    @Test fun `only current explicitly reviewed snapshot can confirm`()=runBlocking {
        val f=Fixture(); f.login(); val batch=f.reviewSample()
        f.flow.confirmReview(batch.copy()); assertEquals(0,f.server.confirmationCalls)
        f.flow.confirmReview(batch); assertEquals(1,f.server.confirmationCalls); assertEquals(1,f.server.attendanceCount)
        assertEquals(NativeState.SUCCESS,f.state.results.single().state); assertNull(f.state.review)
        f.flow.confirmReview(batch); assertEquals(1,f.server.confirmationCalls)
    }
    @Test fun `date change invalidates an old preview confirmation`()=runBlocking {
        val f=Fixture(); f.login(); val batch=f.reviewSample()
        f.flow.cancelReview(); f.flow.chooseDate("2026-10-09"); f.flow.confirmReview(batch)
        assertEquals(0,f.server.confirmationCalls); assertTrue(f.state.selected.isEmpty())
    }
    @Test fun `stale eligibility is rejected on confirmation`()=runBlocking {
        val f=Fixture(); f.login(); val batch=f.reviewSample(); f.server.invalidatePreview(101)
        f.flow.confirmReview(batch)
        assertEquals(0,f.server.attendanceCount); assertEquals(NativeState.ERROR,f.state.results.single().state)
        assertTrue(f.state.message.contains("Eligibility changed"))
    }
    @Test fun `timeout after commit remains uncertain and retries exact snapshot without duplicate attendance`()=runBlocking {
        val f=Fixture(); f.login(); val batch=f.reviewSample(); f.server.timeoutAfterNextConfirmation=true
        f.flow.confirmReview(batch)
        assertEquals(1,f.server.attendanceCount); assertTrue(f.state.uncertain); assertSame(batch,f.state.review); assertTrue(f.state.results.isEmpty())
        f.flow.chooseDate("2026-10-09"); assertEquals(batch.date,f.state.date)
        f.flow.confirmReview(batch)
        assertEquals(1,f.server.attendanceCount); assertEquals(2,f.server.confirmationCalls)
        assertEquals(NativeState.WARNING,f.state.results.single().state); assertFalse(f.state.uncertain)
    }
    @Test fun `duplicate manual confirmation preserves original attendance`()=runBlocking {
        val f=Fixture(); f.login(); f.flow.confirmReview(f.reviewSample())
        f.flow.search(); val ticket=f.state.tickets.first {it.id==101L}; assertNotNull(ticket.checkedInAt)
        f.flow.toggle(ticket); f.flow.reviewSelection(); f.flow.confirmReview(f.state.review!!)
        assertEquals(NativeState.WARNING,f.state.results.single().state); assertEquals(1,f.server.attendanceCount)
    }
    @Test fun `expired session before confirm drops preview and never admits`()=runBlocking {
        val f=Fixture(); f.login(); val batch=f.reviewSample(); f.server.expireSession=true
        f.flow.confirmReview(batch)
        assertNull(f.state.session); assertNull(f.state.review); assertNull(f.store.saved); assertEquals(0,f.server.attendanceCount)
    }
    @Test fun `local expiry is detected without admission`()=runBlocking {
        val f=Fixture(); f.login(); f.now=f.now.plusSeconds(9*3600); f.flow.restore()
        assertNull(f.state.session); assertNull(f.store.saved); assertEquals(0,f.server.confirmationCalls)
    }
    @Test fun `read only session can preview but cannot select or submit`()=runBlocking {
        val f=Fixture(); f.login(true); f.flow.resolve("demo-101"); f.flow.reviewSelection()
        assertNotNull(f.state.preview); assertFalse(f.state.canWrite); assertTrue(f.state.selected.isEmpty()); assertNull(f.state.review)
        assertEquals(0,f.server.confirmationCalls)
    }
    @Test fun `unknown or ineligible previews never select`()=runBlocking {
        val f=Fixture(); f.login(); f.flow.resolve("unknown"); assertTrue(f.state.selected.isEmpty())
        f.flow.resolve("demo-104"); assertFalse(f.state.preview!!.ticket.eligible); assertTrue(f.state.selected.isEmpty()); assertEquals(0,f.server.attendanceCount)
    }
    @Test fun `failed read only session validation does not invent a mutation`()=runBlocking {
        val f=Fixture(); f.login(); f.reviewSample(); f.server.offline=true; f.flow.restore()
        assertFalse(f.state.uncertain); assertEquals(0,f.server.confirmationCalls)
    }
    @Test fun `unseen stale ticket cannot be selected after date change`()=runBlocking {
        val f=Fixture(); f.login(); f.flow.search(); val old=f.state.tickets.first()
        f.flow.chooseDate("2026-10-09"); f.flow.toggle(old)
        assertTrue(f.state.selected.isEmpty()); assertEquals(0,f.server.confirmationCalls)
    }
    @Test fun `offline logout clears local session and reports unconfirmed revocation`()=runBlocking {
        val f=Fixture(); f.login(); f.server.offline=true; f.flow.logout()
        assertNull(f.state.session); assertNull(f.store.saved); assertTrue(f.state.message.contains("not confirmed"))
    }
    @Test fun `history distinguishes previews confirmation and duplicate without storing QR or search`()=runBlocking {
        val f=Fixture(); f.login(); f.flow.setQuery("asha@example.test"); f.flow.search()
        assertEquals(StaffHistoryStatus.LOOKUP,f.state.history.first().status)
        f.flow.resolve("demo-101"); assertEquals(StaffHistoryStatus.PREVIEW_ONLY,f.state.history.first().status)
        assertEquals(0,f.server.attendanceCount)
        f.flow.reviewSelection(); f.flow.confirmReview(f.state.review!!)
        assertEquals(StaffHistoryStatus.CONFIRMED,f.state.history.first().status)
        f.flow.resolve("demo-101"); assertEquals(StaffHistoryStatus.ALREADY_ADMITTED,f.state.history.first().status)
        assertFalse(f.state.history.toString().contains("demo-101")); assertFalse(f.state.history.toString().contains("asha@example.test"))
        assertTrue(f.state.history.all {it.event=="dqor-2026" && it.date=="2026-10-08"})
    }
    @Test fun `history reports uncertain outcome and later duplicate honestly`()=runBlocking {
        val f=Fixture(); f.login(); val batch=f.reviewSample(); f.server.timeoutAfterNextConfirmation=true
        f.flow.confirmReview(batch); assertEquals(StaffHistoryStatus.UNVERIFIED,f.state.history.first().status)
        f.flow.confirmReview(batch); assertEquals(StaffHistoryStatus.ALREADY_ADMITTED,f.state.history.first().status)
        assertFalse(f.state.history.any {it.status==StaffHistoryStatus.CONFIRMED}); assertEquals(1,f.server.attendanceCount)
    }
    @Test fun `history is bounded scoped by day and cleared on logout and expiry`()=runBlocking {
        val f=Fixture(); f.login(); repeat(105) {f.flow.search()}; assertEquals(100,f.state.history.size)
        assertEquals(100,f.state.history.map {it.id}.distinct().size)
        f.flow.chooseDate("2026-10-09"); f.flow.search(); assertEquals("2026-10-09",f.state.history.first().date)
        f.flow.logout(); assertTrue(f.state.history.isEmpty())
        f.login(); f.flow.resolve("demo-101"); f.server.expireSession=true; f.flow.restore(); assertTrue(f.state.history.isEmpty())
    }
    @Test fun `manual order lookup and wallet QR use distinct contracts`()=runBlocking {
        val f=Fixture(); f.login(); f.flow.setQuery("DEMO-102"); f.flow.search()
        assertEquals(listOf(102L),f.state.tickets.map {it.id})
        f.flow.resolve("DEMO-ONLY:WALLET:sample-pass-asha:NOT-VALID-FOR-ENTRY")
        assertTrue(f.state.selected.isEmpty()); assertEquals(0,f.server.attendanceCount)
    }
}
