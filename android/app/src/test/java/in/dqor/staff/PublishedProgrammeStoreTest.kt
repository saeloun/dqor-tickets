package `in`.dqor.staff

import `in`.dqor.staff.programme.*
import kotlinx.coroutines.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.time.Instant

class PublishedProgrammeStoreTest {
    private fun fixture()=javaClass.classLoader!!.getResource("public_programme_example.json")!!.readText()
    @Test fun exactValidator304AndCheckTimeAdvance()=runBlocking {
        var clock=Instant.parse("2026-10-03T10:00:00Z")
        val requests=mutableListOf<ProgrammeRequest>()
        val store=PublishedProgrammeStore({requests+=it; if(requests.size==1) ProgrammeResponse(200,"W/\"a\"",fixture()) else ProgrammeResponse(304,"W/\"a\"")},{clock})
        store.refresh(); val first=store.state.value.snapshot
        store.markUnverified(); assertTrue(store.state.value.stale)
        clock=clock.plusSeconds(60); store.refresh()
        assertSame(first,store.state.value.snapshot); assertEquals("W/\"a\"",requests.last().ifNoneMatch)
        assertFalse(store.state.value.stale); assertEquals(clock,store.state.value.checkedAt)
    }
    @Test fun authoritativeEmptyReplacesBothArrays()=runBlocking {
        var body=fixture();val store=PublishedProgrammeStore(transport=ProgrammeTransport {ProgrammeResponse(200,body=body)})
        store.refresh();body=JSONObject(body).put("sessions",org.json.JSONArray()).put("speakers",org.json.JSONArray()).toString();store.refresh()
        assertTrue(store.state.value.snapshot!!.sessions.isEmpty());assertTrue(store.state.value.snapshot!!.speakers.isEmpty())
    }
    @Test fun clearDoesNotWaitForOldReadAndLateResponseCannotRestore()=runBlocking {
        val old=CompletableDeferred<ProgrammeResponse>();var requests=0
        val store=PublishedProgrammeStore(transport=ProgrammeTransport {requests++;if(requests==1) withContext(NonCancellable) {old.await()} else ProgrammeResponse(200,"\"new\"",fixture())})
        val first=launch(start=CoroutineStart.UNDISPATCHED) {store.refresh()}
        assertTrue(store.state.value.loading);store.clear();first.cancel()
        assertNull(store.state.value.snapshot);assertNull(store.state.value.etag)
        store.refresh();assertEquals("\"new\"",store.state.value.etag)
        val newest=store.state.value.snapshot
        old.complete(ProgrammeResponse(200,"\"old\"",fixture()));first.join()
        assertSame(newest,store.state.value.snapshot);assertEquals("\"new\"",store.state.value.etag);assertEquals(2,requests)
    }
    @Test fun backgroundInvalidatesLateReadAndRetainsTruthfulCache()=runBlocking {
        val pending=CompletableDeferred<ProgrammeResponse>();var requests=0
        val store=PublishedProgrammeStore(transport=ProgrammeTransport {requests++;if(requests==1) ProgrammeResponse(200,"\"first\"",fixture()) else pending.await()})
        store.refresh();val first=store.state.value.snapshot
        val job=launch(start=CoroutineStart.UNDISPATCHED) {store.refresh()}
        store.markUnverified();pending.complete(ProgrammeResponse(200,"\"late\"",fixture()));job.join()
        assertSame(first,store.state.value.snapshot);assertEquals("\"first\"",store.state.value.etag);assertTrue(store.state.value.stale)
    }
    @Test fun repeatedRefreshDoesNotQueueRequests()=runBlocking {
        val pending=CompletableDeferred<ProgrammeResponse>();var requests=0
        val store=PublishedProgrammeStore(transport=ProgrammeTransport {requests++;pending.await()})
        val job=launch(start=CoroutineStart.UNDISPATCHED) {store.refresh()}
        store.refresh();store.refresh();assertEquals(1,requests)
        pending.complete(ProgrammeResponse(200,body=fixture()));job.join();assertFalse(store.state.value.loading)
    }
    @Test fun coldOfflineDoesNotInventProgrammeAndCachedOfflineStaysStale()=runBlocking {
        var online=false;val store=PublishedProgrammeStore(transport=ProgrammeTransport {if(!online) throw ProgrammeOfflineException() else ProgrammeResponse(200,body=fixture())})
        store.refresh();assertNull(store.state.value.snapshot);assertEquals(ProgrammeProblem.OFFLINE,store.state.value.problem)
        online=true;store.refresh();val first=store.state.value.snapshot
        online=false;store.refresh();assertSame(first,store.state.value.snapshot);assertTrue(store.state.value.stale)
    }
    @Test fun invalidOriginOrSchemaCannotPoisonPriorSnapshot()=runBlocking {
        var body=fixture();val store=PublishedProgrammeStore(transport=ProgrammeTransport {ProgrammeResponse(200,body=body)})
        store.refresh();val first=store.state.value.snapshot
        body=JSONObject(body).apply {getJSONObject("event").put("public_url","https://other.invalid")}.toString();store.refresh()
        assertSame(first,store.state.value.snapshot);assertTrue(store.state.value.stale);assertEquals(ProgrammeProblem.INVALID_RESPONSE,store.state.value.problem)
    }
    @Test fun orphan304RevalidatesWithoutCondition()=runBlocking {
        var requests=0;val store=PublishedProgrammeStore(transport=ProgrammeTransport {assertNull(it.ifNoneMatch);requests++;if(requests==1) ProgrammeResponse(304) else ProgrammeResponse(200,body=fixture())})
        store.refresh();assertEquals(2,requests);assertNotNull(store.state.value.snapshot)
    }
    @Test fun mismatched304DoesNotBlessCachedVersion()=runBlocking {
        val responses=ArrayDeque(listOf(ProgrammeResponse(200,"\"a\"",fixture()),ProgrammeResponse(304,"\"b\""),ProgrammeResponse(304)))
        val store=PublishedProgrammeStore(transport=ProgrammeTransport {responses.removeFirst()})
        store.refresh();val first=store.state.value.snapshot;store.refresh()
        assertSame(first,store.state.value.snapshot);assertTrue(store.state.value.stale);assertEquals(ProgrammeProblem.INVALID_RESPONSE,store.state.value.problem)
    }
    @Test fun cancellationDoesNotInventConnectivityFailure()=runBlocking {
        val pending=CompletableDeferred<ProgrammeResponse>();val store=PublishedProgrammeStore(transport=ProgrammeTransport {pending.await()})
        val job=launch(start=CoroutineStart.UNDISPATCHED) {store.refresh()};job.cancelAndJoin()
        assertNull(store.state.value.snapshot);assertNull(store.state.value.problem);assertFalse(store.state.value.loading)
    }
}
