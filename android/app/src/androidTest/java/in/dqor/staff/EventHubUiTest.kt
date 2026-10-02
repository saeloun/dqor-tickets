package `in`.dqor.staff

import android.graphics.Bitmap
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.ComposeContentTestRule
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.test.platform.app.InstrumentationRegistry
import `in`.dqor.staff.experience.*
import java.io.File
import org.junit.Rule
import org.junit.Test

/** Captures the real composables in a synthetic test activity. Launcher FLAG_SECURE stays enabled. */
internal fun ComposeContentTestRule.captureDemo(name: String) {
    waitForIdle()
    val directory=File(InstrumentationRegistry.getInstrumentation().targetContext.filesDir,"review-shots").apply {mkdirs()}
    File(directory,"$name.png").outputStream().use {onRoot().captureToImage().asAndroidBitmap().compress(Bitmap.CompressFormat.PNG,100,it)}
}
class EventHubUiTest {
    @get:Rule val compose=createComposeRule()
    private val events=listOf(Event("dqor-2026","Deccan Queen on Rails","Pune, India","A meeting of curious minds",listOf("2026-10-08","2026-10-09","2026-10-10","2026-10-11"),"heritage"),Event("studio-demo","The Design Assembly","Bengaluru, India · sample event","Ideas deserve a gathering",listOf("2026-11-14"),"midnight"))
    private fun content()=EventExperience.parse(InstrumentationRegistry.getInstrumentation().targetContext.assets.open("experience.json").bufferedReader().use {it.readText()})
    private fun tap(list: String,text: String) {compose.onNodeWithTag(list).performScrollToNode(hasText(text)); compose.onNodeWithText(text).performClick(); compose.waitForIdle()}
    @Test fun eventScheduleBookmarksAndIndependentWalletJourney() {
        compose.setContent {EventHubApp(events,content()) {}}
        compose.captureDemo("01-events")
        tap("event-list","Deccan Queen on Rails"); compose.captureDemo("02-overview")
        compose.onNodeWithTag("event-overview").performScrollToNode(hasText("View my sample passes")); compose.captureDemo("14-event-ticket-action")
        compose.onNodeWithText("Schedule").performScrollTo().performClick()
        compose.captureDemo("03-schedule")
        compose.onNodeWithText("Find a session or speaker").performTextInput("Ananya")
        compose.onNodeWithTag("schedule-list").performScrollToNode(hasContentDescription("Save Small teams, remarkable software"))
        compose.onNodeWithContentDescription("Save Small teams, remarkable software").performClick()
        compose.onNodeWithText("Passes").performScrollTo().performClick(); compose.captureDemo("04-wallet")
        compose.onNodeWithText("Schedule").performScrollTo().performClick()
        compose.onNodeWithText("Find a session or speaker").assertTextContains("Ananya")
        compose.onNodeWithTag("schedule-list").performScrollToNode(hasContentDescription("Unsave Small teams, remarkable software"))
        compose.onNodeWithContentDescription("Unsave Small teams, remarkable software").assertExists()
        compose.onNodeWithText("Passes").performScrollTo().performClick()
        tap("wallet-list","Asha Rao")
        compose.captureDemo("05-sample-pass")
        compose.onNodeWithContentDescription("Sample QR. Not a valid entry or redemption code.").assertExists()
        compose.onNodeWithTag("pass-detail").performScrollToNode(hasText("Checked in"))
        compose.onNodeWithText("Checked in").assertExists()
        compose.onNodeWithTag("pass-detail").performScrollToNode(hasText("Not redeemed"))
        compose.onNodeWithText("Not redeemed").assertExists()
        compose.onNodeWithTag("pass-detail").performScrollToNode(hasText("Redeemed"))
        compose.onNodeWithText("Redeemed").assertExists(); compose.captureDemo("06-independent-redemptions")
        compose.onNodeWithText("← My passes").performClick(); compose.onNodeWithText("← All events").performClick()
        tap("event-list","The Design Assembly"); compose.captureDemo("15-original-studio-art"); compose.onNodeWithText("Passes").performScrollTo().performClick()
        compose.onNodeWithTag("wallet-list").performScrollToNode(hasText("No sample passes for this event"))
        compose.onNodeWithText("No sample passes for this event").assertIsDisplayed(); compose.captureDemo("07-empty-wallet")
    }
    @Test fun largeTextKeepsProgrammeAndPassActionsReachable() {
        compose.setContent {val density=LocalDensity.current; CompositionLocalProvider(LocalDensity provides Density(density.density,2f)) {EventHubApp(events,content()) {}}}
        tap("event-list","Deccan Queen on Rails"); compose.onNodeWithText("Schedule").performScrollTo().performClick()
        compose.onNodeWithTag("schedule-list").performScrollToNode(hasText("Session details"))
        compose.captureDemo("08-schedule-large-text")
        compose.onAllNodesWithText("Session details").onFirst().performClick()
        compose.onNodeWithText("Passes").performScrollTo().performClick(); tap("wallet-list","Asha Rao")
        compose.onNodeWithTag("pass-detail").performScrollToNode(hasText("Meals & community"))
        compose.onNodeWithText("Meals & community").assertIsDisplayed(); compose.captureDemo("09-pass-large-text")
    }
    @Test fun searchEmptyStateCanRecover() {
        compose.setContent {EventHubApp(events,content()) {}}
        tap("event-list","Deccan Queen on Rails"); compose.onNodeWithText("Schedule").performScrollTo().performClick()
        compose.onNodeWithText("Find a session or speaker").performTextInput("no such sample")
        tap("schedule-list","Reset filters")
        compose.onNodeWithTag("schedule-list").performScrollToNode(hasText("Small teams, remarkable software"))
        compose.onNodeWithText("Small teams, remarkable software").assertIsDisplayed()
    }
}
