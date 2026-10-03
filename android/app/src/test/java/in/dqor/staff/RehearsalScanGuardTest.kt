package `in`.dqor.staff

import org.junit.Assert.*
import org.junit.Test

class RehearsalScanGuardTest {
    @Test fun duplicateFramesRequireExplicitRetryAndBusyInputIsIgnored() {
        val guard=RehearsalScanGuard()
        assertFalse(guard.accept("demo-101",false));assertTrue(guard.accept("demo-101",true))
        assertFalse(guard.accept("demo-101",true));assertFalse(guard.accept("demo-102",false))
        assertTrue(guard.accept("demo-102",true));assertFalse(guard.accept("demo-102",true))
        guard.clear();assertTrue(guard.accept("demo-102",true))
    }
    @Test fun blankAndOversizedNoiseNeverBecomesTicketInput() {
        val guard=RehearsalScanGuard();assertFalse(guard.accept(" ",true));assertFalse(guard.accept("x".repeat(8193),true))
        assertTrue(guard.accept("demo-101",true))
    }
}
