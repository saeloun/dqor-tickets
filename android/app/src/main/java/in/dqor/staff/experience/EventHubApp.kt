package `in`.dqor.staff.experience

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import `in`.dqor.staff.Event
import java.time.LocalDate
import java.time.format.DateTimeFormatter

enum class EventSection(val label: String) { OVERVIEW("Overview"), SCHEDULE("Schedule"), PASSES("Passes") }
private fun dayLabel(day: String)=LocalDate.parse(day).format(DateTimeFormatter.ofPattern("EEE, d MMM",java.util.Locale.ENGLISH))
private val PosterShape=RoundedCornerShape(20.dp)

@Composable
fun EventHubApp(events: List<Event>, content: EventExperience, onStaff: () -> Unit) {
    var eventId by rememberSaveable {mutableStateOf<String?>(null)}
    var section by rememberSaveable {mutableStateOf(EventSection.OVERVIEW)}
    var passId by rememberSaveable {mutableStateOf<String?>(null)}
    var saved by rememberSaveable {mutableStateOf(emptyList<String>())}
    val screenState=rememberSaveableStateHolder()
    val event=events.find {it.id==eventId}
    fun save(id: String) {saved=if(id in saved) saved-id else saved+id}
    BackHandler(enabled=event!=null) {
        if(passId!=null) passId=null
        else if(section!=EventSection.OVERVIEW) section=EventSection.OVERVIEW
        else eventId=null
    }
    AttendeeTheme {
        Surface(Modifier.fillMaxSize()) {
            Column(Modifier.safeDrawingPadding()) {
                Row(Modifier.fillMaxWidth().heightIn(min=56.dp).padding(horizontal=12.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.SpaceBetween) {
                    if(event!=null) TextButton(onClick={if(passId!=null) passId=null else {eventId=null; section=EventSection.OVERVIEW}}) {Text(if(passId!=null) "← My passes" else "← All events")}
                    else Text("dqor",Modifier.padding(horizontal=8.dp),fontSize=24.sp,fontWeight=FontWeight.Bold,letterSpacing=(-1).sp)
                    TextButton(onClick=onStaff) {Text("Staff workspace",style=MaterialTheme.typography.labelLarge)}
                }
                if(event!=null && passId==null) ScrollableTabRow(selectedTabIndex=section.ordinal,edgePadding=8.dp,divider={},containerColor=Color.Transparent,
                    indicator={positions -> if(positions.isNotEmpty()) TabRowDefaults.SecondaryIndicator(Modifier.tabIndicatorOffset(positions[section.ordinal]),height=2.dp)}) {
                    EventSection.entries.forEach {tab -> Tab(selected=section==tab,onClick={section=tab},text={Text(tab.label,softWrap=false)},modifier=Modifier.heightIn(min=48.dp))}
                }
                if(event==null) {
                    LazyColumn(Modifier.weight(1f).testTag("event-list"),contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(28.dp)) {
                        item {
                            Text("For the joy of\ncoming together.",fontSize=32.sp,lineHeight=36.sp,fontWeight=FontWeight.SemiBold,letterSpacing=(-1).sp)
                            Spacer(Modifier.height(12.dp)); Text("Discover gatherings. Make room for something good.",color=MaterialTheme.colorScheme.onSurfaceVariant)
                            Spacer(Modifier.height(12.dp)); DemoNote("Sample events · native preview")
                        }
                        items(events,key={it.id}) {item ->
                            Card(onClick={eventId=item.id; section=EventSection.OVERVIEW},colors=CardDefaults.cardColors(containerColor=Color.Transparent),modifier=Modifier.fillMaxWidth()) {
                                EventArtwork(item.theme,Modifier.fillMaxWidth().aspectRatio(1f).clip(PosterShape))
                                Column(Modifier.padding(top=16.dp,bottom=4.dp),verticalArrangement=Arrangement.spacedBy(6.dp)) {
                                    Text("${dayLabel(item.dates.first())}  ·  ${item.location.substringBefore(" · ")}",style=MaterialTheme.typography.labelLarge,color=MaterialTheme.colorScheme.onSurfaceVariant)
                                    Text(item.name,fontSize=24.sp,lineHeight=28.sp,fontWeight=FontWeight.SemiBold)
                                    Text(item.subtitle,color=MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                        item {Text("Programmes and passes are illustrative. No live bookings or account access.",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
                    }
                } else if(passId!=null) {
                    val pass=content.wallet(event.id).find {it.id==passId}
                    if(pass!=null) PassDetail(event,pass) else Text("Sample pass unavailable",Modifier.padding(24.dp))
                } else Box(Modifier.weight(1f)) {screenState.SaveableStateProvider("${event.id}-${section.name}") {when(section) {
                    EventSection.OVERVIEW -> LazyColumn(Modifier.fillMaxSize().testTag("event-overview"),contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(24.dp)) {
                        item {EventArtwork(event.theme,Modifier.fillMaxWidth().aspectRatio(1f).clip(PosterShape))}
                        item {
                            Text(event.name,fontSize=32.sp,lineHeight=36.sp,fontWeight=FontWeight.SemiBold,letterSpacing=(-.8).sp)
                            Spacer(Modifier.height(8.dp)); Text("Hosted by DQOR India · sample event",style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        item {
                            MetadataRow(LocalDate.parse(event.dates.first()).dayOfMonth.toString(),dayLabel(event.dates.first()),"${event.dates.size} event ${if(event.dates.size==1) "day" else "days"} · ${content.timeZone}")
                            Spacer(Modifier.height(12.dp)); MetadataRow("↗",event.location.substringBefore(" · "),"A gathering of curious minds")
                        }
                        item {Surface(shape=MaterialTheme.shapes.medium,color=Color.White,border=androidx.compose.foundation.BorderStroke(1.dp,MaterialTheme.colorScheme.outlineVariant)) {
                            Column(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
                                Text("Your place in the story",style=MaterialTheme.typography.titleMedium)
                                Text("Explore a sample pass and plan your time here.",color=MaterialTheme.colorScheme.onSurfaceVariant)
                                Button(onClick={section=EventSection.PASSES},modifier=Modifier.fillMaxWidth().heightIn(min=52.dp)) {Text("View my sample passes")}
                                Text("Demo only · not valid for entry",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }}
                        item {Text("About the gathering",style=MaterialTheme.typography.titleLarge,fontWeight=FontWeight.SemiBold); Spacer(Modifier.height(12.dp)); Text(event.subtitle+". Find a conversation, learn something new, and enjoy the company."); Spacer(Modifier.height(12.dp)); TextButton(onClick={section=EventSection.SCHEDULE}) {Text("Plan your day")}}
                        item {DemoNote("Illustrative programme, not an announced schedule. All passes and people are synthetic.")}
                    }
                    EventSection.SCHEDULE -> ScheduleScreen(event,content,saved,::save)
                    EventSection.PASSES -> WalletScreen(event,content) {passId=it}
                }}}
            }
        }
    }
}

@Composable private fun MetadataRow(symbol: String,title: String,subtitle: String) {
    Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(14.dp),modifier=Modifier.heightIn(min=48.dp)) {
        Box(Modifier.size(46.dp).border(1.dp,MaterialTheme.colorScheme.outlineVariant,RoundedCornerShape(12.dp)),contentAlignment=Alignment.Center) {Text(symbol,fontWeight=FontWeight.SemiBold)}
        Column(Modifier.weight(1f)) {Text(title,style=MaterialTheme.typography.bodyLarge,fontWeight=FontWeight.Medium); Text(subtitle,style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
    }
}

@Composable private fun EventMiniHeader(event: Event,title: String) {
    Row(horizontalArrangement=Arrangement.spacedBy(14.dp),verticalAlignment=Alignment.CenterVertically) {
        EventArtwork(event.theme,Modifier.size(58.dp).clip(RoundedCornerShape(12.dp)),compact=true)
        Column(Modifier.weight(1f)) {Text(title,fontSize=28.sp,lineHeight=32.sp,fontWeight=FontWeight.SemiBold,letterSpacing=(-.5).sp); Text(event.name,style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
    }
}

@Composable private fun ScheduleScreen(event: Event,content: EventExperience,saved: List<String>,toggle: (String)->Unit) {
    var date by rememberSaveable(event.id) {mutableStateOf(event.dates.first())}
    var query by rememberSaveable(event.id) {mutableStateOf("")}
    var savedOnly by rememberSaveable(event.id) {mutableStateOf(false)}
    val sessions=content.program(event.id,date,query).filter {!savedOnly || it.id in saved}
    LazyColumn(Modifier.fillMaxSize().testTag("schedule-list"),contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(20.dp)) {
        item {EventMiniHeader(event,"A day to remember"); Spacer(Modifier.height(14.dp)); DemoNote("Sample programme · ${content.timeZone}")}
        item {Row(Modifier.horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(8.dp)) {event.dates.forEach {day -> FilterChip(selected=day==date,onClick={date=day},label={Text(dayLabel(day))},modifier=Modifier.heightIn(min=48.dp))}}}
        item {OutlinedTextField(query,{query=it},label={Text("Find a session or speaker")},modifier=Modifier.fillMaxWidth(),singleLine=true,shape=RoundedCornerShape(12.dp)); FilterChip(selected=savedOnly,onClick={savedOnly=!savedOnly},label={Text("Saved sessions")},modifier=Modifier.heightIn(min=48.dp))}
        if(sessions.isEmpty()) item {Column(Modifier.padding(vertical=24.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {Text("No sessions match",style=MaterialTheme.typography.titleMedium); Text("Try another day or clear your filters.",color=MaterialTheme.colorScheme.onSurfaceVariant); TextButton(onClick={query=""; savedOnly=false}) {Text("Reset filters")}}}
        items(sessions,key={it.id}) {session -> SessionCard(session,session.id in saved) {toggle(session.id)}}
        item {Text("Saved sessions are local bookmarks, not seat reservations.",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
    }
}

@Composable private fun SessionCard(session: ProgramSession,saved: Boolean,onSave: ()->Unit) {
    var expanded by rememberSaveable(session.id) {mutableStateOf(false)}
    Column(verticalArrangement=Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement=Arrangement.spacedBy(12.dp),verticalAlignment=Alignment.CenterVertically) {
            Text(session.startsAt,style=MaterialTheme.typography.titleMedium,fontWeight=FontWeight.SemiBold)
            HorizontalDivider(Modifier.weight(1f),color=MaterialTheme.colorScheme.outlineVariant)
            Text(session.track.label,style=MaterialTheme.typography.labelMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Surface(shape=MaterialTheme.shapes.medium,color=Color.White,border=androidx.compose.foundation.BorderStroke(1.dp,MaterialTheme.colorScheme.outlineVariant)) {
            Column(Modifier.padding(18.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) {
                Text(session.title,fontSize=20.sp,lineHeight=25.sp,fontWeight=FontWeight.SemiBold)
                Text(session.speaker,style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
                Text("${session.venue}  ·  until ${session.endsAt}",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                if(expanded) Text(session.description)
                val detail: @Composable ()->Unit={TextButton(onClick={expanded=!expanded},modifier=Modifier.heightIn(min=48.dp)) {Text(if(expanded) "Less detail" else "Session details")}}
                val bookmark: @Composable ()->Unit={TextButton(onClick=onSave,modifier=Modifier.heightIn(min=48.dp).semantics {contentDescription="${if(saved) "Unsave" else "Save"} ${session.title}"; stateDescription=if(saved) "Saved" else "Not saved"}) {Text(if(saved) "✓ Saved" else "+ Save")}}
                if(LocalDensity.current.fontScale>1.3f) Column {detail(); bookmark()} else Row {detail(); Spacer(Modifier.weight(1f)); bookmark()}
            }
        }
    }
}

@Composable private fun WalletScreen(event: Event,content: EventExperience,open: (String)->Unit) {
    LazyColumn(Modifier.fillMaxSize().testTag("wallet-list"),contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(24.dp)) {
        item {EventMiniHeader(event,"Your passes"); Spacer(Modifier.height(14.dp)); DemoNote("Sample wallet · not valid for entry")}
        if(content.wallet(event.id).isEmpty()) item {Surface(shape=MaterialTheme.shapes.medium,color=Color.White,border=androidx.compose.foundation.BorderStroke(1.dp,MaterialTheme.colorScheme.outlineVariant)) {Column(Modifier.padding(24.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {Text("No sample passes for this event",style=MaterialTheme.typography.titleMedium); Text("Try the DQOR event to explore admission and redemption states.",color=MaterialTheme.colorScheme.onSurfaceVariant)}}}
        items(content.wallet(event.id),key={it.id}) {pass -> Card(onClick={open(pass.id)},modifier=Modifier.fillMaxWidth(),colors=CardDefaults.cardColors(containerColor=Color.White),border=androidx.compose.foundation.BorderStroke(1.dp,MaterialTheme.colorScheme.outlineVariant)) {
            EventArtwork(event.theme,Modifier.fillMaxWidth().height(112.dp),compact=true)
            Column(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
                Text(event.name,style=MaterialTheme.typography.labelLarge,color=MaterialTheme.colorScheme.onSurfaceVariant)
                Text(pass.attendee,fontSize=24.sp,lineHeight=28.sp,fontWeight=FontWeight.SemiBold); Text(pass.ticketType,style=MaterialTheme.typography.bodyMedium)
                HorizontalDivider(color=MaterialTheme.colorScheme.outlineVariant)
                StatusLine("Admission · ${dayLabel(pass.admission.first().date)}",pass.admission.first().status.label)
                pass.entitlements.forEach {StatusLine(it.kind.label,it.status.label)}
                Text("Open sample pass  →",style=MaterialTheme.typography.labelLarge,fontWeight=FontWeight.SemiBold)
            }
        }}
        item {Text("These sample statuses do not sync with the staff demo.",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
    }
}

@Composable private fun PassDetail(event: Event,pass: DemoWalletPass) {
    var date by rememberSaveable(pass.id) {mutableStateOf(pass.admission.first().date)}
    LazyColumn(Modifier.fillMaxSize().testTag("pass-detail"),contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(24.dp)) {
        item {Surface(shape=RoundedCornerShape(24.dp),color=Color.White,border=androidx.compose.foundation.BorderStroke(1.dp,MaterialTheme.colorScheme.outlineVariant)) {Column {
            EventArtwork(event.theme,Modifier.fillMaxWidth().height(128.dp),compact=true)
            Column(Modifier.padding(24.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
                Text(event.name,style=MaterialTheme.typography.titleLarge,fontWeight=FontWeight.SemiBold)
                Text("${dayLabel(event.dates.first())} · ${event.location}",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                Text(pass.attendee,fontSize=28.sp,lineHeight=32.sp,fontWeight=FontWeight.SemiBold); Text(pass.ticketType,style=MaterialTheme.typography.bodyMedium)
                DemoNote("SAMPLE PASS · NOT VALID FOR ENTRY")
                HorizontalDivider(color=MaterialTheme.colorScheme.outlineVariant)
                val matrix=remember(pass.id) {QRCodeWriter().encode(pass.demoQrPayload,BarcodeFormat.QR_CODE,160,160)}
                Box(Modifier.fillMaxWidth().padding(vertical=12.dp),contentAlignment=Alignment.Center) {
                    Canvas(Modifier.size(184.dp).background(Color.White).semantics {contentDescription="Sample QR. Not a valid entry or redemption code."}) {
                        val cell=size.width/matrix.width
                        for(x in 0 until matrix.width) for(y in 0 until matrix.height) if(matrix[x,y]) drawRect(Color.Black,Offset(x*cell,y*cell),Size(cell,cell))
                    }
                }
                Text(pass.orderCode,Modifier.align(Alignment.CenterHorizontally),style=MaterialTheme.typography.labelLarge,color=MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }}}
        item {Text("Admission",style=MaterialTheme.typography.titleLarge,fontWeight=FontWeight.SemiBold); Row(Modifier.horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(8.dp)) {pass.admission.forEach {day -> FilterChip(selected=date==day.date,onClick={date=day.date},label={Text(dayLabel(day.date))},modifier=Modifier.heightIn(min=48.dp))}}; StatusLine("Entrance · ${dayLabel(date)}",pass.admissionOn(date).label)}
        item {HorizontalDivider(color=MaterialTheme.colorScheme.outlineVariant); Spacer(Modifier.height(20.dp)); Text("Meals & community",style=MaterialTheme.typography.titleLarge,fontWeight=FontWeight.SemiBold); Spacer(Modifier.height(8.dp)); Text("Admission and benefit redemption are separate.",style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)}
        items(pass.entitlements,key={it.id}) {entitlement -> Surface(shape=MaterialTheme.shapes.medium,color=Color.White,border=androidx.compose.foundation.BorderStroke(1.dp,MaterialTheme.colorScheme.outlineVariant)) {Column(Modifier.fillMaxWidth().padding(20.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) {Text(entitlement.title,style=MaterialTheme.typography.titleMedium); Text("${entitlement.kind.label} · ${dayLabel(entitlement.date)}",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant); StatusLine("Redemption",entitlement.status.label)}}}
        item {DemoNote("Read-only demo. No live account or redemption access.")}
    }
}

@Composable internal fun DemoNote(text: String) {Text(text,color=MaterialTheme.colorScheme.onSurfaceVariant,style=MaterialTheme.typography.labelMedium)}
@Composable private fun StatusLine(label: String,value: String) {
    Column(Modifier.fillMaxWidth(),verticalArrangement=Arrangement.spacedBy(4.dp)) {
        Text(label,style=MaterialTheme.typography.labelMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value,style=MaterialTheme.typography.bodyLarge,fontWeight=FontWeight.Medium)
    }
}
