package `in`.dqor.staff.owned

import android.app.Application
import android.content.Intent

object OwnedEventsIntegration {
    const val productionEnabled = false
    fun enabled(intent: Intent) = productionEnabled
    fun transport(application: Application): OwnedTransport = OwnedEventsHttp()
    fun scenario(transport: OwnedTransport, status: Int) = Unit
}
