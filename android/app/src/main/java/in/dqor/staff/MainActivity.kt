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
import androidx.compose.ui.semantics.*
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

class NativeDemoModel(application: Application) : AndroidViewModel(application) {
    val transport = MockNativeTransport()
    val workflow = NativeDeskWorkflow(NativeStaffClient(
        NativeConfig(enabled=true, origin="https://mock.invalid"), transport, KeystoreCredentialStore(application)
    ))
    init { viewModelScope.launch { workflow.restore() } }
    fun run(action: suspend NativeDeskWorkflow.() -> Unit) { viewModelScope.launch { workflow.action() } }
}

class MainActivity : ComponentActivity() {
    private val model by lazy { ViewModelProvider(this)[NativeDemoModel::class.java] }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        val source = JSONArray(assets.open("events.json").bufferedReader().use { it.readText() })
        val events = (0 until source.length()).map { i -> source.getJSONObject(i).let { e -> Event(e.getString("id"),e.getString("name"),e.getString("location"),e.getString("subtitle"),(0 until e.getJSONArray("dates").length()).map { e.getJSONArray("dates").getString(it) },e.getString("theme")) } }
        setContent { NativeStaffApp(events,model.workflow,model.transport,model::run) }
    }
}

@Composable
internal fun QrScanner(enabled: Boolean, onScan: (String) -> Unit) {
    val context=LocalContext.current
    val lifecycle=LocalLifecycleOwner.current.lifecycle
    var permitted by remember { mutableStateOf(context.checkSelfPermission(Manifest.permission.CAMERA)==PackageManager.PERMISSION_GRANTED) }
    val permission=rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { permitted=it }
    val callback by rememberUpdatedState(onScan)
    val active by rememberUpdatedState(enabled)
    val view=remember { DecoratedBarcodeView(context).apply { barcodeView.decoderFactory=DefaultDecoderFactory(listOf(BarcodeFormat.QR_CODE)) } }
    // Secrets stay in memory only; scanner disposal clears this short-lived duplicate guard.
    var last by remember { mutableStateOf<String?>(null) }
    if(!permitted) { Text("Camera permission is needed for scanning. Search remains available.",Modifier.semantics { liveRegion=LiveRegionMode.Polite }); Button(onClick={permission.launch(Manifest.permission.CAMERA)}) {Text("Allow camera")}; return }
    AndroidView(factory={view},modifier=Modifier.fillMaxWidth().height(240.dp).semantics { contentDescription="QR camera preview. Hold one ticket QR in view." })
    DisposableEffect(view,lifecycle) {
        view.decodeContinuous(object : BarcodeCallback { override fun barcodeResult(result: BarcodeResult) { val raw=result.text ?: return; if(active && raw != last) { last=raw; callback(raw) } } })
        val observer=LifecycleEventObserver { _,event -> if(event==Lifecycle.Event.ON_RESUME) view.resume() else if(event==Lifecycle.Event.ON_PAUSE) view.pause() }
        lifecycle.addObserver(observer)
        if(lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) view.resume()
        onDispose { view.pause(); lifecycle.removeObserver(observer); last=null }
    }
}
