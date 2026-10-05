package `in`.dqor.staff.experience

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

// Attendee surfaces are intentionally independent of the neutral staff workspace.
val AttendeeColors=lightColorScheme(
    primary=Color(0xFF642F47),onPrimary=Color.White,
    primaryContainer=Color(0xFFEDE8E3),onPrimaryContainer=Color(0xFF332631),
    secondary=Color(0xFF766555),onSecondary=Color.White,
    secondaryContainer=Color(0xFF332631),onSecondaryContainer=Color.White,
    background=Color(0xFFF8F5F2),onBackground=Color(0xFF332631),
    surface=Color(0xFFF8F5F2),onSurface=Color(0xFF332631),
    surfaceVariant=Color(0xFFF0EEEA),onSurfaceVariant=Color(0xFF6A6560),
    surfaceContainer=Color.White,surfaceContainerLow=Color.White,
    surfaceContainerHigh=Color(0xFFF0EEEA),surfaceContainerHighest=Color.White,
    outline=Color(0xFF918A82),outlineVariant=Color(0xFFE5E0D9),surfaceTint=Color.Transparent
)
@Composable fun AttendeeTheme(content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalAttendeeMotion provides rememberAttendeeMotion()) {
        MaterialTheme(colorScheme=AttendeeColors,
            shapes=Shapes(small=RoundedCornerShape(10.dp),medium=RoundedCornerShape(18.dp),large=RoundedCornerShape(24.dp)),content=content)
    }
}
