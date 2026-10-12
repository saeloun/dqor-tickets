package `in`.dqor.staff.owned

import android.app.Application
import android.content.Intent

object OwnedEventsIntegration {
    const val productionEnabled = false
    fun enabled(intent: Intent) = intent.getBooleanExtra("dqor.owned_events_fixture", false)
    fun transport(application: Application): OwnedTransport = OwnedPreviewTransport(
        application.assets.open("owned_events_catalog.json").bufferedReader().use { it.readText() },
        application.assets.open("owned_event_detail.json").bufferedReader().use { it.readText() }
    )
    fun scenario(transport: OwnedTransport, status: Int) { (transport as OwnedPreviewTransport).status = status }
}
class OwnedPreviewTransport(private val catalog: String, private val detail: String): OwnedTransport {
    @Volatile var status = 200
    override suspend fun fetch(resource: OwnedResource, validator: String?): OwnedResponse =
        if(status == 304 && validator == null) OwnedResponse(200, "W/\"owned-preview\"", if(resource is OwnedResource.Catalog) catalog else detail)
        else OwnedResponse(status, if(status == 200 || status == 304) "W/\"owned-preview\"" else null, if(status == 200) { if(resource is OwnedResource.Catalog) catalog else detail } else "")
}
