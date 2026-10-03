package `in`.dqor.staff

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.compose.BackHandler
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import `in`.dqor.staff.experience.*
import androidx.compose.ui.semantics.*
import androidx.compose.ui.platform.testTag
import kotlinx.coroutines.CancellationException
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import android.app.Application
import `in`.dqor.staff.nativeapi.*
import androidx.lifecycle.ViewModelProvider
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
import `in`.dqor.staff.programme.*
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import android.content.Intent
import android.net.Uri
import android.content.ActivityNotFoundException

class NativeDemoModel(application: Application) : AndroidViewModel(application) {
    val transport = MockNativeTransport()
    val workflow = NativeDeskWorkflow(NativeStaffClient(
        NativeConfig(enabled=true, origin="https://mock.invalid"), transport, KeystoreCredentialStore(application)
    ))
    init { viewModelScope.launch { workflow.restore() } }
    fun run(action: suspend NativeDeskWorkflow.() -> Unit) { viewModelScope.launch { workflow.action() } }
}

class MainActivity : ComponentActivity() {
    private val attendee by lazy { ViewModelProvider(this)[`in`.dqor.staff.attendee.AttendeeModel::class.java] }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        consumeAttendeeCallback(intent)
    }
    private fun consumeAttendeeCallback(intent: Intent) {
        val callback = intent.dataString
        intent.data = null
        attendee.callback(callback)
    }
    override fun onStart() { super.onStart(); attendee.foreground() }
    override fun onStop() { attendee.background(); super.onStop() }
    private fun openWebsite(url: String): Boolean = try {
        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        true
    } catch (_: ActivityNotFoundException) { false }

    private val model by lazy { ViewModelProvider(this)[NativeDemoModel::class.java] }
    private val published by lazy { ViewModelProvider(this)[PublishedProgrammeModel::class.java] }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        consumeAttendeeCallback(intent)
        val source = JSONArray(assets.open("events.json").bufferedReader().use { it.readText() })
        val events = (0 until source.length()).map { i -> source.getJSONObject(i).let { e -> Event(e.getString("id"),e.getString("name"),e.getString("location"),e.getString("subtitle"),(0 until e.getJSONArray("dates").length()).map { e.getJSONArray("dates").getString(it) },e.getString("theme")) } }
        val experience = EventExperience.parse(assets.open("experience.json").bufferedReader().use { it.readText() })
        setContent {
            var account by rememberSaveable {mutableStateOf(false)}
            var preview by rememberSaveable {mutableStateOf(false)}
            var staff by rememberSaveable {mutableStateOf(false)}
            var browserProblem by remember {mutableStateOf<String?>(null)}
            val savedScreens=rememberSaveableStateHolder()
            if(account) {
                `in`.dqor.staff.attendee.AttendeeAccountApp(attendee.controller,onClose={account=false},
                    onAuthorize={authorization -> if(!openWebsite(authorization.url)) {attendee.controller.cancel(); browserProblem="No system browser is available."}},
                    onWebsite={browserProblem=if(openWebsite(`in`.dqor.staff.attendee.AttendeeIntegration.ACCOUNT_WEBSITE)) null else "No system browser is available."},
                    onTickets={browserProblem=if(openWebsite(`in`.dqor.staff.attendee.AttendeeIntegration.TICKETS_WEBSITE)) null else "No system browser is available."},browserProblem=browserProblem)
            } else if(preview) {
                BackHandler(enabled=!staff) {preview=false}
                Column(Modifier.fillMaxSize().safeDrawingPadding()) {
                    Text("DEMO PREVIEW · synthetic events, passes and staff",Modifier.padding(12.dp),style=MaterialTheme.typography.bodySmall)
                    if(!staff) TextButton(onClick={preview=false}) {Text("Return to published programme")}
                    Box(Modifier.weight(1f)) {
                        if(staff) NativeStaffApp(events,model.workflow,model.transport,onExit={staff=false},run=model::run)
                        else savedScreens.SaveableStateProvider("event-hub") {EventHubApp(events,experience) {staff=true}}
                    }
                }
            } else {
                val state by published.programme.state.collectAsStateWithLifecycle()
                val bookmarks by published.bookmarks.state.collectAsStateWithLifecycle()
                val lifecycle=LocalLifecycleOwner.current.lifecycle
                DisposableEffect(lifecycle) {
                    val observer=LifecycleEventObserver {_,event ->
                        if(event==Lifecycle.Event.ON_RESUME) published.foreground()
                        if(event==Lifecycle.Event.ON_STOP) published.background()
                    }
                    lifecycle.addObserver(observer)
                    if(lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) published.foreground()
                    onDispose {lifecycle.removeObserver(observer); published.background()}
                }
                PublishedProgrammeApp(state,published::refresh,published::clear,onPreview={preview=true},onTickets={
                    browserProblem=null
                    try {startActivity(Intent(Intent.ACTION_VIEW,Uri.parse(OfficialProgrammeTransport.TICKETS)))}
                    catch(_: ActivityNotFoundException) {browserProblem="No browser is available to open the official ticket website."}
                },bookmarks=bookmarks,onBookmark=published.bookmarks::toggle,browserProblem=browserProblem,onAccount={browserProblem=null; account=true})
            }
        }
    }
}

