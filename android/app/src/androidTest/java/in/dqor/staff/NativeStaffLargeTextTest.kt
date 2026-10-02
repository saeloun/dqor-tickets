package `in`.dqor.staff

import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import `in`.dqor.staff.nativeapi.*
import kotlinx.coroutines.launch
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class NativeStaffLargeTextTest {
    @get:Rule val compose=createComposeRule()
    @Test fun largeTextReviewRemainsReachableAndCanCancel() {
        val server=MockNativeTransport()
        val store=object : CredentialStore {
            var value: StoredCredential?=null
            override suspend fun read()=value
            override suspend fun write(value: StoredCredential) {this.value=value}
            override suspend fun clear() {value=null}
        }
        val flow=NativeDeskWorkflow(NativeStaffClient(NativeConfig(true,"https://mock.invalid"),server,store))
        compose.setContent {
            val density=LocalDensity.current; val scope=rememberCoroutineScope()
            CompositionLocalProvider(LocalDensity provides Density(density.density,2f)) {
                NativeStaffApp(listOf(Event("dqor-2026","DQOR","Pune","Demo",listOf("2026-10-08"),"heritage")),flow,server) {action -> scope.launch {flow.action()}}
            }
        }
        fun tap(text: String) {compose.onNodeWithTag("staff-screen").performScrollToNode(hasText(text)); compose.onNodeWithText(text).performClick(); compose.waitForIdle()}
        tap("Sign in to demo"); tap("DQOR"); tap("Preview sample QR")
        compose.onNodeWithText("Review 1 tickets").assertIsDisplayed(); compose.captureDemo("13-staff-large-text")
        compose.onNodeWithText("Review 1 tickets").performClick(); compose.onNodeWithText("Cancel").performClick()
        assertEquals(1,flow.state.value.selected.size); assertEquals(0,server.confirmationCalls)
    }
}
