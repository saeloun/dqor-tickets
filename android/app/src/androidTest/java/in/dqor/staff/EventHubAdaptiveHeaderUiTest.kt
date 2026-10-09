package `in`.dqor.staff

import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.test.platform.app.InstrumentationRegistry
import `in`.dqor.staff.experience.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class EventHubAdaptiveHeaderUiTest {
    @get:Rule val compose=createComposeRule()
    private val instrumentation=InstrumentationRegistry.getInstrumentation()
    private val events=listOf(Event("dqor-2026","Deccan Queen on Rails","Pune, India","A meeting of curious minds",listOf("2026-10-08","2026-10-09","2026-10-10","2026-10-11"),"heritage"))
    private fun fixture(name: String)=instrumentation.targetContext.assets.open(name).bufferedReader().use {it.readText()}
    private fun back(expectedTag: String) {
        instrumentation.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
        compose.waitForIdle()
        compose.waitUntil(5_000) {compose.onAllNodesWithTag(expectedTag).fetchSemanticsNodes().isNotEmpty()}
    }
    @Test fun systemScaledEventHeaderPreservesControlsAndUsefulViewport() {
        var staffClicks=0
        var density=1f
        var fontScale=1f
        compose.setContent {
            density=LocalDensity.current.density
            fontScale=LocalDensity.current.fontScale
            EventHubApp(events,EventExperience.parse(fixture("experience.json"))) {staffClicks++}
        }
        assertEquals("Inherited system font scale",instrumentation.targetContext.resources.configuration.fontScale,fontScale,0.01f)
        compose.onNodeWithTag("event-list").performScrollToNode(hasText("Deccan Queen on Rails"))
        compose.onNodeWithText("Deccan Queen on Rails").performScrollTo().assertIsDisplayed().performClick()
        compose.captureDemo("event-header-overview-system-scale")
        val controls=listOf("← All events","Staff workspace")
        val bounds=controls.map {label ->
            val action=compose.onNodeWithText(label).assertIsDisplayed()
            val layout=mutableListOf<TextLayoutResult>()
            action.performSemanticsAction(SemanticsActions.GetTextLayoutResult) {assertTrue(it(layout))}
            assertEquals(1,layout.size)
            val textLayout=layout.single()
            val textNodes=compose.onAllNodesWithText(label,useUnmergedTree=true).fetchSemanticsNodes()
            val textBounds=compose.runOnUiThread {textNodes.single().boundsInRoot}
            val textSize=compose.runOnUiThread {textNodes.single().size}
            assertTrue("$label text is fully unclipped horizontally",textBounds.width>=textSize.width)
            assertTrue("$label text is fully unclipped vertically",textBounds.height>=textSize.height)
            for(line in 0 until textLayout.lineCount) {
                assertTrue("$label line is complete",textLayout.getLineEnd(line,true)==textLayout.getLineEnd(line))
                assertTrue("$label line is not ellipsized",!textLayout.isLineEllipsized(line))
                assertTrue("$label line horizontal extents fit",textLayout.getLineLeft(line)>=0 && textLayout.getLineRight(line)<=textLayout.size.width)
                assertTrue("$label line vertical extents fit",textLayout.getLineTop(line)>=0 && textLayout.getLineBottom(line)<=textLayout.size.height)
            }
            assertEquals("$label complete visible text",label.length,textLayout.getLineEnd(textLayout.lineCount-1,true))
            for(offset in label.indices) {
                val character=textLayout.getBoundingBox(offset)
                assertTrue("$label character$offset horizontal extents fit",character.left>=0 && character.right<=textLayout.size.width)
                assertTrue("$label character$offset vertical extents fit",character.top>=0 && character.bottom<=textLayout.size.height)
            }
            for(word in label.split(" ")) {
                val first=label.indexOf(word)
                assertEquals("Whole word $word",layout.single().getLineForOffset(first),layout.single().getLineForOffset(first+word.length-1))
            }
            val node=compose.onAllNodesWithText(label).fetchSemanticsNodes().single()
            val rect=compose.runOnUiThread {node.boundsInRoot}
            assertTrue("${label}48dp target height",rect.height>=48*density-1)
            assertTrue("${label}48dp target width",rect.width>=48*density-1)
            rect
        }
        assertTrue("Header actions do not overlap",bounds[0].right<=bounds[1].left || bounds[1].right<=bounds[0].left || bounds[0].bottom<=bounds[1].top || bounds[1].bottom<=bounds[0].top)
        compose.onNodeWithText("Staff workspace").performClick()
        compose.runOnIdle {assertEquals(1,staffClicks)}
        compose.onNodeWithText("Schedule").assertIsDisplayed().performClick()
        val node=compose.onAllNodesWithTag("schedule-list").fetchSemanticsNodes().single()
        val viewport=compose.runOnUiThread {node.boundsInRoot}
        compose.captureDemo("event-header-schedule-system-scale")
        assertTrue("Body viewport fits two48dp controls",viewport.height>=96*density-1)
        compose.onNodeWithTag("schedule-list").performScrollToNode(hasText("Saved sessions"))
        compose.onNodeWithText("Saved sessions").performScrollTo().assertIsDisplayed()
        back("event-overview")
        compose.onNodeWithTag("event-overview").assertExists()
        compose.onNodeWithText("← All events").assertIsDisplayed().performClick()
        compose.onNodeWithTag("event-list").assertExists()
    }
}
