package `in`.dqor.staff

import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.*
import androidx.test.platform.app.InstrumentationRegistry
import `in`.dqor.staff.programme.*
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test

class OfficialProgrammeSmokeTest {
    @get:Rule val compose=createComposeRule()
    @Test fun realApplicationTransportReadsAndRevalidatesPublishedOnlyFeed() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("livePublic")=="true")
        val transport=OfficialProgrammeTransport()
        val first=runBlocking {transport.fetch(ProgrammeRequest())}
        assertEquals(200,first.status)
        val data=PublicProgramme.parse(first.body)
        assertEquals("dqor-2026",data.event.id)
        assertEquals("2026-10-08",data.event.startDate.toString())
        assertEquals("2026-10-11",data.event.endDate.toString())
        assertEquals("Asia/Kolkata",data.event.timezone.id)
        assertTrue(data.sessions.isNotEmpty()); assertTrue(data.speakers.isNotEmpty())
        assertNotNull(first.etag)
        val second=runBlocking {transport.fetch(ProgrammeRequest(first.etag))}
        assertEquals(304,second.status); assertTrue(second.body.isEmpty())
        println("PUBLIC_SMOKE status=${first.status} conditional=${second.status} sessions=${data.sessions.size} speakers=${data.speakers.size} etag=${first.etag} version=${data.contentVersion}")
        compose.setContent {PublishedProgrammeApp(PublishedProgrammeState(snapshot=data,etag=first.etag,checkedAt=java.time.Instant.now()),{},{},{},{},emptySet(),{})}
        compose.captureDemo("public-live-hero")
        compose.onNodeWithTag("published-programme").performScrollToNode(hasText("Explore the programme"))
        compose.captureDemo("public-live-overview")
        compose.onNodeWithText("Explore the programme").performClick()
        compose.onNodeWithTag("published-programme").performScrollToNode(hasText(data.sessions.first().title))
        compose.onNodeWithText(data.sessions.first().title).assertIsDisplayed()
        compose.captureDemo("public-live-first-day")
        compose.onNodeWithText("Sample wallet · not valid for entry").assertDoesNotExist()
    }
}
