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
    private fun tap(text: String) {compose.onNodeWithTag("staff-screen").performScrollToNode(hasText(text)); compose.onNodeWithText(text).performClick(); compose.waitForIdle()}
    private fun preview() {tap("Preview sample QR"); assertEquals(1,server.resolveCalls); assertEquals(0,server.confirmationCalls)}
    @Test fun scanReviewCancelAndExplicitConfirmation() {
        preview(); tap("Review 1 tickets")
        compose.onNodeWithText("Confirm 1 check-ins?").assertExists()
        assertEquals(0,server.attendanceCount)
        compose.onNodeWithText("Cancel").performClick(); compose.waitForIdle(); assertEquals(0,server.confirmationCalls)
        tap("Review 1 tickets"); compose.onNodeWithText("Confirm check-in").performClick(); compose.waitForIdle()
        assertEquals(1,server.confirmationCalls); assertEquals(1,server.attendanceCount)
        assertEquals(NativeState.SUCCESS,flow.state.value.results.single().state)
        tap("Sign out"); compose.onNodeWithText("Sign in to demo").assertExists(); assertNull(flow.state.value.session)
    }
    @Test fun expiryReturnsToSignInWithoutConfirmation() {
        preview(); tap("Expire demo session")
        compose.onNodeWithText("Sign in to demo").assertExists(); assertEquals(0,server.attendanceCount); assertNull(flow.state.value.review)
    }
    @Test fun stalePreviewIsRecheckedOnExplicitConfirmation() {
        preview(); tap("Invalidate selected preview"); tap("Review 1 tickets")
        compose.onNodeWithText("Confirm check-in").performClick(); compose.waitForIdle()
        assertEquals(0,server.attendanceCount); assertEquals(NativeState.ERROR,flow.state.value.results.single().state)
    }
    @Test fun uncertainMutationRequiresExplicitRetryWithSameTickets() {
        preview(); tap("Simulate next confirmation timeout"); tap("Review 1 tickets")
        compose.onNodeWithText("Confirm check-in").performClick(); compose.waitForIdle()
        compose.onNodeWithText("Check-in not confirmed").assertExists(); assertEquals(1,server.attendanceCount)
        compose.onNodeWithText("Retry same tickets").performClick(); compose.waitForIdle()
        assertEquals(1,server.attendanceCount); assertEquals(2,server.confirmationCalls)
        assertEquals(NativeState.WARNING,flow.state.value.results.single().state)
    }
}
