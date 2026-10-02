package `in`.dqor.staff

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.journeyapps.barcodescanner.BarcodeCallback
import com.journeyapps.barcodescanner.BarcodeResult
import com.journeyapps.barcodescanner.DecoratedBarcodeView
import com.journeyapps.barcodescanner.DefaultDecoderFactory
import com.google.zxing.BarcodeFormat
import kotlinx.coroutines.launch
import org.json.JSONArray

class MainActivity : ComponentActivity() {
    private val demo = MockCheckInService()
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        val source = JSONArray(assets.open("events.json").bufferedReader().use { it.readText() })
        val events = (0 until source.length()).map { i -> source.getJSONObject(i).let { e -> Event(e.getString("id"),e.getString("name"),e.getString("location"),e.getString("subtitle"),(0 until e.getJSONArray("dates").length()).map { e.getJSONArray("dates").getString(it) },e.getString("theme")) } }
        setContent { StaffApp(events,demo,demo) }
    }
}

@Composable
fun StaffApp(events: List<Event>, service: CheckInService, demo: MockCheckInService? = null) {
    var event by remember { mutableStateOf<Event?>(null) }
    var role by remember { mutableStateOf(Role.DESK) }
    var signedIn by remember { mutableStateOf(false) }
    val colors = if (event?.theme == "midnight") darkColorScheme(primary=Color(0xFFE9BA7D),background=Color(0xFF141D2A),surface=Color(0xFF202C3D)) else lightColorScheme(primary=Color(0xFF22574F),secondary=Color(0xFFAC7646),background=Color(0xFFF8F3E9),surface=Color(0xFFFFFBF3))
    MaterialTheme(colorScheme=colors) {
        Surface(Modifier.fillMaxSize()) {
            if (!signedIn) Column(Modifier.safeDrawingPadding().padding(24.dp),verticalArrangement=Arrangement.spacedBy(20.dp)) {
                Text("DQOR / STAFF",style=MaterialTheme.typography.labelLarge)
                Text("Welcome to the front desk.",style=MaterialTheme.typography.headlineLarge)
                Text("Demo workspace · No live attendance or authentication. Choose a simulated role to explore the app.")
                Role.entries.forEach { r -> OutlinedButton(onClick={role=r}) { Text(if(role==r) "✓ ${r.name}" else r.name) } }
                Button(onClick={demo?.role=role; demo?.expired=false; signedIn=true}) { Text("Enter demo workspace") }
            } else if (event == null) LazyColumn(Modifier.safeDrawingPadding().padding(24.dp),verticalArrangement=Arrangement.spacedBy(20.dp)) {
                item { Text("Your events",style=MaterialTheme.typography.headlineLarge); Text("DEMO · ${role.name} · Select a gathering") }
                items(events) { e -> Card(onClick={event=e},modifier=Modifier.fillMaxWidth()) { Column(Modifier.padding(24.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) { Text(e.name,style=MaterialTheme.typography.headlineSmall); Text(e.subtitle); Text(e.location); Text(e.dates.joinToString("  ·  ")) } } }
                item { TextButton(onClick={signedIn=false}) { Text("Sign out") } }
            } else key(event!!.id) { Desk(event!!,role,service,demo,onBack={event=null},onSignOut={signedIn=false; event=null}) }
        }
    }
}

@Composable
private fun Desk(event: Event, role: Role, service: CheckInService, demo: MockCheckInService?, onBack: () -> Unit, onSignOut: () -> Unit) {
    var date by remember { mutableStateOf(event.dates.first()) }
    var query by remember { mutableStateOf("") }
    var lookup by remember { mutableStateOf<Lookup?>(null) }
    var selected by remember { mutableStateOf(setOf<Int>()) }
    var results by remember { mutableStateOf<List<Outcome>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var confirm by remember { mutableStateOf(false) }
    var scanning by remember { mutableStateOf(false) }
    var offline by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val canCheckIn = role != Role.VIEWER
    fun search() { if (busy) return; busy=true; error=null; selected=emptySet(); scope.launch { try { val response=service.lookup(event,date,query); lookup=response; date=response.date } catch(e: Exception) { lookup=null; error=e.message } finally { busy=false } } }
    fun submit(ids: List<Int>? = null, secret: String? = null) {
        if (busy || !canCheckIn) return
        busy=true; error=null; results=emptyList()
        scope.launch { try {
            val response = if(secret != null) service.scan(event,date,secret) else service.checkIn(event,date,ids.orEmpty(),true)
            results=response.results; lookup=lookup?.copy(checkedInCount=response.checkedInCount); selected=emptySet()
        } catch(e: Exception) { error=e.message ?: "Not confirmed. Retry the same tickets and date." } finally { busy=false } }
    }
    LaunchedEffect(date) { lookup=null; results=emptyList(); selected=emptySet(); search() }
    if (confirm) AlertDialog(onDismissRequest={confirm=false},title={Text("Confirm ${selected.size} check-ins?")},text={ Column { Text("${event.name} · $date · DEMO"); lookup?.tickets?.filter { it.id in selected }?.forEach { Text("${it.name} · #${it.id}") } } },confirmButton={ Button(onClick={confirm=false; submit(selected.toList())},enabled=!busy) { Text("Confirm check-in") } },dismissButton={TextButton(onClick={confirm=false}) { Text("Cancel") }})
    LazyColumn(Modifier.safeDrawingPadding().padding(horizontal=20.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
        item { Row { TextButton(onClick=onBack,enabled=!busy) {Text("← Events")}; Spacer(Modifier.weight(1f)); TextButton(onClick=onSignOut,enabled=!busy) { Text("Sign out") } }; Text(event.name,style=MaterialTheme.typography.headlineMedium); Text("DEMO ONLY · ${role.name} · ${event.location}",style=MaterialTheme.typography.labelMedium) }
        item { Text("Entrance check-in",style=MaterialTheme.typography.titleLarge); Text("${lookup?.checkedInCount ?: "—"} confirmed in demo for $date") }
        item { Column { event.dates.forEach { day -> FilterChip(selected=date==day,onClick={if(!busy) {scanning=false; date=day}},enabled=!busy,label={Text(day)}) } } }
        item { if (demo != null) Row { Switch(checked=offline,onCheckedChange={offline=it; demo.offline=it; scanning=false; lookup=null; selected=emptySet(); results=emptyList(); error=if(it) "Offline simulation. No attendance is queued." else "Connected simulation. Search to refresh."},enabled=!busy); Text("Simulate offline",Modifier.padding(12.dp)) } }
        item { error?.let { Text(it,color=MaterialTheme.colorScheme.error) }; if(busy) LinearProgressIndicator(Modifier.fillMaxWidth()) }
        if(canCheckIn) item { Button(onClick={scanning=!scanning},enabled=!busy && !offline) { Text(if(scanning) "Stop scanner" else "Start continuous QR scanner") }; if(scanning) { Text("Hold one QR in view. Consecutive identical codes are suppressed. Restart to retry the same code. Demo QR values: demo-101 to demo-104."); QrScanner(enabled=!busy,onScan={submit(secret=it)}) } }
        item { OutlinedTextField(value=query,onValueChange={query=it},label={Text("Search name, email or ticket ID")},modifier=Modifier.fillMaxWidth(),enabled=!busy,singleLine=true); Button(onClick={search()},enabled=!busy && !offline) {Text("Search")}; if(role==Role.VIEWER) Text("Viewer role: attendance controls are unavailable.") }
        items(lookup?.tickets.orEmpty(),key={it.id}) { ticket -> Card(Modifier.fillMaxWidth()) { Row(Modifier.padding(12.dp)) { if(canCheckIn) Checkbox(checked=ticket.id in selected,onCheckedChange={checked -> selected=if(checked) selected+ticket.id else selected-ticket.id},enabled=!busy && !offline && (ticket.id in selected || selected.size < (lookup?.maxBatchSize ?: 50))); Column { Text(ticket.name,style=MaterialTheme.typography.titleMedium); Text(ticket.email); Text("${ticket.type} · #${ticket.id}") } } } }
        item { if(lookup?.tickets?.isEmpty()==true) Text("No eligible attendees found."); if(lookup?.moreResults==true) Text("More results exist. Refine your search; only visible tickets can be selected."); if(canCheckIn) Button(onClick={scanning=false; confirm=true},enabled=selected.isNotEmpty() && !busy && !offline) { Text("Review ${selected.size} selected tickets") } }
        items(results) { result -> Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(16.dp)) { Text("${result.state} · ${result.attendee ?: "Unknown attendee"}",style=MaterialTheme.typography.titleMedium); Text(result.message); result.checkedInAt?.let { Text(it) } } } }
        item { Text("No offline queue. A missing response is never proof of admission. Live authentication and event discovery are pending backend approval.",style=MaterialTheme.typography.bodySmall); Spacer(Modifier.height(20.dp)) }
    }
}

@Composable
private fun QrScanner(enabled: Boolean, onScan: (String) -> Unit) {
    val context=LocalContext.current
    val lifecycle=LocalLifecycleOwner.current.lifecycle
    var permitted by remember { mutableStateOf(context.checkSelfPermission(Manifest.permission.CAMERA)==PackageManager.PERMISSION_GRANTED) }
    val permission=rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { permitted=it }
    val callback by rememberUpdatedState(onScan)
    val active by rememberUpdatedState(enabled)
    val view=remember { DecoratedBarcodeView(context).apply { barcodeView.decoderFactory=DefaultDecoderFactory(listOf(BarcodeFormat.QR_CODE)) } }
    // Secrets stay in memory only; scanner disposal clears this short-lived duplicate guard.
    var last by remember { mutableStateOf<String?>(null) }
    if(!permitted) { Text("Camera permission is needed for scanning. Search remains available."); Button(onClick={permission.launch(Manifest.permission.CAMERA)}) {Text("Allow camera")}; return }
    AndroidView(factory={view},modifier=Modifier.fillMaxWidth().height(240.dp))
    DisposableEffect(view,lifecycle) {
        view.decodeContinuous(object : BarcodeCallback { override fun barcodeResult(result: BarcodeResult) { val raw=result.text ?: return; if(active && raw != last) { last=raw; callback(raw) } } })
        val observer=LifecycleEventObserver { _,event -> if(event==Lifecycle.Event.ON_RESUME) view.resume() else if(event==Lifecycle.Event.ON_PAUSE) view.pause() }
        lifecycle.addObserver(observer)
        if(lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) view.resume()
        onDispose { view.pause(); lifecycle.removeObserver(observer); last=null }
    }
}
