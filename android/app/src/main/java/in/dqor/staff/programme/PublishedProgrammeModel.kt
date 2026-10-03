package `in`.dqor.staff.programme

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

class PublicBookmarks(context: Context) {
    private val preferences=context.getSharedPreferences("dqor.published.bookmarks",Context.MODE_PRIVATE)
    private val mutable=MutableStateFlow(preferences.getStringSet("dqor-2026",emptySet()).orEmpty().filter {it.matches(Regex("[1-9][0-9]*"))}.take(500).toSet())
    val state=mutable.asStateFlow()
    private fun write(ids: Set<String>) {mutable.value=ids; preferences.edit().putStringSet("dqor-2026",ids).apply()}
    fun toggle(id: String) {require(id.matches(Regex("[1-9][0-9]*"))); write(if(id in mutable.value) mutable.value-id else (mutable.value+id).take(500).toSet())}
    fun retain(ids: Set<String>) {write(mutable.value.intersect(ids))}
    fun clear() {mutable.value=emptySet(); preferences.edit().clear().apply()}
}

class PublishedProgrammeModel(application: Application) : AndroidViewModel(application) {
    val programme=PublishedProgrammeStore(OfficialProgrammeTransport())
    val bookmarks=PublicBookmarks(application)
    private var request: Job?=null
    private var cleared=false
    fun refresh() {
        cleared=false
        if(request?.isActive!=true) request=viewModelScope.launch {
            programme.refresh()
            val state=programme.state.value
            if(!state.loading && !state.stale && state.problem==null) state.snapshot?.let {bookmarks.retain(it.sessions.map {session -> session.id}.toSet())}
        }
    }
    fun foreground() {if(!cleared) refresh()}
    fun background() {request?.cancel(); request=null; programme.markUnverified()}
    fun clear() {cleared=true; request?.cancel(); request=null; programme.clear(); bookmarks.clear()}
}
