package `in`.dqor.staff.experience

import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp

internal data class AttendeeMotion(val enabled: Boolean = true) {
    val feedbackMillis get() = if(enabled) 140 else 0
    val revealMillis get() = if(enabled) 200 else 0
}
internal val LocalAttendeeMotion = staticCompositionLocalOf {AttendeeMotion()}

@Composable internal fun rememberAttendeeMotion(): AttendeeMotion {
    val resolver=LocalContext.current.contentResolver
    fun readAnimationsEnabled()=Settings.Global.getFloat(resolver,Settings.Global.ANIMATOR_DURATION_SCALE,1f)>0f
    var enabled by remember {mutableStateOf(readAnimationsEnabled())}
    DisposableEffect(resolver) {
        val observer=object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {enabled=readAnimationsEnabled()}
        }
        resolver.registerContentObserver(Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE),false,observer)
        onDispose {resolver.unregisterContentObserver(observer)}
    }
    return AttendeeMotion(enabled)
}

@Composable internal fun Modifier.attendeeReveal(destination: String): Modifier {
    val motion=LocalAttendeeMotion.current
    val progress=remember {Animatable(1f)}
    LaunchedEffect(destination,motion.enabled) {
        if(motion.enabled) {
            progress.snapTo(.94f)
            progress.animateTo(1f,tween(motion.revealMillis,easing=FastOutSlowInEasing))
        } else progress.snapTo(1f)
    }
    return graphicsLayer {
        alpha=progress.value
        translationY=(1f-progress.value)*80.dp.toPx()
    }
}

@Composable internal fun Modifier.attendeePress(source: MutableInteractionSource): Modifier {
    val pressed by source.collectIsPressedAsState()
    val motion=LocalAttendeeMotion.current
    val scale by animateFloatAsState(if(pressed && motion.enabled) .988f else 1f,tween(motion.feedbackMillis),label="attendee-card-press")
    return graphicsLayer {scaleX=scale; scaleY=scale}
}
