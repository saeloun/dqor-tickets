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
    private fun back() {instrumentation.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK); compose.waitForIdle()}
    private fun shell(command: String)=ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand(command)).bufferedReader().use {it.readText().trim()}
    @Test fun repeatedBookmarkTapsSavedEmptyAndBackRecover() {
        setup(); tap("event-list","Deccan Queen on Rails")
        compose.onNodeWithText("Schedule").performClick()
        tap("schedule-list","Saved sessions")
        compose.onNodeWithText("No saved sessions for this day").assertIsDisplayed()
        compose.captureDemo("21-saved-empty")
        tap("schedule-list","Reset filters")
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
        compose.onNodeWithText("Less detail").assertDoesNotExist()
        compose.onNodeWithTag("schedule-list").assertExists()
        back()
        compose.onNodeWithTag("event-overview").assertExists()
        compose.onNodeWithText("Passes").performClick()
        tap("wallet-list","Asha Rao")
        back(); compose.onNodeWithTag("wallet-list").assertExists()
        back(); compose.onNodeWithTag("event-overview").assertExists()
        back(); compose.onNodeWithTag("event-list").assertExists()
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
            compose.onNodeWithContentDescription("Save Small teams, remarkable software").performClick()
            compose.onNodeWithContentDescription("Unsave Small teams, remarkable software").assertExists()
            compose.captureDemo("23-reduced-motion")
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
