package `in`.dqor.staff.programme

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ProgrammePreview(client: PublicProgrammeClient, demo: DemoProgrammeTransport, onBack: () -> Unit) {
    val state by client.state.collectAsState()
    val scope=rememberCoroutineScope()
    var query by rememberSaveable {mutableStateOf("")}
    LaunchedEffect(client) {if(client.state.value.snapshot==null && client.state.value.problem==null) client.refresh()}
    val snapshot=state.snapshot
    val rows=snapshot?.sessions.orEmpty().filter {query.isBlank() || it.title.contains(query,true) || it.speakerName.orEmpty().contains(query,true)}
    LazyColumn(Modifier.fillMaxSize().testTag("public-programme"),contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
        item {TextButton(onClick=onBack) {Text("← Sample schedule")}; Text("Public programme preview",style=MaterialTheme.typography.headlineMedium); Text("Synthetic transport · no live connection",style=MaterialTheme.typography.bodyMedium)}
        item {Surface(color=MaterialTheme.colorScheme.surfaceVariant,shape=MaterialTheme.shapes.medium) {Column(Modifier.fillMaxWidth().padding(16.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
            Text(when {state.loading -> "Refreshing sample programme…"; state.stale -> "Cached programme · may be outdated"; state.problem!=null -> "Programme unavailable"; snapshot!=null -> "Sample programme revalidated"; else -> "No programme loaded"},style=MaterialTheme.typography.titleMedium)
            if(state.loading) LinearProgressIndicator(Modifier.fillMaxWidth())
            state.problem?.let {Text(when(it) {ProgrammeProblem.OFFLINE -> "Offline. Reconnect and retry to check for changes."; ProgrammeProblem.UNAVAILABLE -> "The programme service is temporarily unavailable. Try again later."; ProgrammeProblem.INVALID_RESPONSE -> "The programme response could not be read. Try again later."})}
            if(state.stale) Text("Cached sessions may have been changed or withdrawn. This is not a confirmed current schedule.")
            Button(onClick={scope.launch {client.refresh()}},enabled=!state.loading,modifier=Modifier.heightIn(min=48.dp)) {Text("Refresh programme")}
        }}}
        item {Text("Synthetic response",style=MaterialTheme.typography.labelLarge); FlowRow(horizontalArrangement=Arrangement.spacedBy(8.dp)) {DemoProgrammeTransport.Scenario.entries.forEach {scenario ->
            TextButton(onClick={demo.scenario=scenario; scope.launch {client.refresh()}},enabled=!state.loading) {Text(when(scenario) {DemoProgrammeTransport.Scenario.PUBLISHED -> "Published"; DemoProgrammeTransport.Scenario.UNCHANGED -> "Unchanged (304)"; DemoProgrammeTransport.Scenario.EMPTY -> "Withdraw all"; DemoProgrammeTransport.Scenario.OFFLINE -> "Offline"; DemoProgrammeTransport.Scenario.UNAVAILABLE -> "Service unavailable"})}
        }}}
        if(snapshot!=null) {
            item {Text(snapshot.event.title,style=MaterialTheme.typography.titleLarge); Text("Times in ${snapshot.event.timezone.id} · ${snapshot.event.venue}"); OutlinedTextField(query,{query=it},label={Text("Search public preview")},modifier=Modifier.fillMaxWidth())}
            if(snapshot.sessions.isEmpty()) item {Text("No sessions published",style=MaterialTheme.typography.titleMedium); Text("The latest sample snapshot is empty. Previously cached sessions have been removed.")}
            else if(rows.isEmpty()) item {Text("No matching sessions"); TextButton(onClick={query=""}) {Text("Clear search")}}
            items(rows,key={it.id}) {session -> Card(Modifier.fillMaxWidth()) {Column(Modifier.padding(16.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                Text(session.localDate?.toString() ?: "Date to be announced",style=MaterialTheme.typography.labelLarge)
                Text(session.timeLabel(snapshot.event.timezone))
                Text(session.title,style=MaterialTheme.typography.titleMedium)
                Text(session.speakerName ?: "Speaker to be announced")
                Text(session.room ?: "Room to be announced")
                session.abstract?.let {Text(it)}
            }}}
        }
    }
}
