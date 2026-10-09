package `in`.dqor.staff

import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.Density
import `in`.dqor.staff.attendee.*
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import java.time.Instant
import java.time.LocalDate

class AttendeeAuthUiTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val now = Instant.parse("2026-10-03T12:00:00Z")
    private var elapsed = 0L
    private var authorization: AttendeeAuthorization? = null
    private var browserOpens = 0
    private var closes = 0
    private var websiteOpens = 0
    private var ticketOpens = 0
    private val bridge = SyntheticBridge()
    private val controller = AttendeeController.synthetic(bridge, { now }, { elapsed })
    private inner class SyntheticBridge : AttendeeBridge {
        var expectedCode = ""
        var expectedChallenge = ""
        private val consumed = mutableSetOf<String>()
        var empty = false
        var rateLimited = false
        var exchanges = 0
        var offline = false
        var pageSizes: List<Int>? = null
        var pageReads = 0
        var observed = now.minusSeconds(5)
        val identity = AttendeeIdentity("11", "Synthetic Attendee", "synthetic@example.invalid")
        override suspend fun exchange(request: AttendeeExchange): AttendeeLease {
            exchanges++
            if (rateLimited) throw AttendeeFailure(AttendeeProblem.RATE_LIMITED)
            if (request.code != expectedCode || AttendeePkce.challenge(request.verifier) != expectedChallenge || !consumed.add(request.code)) throw AttendeeFailure(AttendeeProblem.REVOKED)
            return AttendeeLease(AttendeeCredential("na1_" + "t".repeat(43)), now.plusSeconds(1800))
        }
        override suspend fun session(credential: AttendeeCredential) = AttendeeSession(AttendeeIntegration.CLIENT_ID, setOf("account:read", "passes:read"), now.plusSeconds(1800), now)
        override suspend fun account(credential: AttendeeCredential) = AttendeeAccountResult(identity, now.minusSeconds(5))
        override suspend fun passes(credential: AttendeeCredential, cursor: String?): AttendeePassPage {
            pageReads++
            pageSizes?.takeIf {it.isNotEmpty()}?.let {sizes ->
                val first=(cursor?.toInt() ?: 0)+1
                val last=first+sizes.first()-1
                pageSizes=sizes.drop(1)
                return AttendeePassPage((first..last).map {id -> AttendeePass(id.toString(),"3","Synthetic conference status $id",PassStatus.CONFIRMED,
                    LocalDate.parse("2026-10-08"),LocalDate.parse("2026-10-11"),listOf(AttendeeEntry(LocalDate.parse("2026-10-08"),true,null)))},true,last.toString(),observed)
            }
            return AttendeePassPage(if (empty) emptyList() else listOf(
                AttendeePass("21", "3", "Synthetic conference status", PassStatus.CONFIRMED, LocalDate.parse("2026-10-08"), LocalDate.parse("2026-10-11"),
                    listOf(AttendeeEntry(LocalDate.parse("2026-10-08"), true, null)))), false, null, now.minusSeconds(5))
        }
        override suspend fun revoke(credential: AttendeeCredential): AttendeeRevocation { if (offline) throw AttendeeFailure(AttendeeProblem.OFFLINE); return AttendeeRevocation.REVOKED }
    }
    private fun start(fontScale: Float = 1f) {
        compose.setContent { CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, fontScale)) {
            AttendeeAccountApp(controller, { closes++ }, { authorization=it; bridge.expectedCode="nac1_"+AttendeePkce.challenge(it.state); bridge.expectedChallenge=AttendeePkce.challenge(it.verifier); browserOpens++ }, { websiteOpens++ }, { ticketOpens++ })
        } }
    }
    private fun show(text: String) { compose.onNodeWithTag("attendee-account").performScrollToNode(hasText(text)); compose.onNodeWithText(text).assertIsDisplayed() }
    private fun showAt(index: Int,text: String) {
        val lists = compose.onAllNodesWithTag("attendee-account").fetchSemanticsNodes()
        assertEquals("Exactly one account list must be present", 1, lists.size)
        compose.runOnIdle {
            val action = lists.single().config[androidx.compose.ui.semantics.SemanticsActions.ScrollToIndex].action
            assertNotNull(action); assertTrue(action!!.invoke(index))
        }
        compose.waitForIdle()
        compose.onNodeWithText(text).assertIsDisplayed()
    }
    private fun capture(name: String) {
        compose.waitForIdle()
        val instrumentation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
        val rendered=java.util.concurrent.CountDownLatch(1)
        val listener=android.view.ViewTreeObserver.OnDrawListener {rendered.countDown()}
        compose.activityRule.scenario.onActivity { activity ->
            activity.window.decorView.viewTreeObserver.addOnDrawListener(listener)
            activity.window.decorView.postInvalidateOnAnimation()
        }
        try { assertTrue("Synthetic state did not render a fresh frame",rendered.await(5,java.util.concurrent.TimeUnit.SECONDS)) }
        finally {compose.activityRule.scenario.onActivity {it.window.decorView.viewTreeObserver.removeOnDrawListener(listener)}}
        instrumentation.waitForIdleSync()
        val copied=java.util.concurrent.CountDownLatch(1)
        var copyResult=android.view.PixelCopy.ERROR_UNKNOWN
        lateinit var bitmap: android.graphics.Bitmap
        compose.activityRule.scenario.onActivity { activity ->
            val view=activity.window.decorView
            bitmap=android.graphics.Bitmap.createBitmap(view.width,view.height,android.graphics.Bitmap.Config.ARGB_8888)
            android.view.PixelCopy.request(activity.window,bitmap,{result -> copyResult=result;copied.countDown()},android.os.Handler(android.os.Looper.getMainLooper()))
        }
        try {
            assertTrue("Synthetic window pixels were not copied",copied.await(5,java.util.concurrent.TimeUnit.SECONDS))
            assertEquals(android.view.PixelCopy.SUCCESS,copyResult)
            val directory=java.io.File(instrumentation.targetContext.filesDir,"review-shots").apply {mkdirs()}
            java.io.File(directory,"$name.png").outputStream().use {bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)}
        } finally {bitmap.recycle()}
    }
    private fun complete() {
        val auth = authorization!!
        runBlocking { assertTrue(controller.callback("${AttendeeIntegration.CALLBACK}?code=${bridge.expectedCode}&state=${auth.state}")) }
        compose.waitForIdle()
    }
    @Test fun actualPlatformJsonDecoderRejectsDuplicateKeysAndPreservesCanonicalToken() = runBlocking {
        val token="na1_"+"t".repeat(43)
        val body="{\"access_token\":\"$token\",\"token_type\":\"Bearer\",\"expires_at\":\"${now.plusSeconds(1800)}\",\"event\":\"dqor-2026\",\"capabilities\":[\"account:read\",\"passes:read\"]}"
        val bridge=AttendeeHttpBridge {AttendeeWireResponse(200,body)}
        assertEquals(token,bridge.exchange(AttendeeExchange("nac1_"+"c".repeat(43),"v".repeat(43))).credential.value)
        try {AttendeeJson(body.dropLast(1)+",\"access_token\":\"$token\"}").parse(); fail("Duplicate token key accepted")} catch(failure: AttendeeFailure) {assertEquals(AttendeeProblem.INVALID_RESPONSE,failure.problem)}
    }
    @Test fun browserCancelBackAndSyntheticReadOnlyPassJourney() {
        start()
        show("Sign in through system browser"); compose.onNodeWithText("Sign in through system browser").performClick()
        show("Continue in your browser"); capture("auth-synthetic-browser-pending")
        assertNull(controller.begin()); assertEquals(1,browserOpens)
        show("Cancel sign-in"); compose.onNodeWithText("Cancel sign-in").performClick()
        show("Sign in through system browser"); compose.onNodeWithText("Sign in through system browser").performClick(); complete()
        show("Synthetic conference status"); capture("auth-synthetic-read-only-pass")
        show("Status only · no QR or admission action"); compose.onNodeWithText("Confirm entry").assertDoesNotExist()
        compose.activityRule.scenario.onActivity { it.onBackPressedDispatcher.onBackPressed() }
        assertEquals(1,closes)
    }
    class CooldownFixtureModel : androidx.lifecycle.ViewModel() {
        var controller: AttendeeController? = null
        override fun onCleared() { controller?.forget() }
    }
    @Test fun rateLimitBlocksRepeatedBrowserStartsThroughBackgroundAndResume() {
        bridge.rateLimited = true
        start()
        compose.activityRule.scenario.onActivity { androidx.lifecycle.ViewModelProvider(it)[CooldownFixtureModel::class.java].controller = controller }
        show("Sign in through system browser"); compose.onNodeWithText("Sign in through system browser").performClick(); complete()
        show("Too many attempts. Wait three minutes before trying again.")
        capture("auth-synthetic-rate-limited")
        compose.onNodeWithText("Sign in through system browser").assertIsNotEnabled().performClick().performClick()
        assertNull(controller.begin()); assertEquals(1, browserOpens); assertEquals(1, bridge.exchanges)
        compose.activityRule.scenario.moveToState(androidx.lifecycle.Lifecycle.State.CREATED)
        controller.background()
        compose.activityRule.scenario.moveToState(androidx.lifecycle.Lifecycle.State.RESUMED)
        runBlocking { controller.foreground() }
        show("Sign in through system browser"); compose.onNodeWithText("Sign in through system browser").assertIsNotEnabled()
        show("Open account on official website"); compose.onNodeWithText("Open account on official website").assertIsEnabled()
        compose.onNodeWithText("synthetic@example.invalid").assertDoesNotExist()
        elapsed = 179_999L; compose.runOnIdle { controller.expire() }
        show("Try again in 0:01. You can use the official website while you wait.")
        assertNull(controller.begin())
        elapsed = 180_000L; compose.runOnIdle { controller.expire() }
        show("Sign in through system browser"); compose.onNodeWithText("Sign in through system browser").assertIsEnabled()
        assertEquals(1, browserOpens); assertEquals(1, bridge.exchanges)
        bridge.rateLimited = false
        compose.onNodeWithText("Sign in through system browser").performClick(); complete()
        show("Synthetic conference status"); capture("auth-synthetic-rate-limit-recovered")
        assertEquals(2, browserOpens); assertEquals(2, bridge.exchanges)
        bridge.rateLimited = true
        runBlocking { controller.logout() }
        show("Sign in through system browser"); compose.onNodeWithText("Sign in through system browser").performClick(); complete()
        assertEquals(180, controller.retryAfterSeconds.value)
        compose.activityRule.scenario.recreate()
        compose.activityRule.scenario.onActivity {
            assertSame(controller, androidx.lifecycle.ViewModelProvider(it)[CooldownFixtureModel::class.java].controller)
            assertEquals(180, controller.retryAfterSeconds.value); assertNull(controller.begin())
        }
        assertEquals(3, browserOpens); assertEquals(3, bridge.exchanges)
        controller.forget()
    }
    @Test fun largeTextRateLimitKeepsWebsiteActionsAvailableWithoutStartingNativeAuth() {
        bridge.rateLimited = true; start(1.6f)
        show("Sign in through system browser"); compose.onNodeWithText("Sign in through system browser").performClick(); complete()
        show("Sign in through system browser"); compose.onNodeWithText("Sign in through system browser").assertIsNotEnabled()
        capture("auth-synthetic-rate-limited-large-text")
        show("Open account on official website"); compose.onNodeWithText("Open account on official website").assertIsEnabled().performClick()
        show("Open actual tickets on website"); compose.onNodeWithText("Open actual tickets on website").assertIsEnabled().performClick()
        assertEquals(1, websiteOpens); assertEquals(1, ticketOpens); assertEquals(1, browserOpens); assertEquals(1, bridge.exchanges)
        compose.activityRule.scenario.onActivity { it.onBackPressedDispatcher.onBackPressed() }
        assertEquals(1, closes); assertNull(controller.begin())
        controller.forget()
    }
    @Test fun boundedPassPagesPreserveAccountAndOfferWebsiteInsteadOfMoreReads() {
        start()
        try {
            for(total in listOf(199,200)) {
                bridge.pageSizes=List(9) {20}+listOf(total-180,20)
                bridge.observed=now.minusSeconds(5)
                show("Sign in through system browser");compose.onNodeWithText("Sign in through system browser").performClick();complete()
                repeat(9) {index ->
                    showAt((controller.state.value as AttendeeState.Ready).snapshot.passes.size + 4,"Load more pass status");compose.onNodeWithText("Load more pass status").performClick()
                    compose.waitUntil(5_000) {(controller.state.value as? AttendeeState.Ready)?.snapshot?.passes?.size==minOf((index+2)*20,total)}
                }
                val verified=(controller.state.value as AttendeeState.Ready).snapshot
                assertEquals((1..total).map(Int::toString),verified.passes.map {it.id})
                bridge.observed=now.minusSeconds(1)
                if(total==199) {
                    showAt((controller.state.value as AttendeeState.Ready).snapshot.passes.size + 4,"Load more pass status");compose.onNodeWithText("Load more pass status").performClick()
                    compose.waitUntil(5_000) {(controller.state.value as? AttendeeState.Ready)?.snapshot?.let {it.nextCursor==null}==true}
                }
                val bounded=(controller.state.value as AttendeeState.Ready).snapshot
                assertEquals(verified.identity,bounded.identity);assertEquals(verified.passes,bounded.passes);assertEquals(verified.checkedAt,bounded.checkedAt)
                showAt(3,"synthetic@example.invalid");showAt(total+3,"Synthetic conference status $total")
                showAt(total+4,"More pass status is available on the official website.")
                compose.onNodeWithText("Load more pass status").assertDoesNotExist()
                capture("auth-synthetic-pass-limit-$total")
                val stopped=bridge.pageReads
                runBlocking {controller.nextPage()};assertEquals(stopped,bridge.pageReads)
                bridge.pageSizes=listOf(20)
                showAt(3,"Refresh account status");compose.onNodeWithText("Refresh account status").performClick()
                compose.waitUntil(5_000) {(controller.state.value as? AttendeeState.Ready)?.snapshot?.passes?.size==20}
                showAt((controller.state.value as AttendeeState.Ready).snapshot.passes.size + 4,"Load more pass status");assertEquals(stopped+1,bridge.pageReads)
                showAt((controller.state.value as AttendeeState.Ready).snapshot.passes.size + 5,"Sign out and clear account");compose.onNodeWithText("Sign out and clear account").performClick()
                show("Sign in through system browser")
            }
        } finally {controller.forget()}
    }
    @Test fun emptyPassesAndOfflineLogoutAreHonest() {
        bridge.empty=true; start()
        show("Sign in through system browser"); compose.onNodeWithText("Sign in through system browser").performClick(); complete()
        show("No assigned passes"); capture("auth-synthetic-empty-passes")
        bridge.offline=true; show("Sign out and clear account"); compose.onNodeWithText("Sign out and clear account").performClick()
        show("Account cleared on this device. Server revocation could not be confirmed.")
        compose.onNodeWithText("synthetic@example.invalid").assertDoesNotExist(); capture("auth-synthetic-offline-logout")
    }
    @Test fun largerTextAndConservativeExpiryClearPrivateStatus() {
        start(1.6f); show("Sign in through system browser"); compose.onNodeWithText("Sign in through system browser").performClick(); complete()
        show("Synthetic conference status"); capture("auth-synthetic-large-text")
        elapsed=1_800_000; compose.runOnIdle {controller.expire()}
        show("Your secure session or sign-in expired."); compose.onNodeWithText("synthetic@example.invalid").assertDoesNotExist()
        capture("auth-synthetic-expired-session")
    }
}
