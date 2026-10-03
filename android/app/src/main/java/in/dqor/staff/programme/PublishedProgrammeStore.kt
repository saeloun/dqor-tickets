package `in`.dqor.staff.programme

import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONObject

data class PublishedProgrammeState(val snapshot: PublicProgramme?=null,val etag: String?=null,
    val loading: Boolean=false,val stale: Boolean=false,val problem: ProgrammeProblem?=null,val checkedAt: Instant?=null)

class PublishedProgrammeStore(private val transport: ProgrammeTransport,private val now: ()->Instant={Instant.now()}) {
    private val lock=Any()
    private var generation=0L
    private val mutable=MutableStateFlow(PublishedProgrammeState())
    val state=mutable.asStateFlow()
    fun clear() {synchronized(lock) {generation++; mutable.value=PublishedProgrammeState()}}
    fun markUnverified() {synchronized(lock) {generation++; mutable.value=mutable.value.copy(loading=false,stale=mutable.value.snapshot!=null)}}
    suspend fun refresh() {
        val started=synchronized(lock) {
            if(mutable.value.loading) null else (generation to mutable.value).also {mutable.value=mutable.value.copy(loading=true)}
        } ?: return
        val (version,before)=started
        fun publish(value: PublishedProgrammeState) {synchronized(lock) {if(version==generation) mutable.value=value}}
        try {
            val validator=before.etag.takeIf {before.snapshot!=null}
            var response=transport.fetch(ProgrammeRequest(validator))
            var retried=false
            if(response.status==304 && (validator==null || (response.etag!=null && response.etag!=validator))) {
                retried=true; response=transport.fetch(ProgrammeRequest())
            }
            when(response.status) {
                200 -> {
                    val (snapshot,etag)=withContext(Dispatchers.Default) {
                        val parsed=PublicProgramme.parse(response.body)
                        require(parsed.event.publicUrl==OfficialProgrammeTransport.ORIGIN)
                        parsed to response.etag?.also {require(validProgrammeEtag(it))}
                    }
                    publish(PublishedProgrammeState(snapshot,etag,checkedAt=now()))
                }
                304 -> {
                    require(!retried && validator!=null && before.snapshot!=null && (response.etag==null || response.etag==validator))
                    publish(before.copy(loading=false,stale=false,problem=null,checkedAt=now()))
                }
                503 -> {
                    withContext(Dispatchers.Default) {
                        val error=JSONObject(response.body)
                        require(error.get("schema_version") is Int && error.getInt("schema_version")==1 && error.getJSONObject("error").getString("code")=="programme_unavailable")
                    }
                    publish(before.copy(loading=false,stale=before.snapshot!=null,problem=ProgrammeProblem.UNAVAILABLE))
                }
                else -> publish(before.copy(loading=false,stale=before.snapshot!=null,problem=ProgrammeProblem.INVALID_RESPONSE))
            }
        } catch(cancelled: CancellationException) {
            publish(before.copy(loading=false,stale=before.snapshot!=null)); throw cancelled
        } catch(_: java.io.IOException) {
            publish(before.copy(loading=false,stale=before.snapshot!=null,problem=ProgrammeProblem.OFFLINE))
        } catch(_: Exception) {
            publish(before.copy(loading=false,stale=before.snapshot!=null,problem=ProgrammeProblem.INVALID_RESPONSE))
        }
    }
}
