package `in`.dqor.staff.experience

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import `in`.dqor.staff.R
import `in`.dqor.staff.Event

/** DQOR uses the repository's existing public event illustration, copied unchanged.
 * The assembly motif is an original native geometric drawing, not a third-party asset. */
@Composable internal fun EventArtwork(event: Event, modifier: Modifier=Modifier, compact: Boolean=false) {
    // Poster typography is part of decorative artwork. Accessible event text outside
    // the poster respects the user's font scale, including 200% layouts.
    val density=LocalDensity.current
    CompositionLocalProvider(LocalDensity provides Density(density.density,1f)) {
    Box(modifier.clearAndSetSemantics {}) {
        if(event.theme=="heritage") {
            Image(painterResource(R.drawable.dqor_cover),contentDescription=null,contentScale=ContentScale.Crop,modifier=Modifier.matchParentSize())
            Box(Modifier.matchParentSize().background(Brush.verticalGradient(listOf(Color(0x22170F09),Color(0x05170F09),Color(0xD9170F09)))))
            if(!compact) {
                Text("${event.location.substringBefore(",").uppercase()}   /   ${event.dates.first().take(4)}",Modifier.align(Alignment.TopStart).padding(24.dp),color=Color.White,fontSize=12.sp,letterSpacing=3.sp,fontWeight=FontWeight.Medium)
                Column(Modifier.align(Alignment.BottomStart).padding(24.dp)) {
                    Text(event.name.replace(" on ","\non "),color=Color(0xFFFFF4DB),fontFamily=FontFamily.Serif,fontSize=38.sp,lineHeight=39.sp,fontWeight=FontWeight.Bold)
                    Spacer(Modifier.height(10.dp)); Text("CURIOSITY. CRAFT. COMMUNITY.",color=Color(0xFFE6D9BF),fontSize=10.sp,letterSpacing=1.5.sp)
                }
            }
        } else {
            Canvas(Modifier.matchParentSize().background(Color(0xFFF0B8A1))) {
                val center=Offset(size.width*.73f,size.height*.40f)
                repeat(8) {i -> rotate(i*45f,pivot=center) {drawOval(Color(0xFFCF442D),topLeft=Offset(center.x-size.width*.12f,center.y-size.height*.39f),size=Size(size.width*.24f,size.height*.47f))}}
                drawCircle(Color(0xFFF6D43B),size.width*.1f,center)
                drawCircle(Color(0xFF42372F),size.width*.055f,Offset(size.width*.17f,size.height*.21f))
            }
            if(!compact) Column(Modifier.align(Alignment.BottomStart).padding(24.dp)) {
                Text(event.name.uppercase(),color=Color(0xFF32271F),fontSize=34.sp,lineHeight=34.sp,fontWeight=FontWeight.Black,letterSpacing=(-1).sp)
                Spacer(Modifier.height(12.dp)); Text("IDEAS DESERVE A GATHERING.",color=Color(0xFF32271F),fontSize=10.sp,letterSpacing=1.5.sp)
            }
        }
    }
}
}
