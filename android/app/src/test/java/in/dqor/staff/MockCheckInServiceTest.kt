package `in`.dqor.staff

import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class MockCheckInServiceTest {
    private val event=Event("dqor","DQOR","Pune","",listOf("2026-10-08","2026-10-09"),"heritage")
    @Test fun `duplicates do not increment and attendance is scoped to event and day`() = runBlocking {
        val service=MockCheckInService()
        assertEquals(1,service.checkIn(event,event.dates[0],listOf(101,101),true).checkedInCount)
        val retry=service.checkIn(event,event.dates[0],listOf(101),true)
        assertEquals(OutcomeState.DUPLICATE,retry.results.single().state)
        assertEquals(1,retry.checkedInCount)
        assertEquals(OutcomeState.SUCCESS,service.checkIn(event,event.dates[1],listOf(101),true).results.single().state)
        assertEquals(OutcomeState.SUCCESS,service.checkIn(event.copy(id="other"),event.dates[0],listOf(101),true).results.single().state)
    }
    @Test fun `mixed batch preserves outcomes and unknown IDs`() = runBlocking {
        val result=MockCheckInService().checkIn(event,event.dates[0],listOf(101,104,999),true)
        assertEquals(listOf(OutcomeState.SUCCESS,OutcomeState.ERROR,OutcomeState.ERROR),result.results.map { it.state })
        assertEquals(999,result.results.last().ticketId)
        assertEquals(1,result.checkedInCount)
    }
    @Test fun `invalid batch never mutates attendance`() = runBlocking {
        val service=MockCheckInService()
        for(ids in listOf(emptyList(),listOf(101,-1),(1..51).toList())) {
            try { service.checkIn(event,event.dates[0],ids,true); fail("Expected rejection") } catch(_: IllegalArgumentException) { }
        }
        try {service.checkIn(event,event.dates[0],listOf(101),false); fail("Expected confirmation")} catch(_: IllegalArgumentException) {}
        assertEquals(0,service.lookup(event,event.dates[0],"").checkedInCount)
    }
    @Test fun `offline expired and viewer sessions cannot mutate`() = runBlocking {
        val service=MockCheckInService()
        service.offline=true
        try {service.scan(event,event.dates[0],"demo-101"); fail("Expected offline")} catch(_: NotConfirmed) {}
        service.offline=false; service.expired=true
        try {service.scan(event,event.dates[0],"demo-101"); fail("Expected expired")} catch(_: SessionExpired) {}
        service.expired=false; service.role=Role.VIEWER
        try {service.scan(event,event.dates[0],"demo-101"); fail("Expected role rejection")} catch(_: IllegalStateException) {}
        assertEquals(0,service.lookup(event,event.dates[0],"").checkedInCount)
    }
    @Test fun `unknown QR fails and lookup excludes ineligible tickets`() = runBlocking {
        val service=MockCheckInService()
        assertEquals(OutcomeState.ERROR,service.scan(event,event.dates[0],"arbitrary-secret").results.single().state)
        assertEquals(0,service.lookup(event,event.dates[0],"Mira").tickets.size)
        assertEquals("Grace Shah",service.lookup(event,event.dates[0],"grace").tickets.single().name)
    }
}
