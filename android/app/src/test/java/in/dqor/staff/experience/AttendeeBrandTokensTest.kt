package `in`.dqor.staff.experience

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import org.junit.Assert.*
import org.junit.Test

class AttendeeBrandTokensTest {
    private fun contrast(a: Color,b: Color): Float {
        val first=a.luminance();val second=b.luminance()
        return (maxOf(first,second)+0.05f)/(minOf(first,second)+0.05f)
    }
    @Test fun bothAppearancesKeepReadableCardsButtonsAndSecondaryText() {
        for(colors in listOf(AttendeeLightColors,AttendeeDarkColors)) {
            for((foreground,background) in listOf(colors.onBackground to colors.background,colors.onSurface to colors.surfaceContainer,
                colors.onSurfaceVariant to colors.surfaceVariant,colors.onPrimary to colors.primary,colors.onPrimaryContainer to colors.primaryContainer,
                colors.primary to colors.surfaceContainer,colors.secondary to colors.background)) {
                assertTrue("Text contrast must remain at least 4.5:1",contrast(foreground,background)>=4.5f)
            }
        }
        assertTrue(AttendeeLightColors.background.luminance()>0.9f)
        assertTrue(AttendeeDarkColors.background.luminance()<0.1f)
    }
    @Test fun reducedMotionRemovesFeedbackAndRevealDelays() {
        assertEquals(0,AttendeeMotion(false).feedbackMillis)
        assertEquals(0,AttendeeMotion(false).revealMillis)
        assertEquals(220,AttendeeMotion(true).feedbackMillis)
        assertEquals(240,AttendeeMotion(true).revealMillis)
    }
}
