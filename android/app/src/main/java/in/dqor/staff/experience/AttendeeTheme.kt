package `in`.dqor.staff.experience

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

internal val AttendeeLightColors=lightColorScheme(
    primary=Color(0xFF9C1F42),onPrimary=Color.White,
    primaryContainer=Color(0xFFF8EFF2),onPrimaryContainer=Color(0xFF262626),
    secondary=Color(0xFF5C5C5C),onSecondary=Color.White,
    secondaryContainer=Color(0xFF262626),onSecondaryContainer=Color.White,
    background=Color.White,onBackground=Color(0xFF262626),
    surface=Color.White,onSurface=Color(0xFF262626),
    surfaceVariant=Color(0xFFF2F2F2),onSurfaceVariant=Color(0xFF5C5C5C),
    surfaceContainer=Color.White,surfaceContainerLow=Color.White,
    surfaceContainerHigh=Color(0xFFF2F2F2),surfaceContainerHighest=Color.White,
    outline=Color(0xFF767676),outlineVariant=Color(0xFFDADADA),surfaceTint=Color.Transparent
)
internal val AttendeeDarkColors=darkColorScheme(
    primary=Color(0xFFFA8CA6),onPrimary=Color(0xFF262626),
    primaryContainer=Color(0xFF34262C),onPrimaryContainer=Color(0xFFF5F5F5),
    secondary=Color(0xFFB8B8B8),onSecondary=Color(0xFF262626),
    secondaryContainer=Color(0xFFF5F5F5),onSecondaryContainer=Color(0xFF262626),
    background=Color(0xFF121212),onBackground=Color(0xFFF5F5F5),
    surface=Color(0xFF121212),onSurface=Color(0xFFF5F5F5),
    surfaceVariant=Color(0xFF242424),onSurfaceVariant=Color(0xFFB8B8B8),
    surfaceContainer=Color(0xFF1C1C1E),surfaceContainerLow=Color(0xFF1C1C1E),
    surfaceContainerHigh=Color(0xFF242424),surfaceContainerHighest=Color(0xFF1C1C1E),
    outline=Color(0xFF8D8D8D),outlineVariant=Color(0xFF3D3D40),surfaceTint=Color.Transparent
)
@Composable fun AttendeeTheme(content: @Composable () -> Unit) {
    val colors=if(isSystemInDarkTheme()) AttendeeDarkColors else AttendeeLightColors
    CompositionLocalProvider(LocalAttendeeMotion provides rememberAttendeeMotion()) {
        MaterialTheme(colorScheme=colors,
            shapes=Shapes(small=RoundedCornerShape(10.dp),medium=RoundedCornerShape(18.dp),large=RoundedCornerShape(24.dp)),content=content)
    }
}
