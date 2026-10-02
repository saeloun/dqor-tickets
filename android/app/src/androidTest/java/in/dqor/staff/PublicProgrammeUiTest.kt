package `in`.dqor.staff

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.test.platform.app.InstrumentationRegistry
import `in`.dqor.staff.experience.AttendeeTheme
import `in`.dqor.staff.programme.*
import org.junit.Rule
import org.junit.Test

class PublicProgrammeUiTest {
    @get:Rule val compose=createComposeRule()
    private fun setup(offline: Boolean=false, large: Boolean=false) {
        val fixture=InstrumentationRegistry.getInstrumentation().targetContext.assets.open("public_programme_example.json").bufferedReader().use {it.readText()}
        val demo=DemoProgrammeTransport(fixture).apply {if(offline) scenario=DemoProgrammeTransport.Scenario.OFFLINE}
        val client=PublicProgrammeClient(demo)
        compose.setContent {val density=LocalDensity.current; CompositionLocalProvider(LocalDensity provides Density(density.density,if(large) 2f else 1f)) {AttendeeTheme {Surface(Modifier.fillMaxSize().safeDrawingPadding()) {ProgrammePreview(client,demo) {}}}}}
    }
    private fun show(text: String) {compose.onNodeWithTag("public-programme").performScrollToNode(hasText(text)); compose.onNodeWithText(text).performScrollTo().assertIsDisplayed()}
    private fun tap(text: String) {show(text);compose.onNodeWithText(text).performClick();compose.waitForIdle()}
    @Test fun cachedErrorRetainsSearchAnd304RecoversThenEmptyReplaces() {
        setup(); show("Sample programme revalidated"); compose.captureDemo("16-public-current")
        show("Search public preview"); compose.onNodeWithText("Search public preview").performTextInput("unscheduled")
        show("Synthetic unscheduled session"); show("Time to be announced")
        tap("Offline"); show("Cached programme · may be outdated"); compose.onNodeWithTag("public-programme").performScrollToIndex(0); compose.captureDemo("17-public-stale")
        show("Search public preview");compose.onNodeWithText("Search public preview").assertTextContains("unscheduled")
        show("Synthetic unscheduled session")
        tap("Service unavailable");show("The programme service is temporarily unavailable. Try again later.")
        tap("Unchanged (304)");show("Sample programme revalidated")
        tap("Withdraw all");show("No sessions published");compose.captureDemo("18-public-empty")
        compose.onNodeWithText("Synthetic unscheduled session").assertDoesNotExist()
    }
    @Test fun initialErrorRecoversWithoutFakeSchedule() {
        setup(offline=true);show("Programme unavailable");compose.captureDemo("19-public-error")
        compose.onNodeWithText("Synthetic published session").assertDoesNotExist()
        tap("Published");show("Synthetic published session")
    }
    @Test fun largeTextKeepsRefreshAndStatusReachable() {
        setup(large=true);tap("Offline");show("Cached programme · may be outdated");compose.captureDemo("20-public-large-text")
        tap("Refresh programme");show("Offline. Reconnect and retry to check for changes.")
    }
}
