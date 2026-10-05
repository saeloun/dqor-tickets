package `in`.dqor.staff

import `in`.dqor.staff.programme.*
import kotlinx.coroutines.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class PublicProgrammeTest {
    private fun fixture()=javaClass.classLoader!!.getResource("public_programme_example.json")!!.readText()
    private fun edited(change: (JSONObject)->Unit)=JSONObject(fixture()).also(change).toString()
    private fun run(block: suspend CoroutineScope.()->Unit) {runBlocking(block=block)}
    @Test fun parsesNullsOpaqueIdsAndExplicitTimezone() {
        val data=PublicProgramme.parse(fixture())
        assertEquals("101",data.sessions.first().id)
        assertEquals("Asia/Kolkata",data.event.timezone.id)
        assertEquals("10:20 – 10:30",data.sessions.first().timeLabel(data.event.timezone))
        assertNull(data.sessions[1].localDate)
        assertEquals("Time to be announced",data.sessions[1].timeLabel(data.event.timezone))
    }
    @Test fun convertsOffsetsUsingEventZoneNotDeviceZone() {
        val data=PublicProgramme.parse(edited {it.getJSONArray("sessions").getJSONObject(0).put("starts_at","2026-10-08T04:50:00Z")})
        assertEquals("10:20 – 10:30",data.sessions.first().timeLabel(data.event.timezone))
    }
    @Test fun nullableEndDoesNotInventDuration() {
        val data=PublicProgramme.parse(edited {it.getJSONArray("sessions").getJSONObject(0).put("ends_at",JSONObject.NULL)})
        assertEquals("10:20 · end to be announced",data.sessions.first().timeLabel(data.event.timezone))
    }
    @Test fun rejectsWrongSchemaTypesAndInvalidTimes() {
        val bad=listOf<(JSONObject)->Unit>(
            {it.put("schema_version",2)}, {it.put("schema_version","1")},
            {it.getJSONArray("sessions").getJSONObject(0).put("id",101)},
            {it.getJSONArray("sessions").getJSONObject(0).remove("abstract")},
            {it.getJSONArray("sessions").getJSONObject(0).put("starts_at","2026-10-08T10:20:00")},
            {it.getJSONArray("sessions").getJSONObject(0).put("local_date","2026-10-09")},
            {it.getJSONObject("event").put("timezone","UTC")})
        bad.forEach {change -> assertThrows(Exception::class.java) {PublicProgramme.parse(edited(change))}}
    }
    @Test fun toleratesAdditiveFieldsAndTreatsTextLiterally() {
        val data=PublicProgramme.parse(edited {it.put("future",true);it.getJSONArray("sessions").getJSONObject(0).put("title","<b>Text</b>")})
        assertEquals("<b>Text</b>",data.sessions[0].title)
    }
    @Test fun conditional304KeepsSnapshotAndExactWeakValidator()=run {
        val requests=mutableListOf<ProgrammeRequest>()
        val client=PublicProgrammeClient {r -> requests+=r; if(requests.size==1) ProgrammeResponse(200,"W/\"value\"",fixture()) else ProgrammeResponse(304)}
        client.refresh(); val first=client.state.value.snapshot; client.refresh()
        assertNull(requests[0].ifNoneMatch); assertEquals("W/\"value\"",requests[1].ifNoneMatch)
        assertSame(first,client.state.value.snapshot); assertNull(client.state.value.problem)
    }
    @Test fun orphan304RetriesWithoutConditionAndDoesNotInventEmpty()=run {
        var calls=0
        val client=PublicProgrammeClient {r -> assertNull(r.ifNoneMatch); calls++; if(calls==1) ProgrammeResponse(304) else ProgrammeResponse(200,body=fixture())}
        client.refresh(); assertEquals(2,calls); assertEquals(2,client.state.value.snapshot!!.sessions.size)
    }
    @Test fun repeatedOrMismatched304NeverRevalidatesWrongSnapshot()=run {
        val replies=ArrayDeque(listOf(ProgrammeResponse(200,"\"a\"",fixture()),ProgrammeResponse(304,"\"b\""),ProgrammeResponse(304,"\"a\"")))
        val requests=mutableListOf<ProgrammeRequest>()
        val client=PublicProgrammeClient {requests+=it; replies.removeFirst()}
        client.refresh(); client.refresh()
        assertNull(requests.last().ifNoneMatch); assertTrue(client.state.value.stale)
    }
    @Test fun authoritativeEmptyRemovesSessionsAndSpeakers()=run {
        val demo=DemoProgrammeTransport(fixture()); val client=PublicProgrammeClient(demo)
        client.refresh(); demo.scenario=DemoProgrammeTransport.Scenario.EMPTY; client.refresh()
        assertTrue(client.state.value.snapshot!!.sessions.isEmpty()); assertTrue(client.state.value.snapshot!!.speakers.isEmpty())
        assertFalse(client.state.value.stale)
    }
    @Test fun authoritativeEditReplacesRatherThanMerges()=run {
        var body=fixture(); val client=PublicProgrammeClient {ProgrammeResponse(200,body=body)}
        client.refresh()
        body=edited {it.getJSONArray("sessions").remove(1);it.getJSONArray("sessions").getJSONObject(0).put("title","Edited")}
        client.refresh(); assertEquals(listOf("Edited"),client.state.value.snapshot!!.sessions.map {it.title})
    }
    @Test fun offlineAnd503RetainSnapshotAndRecoverVia304()=run {
        val demo=DemoProgrammeTransport(fixture()); val client=PublicProgrammeClient(demo)
        client.refresh(); val original=client.state.value.snapshot
        for(scenario in listOf(DemoProgrammeTransport.Scenario.OFFLINE,DemoProgrammeTransport.Scenario.UNAVAILABLE)) {
            demo.scenario=scenario; client.refresh(); assertTrue(client.state.value.stale); assertSame(original,client.state.value.snapshot)
        }
        demo.scenario=DemoProgrammeTransport.Scenario.UNCHANGED; client.refresh(); assertFalse(client.state.value.stale); assertSame(original,client.state.value.snapshot)
    }
    @Test fun initialOfflineHasNoInventedSnapshot()=run {
        val client=PublicProgrammeClient {throw ProgrammeOfflineException()}; client.refresh()
        assertNull(client.state.value.snapshot); assertEquals(ProgrammeProblem.OFFLINE,client.state.value.problem)
    }
    @Test fun malformedResponseCannotPoisonCacheOrValidator()=run {
        var response=ProgrammeResponse(200,"\"good\"",fixture()); val client=PublicProgrammeClient {response}
        client.refresh(); response=ProgrammeResponse(200,"\"bad\"",edited {it.put("schema_version",9)})
        client.refresh(); assertEquals("\"good\"",client.state.value.etag); assertTrue(client.state.value.stale)
    }
    @Test fun unknown503IsInvalidResponse()=run {
        val client=PublicProgrammeClient {ProgrammeResponse(503,body="{}")}; client.refresh()
        assertEquals(ProgrammeProblem.INVALID_RESPONSE,client.state.value.problem)
    }
    @Test fun loadingRetainsSnapshotAndCancellationRestoresPriorState()=run {
        var suspendFetch=false
        val entered=CompletableDeferred<Unit>()
        val client=PublicProgrammeClient {if(suspendFetch) {entered.complete(Unit); awaitCancellation()} else ProgrammeResponse(200,body=fixture())}
        client.refresh(); val before=client.state.value; suspendFetch=true
        val job=launch {client.refresh()}; entered.await()
        assertTrue(client.state.value.loading); assertSame(before.snapshot,client.state.value.snapshot)
        job.cancelAndJoin(); assertEquals(before,client.state.value)
    }
}
