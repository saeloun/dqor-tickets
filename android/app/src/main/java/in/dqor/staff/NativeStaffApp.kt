package `in`.dqor.staff

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.horizontalScroll
import androidx.compose.runtime.saveable.rememberSaveable
import `in`.dqor.staff.experience.ExperienceTheme
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import `in`.dqor.staff.nativeapi.*

@Composable
fun NativeStaffApp(events: List<Event>, workflow: NativeDeskWorkflow, demo: MockNativeTransport,
                   onExit: (() -> Unit)? = null, run: (suspend NativeDeskWorkflow.() -> Unit) -> Unit) {
    val state by workflow.state.collectAsStateWithLifecycle()
    val listState=rememberLazyListState()
    val focus=LocalFocusManager.current
    LaunchedEffect(state.event,state.session==null) {listState.scrollToItem(0)}
    LaunchedEffect(state.results) {if(state.results.isNotEmpty()) listState.scrollToItem(0)}
    var scanning by remember { mutableStateOf(false) }
    var offline by remember { mutableStateOf(demo.offline) }
    var timeoutArmed by remember { mutableStateOf(false) }
    var demoNotice by remember { mutableStateOf("") }
    var readOnly by remember { mutableStateOf(false) }
    var pendingNavigation by remember { mutableStateOf<(() -> Unit)?>(null) }
    var section by rememberSaveable { mutableStateOf("Scan") }
    var demoControls by rememberSaveable { mutableStateOf(false) }
    val event=events.find {it.id==state.event}
    val lifecycle=LocalLifecycleOwner.current.lifecycle
    fun navigate(action: () -> Unit) {
        if(state.busy) return
        scanning=false
        if(state.selected.isNotEmpty() || state.uncertain) pendingNavigation=action else action()
    }
    LaunchedEffect(state.uncertain) { if(state.uncertain) timeoutArmed=false }
    LaunchedEffect(state.session,state.review) { if(state.session==null || state.review!=null) scanning=false }
    DisposableEffect(lifecycle) {
        val observer=LifecycleEventObserver { _,change ->
            if(change==Lifecycle.Event.ON_STOP) scanning=false
            if(change==Lifecycle.Event.ON_RESUME && workflow.state.value.session!=null && !workflow.state.value.busy) run {restore()}
        }
        lifecycle.addObserver(observer)
        onDispose {lifecycle.removeObserver(observer)}
    }
    LaunchedEffect(scanning) {if(scanning) listState.animateScrollToItem(7+state.results.size)}
    BackHandler(enabled=state.event!=null || onExit!=null) {
        if(scanning) scanning=false else if(!state.busy) navigate {
            if(state.event==null) onExit?.invoke() else {workflow.discardUncertain(); workflow.chooseEvent(null)}
        }
    }
    ExperienceTheme {
        Surface(Modifier.fillMaxSize()) {
            if(pendingNavigation!=null) AlertDialog(onDismissRequest={pendingNavigation=null},title={Text("Leave this check-in?")},
                text={Text(if(state.uncertain) "Admission is not confirmed. Leaving will not undo any server attendance. Recheck the same tickets/date before admitting." else "Unsubmitted preview selections will be cleared. No attendance will be submitted.")},
                confirmButton={TextButton(onClick={val action=pendingNavigation; pendingNavigation=null; action?.invoke()}) {Text("Leave")}},
                dismissButton={TextButton(onClick={pendingNavigation=null}) {Text("Stay")}})
            state.review?.let { review ->
                AlertDialog(onDismissRequest={if(!state.busy && !state.uncertain) workflow.cancelReview()},title={Text(if(state.uncertain) "Check-in not confirmed" else "Confirm ${review.tickets.size} ${if(review.tickets.size==1) "check-in" else "check-ins"}?")},
                    text={Column(Modifier.verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                        Text("${event?.name ?: review.event} · ${review.date} · DEMO")
                        review.tickets.forEach {Text("${it.attendeeName} · ${it.attendeeEmail} · #${it.id}")}
                        if(state.uncertain && offline) TextButton(onClick={offline=false; demo.offline=false}) {Text("Restore mock connection")}
                        if(state.uncertain) Text("${state.message} Retrying submits exactly these IDs and date; duplicate attendance is not added.",Modifier.semantics {liveRegion=LiveRegionMode.Polite})
                    }},
                    confirmButton={Button(onClick={run {confirmReview(review)}},enabled=!state.busy) {Text(if(state.uncertain) "Retry same tickets" else "Confirm check-in")}},
                    dismissButton={TextButton(onClick={if(state.uncertain) workflow.discardUncertain() else workflow.cancelReview()},enabled=!state.busy) {Text(if(state.uncertain) "Dismiss without admitting" else "Cancel")}})
            }
            Column(Modifier.safeDrawingPadding()) {
            if(onExit!=null) TextButton(onClick={navigate {workflow.discardUncertain(); workflow.chooseEvent(null); onExit()}},enabled=!state.busy,modifier=Modifier.padding(horizontal=12.dp)) {Text("← Explore events")}
            LazyColumn(Modifier.weight(1f).testTag("staff-screen").padding(horizontal=24.dp),state=listState,verticalArrangement=Arrangement.spacedBy(14.dp)) {
                item {Spacer(Modifier.height(12.dp)); Text("DQOR / STAFF",style=MaterialTheme.typography.labelLarge); Text("DEMO WORKSPACE · No live attendance",style=MaterialTheme.typography.labelMedium)}
                item {Text(state.message,Modifier.semantics {liveRegion=LiveRegionMode.Polite}); if(state.busy) LinearProgressIndicator(Modifier.fillMaxWidth())}
                item {Text(if(offline) "○ Offline simulation · no pending sync" else "● Demo connection · on this device only",style=MaterialTheme.typography.labelLarge)}
                if(state.session==null) {
                    item {Text("Welcome to the front desk.",style=MaterialTheme.typography.headlineLarge); Text("Use a synthetic demo identity. No real email or password is collected.")}
                    item {Row {Switch(readOnly,{readOnly=it},enabled=!state.busy,modifier=Modifier.semantics {contentDescription="Read-only demo role"}); Text("Read-only role",Modifier.padding(12.dp))}}
                    item {Button(onClick={run {signIn(readOnly)}},enabled=!state.busy) {Text("Sign in to demo")}}
                } else {
                    item {Row {if(event!=null) TextButton(onClick={navigate {workflow.discardUncertain(); workflow.chooseEvent(null)}},enabled=!state.busy) {Text("← Events")}; Spacer(Modifier.weight(1f)); TextButton(onClick={navigate {run {logout()}}},enabled=!state.busy) {Text("Sign out")}}}
                    if(event==null) {
                        item {Text("Your events",style=MaterialTheme.typography.headlineLarge)}
                        items(events) { item -> Card(onClick={workflow.chooseEvent(item.id); run {search()}},enabled=item.id==state.session?.event && !state.busy,modifier=Modifier.fillMaxWidth()) {
                            Column(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {Text(item.name,style=MaterialTheme.typography.headlineSmall); Text(item.subtitle); Text(item.location); Text(item.dates.joinToString(" · ")); if(item.id!=state.session?.event) Text("No staff access in this demo session")}
                        }}
                    } else {
                        item {Text(event.name,style=MaterialTheme.typography.headlineMedium); Text("${event.location} · ${if(state.canWrite) "Staff" else "Read-only"}"); Text("Preview each guest, then explicitly confirm admission.")}
                        item {Row(Modifier.horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(8.dp)) {state.session!!.eventDates.forEach {day -> FilterChip(selected=day==state.date,onClick={if(day!=state.date) navigate {workflow.chooseDate(day); run {search()}}},enabled=!state.busy && !state.uncertain,label={Text(day)},modifier=Modifier.heightIn(min=48.dp))}}}
                        item {StaffSections(section) {section=it; scanning=false; focus.clearFocus()}}
                        items(state.results) {result -> Card(Modifier.fillMaxWidth()) {Column(Modifier.padding(16.dp)) {Text("${when(result.state) {NativeState.SUCCESS -> "✓ Confirmed"; NativeState.WARNING -> "! Already admitted"; NativeState.ERROR -> "× Rejected"}} · ${result.attendee ?: "Unknown attendee"} · #${result.ticketId}",style=MaterialTheme.typography.titleMedium); Text(result.message)}}}
                        if(section=="Scan") item {
                            Text("Scan, review, welcome.",style=MaterialTheme.typography.titleLarge)
                            Text("A QR preview never admits a guest. Keep scanning to build a batch, then review every name.")
                            if(scanning) {Text("Scanning resolves identity only. Hold one QR in view; review the selected identities before confirming."); QrScanner(enabled=!state.busy && state.review==null,onScan={secret -> run {resolve(secret)}})}
                            OutlinedButton(onClick={run {resolve("demo-101")}},enabled=!state.busy && !offline && state.review==null) {Text("Preview sample QR")}
                        }
                        if(section=="Scan") state.preview?.let {preview -> item {Card(Modifier.fillMaxWidth()) {Column(Modifier.padding(16.dp)) {Text("Preview · NOT an admission",style=MaterialTheme.typography.titleMedium); Text("${preview.ticket.attendeeName} · ${preview.ticket.attendeeEmail} · #${preview.ticket.id}"); Text(if(!preview.ticket.eligible) "Ineligible — do not admit" else if(preview.ticket.checkedInAt!=null) "Already checked in" else "Eligible at preview time; rechecked on confirmation")}}}}
                        if(section=="Lookup") item {Text("Find a guest",style=MaterialTheme.typography.titleLarge); OutlinedTextField(state.query,workflow::setQuery,label={Text("Name, email or order code")},modifier=Modifier.fillMaxWidth(),enabled=!state.busy,singleLine=true); TextButton(onClick={workflow.setQuery("")},enabled=!state.busy && state.query.isNotEmpty()) {Text("Clear search")}; Text("Demo order example: DEMO-101. Search does not change attendance.",style=MaterialTheme.typography.bodySmall)
                            if(state.tickets.isEmpty() && !state.busy) Text("No visible matches. Edit the search and try again.")}
                        if(section=="Lookup") items(state.tickets,key={it.id}) {ticket -> Card(Modifier.fillMaxWidth()) {Row(Modifier.padding(12.dp)) {
                            if(state.canWrite) Checkbox(state.selected.any {it.id==ticket.id},onCheckedChange={workflow.toggle(ticket)},enabled=!state.busy && state.review==null && !state.uncertain && ticket.eligible,modifier=Modifier.semantics {contentDescription="Select ${ticket.attendeeName}, ${ticket.attendeeEmail}, ticket ${ticket.id}"})
                            Column {Text(ticket.attendeeName,style=MaterialTheme.typography.titleMedium); Text(ticket.attendeeEmail); Text("${ticket.ticketType} · #${ticket.id}"); if(ticket.checkedInAt!=null) Text("Already checked in")}
                        }}}
                        if(section!="History") items(state.selected,key={"selected-${it.id}"}) {ticket -> Row(Modifier.fillMaxWidth()) {Text("${ticket.attendeeName} · #${ticket.id}",Modifier.weight(1f)); TextButton(onClick={workflow.toggle(ticket)},enabled=!state.busy && state.review==null && !state.uncertain,modifier=Modifier.semantics {contentDescription="Remove ${ticket.attendeeName}, ticket ${ticket.id}"}) {Text("Remove #${ticket.id}")}}}
                        if(section=="Lookup" && state.moreResults) item {Text("More matches exist. Refine your search; only visible tickets can be selected.")}
                        if(section=="History") {
                            item {Text("This desk session",style=MaterialTheme.typography.titleLarge); Text("Last 100 activities, filtered to this event and day. Local history is not a server audit log and clears on sign-out or session expiry.",style=MaterialTheme.typography.bodyMedium)}
                            val history=state.history.filter {it.event==state.event && it.date==state.date}
                            if(history.isEmpty()) item {Text("No activity on this day yet. Preview a QR or find a guest to begin.")}
                            items(history,key={"history-${it.id}"}) {entry -> Card(Modifier.fillMaxWidth()) {Column(Modifier.padding(16.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                                Text("${when(entry.status) {StaffHistoryStatus.CONFIRMED -> "✓"; StaffHistoryStatus.REJECTED -> "×"; StaffHistoryStatus.UNVERIFIED -> "?"; else -> "○"}} ${entry.status.label}",style=MaterialTheme.typography.titleMedium)
                                Text("${entry.kind.name.lowercase().replaceFirstChar {it.uppercase()}} · ${entry.at.atZone(ZoneId.of("Asia/Kolkata")).format(DateTimeFormatter.ofPattern("HH:mm:ss"))} IST",style=MaterialTheme.typography.labelMedium)
                                entry.attendee?.let {Text("$it · #${entry.ticketId}")}; Text(entry.detail)
                            }}}
                        }
                    }
                }
                item {TextButton(onClick={demoControls=!demoControls}) {Text(if(demoControls) "Hide demo scenarios" else "Demo scenarios")}}
                if(demoControls) item {HorizontalDivider(); Text("Synthetic demo controls",style=MaterialTheme.typography.titleMedium)
                            Row {Switch(offline,{offline=it; demo.offline=it; scanning=false},enabled=!state.busy,modifier=Modifier.semantics {contentDescription="Simulate offline connection"}); Text("Simulate offline",Modifier.padding(12.dp))}
                            if(event!=null) {
                            if(demoNotice.isNotEmpty()) Text(demoNotice,Modifier.semantics {liveRegion=LiveRegionMode.Polite})
                            TextButton(onClick={demo.expireSession=true; scanning=false; run {restore()}},enabled=!state.busy) {Text("Expire demo session")}
                            TextButton(onClick={state.selected.firstOrNull()?.let {demo.invalidatePreview(it.id); demoNotice="Mock eligibility changed. The preview stays stale until confirmation rechecks it."}},enabled=!state.busy && state.selected.isNotEmpty()) {Text("Invalidate selected preview")}
                            TextButton(onClick={demo.timeoutAfterNextConfirmation=true; timeoutArmed=true},enabled=!state.busy) {Text(if(timeoutArmed) "Next confirmation will time out" else "Simulate next confirmation timeout")}
                            }
                        }
                item {Text("No offline queue. A missing response is never proof of admission. Demo attendance is in memory; recheck after restarting.",style=MaterialTheme.typography.bodySmall); Spacer(Modifier.height(20.dp))}
            }
            if(event!=null && state.session!=null) Surface(shadowElevation=8.dp) {Column(Modifier.fillMaxWidth().padding(horizontal=24.dp,vertical=12.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                if(state.selected.isNotEmpty()) {
                    Text("${state.selected.size} selected · ${state.date}",style=MaterialTheme.typography.labelLarge)
                    Button(onClick={scanning=false; workflow.reviewSelection()},enabled=!state.busy && !state.uncertain && state.review==null,modifier=Modifier.fillMaxWidth().heightIn(min=56.dp)) {Text("Review ${state.selected.size} ${if(state.selected.size==1) "ticket" else "tickets"}")}
                    if(section=="Lookup") TextButton(onClick={focus.clearFocus(); run {search()}},enabled=!state.busy && !offline,modifier=Modifier.fillMaxWidth()) {Text("Search")}
                    if(section=="Scan") TextButton(onClick={scanning=!scanning},enabled=!state.busy && !offline && state.review==null,modifier=Modifier.fillMaxWidth()) {Text(if(scanning) "Stop scanner" else "Scan another QR")}
                } else if(section=="Scan") Button(onClick={scanning=!scanning},enabled=!state.busy && !offline && state.review==null,modifier=Modifier.fillMaxWidth().heightIn(min=56.dp)) {Text(if(scanning) "Stop scanner" else "Start QR preview scanner")}
                else if(section=="Lookup") Button(onClick={focus.clearFocus(); run {search()}},enabled=!state.busy && !offline,modifier=Modifier.fillMaxWidth().heightIn(min=56.dp)) {Text("Search")}
            }}
            }
        }
    }
}

@Composable private fun StaffSections(selected: String, choose: (String)->Unit) {
    val sections=listOf("Scan","Lookup","History")
    if(LocalDensity.current.fontScale>1.3f) Row(Modifier.horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(8.dp)) {
        sections.forEach {label -> FilterChip(selected=selected==label,onClick={choose(label)},label={Text(label)},modifier=Modifier.heightIn(min=48.dp))}
    } else SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        sections.forEachIndexed {index,label -> SegmentedButton(selected=selected==label,onClick={choose(label)},shape=SegmentedButtonDefaults.itemShape(index,3),modifier=Modifier.heightIn(min=48.dp)) {Text(label)}}
    }
}
