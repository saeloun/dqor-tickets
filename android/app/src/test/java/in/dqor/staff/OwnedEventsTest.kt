package `in`.dqor.staff

import `in`.dqor.staff.owned.*
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class OwnedEventsTest {
    private val catalog get() = File("src/debug/assets/owned_events_catalog.json").readText()
    private val detail get() = File("src/debug/assets/owned_event_detail.json").readText()
    private val tag = "W/\"synthetic-owned\""
    private val resource = OwnedResource.Catalog()
    private class Queue(val replies: MutableList<OwnedResponse>): OwnedTransport {
        val validators = mutableListOf<String?>()
        override suspend fun fetch(resource: OwnedResource, validator: String?): OwnedResponse { validators.add(validator); return replies.removeAt(0) }
    }
    private fun response(status: Int = 200, body: String = catalog, etag: String? = tag) = OwnedResponse(status, etag, body)
    @Test fun catalogAndDetailPreserveOrganizerLocalDatesAndFixedWebsite() = runBlocking {
        val client = OwnedEventsClient(Queue(mutableListOf(response(), response(body = detail))))
        val rows = client.refresh(resource).catalog!!
        assertEquals(1L, rows.total); assertEquals("Synthetic organizers", rows.events[0].organizer)
        assertEquals("2026-11-07", rows.events[0].startDate.toString())
        val event = client.refresh(OwnedResource.Detail("hosted-event-101")).event!!
        assertEquals(rows.events[0], event)
        assertEquals("https://deccanqueenonrails.com/events/synthetic-organizers/synthetic-meetup", event.website)
    }
    @Test fun unavailablePreservesStaleRowsAnd304RecoversExactValidator() = runBlocking {
        val queue = Queue(mutableListOf(response(), response(503), response(304, body = "")))
        val client = OwnedEventsClient(queue); val first = client.refresh(resource)
        val failed = client.refresh(resource); assertEquals(first.catalog, failed.catalog); assertTrue(failed.stale); assertEquals(OwnedProblem.UNAVAILABLE, failed.problem)
        val next = client.refresh(resource); assertFalse(next.stale); assertNull(next.problem)
        assertEquals(listOf(null, tag, tag), queue.validators)
    }
    @Test fun detailWithdrawalClearsCatalogAndDetailBeforeRecovery() = runBlocking {
        val client = OwnedEventsClient(Queue(mutableListOf(response(), response(body = detail), response(404), response())))
        client.refresh(resource); client.refresh(OwnedResource.Detail("hosted-event-101"))
        val withdrawn = client.refresh(OwnedResource.Detail("hosted-event-101")); assertTrue(withdrawn.unavailable); assertNull(withdrawn.event); assertNull(client.state(resource).catalog)
        assertNotNull(client.refresh(resource).catalog)
    }
    @Test fun catalog404AlsoClearsDetailAndEmpty200ReplacesRows() = runBlocking {
        val empty = JSONObject(catalog).put("events", JSONArray()).put("pagination", JSONObject().put("page", 1).put("per_page", 24).put("total", 0)).toString()
        val client = OwnedEventsClient(Queue(mutableListOf(response(body = detail), response(), response(body = empty), response(404))))
        client.refresh(OwnedResource.Detail("hosted-event-101")); client.refresh(resource)
        assertTrue(client.refresh(resource).catalog!!.events.isEmpty())
        assertTrue(client.refresh(resource).unavailable); assertNull(client.state(OwnedResource.Detail("hosted-event-101")).event)
    }
    @Test fun orphan304RetriesOnceWithoutInventingSnapshot() = runBlocking {
        val queue = Queue(mutableListOf(response(304, ""), response()))
        val client = OwnedEventsClient(queue); assertNotNull(client.refresh(resource).catalog); assertEquals(listOf(null, null), queue.validators)
        val invalid = OwnedEventsClient(Queue(mutableListOf(response(304, ""), response(304, ""))))
        assertEquals(OwnedProblem.INVALID_RESPONSE, invalid.refresh(resource).problem)
    }
    @Test fun mismatched304KeepsStaleSnapshot() = runBlocking {
        val client = OwnedEventsClient(Queue(mutableListOf(response(), response(304, "", "\"other\""))))
        val first = client.refresh(resource); val invalid = client.refresh(resource)
        assertTrue(invalid.stale); assertEquals(first.catalog, invalid.catalog); assertEquals(OwnedProblem.INVALID_RESPONSE, invalid.problem)
    }
    @Test fun foreignIdsAndInvalidPagesNeverReachTransport() = runBlocking {
        val queue = Queue(mutableListOf()); val client = OwnedEventsClient(queue)
        for(id in listOf("external-101", "hosted-event-0", "hosted-event-01", "hosted-event-9223372036854775808", "hosted-event-1/../2")) {
            assertFalse(OwnedEvent.validId(id)); try { client.refresh(OwnedResource.Detail(id)); fail() } catch(_: IllegalArgumentException) { }
        }
        for(page in listOf(0, 1001)) { try { client.refresh(OwnedResource.Catalog(page)); fail() } catch(_: IllegalArgumentException) { } }
        assertTrue(queue.validators.isEmpty())
    }
    @Test fun unicodeLimitsAccept255CodePointsAndReject256ForTitlesAndOrganizers() = runBlocking {
        for(length in listOf(255, 256)) for(field in listOf("title", "name")) {
            val root = JSONObject(detail)
            val objectToEdit = if(field == "title") root.getJSONObject("event") else root.getJSONObject("event").getJSONObject("organizer")
            objectToEdit.put(field, "😀".repeat(length))
            val state = OwnedEventsClient(Queue(mutableListOf(response(body = root.toString())))).refresh(OwnedResource.Detail("hosted-event-101"))
            if(length == 255) assertNotNull(state.event) else { assertNull(state.event); assertEquals(OwnedProblem.INVALID_RESPONSE, state.problem) }
        }
    }
    @Test fun timezoneRejectsFixedOffsetsAndAcceptsPublishedAliases() = runBlocking {
        for(zone in listOf("+05:30", "Z", "Asia/Calcutta")) {
            val root = JSONObject(detail); root.getJSONObject("event").put("timezone", zone)
            val state = OwnedEventsClient(Queue(mutableListOf(response(body = root.toString())))).refresh(OwnedResource.Detail("hosted-event-101"))
            if(zone == "Asia/Calcutta") assertNotNull(state.event) else assertEquals(OwnedProblem.INVALID_RESPONSE, state.problem)
        }
    }
    @Test fun decodingLeavesCallerThreadAndClearIsNotBlockedByDecode() = runBlocking {
        val entered = CompletableDeferred<String>()
        val release = java.util.concurrent.CountDownLatch(1)
        val caller = Thread.currentThread().name
        val client = OwnedEventsClient(Queue(mutableListOf(response())), decoder = { resource, body ->
            entered.complete(Thread.currentThread().name)
            check(release.await(3, java.util.concurrent.TimeUnit.SECONDS))
            OwnedSnapshotDecoder.parse(resource, body)
        })
        val request = async { client.refresh(resource) }
        try {
            assertNotEquals(caller, kotlinx.coroutines.withTimeout(2000) { entered.await() })
            val clearing = async(Dispatchers.Default) { client.clear() }
            withTimeout(1000) { clearing.await() }
            release.countDown()
            try { request.await(); fail("Cleared decode must not commit") } catch(_: kotlinx.coroutines.CancellationException) { }
            assertNull(client.state(resource).catalog)
        } finally { release.countDown(); request.cancel() }
    }
    @Test fun invalidEventFieldsAndUnknownPrivateFieldsRejected() = runBlocking {
        val cases = listOf("id" to "hosted-event-102", "ownership" to "external_listing", "title" to " ", "starts_at" to "2026-11-07T00:15:00", "ends_at" to "2025-11-07T01:30:00+05:30", "timezone" to "Invalid/Zone", "start_date" to "2026-11-08", "details_path" to "https://example.com/private", "private_token" to "synthetic")
        for((key, value) in cases) {
            val root = JSONObject(detail); root.getJSONObject("event").put(key, value)
            val state = OwnedEventsClient(Queue(mutableListOf(response(body = root.toString())))).refresh(OwnedResource.Detail("hosted-event-101"))
            assertNull(key, state.event); assertEquals(key, OwnedProblem.INVALID_RESPONSE, state.problem)
        }
        val root = JSONObject(catalog).put("account", JSONObject().put("email", "synthetic@example.invalid"))
        assertEquals(OwnedProblem.INVALID_RESPONSE, OwnedEventsClient(Queue(mutableListOf(response(body = root.toString())))).refresh(resource).problem)
    }
    @Test fun schemaDuplicateRowsAndPaginationAreValidated() = runBlocking {
        val duplicate = JSONObject(catalog); val row = duplicate.getJSONArray("events").getJSONObject(0); duplicate.put("events", JSONArray().put(row).put(row))
        val page = JSONObject(catalog); page.getJSONObject("pagination").put("page", 2)
        for(body in listOf(duplicate.toString(), page.toString(), JSONObject(catalog).put("content_version", "invalid").toString(), JSONObject(catalog).put("schema_version", true).toString())) {
            assertEquals(OwnedProblem.INVALID_RESPONSE, OwnedEventsClient(Queue(mutableListOf(response(body = body)))).refresh(resource).problem)
        }
        val future = JSONObject(catalog).put("schema_version", 2).toString()
        assertEquals(OwnedProblem.UNSUPPORTED_SCHEMA, OwnedEventsClient(Queue(mutableListOf(response(body = future)))).refresh(resource).problem)
    }
    @Test fun clearAndBackgroundInvalidateDelayedResponses() = runBlocking {
        for(clear in listOf(true, false)) {
            val entered = CompletableDeferred<Unit>(); val reply = CompletableDeferred<OwnedResponse>()
            val client = OwnedEventsClient(OwnedTransport { _, _ -> entered.complete(Unit); reply.await() })
            val request = async { client.refresh(resource) }; entered.await()
            if(clear) client.clear() else client.background()
            reply.complete(response())
            try { request.await(); fail() } catch(_: kotlinx.coroutines.CancellationException) { }
            assertNull(client.state(resource).catalog)
        }
    }
    @Test fun cacheBoundEvictsValidatorsAndRejectsOversizedPayload() = runBlocking {
        val replies = (1..9).map { page -> val root = JSONObject(catalog); root.getJSONObject("pagination").put("page", page).put("total", 250); response(body = root.toString()) }.toMutableList()
        replies.add(response()); val queue = Queue(replies); val client = OwnedEventsClient(queue)
        for(page in 1..9) client.refresh(OwnedResource.Catalog(page))
        assertNull(client.state(resource).catalog); client.refresh(resource); assertNull(queue.validators.last())
        assertEquals(OwnedProblem.INVALID_RESPONSE, OwnedEventsClient(Queue(mutableListOf(response(body = " ".repeat(OwnedEventsHttp.MAX_BODY + 1))))).refresh(resource).problem)
    }
    @Test fun validatorsCannotContainControlCharactersAndProductionIsClosed() {
        for(value in listOf("bad", "\"a\r\nb\"", "\"a\\b\"", "\"a\"b\"", "\"" + "a".repeat(255) + "\"")) assertFalse(value, OwnedEventsClient.validEtag(value))
        assertTrue(OwnedEventsClient.validEtag(tag)); assertFalse(OwnedEventsIntegration.productionEnabled)
    }
    @Test fun privacyClearSurvivesForegroundUntilExplicitRefresh() = runBlocking {
        val scope = CoroutineScope(Dispatchers.Unconfined)
        val controller = OwnedEventsController(OwnedEventsClient(Queue(mutableListOf(response(), response()))), scope)
        controller.refresh(); withTimeout(2000) { controller.state.first { !it.loading && it.catalog.catalog != null } }; assertNotNull(controller.state.value.catalog.catalog)
        controller.clear(); controller.background(); controller.foreground()
        assertTrue(controller.state.value.cleared); assertNull(controller.state.value.catalog.catalog)
        controller.refresh(); withTimeout(2000) { controller.state.first { !it.loading && it.catalog.catalog != null } }; assertFalse(controller.state.value.cleared); assertNotNull(controller.state.value.catalog.catalog)
    }
}
