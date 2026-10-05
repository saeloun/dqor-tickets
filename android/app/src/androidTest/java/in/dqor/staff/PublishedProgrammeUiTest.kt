package `in`.dqor.staff

import android.os.ParcelFileDescriptor
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.test.platform.app.InstrumentationRegistry
import `in`.dqor.staff.programme.*
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.launch
import java.io.File
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class PublishedProgrammeUiTest {
    @get:Rule val compose=createComposeRule()
    private val instrumentation=InstrumentationRegistry.getInstrumentation()
    private fun fixture(): PublicProgramme {
        val source=PublicProgramme.parse(instrumentation.targetContext.assets.open("public_programme_example.json").bufferedReader().use {it.readText()})
        return source.copy(sessions=(1..20).map {id -> source.sessions.first().copy(id=id.toString(),title="Synthetic session $id",abstract="Synthetic description $id",startsAt=source.sessions.first().startsAt!!.plusMinutes(id.toLong()),endsAt=source.sessions.first().endsAt!!.plusMinutes(id.toLong()))})
    }
    private var data by mutableStateOf(PublishedProgrammeState(snapshot=fixture()))
    private var saved by mutableStateOf(emptySet<String>())
    private fun setup(scale: Float=1f) {compose.setContent {val density=LocalDensity.current; CompositionLocalProvider(LocalDensity provides Density(density.density,scale)) {PublishedProgrammeApp(data,{}, {data=PublishedProgrammeState();saved=emptySet()},{},{},saved,{saved=if(it in saved) saved-it else saved+it})}}}
    private fun show(text: String) {compose.onNodeWithTag("published-programme").performScrollToNode(hasText(text));compose.onNodeWithText(text).performScrollTo().assertIsDisplayed()}
    private fun detail(id: Int,text: String="Session details") {compose.onNodeWithTag("published-programme").performScrollToNode(hasTestTag("public-session-$id")); compose.onNode(hasText(text) and hasAnyAncestor(hasTestTag("public-session-$id"))).performScrollTo().performClick();compose.waitForIdle()}
    private fun back(overview: Boolean=false) {instrumentation.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK);compose.waitForIdle();if(overview) compose.waitUntil(5_000) {compose.onAllNodesWithTag("published-overview").fetchSemanticsNodes().isNotEmpty()}}
    private fun collapsed(id: Int) {val matcher=hasText("Session details") and hasAnyAncestor(hasTestTag("public-session-$id"));compose.waitUntil(5_000) {compose.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty()};compose.onNode(matcher).performScrollTo().assertIsDisplayed()}
    private fun programme() {compose.onNodeWithText("Programme").performClick();compose.waitForIdle()}
    private fun filterEvidence(name: String) {
        compose.captureDemo(name)
        File(instrumentation.targetContext.filesDir,"review-shots/$name-semantics.txt").writeText(compose.onRoot().printToString())
    }
    private fun unmatchedQuery() {
        compose.onNode(hasSetTextAction()).assert(SemanticsMatcher.expectValue(SemanticsProperties.EditableText,AnnotatedString("unmatched")))
        compose.onNodeWithText("0 sessions").assertExists()
        compose.onAllNodes(SemanticsMatcher("Published session row") {it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("public-session-")==true}).assertCountEquals(0)
    }
    @Test fun actualBackCollapsesLatestOffscreenDetailBeforeReturningToOverview() {
        setup();programme();detail(1);detail(20)
        show("Find a session or speaker");compose.captureDemo("public-long-list-before-back")
        back();compose.onNodeWithText("Programme").assertIsDisplayed()
        compose.onNodeWithTag("published-programme").performScrollToNode(hasTestTag("public-session-20"))
        collapsed(20)
        show("Find a session or speaker");back()
        compose.onNodeWithTag("published-programme").performScrollToNode(hasTestTag("public-session-1"))
        collapsed(1)
        compose.captureDemo("public-long-list-after-collapse")
        back(true);show("Your tickets");compose.onNodeWithText("A day to remember").assertDoesNotExist()
    }
    @Test fun savedUnsaveAndDateSearchChangesLeaveNoHiddenBackStep() {
        setup();programme();detail(1)
        compose.onNodeWithContentDescription("Save Synthetic session 1").performClick()
        show("Saved sessions");compose.onNodeWithText("Saved sessions").performClick();detail(1)
        compose.onNodeWithContentDescription("Unsave Synthetic session 1").performClick()
        show("No saved sessions for this day");back(true);show("Your tickets")
        programme();show("Reset filters");compose.onNodeWithText("Reset filters").performClick();detail(1)
        show("Fri, 9 Oct");compose.onNodeWithText("Fri, 9 Oct").performClick();show("No sessions match");back(true);show("Your tickets")
        programme();show("Thu, 8 Oct");compose.onNodeWithText("Thu, 8 Oct").performClick();detail(1)
        try {
            show("Find a session or speaker");compose.onNodeWithText("Find a session or speaker").performTextInput("unmatched")
            unmatchedQuery()
            instrumentation.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_ESCAPE);compose.waitForIdle()
            unmatchedQuery();show("No sessions match")
            filterEvidence("public-filter-after-assertions")
            back(true);show("Your tickets")
        } catch(failure: Throwable) {
            filterEvidence("public-filter-failure")
            throw failure
        }
    }
    @Test fun authoritativeWithdrawalAndClearRemoveSavedDetailState() {
        setup();programme();detail(1);compose.onNodeWithContentDescription("Save Synthetic session 1").performClick()
        compose.runOnIdle {data=data.copy(snapshot=data.snapshot!!.copy(sessions=emptyList(),speakers=emptyList()));saved=emptySet()}
        show("No sessions published");back(true);show("Your tickets")
        show("Clear local programme and bookmarks");compose.onNodeWithText("Clear local programme and bookmarks").performClick()
        compose.onNodeWithText("Cancel").performClick();assertNotNull(data.snapshot)
        compose.onNodeWithText("Clear local programme and bookmarks").performClick();compose.onNodeWithText("Clear local data").performClick()
        show("No programme downloaded");assertNull(data.snapshot);assertTrue(saved.isEmpty())
        compose.captureDemo("public-local-data-cleared")
    }
    @Test fun slowOfflineRefreshBlocksRepeatedTapsAndRecovers() {
        val response=CompletableDeferred<ProgrammeResponse>();var requests=0
        val source=instrumentation.targetContext.assets.open("public_programme_example.json").bufferedReader().use {it.readText()}
        val store=PublishedProgrammeStore(ProgrammeTransport {requests++;if(requests==1) response.await() else ProgrammeResponse(200,"\"fixture\"",source)})
        compose.setContent {val state by store.state.collectAsState();val scope=rememberCoroutineScope();LaunchedEffect(Unit) {store.refresh()};PublishedProgrammeApp(state,{scope.launch {store.refresh()}},{store.clear()},{},{},emptySet(),{})}
        compose.onNodeWithText("Checking the published programme…").assertIsDisplayed()
        compose.onNodeWithText("Load published programme").assertIsNotEnabled().performClick().performClick()
        compose.runOnIdle {assertEquals(1,requests)};compose.captureDemo("public-pending-download")
        compose.runOnIdle {response.completeExceptionally(ProgrammeOfflineException())};compose.waitForIdle()
        compose.onNodeWithText("Programme unavailable").assertIsDisplayed();compose.onNodeWithText("Could not connect. Check your connection and retry.").assertIsDisplayed()
        compose.captureDemo("public-offline-empty")
        assertNull(store.state.value.snapshot)
        compose.onNodeWithText("Load published programme").performClick();compose.waitForIdle()
        compose.waitUntil(5_000) {compose.onAllNodesWithText("Published programme verified").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithText("Published programme verified").assertIsDisplayed();assertNotNull(store.state.value.snapshot)
    }
    @Test fun largeTextReducedMotionAndRepeatedBookmarksKeepActualBackAvailable() {
        val stream=ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand("settings get global animator_duration_scale"))
        val initial=stream.bufferedReader().use {it.readText().trim()}
        fun shell(command: String)=ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand(command)).bufferedReader().use {it.readText().trim()}
        try {shell("settings put global animator_duration_scale 0");assertEquals("0",shell("settings get global animator_duration_scale"));setup(2f);programme();detail(1)
            repeat(3) {compose.onNodeWithContentDescription("Save Synthetic session 1").performScrollTo().performClick();compose.onNodeWithContentDescription("Unsave Synthetic session 1").performScrollTo().performClick()}
            compose.captureDemo("public-large-text-reduced-motion");show("Find a session or speaker");back()
            compose.onNodeWithTag("published-programme").performScrollToNode(hasTestTag("public-session-1"));collapsed(1)
            back(true);show("Your tickets")
        } finally {shell(if(initial=="null") "settings delete global animator_duration_scale" else "settings put global animator_duration_scale $initial")}
    }
    @Test fun staleCacheWarnsUntilAnAuthoritativeEmptyReplacement() {
        val source=instrumentation.targetContext.assets.open("public_programme_example.json").bufferedReader().use {it.readText()}
        var requests=0
        val store=PublishedProgrammeStore(ProgrammeTransport {when(++requests) {1 -> ProgrammeResponse(200,"\"fixture\"",source);2 -> throw ProgrammeOfflineException();else -> ProgrammeResponse(200,"\"empty\"",org.json.JSONObject(source).put("sessions",org.json.JSONArray()).put("speakers",org.json.JSONArray()).toString())}})
        compose.setContent {val state by store.state.collectAsState();val scope=rememberCoroutineScope();LaunchedEffect(Unit) {store.refresh()};PublishedProgrammeApp(state,{scope.launch {store.refresh()}},{store.clear()},{},{},emptySet(),{})}
        compose.waitUntil(5_000) {compose.onAllNodesWithText("Published programme verified").fetchSemanticsNodes().isNotEmpty()};compose.onNodeWithText("Published programme verified").assertIsDisplayed()
        compose.onNodeWithText("Refresh programme").performClick();compose.waitForIdle()
        compose.onNodeWithText("Saved programme · needs revalidation").assertIsDisplayed()
        compose.onNodeWithText("Sessions may have changed or been withdrawn. Reconnect to verify the latest programme.").assertIsDisplayed();compose.captureDemo("public-cached-offline-warning")
        compose.onNodeWithText("Refresh programme").performClick();compose.waitForIdle()
        compose.waitUntil(5_000) {compose.onAllNodesWithText("Published programme verified").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithText("Published programme verified").assertIsDisplayed();programme();show("No sessions published")
        compose.onNodeWithText("Synthetic published session").assertDoesNotExist();compose.captureDemo("public-authoritative-empty")
    }
    @Test fun onlyOpaqueBookmarksSurviveColdStoreAndPrivacyClear() {
        val context=instrumentation.targetContext;val first=PublicBookmarks(context);first.clear()
        try {first.toggle("101");first.toggle("102");assertEquals(setOf("101","102"),PublicBookmarks(context).state.value)
            first.retain(setOf("102"));assertEquals(setOf("102"),PublicBookmarks(context).state.value)
            first.clear();assertTrue(PublicBookmarks(context).state.value.isEmpty())
            assertNull(PublishedProgrammeStore(ProgrammeTransport {throw ProgrammeOfflineException()}).state.value.snapshot)
        } finally {first.clear()}
    }
}