@Suppress("DEPRECATION")
@Composable
internal fun QrScanner(enabled: Boolean, onScan: (String) -> Unit) {
    val context=LocalContext.current
    val lifecycle=LocalLifecycleOwner.current.lifecycle
    fun hasPermission()=context.checkSelfPermission(Manifest.permission.CAMERA)==PackageManager.PERMISSION_GRANTED
    var permitted by remember {mutableStateOf(hasPermission())}
    var denied by remember {mutableStateOf(false)}
    var problem by remember {mutableStateOf<String?>(null)}
    var previewReady by remember {mutableStateOf(false)}
    val permission=rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {permitted=it;denied=!it}
    val callback by rememberUpdatedState(onScan)
    val active by rememberUpdatedState(enabled)
    val guard=remember {RehearsalScanGuard()}
    if(!permitted) {
        Text(if(denied) "Camera access was denied. You can retry, open app settings, or use manual lookup." else "Camera access is needed for the scanner rehearsal. Manual lookup remains available.",modifier=Modifier.semantics {liveRegion=LiveRegionMode.Polite})
        Button(onClick={permission.launch(Manifest.permission.CAMERA)},modifier=Modifier.heightIn(min=48.dp)) {Text(if(denied) "Retry camera permission" else "Allow camera")}
        if(denied) TextButton(onClick={context.startActivity(Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,Uri.parse("package:${context.packageName}")))}) {Text("Open camera settings")}
    }
    val rear=remember(permitted) {if(!permitted) null else (0 until android.hardware.Camera.getNumberOfCameras()).firstOrNull {id -> android.hardware.Camera.CameraInfo().let {android.hardware.Camera.getCameraInfo(id,it);it.facing==android.hardware.Camera.CameraInfo.CAMERA_FACING_BACK}}}
    val view=remember(permitted,rear) {if(permitted && rear!=null) DecoratedBarcodeView(context).apply {
        barcodeView.decoderFactory=DefaultDecoderFactory(listOf(BarcodeFormat.QR_CODE))
        barcodeView.cameraSettings.requestedCameraId=rear
        barcodeView.addStateListener(object : com.journeyapps.barcodescanner.CameraPreview.StateListener {
            override fun previewSized() {}
            override fun previewStarted() {previewReady=true}
            override fun previewStopped() {previewReady=false}
            override fun cameraClosed() {previewReady=false}
            override fun cameraError(error: Exception) {problem="Camera unavailable. Retry the camera or use manual lookup."}
        })
    } else null}
    if(permitted && rear==null) Text("No rear camera is available. Use manual lookup.",modifier=Modifier.semantics {liveRegion=LiveRegionMode.Polite})
    if(view!=null) {
        Text("Event admission · scanner rehearsal",style=MaterialTheme.typography.titleMedium)
        Text(if(previewReady) "Rear camera ready" else if(enabled) "Starting rear camera…" else "Rear camera paused",modifier=Modifier.semantics {liveRegion=LiveRegionMode.Polite})
        Text(if(enabled) "Hold one synthetic ticket QR in view. Scanning previews identity; it never confirms admission." else "Scanner paused while a request, review or connection is unavailable.")
        AndroidView(factory={view},modifier=Modifier.fillMaxWidth().height(240.dp).testTag("rehearsal-camera").semantics {contentDescription="Rear camera QR preview. Scanner rehearsal with synthetic tickets only."})
        problem?.let {Text(it,modifier=Modifier.semantics {liveRegion=LiveRegionMode.Polite})}
        TextButton(onClick={guard.clear();problem=null;if(enabled) view.resume()},enabled=enabled,modifier=Modifier.heightIn(min=48.dp)) {Text(if(problem!=null) "Retry camera" else "Scan this code again")}
    }
    DisposableEffect(view,lifecycle,enabled) {
        view?.decodeContinuous(object : BarcodeCallback {
            override fun barcodeResult(result: BarcodeResult) {result.text?.let {if(guard.accept(it,active)) callback(it)}}
        })
        val observer=LifecycleEventObserver {_,event ->
            if(event==Lifecycle.Event.ON_RESUME) {permitted=hasPermission();if(permitted && active) view?.resume()}
            if(event==Lifecycle.Event.ON_PAUSE) {view?.pause();guard.clear()}
        }
        lifecycle.addObserver(observer)
        if(permitted && enabled && lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) view?.resume() else view?.pause()
        onDispose {view?.pause();lifecycle.removeObserver(observer)}
    }
    DisposableEffect(Unit) {onDispose {guard.clear()}}
}
