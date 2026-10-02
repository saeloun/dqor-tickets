package `in`.dqor.staff.experience

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalDensity
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

@Composable
fun EventHubApp(events: List<Event>, content: EventExperience, onStaff: () -> Unit) {
    var eventId by rememberSaveable {mutableStateOf<String?>(null)}
    var section by rememberSaveable {mutableStateOf(EventSection.OVERVIEW)}
    var passId by rememberSaveable {mutableStateOf<String?>(null)}
    var saved by rememberSaveable {mutableStateOf(emptyList<String>())}
    val screenState=rememberSaveableStateHolder()
    val event=events.find {it.id==eventId}
    BackHandler(enabled=event!=null) {if(passId!=null) passId=null else if(section!=EventSection.OVERVIEW) section=EventSection.OVERVIEW else eventId=null}
    ExperienceTheme(event?.theme) {
        Surface(Modifier.fillMaxSize()) {
            Column(Modifier.safeDrawingPadding()) {
                Row(Modifier.fillMaxWidth().padding(horizontal=16.dp),horizontalArrangement=Arrangement.SpaceBetween) {
                    if(event!=null) TextButton(onClick={if(passId!=null) passId=null else {eventId=null; section=EventSection.OVERVIEW}}) {Text(if(passId!=null) "← My passes" else "← All events")}
                    else Text("DQOR INDIA",Modifier.padding(vertical=20.dp,horizontal=8.dp),style=MaterialTheme.typography.labelLarge,letterSpacing=2.sp)
                    TextButton(onClick=onStaff) {Text("Staff workspace",maxLines=2)}
                }
                if(event!=null && passId==null) ScrollableTabRow(selectedTabIndex=section.ordinal,edgePadding=16.dp) {EventSection.entries.forEach {tab -> Tab(selected=section==tab,onClick={section=tab},text={Text(tab.label,softWrap=false)},modifier=Modifier.heightIn(min=48.dp))}}
                if(event==null) {
                    LazyColumn(Modifier.weight(1f).testTag("event-list"),contentPadding=PaddingValues(24.dp),verticalArrangement=Arrangement.spacedBy(24.dp)) {
                        item {Text("Good company.\nGreat ideas.",style=MaterialTheme.typography.displaySmall,fontWeight=FontWeight.SemiBold); Spacer(Modifier.height(12.dp)); Text("Discover a gathering, plan your day and keep your passes close.",style=MaterialTheme.typography.bodyLarge)}
                        item {DemoNote("A native experience preview. All programmes, people and passes below are sample data.")}
                        items(events,key={it.id}) {item -> Card(onClick={eventId=item.id; section=EventSection.OVERVIEW},modifier=Modifier.fillMaxWidth()) {
                            Column(Modifier.background(Brush.linearGradient(listOf(if(item.theme=="midnight") Color(0xFF202C3D) else Color(0xFF9F442C),if(item.theme=="midnight") Color(0xFF3E4C62) else Color(0xFF72321F)))).padding(24.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
                                Text("SAMPLE EVENT  /  ${LocalDate.parse(item.dates.first()).year}",color=Color.White,style=MaterialTheme.typography.labelMedium,letterSpacing=1.sp)
                                Text(item.name,color=Color.White,style=MaterialTheme.typography.headlineMedium,fontWeight=FontWeight.SemiBold)
                                Text(item.subtitle,color=Color.White); HorizontalDivider(color=Color.White.copy(alpha=.35f)); Text("${dayLabel(item.dates.first())}  •  ${item.location}",color=Color.White)
                                Text("Explore event  →",color=Color.White,style=MaterialTheme.typography.labelLarge)
                            }
                        }}
                        item {Text("Browse locally. No bookings, payments or live account access.",style=MaterialTheme.typography.bodySmall)}
                    }
                } else if(passId!=null) {
                    val pass=content.wallet(event.id).find {it.id==passId}
                    if(pass!=null) PassDetail(event,pass) else {Text("Sample pass unavailable",Modifier.padding(24.dp)); TextButton(onClick={passId=null}) {Text("Back to passes")}}
                } else Box(Modifier.weight(1f)) {screenState.SaveableStateProvider("${event.id}-${section.name}") {when(section) {
                    EventSection.OVERVIEW -> LazyColumn(Modifier.fillMaxSize().testTag("event-overview"),contentPadding=PaddingValues(24.dp),verticalArrangement=Arrangement.spacedBy(24.dp)) {
                        item {Text("${event.location}  /  ${dayLabel(event.dates.first())}",style=MaterialTheme.typography.labelLarge,color=MaterialTheme.colorScheme.primary); Spacer(Modifier.height(16.dp)); Text(event.name,style=MaterialTheme.typography.headlineLarge,fontWeight=FontWeight.SemiBold); Spacer(Modifier.height(12.dp)); Text(event.subtitle,style=MaterialTheme.typography.titleMedium)}
                        item {DemoNote("Illustrative programme and passes. This is not the announced event schedule.")}
                        item {Button(onClick={section=EventSection.SCHEDULE},modifier=Modifier.fillMaxWidth().heightIn(min=56.dp)) {Text("Plan your day")}; OutlinedButton(onClick={section=EventSection.PASSES},modifier=Modifier.fillMaxWidth().heightIn(min=48.dp)) {Text("View my sample passes")}}
                        item {Text("A taste of the programme",style=MaterialTheme.typography.titleLarge)}
                        items(content.program(event.id).take(2),key={it.id}) {session -> SessionCard(session,session.id in saved) {saved=if(session.id in saved) saved-session.id else saved+session.id}}
                        item {Text("Times shown in ${content.timeZone}. Saving a session is a local bookmark, not a seat reservation.",style=MaterialTheme.typography.bodySmall)}
                    }
                    EventSection.SCHEDULE -> ScheduleScreen(event,content,saved) {id -> saved=if(id in saved) saved-id else saved+id}
                    EventSection.PASSES -> LazyColumn(Modifier.fillMaxSize().testTag("wallet-list"),contentPadding=PaddingValues(24.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
                        item {Text("Your event,\nin your pocket.",style=MaterialTheme.typography.headlineLarge); Spacer(Modifier.height(8.dp)); DemoNote("Sample attendee wallet. These passes are not valid for entry. Staff admission and wallet fixtures are independent.")}
                        if(content.wallet(event.id).isEmpty()) item {Card(Modifier.fillMaxWidth()) {Column(Modifier.padding(24.dp)) {Text("No sample passes for this event",style=MaterialTheme.typography.titleMedium); Text("Try the DQOR event to explore admission and redemption states.")}}}
                        items(content.wallet(event.id),key={it.id}) {pass -> Card(onClick={passId=pass.id},modifier=Modifier.fillMaxWidth()) {Column(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
                            Text(pass.attendee,style=MaterialTheme.typography.titleLarge); Text(pass.ticketType); Text(pass.orderCode,style=MaterialTheme.typography.labelMedium)
                            StatusLine("Admission · ${dayLabel(pass.admission.first().date)}",pass.admission.first().status.label)
                            pass.entitlements.forEach {StatusLine(it.kind.label,it.status.label)}
                            Text("Open sample pass  →",color=MaterialTheme.colorScheme.primary,style=MaterialTheme.typography.labelLarge)
                        }}}
                    }
                }}}
            }
        }
    }
}

@Composable private fun ScheduleScreen(event: Event, content: EventExperience, saved: List<String>, toggle: (String) -> Unit) {
    var date by rememberSaveable(event.id) {mutableStateOf(event.dates.first())}
    var query by rememberSaveable(event.id) {mutableStateOf("")}
    var savedOnly by rememberSaveable(event.id) {mutableStateOf(false)}
    val sessions=content.program(event.id,date,query).filter {!savedOnly || it.id in saved}
    LazyColumn(Modifier.fillMaxSize().testTag("schedule-list"),contentPadding=PaddingValues(24.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
        item {Text("Make the day yours",style=MaterialTheme.typography.headlineMedium); Text("Sample programme · ${content.timeZone}",style=MaterialTheme.typography.bodyMedium)}
        item {Row(Modifier.horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(8.dp)) {event.dates.forEach {day -> FilterChip(selected=day==date,onClick={date=day},label={Text(dayLabel(day))},modifier=Modifier.heightIn(min=48.dp))}}}
        item {OutlinedTextField(query,{query=it},label={Text("Find a session or speaker")},modifier=Modifier.fillMaxWidth(),singleLine=true); FilterChip(selected=savedOnly,onClick={savedOnly=!savedOnly},label={Text("Saved sessions")},modifier=Modifier.heightIn(min=48.dp))}
        if(sessions.isEmpty()) item {Card(Modifier.fillMaxWidth()) {Column(Modifier.padding(24.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {Text("No sessions match",style=MaterialTheme.typography.titleMedium); Text("Try another day, clear your search, or show all sessions."); TextButton(onClick={query=""; savedOnly=false}) {Text("Reset filters")}}}}
        items(sessions,key={it.id}) {session -> SessionCard(session,session.id in saved) {toggle(session.id)}}
        item {Text("Bookmarks stay in this demo while the app is open. They do not reserve a place.",style=MaterialTheme.typography.bodySmall)}
    }
}

@Composable private fun SessionCard(session: ProgramSession,saved: Boolean,onSave: () -> Unit) {
    var expanded by rememberSaveable(session.id) {mutableStateOf(false)}
    Card(Modifier.fillMaxWidth()) {Column(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
        Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween) {Text("${session.startsAt}–${session.endsAt}",style=MaterialTheme.typography.labelLarge,color=MaterialTheme.colorScheme.primary); Text(session.track.label,style=MaterialTheme.typography.labelMedium)}
        Text(session.title,style=MaterialTheme.typography.titleLarge); Text(session.speaker); Text(session.venue,style=MaterialTheme.typography.bodyMedium)
        if(expanded) Text(session.description)
        val detail: @Composable () -> Unit = {TextButton(onClick={expanded=!expanded},modifier=Modifier.heightIn(min=48.dp)) {Text(if(expanded) "Less detail" else "Session details")}}
        val bookmark: @Composable () -> Unit = {TextButton(onClick=onSave,modifier=Modifier.heightIn(min=48.dp).semantics {contentDescription="${if(saved) "Unsave" else "Save"} ${session.title}"; stateDescription=if(saved) "Saved" else "Not saved"}) {Text(if(saved) "✓ Saved" else "+ Save")}}
        if(LocalDensity.current.fontScale>1.3f) Column {detail(); bookmark()} else Row {detail(); Spacer(Modifier.weight(1f)); bookmark()}
    }}
}

@Composable private fun PassDetail(event: Event,pass: DemoWalletPass) {
    var date by rememberSaveable(pass.id) {mutableStateOf(pass.admission.first().date)}
    LazyColumn(Modifier.fillMaxSize().testTag("pass-detail"),contentPadding=PaddingValues(24.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
        item {Text("SAMPLE PASS · NOT VALID FOR ENTRY",style=MaterialTheme.typography.labelLarge,color=MaterialTheme.colorScheme.primary); Text(pass.attendee,style=MaterialTheme.typography.headlineLarge); Text("${event.name}\n${pass.ticketType}")}
        item {Card(Modifier.fillMaxWidth()) {Row(Modifier.padding(20.dp),horizontalArrangement=Arrangement.spacedBy(16.dp)) {
            val matrix=remember(pass.id) {QRCodeWriter().encode(pass.demoQrPayload,BarcodeFormat.QR_CODE,120,120)}
            Canvas(Modifier.size(120.dp).background(Color.White).semantics {contentDescription="Sample QR. Not a valid entry or redemption code."}) {
                val cell=size.width/matrix.width
                for(x in 0 until matrix.width) for(y in 0 until matrix.height) if(matrix[x,y]) drawRect(Color.Black,Offset(x*cell,y*cell),Size(cell,cell))
            }
            Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(8.dp)) {Text("Demo only",style=MaterialTheme.typography.titleMedium); Text(pass.orderCode); Text("No live ticket secret",style=MaterialTheme.typography.bodySmall)}
        }}}
        item {Text("Admission",style=MaterialTheme.typography.titleLarge); Row(Modifier.horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(8.dp)) {pass.admission.forEach {day -> FilterChip(selected=date==day.date,onClick={date=day.date},label={Text(dayLabel(day.date))},modifier=Modifier.heightIn(min=48.dp))}}; StatusLine("Entrance · ${dayLabel(date)}",pass.admissionOn(date).label)}
        item {HorizontalDivider(); Text("Meals & community",style=MaterialTheme.typography.titleLarge); Text("Separate entitlements. Admission does not redeem a meal or party pass.")}
        items(pass.entitlements,key={it.id}) {entitlement -> Card(Modifier.fillMaxWidth()) {Column(Modifier.padding(16.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {Text(entitlement.title,style=MaterialTheme.typography.titleMedium); Text("${entitlement.kind.label} · ${dayLabel(entitlement.date)}"); StatusLine("Redemption",entitlement.status.label)}}}
        item {DemoNote("Read-only sample statuses. Live attendee access and redemption contracts are not connected.")}
    }
}
@Composable internal fun DemoNote(text: String) {Surface(color=MaterialTheme.colorScheme.surfaceVariant,shape=MaterialTheme.shapes.medium) {Text(text,Modifier.padding(16.dp),style=MaterialTheme.typography.bodyMedium)}}
@Composable private fun StatusLine(label: String,value: String) {Column(Modifier.fillMaxWidth(),verticalArrangement=Arrangement.spacedBy(4.dp)) {Text(label,style=MaterialTheme.typography.labelMedium,color=MaterialTheme.colorScheme.onSurfaceVariant); Text(value,style=MaterialTheme.typography.titleMedium,fontWeight=FontWeight.Medium)}}
