package `in`.dqor.staff

import android.content.Intent
import android.net.Uri
import android.view.WindowManager
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import `in`.dqor.staff.attendee.AttendeeIntegration
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class AttendeeDisabledLauncherTest {
    @get:Rule val compose=createEmptyComposeRule()
    @Test fun actualLauncherRejectsCallbackAndActivationExtrasAndPreservesSecureWindow() {
        assertFalse(AttendeeIntegration.ENABLED)
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val intent=Intent(context,MainActivity::class.java).apply {
            putExtra("syntheticAuth",true); putExtra("attendeeEnabled",true)
        }
        ActivityScenario.launch<MainActivity>(intent).use {scenario ->
            var original: MainActivity? = null
            scenario.onActivity {original=it; assertNull(it.intent.data); assertTrue(it.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE != 0)}
            compose.onNodeWithText("Account").assertIsDisplayed().performClick()
            compose.onNodeWithText("Native account access is not enabled").assertIsDisplayed()
            compose.onNodeWithText("Sign in through system browser").assertDoesNotExist()
            compose.onNodeWithTag("attendee-account").performScrollToNode(hasText("Open account on official website"))
            compose.onNodeWithText("Open account on official website").assertIsEnabled().assertIsDisplayed()
            scenario.onActivity {it.startActivity(Intent(intent).setFlags(Intent.FLAG_ACTIVITY_NEW_TASK).setData(Uri.parse("${AttendeeIntegration.CALLBACK}?code=synthetic-unsolicited&state=unknown")))}
            compose.waitUntil(5_000) {compose.onAllNodesWithTag("attendee-account").fetchSemanticsNodes().isNotEmpty()}
            scenario.onActivity {assertSame(original,it); assertNull(it.intent.data)}
            compose.onNodeWithTag("attendee-account").performScrollToIndex(0)
            compose.onNodeWithText("Native account access is not enabled").assertIsDisplayed()
            scenario.recreate()
            compose.onNodeWithTag("attendee-account").performScrollToIndex(0)
            compose.onNodeWithText("Native account access is not enabled").assertIsDisplayed()
            compose.onNodeWithText("Sign in through system browser").assertDoesNotExist()
            compose.onNodeWithText("Back to programme").performClick()
            compose.onNodeWithText("Official public programme").assertIsDisplayed()
        }
    }
}
