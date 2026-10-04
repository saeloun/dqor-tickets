package `in`.dqor.staff

import android.os.ParcelFileDescriptor
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import `in`.dqor.staff.experience.*
import `in`.dqor.staff.programme.*
import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class PremiumAttendeeUiTest {
    @get:Rule val compose=createComposeRule()
    private val instrumentation=InstrumentationRegistry.getInstrumentation()
    private val events=listOf(Event("dqor-2026","Deccan Queen on Rails","Pune, India","A meeting of curious minds",listOf("2026-10-08","2026-10-09","2026-10-10","2026-10-11"),"heritage"))
    private fun fixture(name: String)=instrumentation.targetContext.assets.open(name).bufferedReader().use {it.readText()}
    private fun setup() {compose.setContent {EventHubApp(events,EventExperience.parse(fixture("experience.json"))) {}}}
    private fun tap(list: String,text: String) {compose.onNodeWithTag(list).performScrollToNode(hasText(text)); compose.onNodeWithText(text).performClick(); compose.waitForIdle()}
    private fun back(expectedTag: String?=null) {
        instrumentation.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
        compose.waitForIdle()
        if(expectedTag!=null) compose.waitUntil(5_000) {compose.onAllNodesWithTag(expectedTag).fetchSemanticsNodes().isNotEmpty()}
    }
    private fun awaitCollapsedSession() {compose.waitUntil(5_000) {compose.onAllNodesWithText("Less detail").fetchSemanticsNodes().isEmpty()}}
    private fun shell(command: String)=ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand(command)).bufferedReader().use {it.readText().trim()}
    @Test fun repeatedBookmarkTapsSavedEmptyAndBackRecover() {
        setup(); tap("event-list","Deccan Queen on Rails")
        compose.onNodeWithText("Schedule").performClick()
        tap("schedule-list","Saved sessions")
        compose.onNodeWithTag("schedule-list").performScrollToNode(hasText("No saved sessions for this day"))
        compose.onNodeWithText("No saved sessions for this day").performScrollTo().assertIsDisplayed()
        compose.captureDemo("21-saved-empty")
        compose.onNodeWithTag("schedule-list").performScrollToNode(hasText("Reset filters"))
        compose.onNodeWithText("Reset filters").performScrollTo().assertIsDisplayed().performClick()
        compose.waitForIdle()
        val save="Save Small teams, remarkable software"
        val unsave="Unsave Small teams, remarkable software"
        compose.onNodeWithTag("schedule-list").performScrollToNode(hasContentDescription(save))
        repeat(3) {
            compose.onNodeWithContentDescription(save).performClick()
            compose.onNodeWithContentDescription(unsave).performClick()
        }
        compose.onNodeWithContentDescription(save).performClick()
        compose.captureDemo("22-saved-session")
        compose.onAllNodesWithText("Session details").onFirst().performClick()
        compose.onNodeWithText("Less detail").assertExists()
        back()
        awaitCollapsedSession()
        compose.onNodeWithText("Less detail").assertDoesNotExist()
        compose.onNodeWithTag("schedule-list").assertExists()
        back("event-overview")
        compose.onNodeWithTag("event-overview").assertExists()
        compose.onNodeWithText("Passes").performClick()
        tap("wallet-list","Asha Rao")
        back("wallet-list"); compose.onNodeWithTag("wallet-list").assertExists()
        back("event-overview"); compose.onNodeWithTag("event-overview").assertExists()
        back("event-list"); compose.onNodeWithTag("event-list").assertExists()
    }
    @Test fun backCollapsesAnExpandedSessionAfterItScrollsOffscreen() {verifyOffscreenBack()}
    private fun verifyOffscreenBack(suffix: String="") {
        val original=EventExperience.parse(fixture("experience.json"))
        val sessions=original.program("dqor-2026","2026-10-08")
        val longProgramme=sessions+(1..20).map {sessions.first().copy(id="synthetic-extra-$it",title="Synthetic long-list session $it",startsAt="15:00",endsAt="15:30")}
        compose.setContent {EventHubApp(events,EventExperience(original.timeZone,longProgramme,original.wallet("dqor-2026"))) {}}
        tap("event-list","Deccan Queen on Rails")
        compose.onNodeWithText("Schedule").performClick()
        compose.onNodeWithTag("schedule-list").performScrollToNode(hasText("Small teams, remarkable software"))
        compose.onAllNodesWithText("Session details").onFirst().performClick()
        compose.onNodeWithText("Less detail").assertExists()
        compose.captureDemo("back-long-expanded-visible$suffix")
        compose.onNodeWithTag("schedule-list").performScrollToNode(hasText("Public feed preview"))
        compose.captureDemo("back-long-offscreen-before$suffix")
        compose.onNodeWithText("Less detail").assertIsNotDisplayed()
        back()
        compose.captureDemo("back-long-offscreen-after$suffix")
        compose.onNodeWithTag("schedule-list").assertExists()
        compose.onNodeWithTag("schedule-list").performScrollToNode(hasText("Small teams, remarkable software"))
        awaitCollapsedSession()
        compose.captureDemo("back-long-restored-card$suffix")
        compose.onNodeWithTag("schedule-list").assertExists()
        compose.onNodeWithText("Less detail").assertDoesNotExist()
        back("event-overview")
        compose.onNodeWithTag("event-overview").assertExists()
    }
    @Test fun previewBackPrecedesMultipleOffscreenExpansions() {
        val original=EventExperience.parse(fixture("experience.json"))
        val sessions=original.program("dqor-2026","2026-10-08")
        val longProgramme=sessions+(1..20).map {sessions.first().copy(id="synthetic-extra-$it",title="Synthetic long-list session $it",startsAt="15:00",endsAt="15:30")}
        compose.setContent {EventHubApp(events,EventExperience(original.timeZone,longProgramme,original.wallet("dqor-2026"))) {}}
        tap("event-list","Deccan Queen on Rails")
        compose.onNodeWithText("Schedule").performClick()
        compose.onNodeWithTag("schedule-list").performScrollToNode(hasContentDescription("Save ${sessions.first().title}"))
        compose.onNodeWithContentDescription("Save ${sessions.first().title}").performClick()
        compose.onAllNodesWithText("Session details").onFirst().performClick()
        compose.onNodeWithTag("schedule-list").performScrollToNode(hasText(sessions[1].title))
        compose.onAllNodesWithText("Session details").onFirst().performClick()
        compose.onNodeWithText(sessions[1].description).assertExists()
        tap("schedule-list","Public feed preview")
        compose.onNodeWithTag("public-programme").assertExists()
        back("schedule-list")
        compose.onNodeWithTag("public-programme").assertDoesNotExist()
        compose.onNodeWithTag("schedule-list").performScrollToNode(hasText(sessions[1].title))
        compose.onNodeWithText(sessions[1].description).assertExists()
        compose.onNodeWithTag("schedule-list").performScrollToNode(hasText("Public feed preview"))
        back()
        compose.onNodeWithTag("schedule-list").assertExists()
        compose.onNodeWithTag("schedule-list").performScrollToNode(hasText(sessions[1].title))
        compose.waitUntil(5_000) {compose.onAllNodesWithText(sessions[1].description).fetchSemanticsNodes().isEmpty()}
        compose.onNodeWithText(sessions[1].description).assertDoesNotExist()
        compose.onNodeWithTag("schedule-list").performScrollToNode(hasText(sessions.first().title))
        compose.onNodeWithText(sessions.first().description).assertExists()
        compose.onNodeWithContentDescription("Unsave ${sessions.first().title}").assertExists()
        back()
        awaitCollapsedSession()
        compose.onNodeWithTag("schedule-list").assertExists()
        back("event-overview")
        compose.onNodeWithTag("event-overview").assertExists()
    }
    @Test fun dateAndSavedFilterChangesLeaveNoHiddenBackStep() {
        setup(); tap("event-list","Deccan Queen on Rails")
        compose.onNodeWithText("Schedule").performClick()
        val title="Small teams, remarkable software"
        compose.onNodeWithTag("schedule-list").performScrollToNode(hasContentDescription("Save $title"))
        compose.onNodeWithContentDescription("Save $title").performClick()
        compose.onAllNodesWithText("Session details").onFirst().performClick()
        tap("schedule-list","Fri, 9 Oct")
        compose.onNodeWithText("Less detail").assertDoesNotExist()
        back("event-overview")
        compose.onNodeWithText("Schedule").performClick()
        tap("schedule-list","Thu, 8 Oct")
        tap("schedule-list","Saved sessions")
        compose.onNodeWithTag("schedule-list").performScrollToNode(hasContentDescription("Unsave $title"))
        compose.onNodeWithContentDescription("Unsave $title").assertExists()
        compose.onAllNodesWithText("Session details").onFirst().performClick()
        compose.onNodeWithText("Less detail").assertExists()
        compose.onNodeWithContentDescription("Unsave $title").performScrollTo().assertIsDisplayed().performClick()
        compose.onNodeWithTag("schedule-list").performScrollToNode(hasText("No saved sessions for this day"))
        compose.onNodeWithText("No saved sessions for this day").assertIsDisplayed()
        back("event-overview")
        compose.onNodeWithTag("event-overview").assertExists()
    }
    @Test fun systemReducedMotionKeepsAllActionsAvailable() {
        val initial=shell("settings get global animator_duration_scale")
        try {
            shell("settings put global animator_duration_scale 0")
            setup(); tap("event-list","Deccan Queen on Rails")
            compose.onNodeWithText("Schedule").performClick()
            compose.onNodeWithTag("schedule-list").performScrollToNode(hasText("Session details"))
            compose.onAllNodesWithText("Session details").onFirst().performClick()
            compose.onNodeWithText("Less detail").assertExists()
            compose.onNodeWithTag("schedule-list").performScrollToNode(hasContentDescription("Save Small teams, remarkable software"))
            compose.onNodeWithContentDescription("Save Small teams, remarkable software").performScrollTo().assertIsDisplayed().performClick()
            compose.onNodeWithContentDescription("Unsave Small teams, remarkable software").assertExists()
            compose.captureDemo("23-reduced-motion")
            back()
            awaitCollapsedSession()
            compose.onNodeWithTag("schedule-list").assertExists()
            compose.onNodeWithContentDescription("Unsave Small teams, remarkable software").assertExists()
        } finally {
            if(initial=="null") shell("settings delete global animator_duration_scale") else shell("settings put global animator_duration_scale $initial")
        }
    }
    @Test fun reducedMotionBackCollapsesOffscreenSession() {
        val initial=shell("settings get global animator_duration_scale")
        try {
            shell("settings put global animator_duration_scale 0")
            verifyOffscreenBack("-reduced-motion")
        } finally {
            if(initial=="null") shell("settings delete global animator_duration_scale") else shell("settings put global animator_duration_scale $initial")
        }
    }
    @Test fun slowProgrammeShowsLoadingAndBlocksRepeatRefresh() {
        val response=CompletableDeferred<ProgrammeResponse>()
        var requests=0
        val transport=ProgrammeTransport {requests++; response.await()}
        val client=PublicProgrammeClient(transport)
        val source=fixture("public_programme_example.json")
        compose.setContent {AttendeeTheme {Surface(Modifier.fillMaxSize().safeDrawingPadding()) {ProgrammePreview(client,DemoProgrammeTransport(source)) {}}}}
        compose.onNodeWithText("Refreshing sample programme…").assertIsDisplayed()
        compose.onNodeWithText("Refresh programme").assertIsNotEnabled().performClick().performClick()
        compose.runOnIdle {assertEquals(1,requests)}
        compose.captureDemo("24-slow-programme")
        compose.runOnIdle {response.complete(ProgrammeResponse(200,"W/\"synthetic-v1\"",source))}
        compose.waitForIdle()
        compose.onNodeWithText("Sample programme revalidated").assertIsDisplayed()
        compose.onNodeWithText("Refresh programme").assertIsEnabled()
    }
}
