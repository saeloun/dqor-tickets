package `in`.dqor.staff

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.test.platform.app.InstrumentationRegistry
import `in`.dqor.staff.owned.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class OwnedEventsUiTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var controller: OwnedEventsController
    private fun setup(large: Boolean = false, unavailable: Boolean = false) {
        val assets = InstrumentationRegistry.getInstrumentation().targetContext.assets
        val preview = OwnedPreviewTransport(assets.open("owned_events_catalog.json").bufferedReader().use { it.readText() }, assets.open("owned_event_detail.json").bufferedReader().use { it.readText() })
        if(unavailable) preview.status = 503
        compose.setContent {
            val scope = rememberCoroutineScope(); val client = remember { OwnedEventsClient(preview, decoder = { resource, body ->
                check(android.os.Looper.myLooper() != android.os.Looper.getMainLooper())
                OwnedSnapshotDecoder.parse(resource, body)
            }) }
            controller = remember { OwnedEventsController(client, scope) }
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, if(large) 2f else 1f)) {
                OwnedEventsScreen(controller, onWebsite = { false }, scenario = { preview.status = it; controller.refresh() })
            }
        }
        compose.waitForIdle()
    }
    private fun show(text: String) {
        compose.waitUntil(5_000) { !controller.state.value.loading }
        compose.onNodeWithTag("owned-events").performScrollToNode(hasText(text))
        compose.onNodeWithText(text).assertIsDisplayed()
    }
    private fun tap(text: String) { show(text); compose.onNodeWithText(text).performClick(); compose.waitForIdle() }
    private fun open() {
        show("Events up to date")
        compose.onNodeWithTag("owned-events").performScrollToNode(hasTestTag("hosted-event-101"))
        compose.onNodeWithTag("hosted-event-101").performClick()
        show("Event details"); show("Synthetic meetup contract fixture")
    }
    @Test fun catalogDetailRealBack503304WithdrawalRecoveryAndPrivacyClear() {
        setup(); show("Preview · synthetic events"); compose.captureDemo("owned-synthetic-catalog")
        open(); show("Synthetic organizers"); show("View event website"); compose.captureDemo("owned-synthetic-detail")
        tap("Service unavailable"); show("Saved information · may be outdated"); show("Synthetic meetup contract fixture")
        compose.captureDemo("owned-synthetic-stale-detail")
        tap("Unchanged"); show("Events up to date"); compose.onNodeWithText("Saved information · may be outdated").assertDoesNotExist()
        tap("Withdraw event"); show("Event information is no longer available"); compose.onNodeWithTag("owned-title").assertDoesNotExist(); compose.captureDemo("owned-synthetic-withdrawn")
        InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK); compose.waitForIdle()
        show("Events"); show("Event information is no longer available"); compose.onNodeWithTag("hosted-event-101").assertDoesNotExist()
        tap("Published"); show("Synthetic meetup contract fixture")
        tap("Clear local events"); show("Your local events are cleared."); compose.onNodeWithTag("hosted-event-101").assertDoesNotExist()
        compose.runOnIdle { controller.background(); controller.foreground() }
        show("Your local events are cleared."); compose.onNodeWithTag("hosted-event-101").assertDoesNotExist(); compose.captureDemo("owned-synthetic-cleared")
        tap("Refresh events"); show("Synthetic meetup contract fixture")
    }
    @Test fun largestTextDetailWebsiteFailureAndForegroundRecoveryRemainReachable() {
        setup(large = true); open(); show("Preview · synthetic events")
        tap("View event website"); show("No system browser is available."); compose.captureDemo("owned-synthetic-largest-text")
        tap("Service unavailable"); show("Saved information · may be outdated")
        tap("Published"); show("Events up to date")
        compose.runOnIdle { controller.background(); controller.foreground() }
        show("Events up to date"); show("Synthetic meetup contract fixture")
        tap("Back to events"); show("Events"); show("Synthetic meetup contract fixture")
    }
    @Test fun initial503HasNoInventedRowsAndExplicitRetryRecovers() {
        setup(unavailable = true); show("Events could not be refreshed. Try again.")
        compose.onNodeWithTag("hosted-event-101").assertDoesNotExist(); compose.captureDemo("owned-synthetic-initial-unavailable")
        tap("Published"); show("Synthetic meetup contract fixture")
    }
}
