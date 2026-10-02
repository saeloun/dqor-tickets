package `in`.dqor.staff

import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import `in`.dqor.staff.nativeapi.*
import kotlinx.coroutines.launch
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test

class NativeStaffUiTest {
    @get:Rule val compose=createComposeRule()
    private val server=MockNativeTransport()
    private val store=object : CredentialStore {
        var value: StoredCredential?=null
        override suspend fun read()=value
        override suspend fun write(value: StoredCredential) {this.value=value}
        override suspend fun clear() {value=null}
    }
    private val flow=NativeDeskWorkflow(NativeStaffClient(NativeConfig(true,"https://mock.invalid"),server,store))
    @Before fun showApp() {
        compose.setContent {
            val scope=rememberCoroutineScope()
            NativeStaffApp(listOf(Event("dqor-2026","DQOR","Pune","Demo",listOf("2026-10-08"),"heritage")),flow,server) {action -> scope.launch {flow.action()}}
        }
        tap("Sign in to demo"); tap("DQOR")
    }
    private fun tap(text: String) {if(!text.startsWith("Review ")) compose.onNodeWithTag("staff-screen").performScrollToNode(hasText(text)); compose.onNodeWithText(text).performClick(); compose.waitForIdle()}
    private fun preview() {tap("Preview sample QR"); assertEquals(1,server.resolveCalls); assertEquals(0,server.confirmationCalls)}
    @Test fun scanReviewCancelAndExplicitConfirmation() {
        preview(); tap("Review 1 ticket")
        compose.onNodeWithText("Confirm 1 check-in?").assertExists()
        assertEquals(0,server.attendanceCount)
        compose.onNodeWithText("Cancel").performClick(); compose.waitForIdle(); assertEquals(0,server.confirmationCalls)
        tap("Review 1 ticket"); compose.onNodeWithText("Confirm check-in").performClick(); compose.waitForIdle()
        assertEquals(1,server.confirmationCalls); assertEquals(1,server.attendanceCount)
        assertEquals(NativeState.SUCCESS,flow.state.value.results.single().state)
        compose.captureDemo("11-staff-confirmed")
        compose.onNodeWithText("Asha Rao: Demo check-in confirmed").assertIsDisplayed()
        tap("Sign out"); compose.onNodeWithText("Sign in to demo").assertExists(); assertNull(flow.state.value.session)
    }
    @Test fun expiryReturnsToSignInWithoutConfirmation() {
        preview(); tap("Demo scenarios"); tap("Expire demo session")
        compose.onNodeWithText("Sign in to demo").assertExists(); assertEquals(0,server.attendanceCount); assertNull(flow.state.value.review)
    }
    @Test fun stalePreviewIsRecheckedOnExplicitConfirmation() {
        preview(); tap("Demo scenarios"); tap("Invalidate selected preview"); tap("Review 1 ticket")
        compose.onNodeWithText("Confirm check-in").performClick(); compose.waitForIdle()
        assertEquals(0,server.attendanceCount); assertEquals(NativeState.ERROR,flow.state.value.results.single().state)
    }
    @Test fun uncertainMutationRequiresExplicitRetryWithSameTickets() {
        preview(); tap("Demo scenarios"); tap("Simulate next confirmation timeout"); tap("Review 1 ticket")
        compose.onNodeWithText("Confirm check-in").performClick(); compose.waitForIdle()
        compose.onNodeWithText("Check-in not confirmed").assertExists(); assertEquals(1,server.attendanceCount)
        compose.onNodeWithText("Retry same tickets").performClick(); compose.waitForIdle()
        assertEquals(1,server.attendanceCount); assertEquals(2,server.confirmationCalls)
        assertEquals(NativeState.WARNING,flow.state.value.results.single().state)
    }
    @Test fun manualLookupAndHistoryPreserveSelectionAndReportPreviewOnly() {
        tap("Lookup")
        compose.onNodeWithText("Name, email or order code").performTextInput("DEMO-102")
        compose.onNodeWithText("Search").performClick(); compose.waitForIdle()
        compose.onNodeWithTag("staff-screen").performScrollToNode(hasContentDescription("Select Grace Shah, grace@example.test, ticket 102"))
        compose.onNodeWithContentDescription("Select Grace Shah, grace@example.test, ticket 102").performClick()
        assertEquals(0,server.confirmationCalls); assertEquals(listOf(102L),flow.state.value.selected.map {it.id})
        compose.captureDemo("10-staff-lookup")
        tap("History"); assertEquals("DEMO-102",flow.state.value.query); assertEquals(1,flow.state.value.selected.size)
        tap("Scan"); tap("Preview sample QR"); tap("History")
        compose.onNodeWithTag("staff-screen").performScrollToNode(hasText("○ Preview only"))
        compose.onNodeWithText("○ Preview only").assertIsDisplayed(); compose.captureDemo("12-staff-history")
        assertEquals(0,server.attendanceCount)
    }
}
