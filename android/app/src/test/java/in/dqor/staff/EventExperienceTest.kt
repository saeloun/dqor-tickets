package `in`.dqor.staff

import `in`.dqor.staff.experience.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class EventExperienceTest {
    private fun source()=javaClass.classLoader!!.getResource("experience.json")!!.readText()
    private fun content()=EventExperience.parse(source())
    @Test fun `programme stays scoped to event and day and sorts chronologically`() {
        val sessions=content().program("dqor-2026","2026-10-08")
        assertEquals(3,sessions.size); assertTrue(sessions.all {it.eventId=="dqor-2026" && it.date=="2026-10-08"})
        assertEquals(sessions.map {it.startsAt}.sorted(),sessions.map {it.startsAt})
        assertTrue(content().program("unknown").isEmpty()); assertEquals(1,content().program("studio-demo").size)
    }
    @Test fun `search matches speaker and title while track filtering remains scoped`() {
        assertEquals(1,content().program("dqor-2026",query=" ANANYA ").size)
        assertEquals(1,content().program("dqor-2026",query="rails",track=SessionTrack.WORKSHOP).size)
        assertTrue(content().program("studio-demo",query="rails").isEmpty())
    }
    @Test fun `admission never implies meal or party redemption`() {
        val pass=content().wallet("dqor-2026").first()
        assertEquals(AdmissionStatus.CHECKED_IN,pass.admissionOn("2026-10-08"))
        assertEquals(AdmissionStatus.NOT_CHECKED_IN,pass.admissionOn("2026-10-09"))
        assertEquals(AdmissionStatus.UNKNOWN,pass.admissionOn("2030-01-01"))
        assertEquals(RedemptionStatus.AVAILABLE,pass.entitlements.first {it.kind==EntitlementKind.MEAL}.status)
        assertEquals(RedemptionStatus.REDEEMED,pass.entitlements.first {it.kind==EntitlementKind.PARTY}.status)
        assertTrue(content().wallet("studio-demo").isEmpty())
    }
    @Test fun `sample wallet code cannot resemble a staff claim secret`() {
        content().wallet("dqor-2026").forEach {assertTrue(it.demoQrPayload.startsWith("DEMO-ONLY:WALLET:")); assertTrue(it.demoQrPayload.endsWith("NOT-VALID-FOR-ENTRY"))}
    }
    @Test fun `fixtures require explicit demo marker and valid dates and unique identities`() {
        fun rejected(change: (JSONObject)->Unit) {val root=JSONObject(source()); change(root); assertThrows(Exception::class.java) {EventExperience.parse(root.toString())}}
        rejected {it.put("demo_only",false)}
        rejected {it.put("time_zone","unknown")}
        rejected {it.getJSONArray("sessions").getJSONObject(0).put("date","tomorrow")}
        rejected {it.getJSONArray("sessions").getJSONObject(0).put("ends_at","01:00")}
        rejected {it.getJSONArray("passes").getJSONObject(0).put("admission",org.json.JSONArray())}
        rejected {it.getJSONArray("sessions").put(it.getJSONArray("sessions").getJSONObject(0))}
    }
}
