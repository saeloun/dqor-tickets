package `in`.dqor.staff

import android.accessibilityservice.AccessibilityServiceInfo
import android.Manifest
import android.content.pm.PackageManager
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.Lifecycle
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class ScannerRehearsalUiTest {
    @get:Rule val compose=createAndroidComposeRule<ComponentActivity>()
    private val instrumentation=InstrumentationRegistry.getInstrumentation()
    private fun nodes(node: AccessibilityNodeInfo?): List<AccessibilityNodeInfo> = if(node==null) emptyList() else listOf(node)+(0 until node.childCount).flatMap {nodes(node.getChild(it))}
    private fun permissionButton(id: String) {
        val automation=instrumentation.uiAutomation
        println("SCANNER_PERMISSION_ACCESS flags=${automation.serviceInfo.flags} rootPackage=${automation.rootInActiveWindow?.packageName}")
        fun permissionNodes()=automation.windows.flatMap {nodes(it.root)}.filter {it.packageName?.toString()?.endsWith("permissioncontroller")==true && it.isVisibleToUser}
        compose.waitUntil(10_000) {permissionNodes().any {it.viewIdResourceName?.endsWith(id)==true}}
        println("SCANNER_PERMISSION_ACCESS windows=${automation.windows.size} target=$id")
        assertTrue(permissionNodes().first {it.viewIdResourceName?.endsWith(id)==true}.performAction(AccessibilityNodeInfo.ACTION_CLICK))
        compose.waitForIdle()
    }
    @Test fun denialRetryRearPreviewPauseAndResumeRemainReadOnly() {
        assertEquals("Run this camera rehearsal from a fresh test app install with CAMERA ungranted",PackageManager.PERMISSION_DENIED,instrumentation.targetContext.checkSelfPermission(Manifest.permission.CAMERA))
        val automation=instrumentation.uiAutomation
        val previous=automation.serviceInfo.flags
        automation.serviceInfo=automation.serviceInfo.apply {flags=flags or AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS}
        try {
        var enabled by mutableStateOf(true);var scans=0
        compose.setContent {MaterialTheme {Column(Modifier.fillMaxSize().safeDrawingPadding()) {QrScanner(enabled) {scans++}}}}
        compose.onNodeWithText("Allow camera").assertIsDisplayed().performClick();permissionButton("permission_deny_button")
        compose.onNodeWithText("Retry camera permission").assertIsDisplayed();compose.onNodeWithText("Open camera settings").assertIsDisplayed()
        compose.captureDemo("scanner-permission-denied")
        compose.onNodeWithText("Retry camera permission").performClick();permissionButton("permission_allow_foreground_only_button")
        compose.waitUntil(15_000) {compose.onAllNodesWithText("Rear camera ready").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("rehearsal-camera").assertIsDisplayed();compose.onNodeWithText("Event admission · scanner rehearsal").assertIsDisplayed()
        compose.onNodeWithText("Scan this code again").performClick();assertEquals(0,scans);compose.captureDemo("scanner-rear-camera-rehearsal")
        compose.runOnIdle {enabled=false}
        compose.waitUntil(10_000) {compose.onAllNodesWithText("Rear camera paused").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithText("Scan this code again").assertIsNotEnabled();compose.captureDemo("scanner-paused-fail-closed")
        compose.runOnIdle {enabled=true};compose.waitUntil(15_000) {compose.onAllNodesWithText("Rear camera ready").fetchSemanticsNodes().isNotEmpty()}
        compose.activityRule.scenario.moveToState(Lifecycle.State.CREATED);compose.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
        compose.waitUntil(15_000) {compose.onAllNodesWithText("Rear camera ready").fetchSemanticsNodes().isNotEmpty()}
        assertEquals(0,scans)
        } finally {automation.serviceInfo=automation.serviceInfo.apply {flags=previous}}
    }
}
