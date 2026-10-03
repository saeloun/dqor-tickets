package `in`.dqor.staff

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.lifecycle.Lifecycle
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test

class PublishedLauncherSmokeTest {
    @get:Rule val compose=createEmptyComposeRule()
    @Test fun actualLauncherLoadsPublishedProgrammeAndRevalidatesOnResume() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("livePublic")=="true")
        var savedDescription=""
        ActivityScenario.launch(MainActivity::class.java).use {scenario ->
            compose.waitUntil(30_000) {compose.onAllNodesWithText("Published programme verified").fetchSemanticsNodes().isNotEmpty()}
            compose.onNodeWithText("Official public programme").assertIsDisplayed()
            compose.onNodeWithText("Programme").performClick()
            compose.onNodeWithTag("published-programme").performScrollToNode(hasText("Thu, 8 Oct"))
            compose.onNodeWithText("Thu, 8 Oct").assertIsDisplayed()
            compose.onNodeWithTag("published-programme").performScrollToNode(hasText("Find a session or speaker"))
            compose.onNodeWithText("Find a session or speaker").assertIsDisplayed()
            compose.onNodeWithText("Sample wallet · not valid for entry").assertDoesNotExist()
            compose.onNodeWithTag("published-programme").performScrollToNode(hasContentDescription("Save ",substring=true))
            val save=compose.onAllNodes(hasContentDescription("Save ",substring=true)).onFirst()
            savedDescription=save.fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.ContentDescription].first().replaceFirst("Save ","Unsave ")
            save.performClick()
            scenario.moveToState(Lifecycle.State.CREATED);scenario.moveToState(Lifecycle.State.RESUMED)
            compose.onNodeWithTag("published-programme").performScrollToIndex(0)
            compose.waitUntil(30_000) {compose.onAllNodesWithText("Published programme verified").fetchSemanticsNodes().isNotEmpty()}
            compose.onNodeWithText("Refresh programme").assertIsEnabled().performClick()
            compose.waitUntil(30_000) {compose.onAllNodesWithText("Published programme verified").fetchSemanticsNodes().isNotEmpty()}
        }
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.waitUntil(30_000) {compose.onAllNodesWithText("Published programme verified").fetchSemanticsNodes().isNotEmpty()}
            compose.onNodeWithText("Programme").performClick()
            compose.onNodeWithTag("published-programme").performScrollToNode(hasContentDescription(savedDescription))
            compose.onNodeWithContentDescription(savedDescription).assertIsDisplayed()
            compose.onNodeWithTag("published-programme").performScrollToNode(hasText("Clear local programme and bookmarks"))
            compose.onNodeWithText("Clear local programme and bookmarks").performClick()
            compose.onNodeWithText("Clear local data").performClick()
            compose.onNodeWithText("No programme downloaded").assertIsDisplayed()
            compose.onNodeWithText("Load published programme").assertIsEnabled()
        }
    }
}
