package `in`.dqor.staff.attendee

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.launch

class AttendeeModel : ViewModel() {
    val controller = AttendeeController.unavailable()
    fun callback(url: String?) { if (url != null) viewModelScope.launch { controller.callback(url) } }
    fun foreground() { viewModelScope.launch { controller.foreground() } }
    fun background() { controller.background() }
    override fun onCleared() { controller.forget() }
}
