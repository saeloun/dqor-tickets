package `in`.dqor.staff.nativeapi

import java.io.IOException
import java.net.URLDecoder
import java.time.Instant
import org.json.JSONArray
import org.json.JSONObject

/** An in-process server double. It cannot open a socket. All identities are synthetic. */
class MockNativeTransport(private val now: () -> Instant = Instant::now) : NativeTransport {
    var offline = false
    var expireSession = false
    var timeoutAfterNextConfirmation = false
    private var signedIn = false
    private var canWrite = true
    private val token = "synthetic_demo_session_never_a_real_credential_123456"
    private var expiresAt = now().plusSeconds(8 * 3600)
    private val canceled = mutableSetOf<Long>(104)
    private val attendance = mutableMapOf<Pair<String, Long>, String>()
    var resolveCalls = 0; private set
    var confirmationCalls = 0; private set
    val attendanceCount get() = attendance.size
    private val people = listOf(
        Triple(101L,"Asha Rao","asha@example.test"), Triple(102L,"Grace Shah","grace@example.test"),
        Triple(103L,"Kabir Desai","kabir@example.test"), Triple(104L,"Mira Patel","mira@example.test"),
        Triple(105L,"Grace Shah","grace.second@example.test")
    )
    fun invalidatePreview(id: Long) { canceled += id }
    private fun scope() = JSONObject().put("event","dqor-2026")
        .put("event_dates",JSONArray(listOf("2026-10-08","2026-10-09","2026-10-10","2026-10-11")))
        .put("capabilities",JSONArray(if(canWrite) listOf("tickets:read","checkins:write") else listOf("tickets:read")))
        .put("expires_at",expiresAt.toString()).put("max_batch_size",50)
    private fun ticket(person: Triple<Long,String,String>, date: String) = JSONObject()
        .put("id",person.first).put("attendee_name",person.second).put("attendee_email",person.third)
        .put("ticket_type","Conference").put("order_code","DEMO-${person.first}")
        .put("eligible",person.first !in canceled).put("checked_in_at",attendance[date to person.first] ?: JSONObject.NULL)
    override suspend fun execute(request: NativeRequest): NativeResponse {
        if(offline) throw IOException("Simulated offline transport")
        val route=request.path.substringBefore('?')
        val body=request.body?.let(::JSONObject)
        if(route=="/api/staff/session" && request.method=="POST") {
            if(body?.optString("password")!="demo-only" || body.optString("email") !in listOf("desk@demo.invalid","viewer@demo.invalid")) return NativeResponse(401)
            canWrite=body.getString("email")=="desk@demo.invalid"; signedIn=true; expireSession=false; expiresAt=now().plusSeconds(8*3600)
            return NativeResponse(201,scope().put("access_token",token).put("token_type","Bearer").toString())
        }
        if(!signedIn || expireSession || request.bearer!=token || !expiresAt.isAfter(now())) return NativeResponse(401)
        if(route=="/api/staff/session") return when(request.method) {
            "GET" -> NativeResponse(200,scope().toString())
            "DELETE" -> {signedIn=false; NativeResponse(204)}
            else -> NativeResponse(422)
        }
        val query=request.path.substringAfter('?',"").split('&').filter {it.contains('=')}.associate {it.substringBefore('=') to URLDecoder.decode(it.substringAfter('='),"UTF-8")}
        val date=body?.optString("date") ?: query["date"].orEmpty()
        if(date !in listOf("2026-10-08","2026-10-09","2026-10-10","2026-10-11")) return NativeResponse(403)
        return when(route) {
            "/api/staff/checkins" -> {
                val term=query["q"].orEmpty()
                val matches=people.filter {it.first !in canceled && (it.second.contains(term,true)||it.third.contains(term,true)||"DEMO-${it.first}".contains(term,true))}
                NativeResponse(200,JSONObject().put("date",date).put("more_results",false).put("tickets",JSONArray(matches.map {ticket(it,date)})).toString())
            }
            "/api/staff/checkins/resolve" -> {
                resolveCalls++
                val person=people.find {"demo-${it.first}"==body?.optString("secret")} ?: return NativeResponse(404)
                NativeResponse(200,JSONObject().put("state","resolved").put("date",date).put("ticket",ticket(person,date)).toString())
            }
            "/api/staff/checkins/confirm" -> {
                if(!canWrite) return NativeResponse(403)
                if(body?.optBoolean("confirmed")!=true) return NativeResponse(422)
                val ids=body.getJSONArray("ticket_ids").let {array -> (0 until array.length()).map {array.getLong(it)}.distinct()}
                if(ids.isEmpty() || ids.size>50 || ids.any {it<=0}) return NativeResponse(422)
                confirmationCalls++
                val results=ids.map {id ->
                    val person=people.find {it.first==id}; val key=date to id
                    val result=JSONObject().put("ticket_id",id.toString())
                    person?.let {result.put("attendee",it.second)}
                    when {
                        person==null -> result.put("code","not_found").put("state","error").put("message","Unknown ticket")
                        id in canceled -> result.put("code","canceled").put("state","error").put("message","Eligibility changed. Do not admit.")
                        key in attendance -> result.put("code","duplicate").put("state","warning").put("message","Already checked in for this date")
                        else -> {val time=now().toString(); attendance[key]=time; result.put("code","success").put("state","success").put("message","Demo check-in confirmed").put("checked_in_at",time)}
                    }
                }
                if(timeoutAfterNextConfirmation) {timeoutAfterNextConfirmation=false; throw IOException("Simulated timeout after commit")}
                NativeResponse(200,JSONObject().put("date",date).put("results",JSONArray(results)).toString())
            }
            else -> NativeResponse(404)
        }
    }
}
