package `in`.dqor.staff.programme

import androidx.activity.compose.BackHandler
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import `in`.dqor.staff.Event
import `in`.dqor.staff.experience.*
import java.time.LocalDate
import java.time.format.DateTimeFormatter

@Composable
fun PublishedProgrammeApp(state: PublishedProgrammeState,onRefresh: ()->Unit,onClear: ()->Unit,
    onPreview: ()->Unit,onTickets: ()->Unit,bookmarks: Set<String>,onBookmark: (String)->Unit,browserProblem: String?=null,onAccount: (() -> Unit)?=null) {
    var schedule by rememberSaveable {mutableStateOf(false)}
    var date by rememberSaveable {mutableStateOf("")}
    var query by rememberSaveable {mutableStateOf("")}
    var savedOnly by rememberSaveable {mutableStateOf(false)}
    val saved=bookmarks
    var expanded by rememberSaveable {mutableStateOf(emptyList<String>())}
    var clearDialog by remember {mutableStateOf(false)}
    val programme=state.snapshot
    val days=programme?.let {data -> generateSequence(data.event.startDate) {day -> day.plusDays(1).takeIf {it<=data.event.endDate}}.map {it.toString()}.take(32).toList()}.orEmpty()
    LaunchedEffect(days) {if(date !in days && date!="unknown") date=days.firstOrNull().orEmpty()}
    val rows=programme?.sessions.orEmpty().filter {
        (if(date=="unknown") it.localDate==null else it.localDate?.toString()==date) &&
            (!savedOnly || it.id in saved) && (query.isBlank() || listOfNotNull(it.title,it.speakerName,it.room).any {text -> text.contains(query.trim(),true)})
    }.sortedWith(compareBy({it.startsAt?.toInstant()},{it.id}))
    val activeExpanded=expanded.filter {id -> rows.any {it.id==id}}
    LaunchedEffect(rows.map {it.id}) {expanded=expanded.filter {id -> rows.any {it.id==id}}}
    BackHandler(enabled=schedule || clearDialog) {
        when {clearDialog -> clearDialog=false; activeExpanded.isNotEmpty() -> expanded=expanded-activeExpanded.last(); else -> schedule=false}
    }
    AttendeeTheme {
        if(clearDialog) AlertDialog(onDismissRequest={clearDialog=false},title={Text("Clear local programme?")},
            text={Text("Remove the downloaded programme and saved sessions from this app. Your tickets on the website are unchanged.")},
            confirmButton={TextButton(onClick={clearDialog=false; expanded=emptyList(); query=""; date=""; savedOnly=false; schedule=false; onClear()}) {Text("Clear local data")}},
            dismissButton={TextButton(onClick={clearDialog=false}) {Text("Cancel")}})
        Surface(Modifier.fillMaxSize()) {
            Box(Modifier.safeDrawingPadding(),contentAlignment=Alignment.TopCenter) {
                Column(Modifier.widthIn(max=680.dp).fillMaxSize().testTag(if(schedule) "published-schedule" else "published-overview")) {
                    Row(Modifier.fillMaxWidth().padding(horizontal=16.dp),verticalAlignment=Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {Text("dqor",fontSize=24.sp,fontWeight=FontWeight.Bold); Text("Official public programme",style=MaterialTheme.typography.bodySmall)}
                        Column {onAccount?.let {TextButton(onClick=it,modifier=Modifier.heightIn(min=48.dp)) {Text("Account")}}
                            TextButton(onClick=onPreview,modifier=Modifier.heightIn(min=48.dp)) {Text("Demo preview")}}
                    }
                    if(programme!=null) Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal=16.dp),horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                        FilterChip(selected=!schedule,onClick={schedule=false},label={Text("Overview")})
                        FilterChip(selected=schedule,onClick={schedule=true},label={Text("Programme")})
                    }
                    LazyColumn(Modifier.weight(1f).testTag("published-programme"),contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(20.dp)) {
                        item {PublishedStatus(state,onRefresh)}
                        if(programme==null) {
                            item {Text("Deccan Queen on Rails",fontSize=32.sp,lineHeight=36.sp,fontWeight=FontWeight.SemiBold); Text("The official published programme will appear here when it can be verified.")}
                            item {OutlinedButton(onClick=onTickets,modifier=Modifier.fillMaxWidth().heightIn(min=48.dp)) {Text("Tickets on the official website")}}
                        } else if(!schedule) {
                            val event=Event(programme.event.id,programme.event.title,"Pune, India","",days,"heritage")
                            item {EventArtwork(event,Modifier.fillMaxWidth().aspectRatio(1f).clip(RoundedCornerShape(16.dp)))}
                            item {Text(programme.event.title,fontSize=34.sp,lineHeight=39.sp,fontWeight=FontWeight.SemiBold); Spacer(Modifier.height(10.dp)); Text("${programme.event.startDate.format(DateTimeFormatter.ofPattern("d MMM"))}–${programme.event.endDate.format(DateTimeFormatter.ofPattern("d MMM yyyy"))}"); Text(programme.event.venue); Text("Times in ${programme.event.timezone.id}",style=MaterialTheme.typography.bodySmall)}
                            item {Text("${programme.sessions.size} published sessions · ${programme.speakers.size} speakers",style=MaterialTheme.typography.titleMedium); Spacer(Modifier.height(12.dp)); Button(onClick={schedule=true},modifier=Modifier.fillMaxWidth().heightIn(min=52.dp)) {Text("Explore the programme")}}
                            item {Surface(shape=MaterialTheme.shapes.medium,color=Color.White,border=BorderStroke(1.dp,MaterialTheme.colorScheme.outlineVariant)) {Column(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
                                Text("Your tickets",style=MaterialTheme.typography.titleLarge)
                                Text("Find or manage your tickets securely on the official website.")
                                OutlinedButton(onClick=onTickets,modifier=Modifier.fillMaxWidth().heightIn(min=48.dp)) {Text("Open my tickets on website")}
                            }}}
                        } else {
                            item {Text("A day to remember",fontSize=28.sp,lineHeight=33.sp,fontWeight=FontWeight.SemiBold); Text("${programme.event.venue} · ${programme.event.timezone.id}")}
                            item {Row(Modifier.horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                                days.forEach {day -> FilterChip(selected=day==date,onClick={date=day; expanded=emptyList()},label={Text(LocalDate.parse(day).format(DateTimeFormatter.ofPattern("EEE, d MMM",java.util.Locale.ENGLISH)))},modifier=Modifier.heightIn(min=48.dp))}
                                if(programme.sessions.any {it.localDate==null}) FilterChip(selected=date=="unknown",onClick={date="unknown"; expanded=emptyList()},label={Text("Date to be announced")})
                            }}
                            item {OutlinedTextField(query,{query=it; expanded=emptyList()},label={Text("Find a session or speaker")},modifier=Modifier.fillMaxWidth(),singleLine=true,trailingIcon={if(query.isNotEmpty()) TextButton(onClick={query=""; expanded=emptyList()}) {Text("Clear")}})
                                FilterChip(selected=savedOnly,onClick={savedOnly=!savedOnly; expanded=emptyList()},label={Text("Saved sessions")},trailingIcon={Text(programme.sessions.count {it.id in saved}.toString())})
                                Text("${rows.size} sessions",style=MaterialTheme.typography.bodySmall,modifier=Modifier.semantics {liveRegion=LiveRegionMode.Polite})}
                            if(rows.isEmpty()) item {Text(if(programme.sessions.isEmpty()) "No sessions published" else if(savedOnly) "No saved sessions for this day" else "No sessions match",style=MaterialTheme.typography.titleMedium); TextButton(onClick={query=""; savedOnly=false; expanded=emptyList()}) {Text("Reset filters")}}
                            items(rows,key={it.id}) {session -> PublishedSessionCard(session,programme,session.id in saved,session.id in activeExpanded,
                                onDetail={expanded=if(session.id in expanded) expanded-session.id else expanded+session.id},
                                onSave={if(savedOnly) expanded=emptyList(); onBookmark(session.id)})}
                            item {Text("Saved sessions are local bookmarks, not seat reservations.",style=MaterialTheme.typography.bodySmall)}
                        }
                        browserProblem?.let {item {Text(it,modifier=Modifier.semantics {liveRegion=LiveRegionMode.Polite})}}
                        item {TextButton(onClick={clearDialog=true},modifier=Modifier.heightIn(min=48.dp)) {Text("Clear local programme and bookmarks")}}
                    }
                }
            }
        }
    }
}

