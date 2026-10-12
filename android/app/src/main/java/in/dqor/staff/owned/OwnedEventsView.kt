package `in`.dqor.staff.owned

import android.app.Application
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class OwnedScreenState(val catalog: OwnedState = OwnedState(), val detail: OwnedState = OwnedState(), val page: Int = 1, val selectedId: String? = null, val loading: Boolean = false, val cleared: Boolean = false)
class OwnedEventsController(private val client: OwnedEventsClient, private val scope: CoroutineScope) {
    private val mutable = MutableStateFlow(OwnedScreenState())
    val state = mutable.asStateFlow()
    private var task: Job? = null
    private var generation = 0
    fun refresh() {
        generation++; task?.cancel(); client.cancelPending()
        val current = generation; val before = mutable.value
        val resource = before.selectedId?.let { OwnedResource.Detail(it) } ?: OwnedResource.Catalog(before.page)
        mutable.value = before.copy(loading = true, cleared = false)
        task = scope.launch {
            try {
                val next = client.refresh(resource)
                if(current != generation) return@launch
                mutable.value = if(resource is OwnedResource.Catalog) mutable.value.copy(catalog = next, loading = false)
                    else mutable.value.copy(detail = next, catalog = client.state(OwnedResource.Catalog(before.page)), loading = false)
            } catch(_: CancellationException) { }
            catch(_: Exception) { if(current == generation) mutable.value = mutable.value.copy(loading = false) }
        }
    }
    fun select(id: String) { if(!OwnedEvent.validId(id)) return; mutable.value = mutable.value.copy(selectedId = id, detail = OwnedState()); refresh() }
    fun back() { mutable.value = mutable.value.copy(selectedId = null); if(!mutable.value.cleared) refresh() }
    fun page(delta: Int) { if(mutable.value.loading) return; mutable.value = mutable.value.copy(page = (mutable.value.page + delta).coerceIn(1, 1000), catalog = OwnedState()); refresh() }
    fun clear() { generation++; task?.cancel(); client.clear(); mutable.value = mutable.value.copy(catalog = OwnedState(), detail = OwnedState(), loading = false, cleared = true) }
    fun background() { generation++; task?.cancel(); client.background(); mutable.value = mutable.value.copy(catalog = mutable.value.catalog.copy(stale = true), detail = mutable.value.detail.copy(stale = true), loading = false) }
    fun foreground() { if(!mutable.value.cleared) refresh() }
}
class OwnedEventsModel(application: Application): AndroidViewModel(application) {
    private val transport = OwnedEventsIntegration.transport(application)
    val controller = OwnedEventsController(OwnedEventsClient(transport), viewModelScope)
    fun scenario(status: Int) { OwnedEventsIntegration.scenario(transport, status); controller.refresh() }
    override fun onCleared() { controller.background(); super.onCleared() }
}
@Composable
fun OwnedEventsScreen(controller: OwnedEventsController, onWebsite: (String) -> Boolean, scenario: ((Int) -> Unit)? = null) {
    val state by controller.state.collectAsStateWithLifecycle()
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var websiteProblem by remember { mutableStateOf(false) }
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            if(event == Lifecycle.Event.ON_RESUME) controller.foreground()
            if(event == Lifecycle.Event.ON_STOP) controller.background()
        }
        lifecycle.addObserver(observer)
        if(lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) controller.foreground()
        onDispose { lifecycle.removeObserver(observer); controller.background() }
    }
    BackHandler(enabled = state.selectedId != null) { controller.back() }
    val displayed = if(state.selectedId == null) state.catalog else state.detail
    MaterialTheme {
        Surface(Modifier.fillMaxSize().safeDrawingPadding()) {
            LazyColumn(Modifier.fillMaxSize().testTag("owned-events"), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                item { Text(if(state.selectedId == null) "Events" else "Event details", style = MaterialTheme.typography.headlineMedium) }
                if(scenario != null) item { Text("Preview · synthetic events", Modifier.testTag("owned-preview")) }
                if(state.selectedId != null) item { TextButton(onClick = controller::back) { Text("Back to events") } }
                if(state.loading) item { Text("Refreshing events…", Modifier.semantics { liveRegion = LiveRegionMode.Polite }) }
                if(state.cleared) item { Text("Your local events are cleared.") }
                if(displayed.unavailable) item { Text("Event information is no longer available", Modifier.testTag("owned-withdrawn")) }
                if(displayed.problem != null) item { Text(if(displayed.problem == OwnedProblem.UNSUPPORTED_SCHEMA) "These events need a newer app version." else "Events could not be refreshed. Try again.", Modifier.semantics { liveRegion = LiveRegionMode.Polite }) }
                if(displayed.stale && (displayed.catalog != null || displayed.event != null)) item { Text("Saved information · may be outdated", Modifier.testTag("owned-stale")) }
                if(!displayed.stale && !displayed.unavailable && (displayed.catalog != null || displayed.event != null)) item { Text("Events up to date", Modifier.testTag("owned-fresh")) }
                if(state.selectedId == null) {
                    state.catalog.catalog?.let { catalog ->
                        if(catalog.events.isEmpty()) item { Text("No events published") }
                        items(catalog.events, key = { it.id }) { event ->
                            OutlinedCard(onClick = { controller.select(event.id) }, modifier = Modifier.fillMaxWidth().testTag(event.id)) {
                                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Text(event.title, style = MaterialTheme.typography.titleMedium)
                                    Text(event.organizer)
                                    Text("${event.startDate} · ${event.timezone.id}")
                                }
                            }
                        }
                        item {
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                TextButton(onClick = { controller.page(-1) }, enabled = state.page > 1 && !state.loading) { Text("Previous") }
                                Text("Page ${state.page}")
                                TextButton(onClick = { controller.page(1) }, enabled = state.page < 1000 && state.page.toLong() * 24 < catalog.total && !state.loading) { Text("Next") }
                            }
                        }
                    }
                } else state.detail.event?.let { event ->
                    item { Text(event.title, style = MaterialTheme.typography.headlineSmall, modifier = Modifier.testTag("owned-title")) }
                    item { Text(event.organizer) }
                    item { Text("${event.startDate} – ${event.endDate}") }
                    item { Text("${event.startsAt.atZoneSameInstant(event.timezone).toLocalTime()} – ${event.endsAt.atZoneSameInstant(event.timezone).toLocalTime()} · ${event.timezone.id}") }
                    item { TextButton(onClick = { websiteProblem = !onWebsite(event.website) }) { Text("View event website") } }
                    if(websiteProblem) item { Text("No system browser is available.") }
                }
                item { Button(onClick = controller::refresh, enabled = !state.loading) { Text(if(state.selectedId == null) "Refresh events" else "Refresh event") } }
                item { TextButton(onClick = controller::clear) { Text("Clear local events") } }
                if(scenario != null) {
                    item { Text("Preview scenarios", style = MaterialTheme.typography.titleMedium) }
                    items(listOf(200 to "Published", 503 to "Service unavailable", 304 to "Unchanged", 404 to "Withdraw event")) { (status, label) ->
                        TextButton(onClick = { scenario(status) }, enabled = !state.loading) { Text(label) }
                    }
                }
            }
        }
    }
}
