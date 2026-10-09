package `in`.dqor.staff

import android.content.res.Configuration
import androidx.compose.runtime.*
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import `in`.dqor.staff.experience.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import `in`.dqor.staff.programme.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class AttendeeBrandThemeUiTest {
    @get:Rule val compose=createComposeRule()
    @Test fun disabledMotionLeavesNativeRevealAndPressActionsImmediatelyUsable() {
        var clicks=0
        compose.setContent {
            AttendeeTheme {
                CompositionLocalProvider(LocalAttendeeMotion provides AttendeeMotion(false)) {
                    val interaction=remember {MutableInteractionSource()}
                    Column(Modifier.attendeeReveal("programme")) {
                        Button(onClick={clicks++},interactionSource=interaction,modifier=Modifier.attendeePress(interaction)) {Text("Open programme")}
                    }
                }
            }
        }
        compose.mainClock.autoAdvance=false
        compose.onNodeWithText("Open programme").assertIsDisplayed().performClick()
        compose.runOnIdle {assertEquals(1,clicks)}
        compose.captureDemo("brand-reduced-motion-native-action")
    }
    @Test fun publicLightDarkSwitchPreservesSavedDetailsAndActions() {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val data=PublicProgramme.parse(context.assets.open("public_programme_example.json").bufferedReader().use {it.readText()})
        var dark by mutableStateOf(false)
        var saved by mutableStateOf(emptySet<String>())
        var refreshes=0
        var background=Color.Unspecified
        compose.setContent {
            val config=Configuration(LocalConfiguration.current).apply {uiMode=(uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or if(dark) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO}
            CompositionLocalProvider(LocalConfiguration provides config) {
                PublishedProgrammeApp(PublishedProgrammeState(snapshot=data),{refreshes++},{},{},{},saved,{id -> saved=if(id in saved) saved-id else saved+id},onAccount={})
            }
        }
        compose.onNodeWithText("Programme",useUnmergedTree=true).performClick()
        val list=compose.onNodeWithTag("published-programme")
        val title="Synthetic published session"
        list.performScrollToNode(hasContentDescription("Save $title"))
        compose.onNodeWithContentDescription("Save $title").assertIsDisplayed().performClick()
        compose.onNodeWithContentDescription("Unsave $title").assertIsDisplayed()
        compose.onAllNodesWithText("Session details").onFirst().performClick()
        list.performScrollToNode(hasText("Synthetic fixture for typed-client development."))
        compose.onNodeWithText("Synthetic fixture for typed-client development.").assertIsDisplayed()
        compose.captureDemo("brand-baseline-light-programme")
        compose.runOnIdle {dark=true}
        compose.waitForIdle()
        list.performScrollToNode(hasContentDescription("Unsave $title"))
        compose.onNodeWithContentDescription("Unsave $title").assertIsDisplayed()
        list.performScrollToNode(hasText("Synthetic fixture for typed-client development."))
        compose.onNodeWithText("Synthetic fixture for typed-client development.").assertIsDisplayed()
        compose.captureDemo("brand-baseline-dark-programme")
        val pixel=compose.onRoot().captureToImage()
        background=pixel.toPixelMap()[pixel.width-4,pixel.height/2]
        assertTrue("Dark public surface must use dark canvas",background.luminance()<0.1f)
        InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
        compose.waitUntil(5_000) {compose.onAllNodesWithText("Less detail").fetchSemanticsNodes().isEmpty()}
        compose.onNodeWithContentDescription("Unsave $title").assertExists()
        list.performScrollToNode(hasText("Refresh programme"))
        compose.onNodeWithText("Refresh programme").assertIsDisplayed().performClick()
        compose.runOnIdle {assertEquals(setOf("101"),saved);assertEquals(1,refreshes)}
    }
}
