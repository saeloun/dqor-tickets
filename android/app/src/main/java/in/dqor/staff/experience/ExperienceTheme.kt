package `in`.dqor.staff.experience

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

val OpsCanvas=Color(0xFFF6F5EF)
val OpsInk=Color(0xFF243024)
val OpsForest=Color(0xFF334B28)
val OperationsColors=lightColorScheme(primary=OpsForest,onPrimary=Color.White,background=OpsCanvas,
    secondary=OpsForest,onSecondary=Color.White,secondaryContainer=Color(0xFFE0E8D7),onSecondaryContainer=OpsInk,
    primaryContainer=Color(0xFFE0E8D7),onPrimaryContainer=OpsInk,
    surfaceContainer=Color(0xFFF0F0E8),surfaceContainerLow=Color(0xFFF0F0E8),surfaceContainerHigh=Color(0xFFE8EBDF),surfaceContainerHighest=Color(0xFFE8EBDF),
    onBackground=OpsInk,surface=Color(0xFFFFFEF9),onSurface=OpsInk,surfaceVariant=Color(0xFFE8EBDF),onSurfaceVariant=Color(0xFF465143),outline=Color(0xFF737D70))
val ConferenceColors=OperationsColors.copy(primary=Color(0xFF9F442C),onPrimary=Color.White,secondary=OpsForest,
    primaryContainer=Color(0xFFF5DDD2),onPrimaryContainer=Color(0xFF532210),secondaryContainer=Color(0xFFF5DDD2),onSecondaryContainer=Color(0xFF532210),surfaceContainerHighest=Color(0xFFF0E9DE))
val MidnightColors=darkColorScheme(primary=Color(0xFFE9BA7D),onPrimary=Color(0xFF302310),background=Color(0xFF141D2A),
    surface=Color(0xFF202C3D),onSurface=Color(0xFFF8F5ED),onBackground=Color(0xFFF8F5ED))
@Composable fun ExperienceTheme(theme: String? = null, content: @Composable () -> Unit) {
    MaterialTheme(colorScheme=when(theme) {"midnight" -> MidnightColors; "heritage" -> ConferenceColors; else -> OperationsColors},
        shapes=Shapes(small=RoundedCornerShape(8.dp),medium=RoundedCornerShape(12.dp),large=RoundedCornerShape(12.dp)),content=content)
}