@Composable private fun PublishedStatus(state: PublishedProgrammeState,onRefresh: ()->Unit) {
    Surface(shape=MaterialTheme.shapes.medium,color=MaterialTheme.colorScheme.surfaceVariant) {
        Column(Modifier.padding(16.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
            Text(when {state.loading -> "Checking the published programme…"; state.stale -> "Saved programme · needs revalidation"; state.snapshot!=null -> "Published programme verified"; state.problem!=null -> "Programme unavailable"; else -> "No programme downloaded"},style=MaterialTheme.typography.titleMedium,modifier=Modifier.semantics {liveRegion=LiveRegionMode.Polite})
            if(state.loading) LinearProgressIndicator(Modifier.fillMaxWidth())
            state.checkedAt?.let {Text("Last checked ${it.atZone(java.time.ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern("d MMM, HH:mm"))}",style=MaterialTheme.typography.bodySmall)}
            if(state.stale) Text("Sessions may have changed or been withdrawn. Reconnect to verify the latest programme.",style=MaterialTheme.typography.bodySmall)
            state.problem?.let {Text(when(it) {ProgrammeProblem.OFFLINE -> "Could not connect. Check your connection and retry."; ProgrammeProblem.UNAVAILABLE -> "The programme service is temporarily unavailable. Try again later."; ProgrammeProblem.INVALID_RESPONSE -> "The published programme could not be verified. Retry or visit the official website."})}
            OutlinedButton(onClick=onRefresh,enabled=!state.loading,modifier=Modifier.heightIn(min=48.dp)) {Text(if(state.snapshot==null) "Load published programme" else "Refresh programme")}
        }
    }
}

@Composable private fun PublishedSessionCard(session: PublicSession,programme: PublicProgramme,saved: Boolean,expanded: Boolean,onDetail: ()->Unit,onSave: ()->Unit) {
    val motion=LocalAttendeeMotion.current
    Surface(modifier=Modifier.testTag("public-session-${session.id}"),shape=MaterialTheme.shapes.medium,color=if(saved) Color(0xFFF8EFF2) else Color.White,border=BorderStroke(1.dp,if(saved) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant)) {
        Column(Modifier.animateContentSize(tween(motion.revealMillis)).padding(18.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) {
            Text(session.timeLabel(programme.event.timezone),style=MaterialTheme.typography.labelLarge,color=MaterialTheme.colorScheme.primary)
            Text(session.title,fontSize=21.sp,lineHeight=27.sp,fontWeight=FontWeight.SemiBold)
            session.speakerName?.let {Text(it,style=MaterialTheme.typography.bodyMedium)}
            session.room?.let {Text(it,style=MaterialTheme.typography.bodySmall)}
            if(expanded) {Text(session.abstract ?: "No additional description published.",modifier=Modifier.semantics {liveRegion=LiveRegionMode.Polite}); programme.speakers.find {it.id==session.speakerId}?.bio?.let {Text(it,style=MaterialTheme.typography.bodySmall)}}
            val detail: @Composable ()->Unit={TextButton(onClick=onDetail,modifier=Modifier.heightIn(min=48.dp)) {Text(if(expanded) "Less detail" else "Session details")}}
            val bookmark: @Composable ()->Unit={TextButton(onClick=onSave,modifier=Modifier.heightIn(min=48.dp).semantics {contentDescription="${if(saved) "Unsave" else "Save"} ${session.title}"; stateDescription=if(saved) "Saved" else "Not saved"}) {Text(if(saved) "✓ Saved" else "+ Save")}}
            if(LocalDensity.current.fontScale>1.3f) Column {detail(); bookmark()} else Row {detail(); Spacer(Modifier.weight(1f)); bookmark()}
        }
    }
}
