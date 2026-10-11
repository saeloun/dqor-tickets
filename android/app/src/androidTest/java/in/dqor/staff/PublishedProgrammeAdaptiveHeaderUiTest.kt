package `in`.dqor.staff

import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.test.platform.app.InstrumentationRegistry
import `in`.dqor.staff.programme.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class PublishedProgrammeAdaptiveHeaderUiTest {
    @get:Rule val compose=createComposeRule()
    private val instrumentation=InstrumentationRegistry.getInstrumentation()
    @Test fun systemScaledHeaderPreservesWordsActionsAndScrollableContent() {
        val data=PublicProgramme.parse(instrumentation.targetContext.assets.open("public_programme_example.json").bufferedReader().use {it.readText()})
        var accounts=0
        var previews=0
        var density=1f
        compose.setContent {
            density=LocalDensity.current.density
            PublishedProgrammeApp(PublishedProgrammeState(snapshot=data),{},{},{previews++},{},emptySet(),{},onAccount={accounts++})
        }
        val source="Official public programme"
        if(!compose.onNodeWithText(source).isDisplayed()) compose.onNodeWithTag("published-programme").performScrollToNode(hasText(source))
        val layout=mutableListOf<TextLayoutResult>()
        compose.onNodeWithText(source).assertIsDisplayed().performSemanticsAction(SemanticsActions.GetTextLayoutResult) {assertTrue(it(layout))}
        assertEquals(1,layout.size)
        for(word in source.split(" ")) {
            val first=source.indexOf(word)
            assertEquals("Whole word $word",layout.single().getLineForOffset(first),layout.single().getLineForOffset(first+word.length-1))
        }
        for(label in listOf("Account","Demo preview")) {
            if(!compose.onNodeWithText(label).isDisplayed()) compose.onNodeWithTag("published-programme").performScrollToNode(hasText(label))
            val action=compose.onNodeWithText(label).assertIsDisplayed()
            assertTrue("$label target height",action.fetchSemanticsNode().boundsInRoot.height>=48*density-1)
            action.performClick()
        }
        compose.runOnIdle {assertEquals(1,accounts);assertEquals(1,previews)}
        compose.captureDemo("public-adaptive-header-both-actions")
        compose.onNodeWithTag("published-programme").performScrollToNode(hasText("Your tickets"))
        compose.onNodeWithText("Your tickets").assertIsDisplayed()
        compose.onNodeWithText("Overview").assertIsDisplayed()
        compose.captureDemo("public-adaptive-header-body-visible")
        compose.onNodeWithText("Programme").performClick()
        compose.onNodeWithTag("published-programme").performScrollToNode(hasText("Find a session or speaker"))
        compose.onNodeWithText("Find a session or speaker").assertIsDisplayed()
        instrumentation.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
        compose.waitUntil(5_000) {compose.onAllNodesWithTag("published-overview").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("published-programme").performScrollToNode(hasText("Your tickets"))
        compose.onNodeWithText("Your tickets").assertIsDisplayed()
    }
}
