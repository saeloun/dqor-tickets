package `in`.dqor.staff.attendee

import java.time.Instant
import java.time.LocalDate

object AttendeeIntegration {
    const val ENABLED = false
    const val ORIGIN = "https://deccanqueenonrails.com"
    const val CLIENT_ID = "dqor-android"
    const val CALLBACK = "$ORIGIN/native/attendee/android/callback"
    const val ACCOUNT_WEBSITE = "$ORIGIN/account"
    const val TICKETS_WEBSITE = "$ORIGIN/tickets/mine"
}

class AttendeeCredential internal constructor(internal val value: String) {
    override fun toString() = "AttendeeCredential([redacted])"
}

class AttendeeExchange(val code: String, val verifier: String) {
    val clientId = AttendeeIntegration.CLIENT_ID
    val redirectUri = AttendeeIntegration.CALLBACK
    override fun toString() = "AttendeeExchange([redacted])"
}

class AttendeeLease(val credential: AttendeeCredential, val expiresAt: Instant) {
    override fun toString() = "AttendeeLease([redacted])"
}

data class AttendeeIdentity(val id: String, val name: String?, val email: String)
data class AttendeeAccountResult(val identity: AttendeeIdentity, val checkedAt: Instant)
data class AttendeeSession(val clientId: String, val capabilities: Set<String>, val expiresAt: Instant, val checkedAt: Instant)
enum class PassStatus { CONFIRMED, CANCELED, EXPIRED, PENDING }
data class AttendeeEntry(val date: LocalDate, val eligible: Boolean, val checkedInAt: Instant?)
data class AttendeePass(val id: String, val typeId: String, val typeName: String,
    val status: PassStatus, val startsOn: LocalDate?, val endsOn: LocalDate?, val entry: List<AttendeeEntry>)
data class AttendeePassPage(val passes: List<AttendeePass>, val moreResults: Boolean, val nextCursor: String?, val checkedAt: Instant)
data class AttendeeSnapshot(val identity: AttendeeIdentity, val passes: List<AttendeePass>,
    val moreResults: Boolean, val nextCursor: String?, val checkedAt: Instant)
enum class AttendeeProblem { UNAVAILABLE, OFFLINE, TIMEOUT, INVALID_CALLBACK, INVALID_RESPONSE, EXPIRED, REVOKED, IDENTITY_CHANGED, RATE_LIMITED }
class AttendeeFailure(val problem: AttendeeProblem) : Exception(problem.name)

enum class AttendeeRevocation { REVOKED, ALREADY_INVALID }

interface AttendeeBridge {
    suspend fun exchange(request: AttendeeExchange): AttendeeLease
    suspend fun session(credential: AttendeeCredential): AttendeeSession
    suspend fun account(credential: AttendeeCredential): AttendeeAccountResult
    suspend fun passes(credential: AttendeeCredential, cursor: String?): AttendeePassPage
    suspend fun revoke(credential: AttendeeCredential): AttendeeRevocation
}

internal object DisabledAttendeeBridge : AttendeeBridge {
    private fun unavailable(): Nothing = throw AttendeeFailure(AttendeeProblem.UNAVAILABLE)
    override suspend fun exchange(request: AttendeeExchange): AttendeeLease = unavailable()
    override suspend fun session(credential: AttendeeCredential): AttendeeSession = unavailable()
    override suspend fun account(credential: AttendeeCredential): AttendeeAccountResult = unavailable()
    override suspend fun passes(credential: AttendeeCredential, cursor: String?): AttendeePassPage = unavailable()
    override suspend fun revoke(credential: AttendeeCredential): AttendeeRevocation = unavailable()
}
