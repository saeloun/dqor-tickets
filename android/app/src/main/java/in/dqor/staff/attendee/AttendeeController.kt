package `in`.dqor.staff.attendee

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withTimeout
import java.time.Instant

sealed interface AttendeeState {
    data object Unavailable : AttendeeState
    data object SignedOut : AttendeeState
    data object Authorizing : AttendeeState
    data object Exchanging : AttendeeState
    data object Loading : AttendeeState
    data class Ready(val snapshot: AttendeeSnapshot) : AttendeeState
    data class Failed(val problem: AttendeeProblem) : AttendeeState
    data class SignedOutResult(val revocation: AttendeeRevocation?) : AttendeeState
}

class AttendeeController internal constructor(private val bridge: AttendeeBridge,
    private val enabled: Boolean, private val synthetic: Boolean = false,
    private val wallTime: () -> Instant = Instant::now,
    private val elapsedTime: () -> Long = { android.os.SystemClock.elapsedRealtime() },
    private val requestTimeoutMillis: Long = 20_000L) {
    private val lock = Any()
    private val expiryScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var expiryJob: Job? = null
    private var generation = 0L
    private var pending: AttendeeAuthorization? = null
    private var lease: AttendeeLease? = null
    private var leaseDeadline = 0L
    private var identity: AttendeeIdentity? = null
    private var readInFlight = false
    private var foreground = true
    private var disposed = false
    private val mutable = MutableStateFlow<AttendeeState>(if (enabled) AttendeeState.SignedOut else AttendeeState.Unavailable)
    val state: StateFlow<AttendeeState> = mutable.asStateFlow()
    val isSynthetic: Boolean get() = synthetic

    companion object {
        fun unavailable() = AttendeeController(DisabledAttendeeBridge, false)
        internal fun synthetic(bridge: AttendeeBridge, wallTime: () -> Instant = Instant::now,
            elapsedTime: () -> Long = { android.os.SystemClock.elapsedRealtime() }) =
            AttendeeController(bridge, true, true, wallTime, elapsedTime)
    }

    fun begin(): AttendeeAuthorization? = synchronized(lock) {
        expireLocked()
        if (!enabled || disposed || pending != null || lease != null || mutable.value == AttendeeState.Exchanging || readInFlight) return null
        generation++
        AttendeePkce.create(elapsedTime()).also {
            pending = it
            mutable.value = AttendeeState.Authorizing
            scheduleExpiryLocked(600_000L)
        }
    }

    fun cancel() = synchronized(lock) {
        if (mutable.value == AttendeeState.Authorizing || mutable.value == AttendeeState.Exchanging) {
            clearLocked(if (enabled) AttendeeState.SignedOut else AttendeeState.Unavailable)
        }
    }

    fun forget() = synchronized(lock) {
        clearLocked(if (enabled) AttendeeState.SignedOutResult(null) else AttendeeState.Unavailable)
        disposed = true
        expiryScope.cancel()
    }

    fun expire() = synchronized(lock) { expireLocked() }

    fun background() = synchronized(lock) {
        expireLocked()
        foreground = false
        if (lease != null) {
            generation++
            readInFlight = false
            mutable.value = AttendeeState.Loading
            scheduleExpiryLocked((leaseDeadline - elapsedTime()).coerceAtLeast(1L))
        }
    }

    suspend fun foreground() {
        synchronized(lock) { foreground = true; expireLocked() }
        refresh()
    }

    private fun expireLocked() {
        val transaction = pending
        if (transaction != null && elapsedTime() - transaction.startedAt >= 600_000L) {
            clearLocked(AttendeeState.Failed(AttendeeProblem.EXPIRED))
        }
        if (lease != null && (!wallTime().isBefore(lease!!.expiresAt) || elapsedTime() >= leaseDeadline)) {
            clearLocked(AttendeeState.Failed(AttendeeProblem.EXPIRED))
        }
    }

    private fun scheduleExpiryLocked(afterMillis: Long) {
        expiryJob?.cancel()
        val version = generation
        expiryJob = expiryScope.launch {
            delay(afterMillis)
            synchronized(lock) { if (generation == version) expireLocked() }
        }
    }

    private fun clearLocked(state: AttendeeState) {
        expiryJob?.cancel()
        expiryJob = null
        generation++
        pending = null
        lease = null
        identity = null
        readInFlight = false
        mutable.value = state
    }

    suspend fun callback(url: String): Boolean {
        val work = synchronized(lock) {
            expireLocked()
            val transaction = pending ?: return false
            val code = AttendeePkce.code(url, transaction.state) ?: return false
            pending = null
            mutable.value = AttendeeState.Exchanging
            generation to AttendeeExchange(code, transaction.verifier)
        }
        try {
            val result = withTimeout(requestTimeoutMillis) { bridge.exchange(work.second) }
            val accepted = synchronized(lock) {
                if (generation != work.first) false else {
                    val remaining = java.time.Duration.between(wallTime(), result.expiresAt).toMillis().coerceAtMost(1_800_000L)
                    if (!result.credential.value.matches(Regex("na1_[A-Za-z0-9_-]{43}")) || remaining !in 1..1_800_000L) {
                        clearLocked(AttendeeState.Failed(AttendeeProblem.INVALID_RESPONSE))
                        false
                    } else {
                        lease = result
                        leaseDeadline = elapsedTime() + remaining
                        scheduleExpiryLocked(remaining)
                        mutable.value = AttendeeState.Loading
                        true
                    }
                }
            }
            if (!accepted) {
                if (result.credential.value.matches(Regex("na1_[A-Za-z0-9_-]{43}"))) {
                    try { withTimeout(10_000L) { bridge.revoke(result.credential) } }
                    catch (failure: CancellationException) { if (failure !is kotlinx.coroutines.TimeoutCancellationException) throw failure }
                    catch (_: Exception) { }
                }
                return true
            }
            read(work.first, null)
        } catch (failure: Exception) {
            fail(work.first, failure)
        }
        return true
    }

    suspend fun refresh() {
        val work = synchronized(lock) {
            expireLocked()
            if (!foreground || lease == null || readInFlight) return
            mutable.value = AttendeeState.Loading
            generation
        }
        read(work, null)
    }

    suspend fun nextPage() {
        val work = synchronized(lock) {
            expireLocked()
            val snapshot = (mutable.value as? AttendeeState.Ready)?.snapshot ?: return
            if (!snapshot.moreResults || snapshot.nextCursor == null || readInFlight || snapshot.passes.size >= 200) return
            mutable.value = AttendeeState.Loading
            Triple(generation, snapshot.nextCursor, snapshot.passes)
        }
        read(work.first, work.second, work.third)
    }

    private suspend fun read(version: Long, cursor: String?, previous: List<AttendeePass> = emptyList()) {
        val credential = synchronized(lock) {
            expireLocked()
            if (!foreground || generation != version || readInFlight) return
            readInFlight = true
            lease?.credential ?: return
        }
        try {
            val snapshot = withTimeout(requestTimeoutMillis) {
                val session = bridge.session(credential)
                if (!current(version)) return@withTimeout null
                val accountResponse = bridge.account(credential)
                if (!current(version)) return@withTimeout null
                val account = accountResponse.identity
                val serverRemaining = java.time.Duration.between(session.checkedAt, session.expiresAt).toMillis()
                if (session.clientId != AttendeeIntegration.CLIENT_ID || session.capabilities != setOf("account:read", "passes:read") || serverRemaining !in 1..1_800_000L) {
                    throw AttendeeFailure(AttendeeProblem.INVALID_RESPONSE)
                }
                synchronized(lock) {
                    if (generation != version) return@withTimeout null
                    leaseDeadline = minOf(leaseDeadline, elapsedTime() + serverRemaining)
                    scheduleExpiryLocked((leaseDeadline - elapsedTime()).coerceAtLeast(1L))
                }
                synchronized(lock) {
                    val established = identity
                    if (established != null && (account.id != established.id || account.email != established.email)) throw AttendeeFailure(AttendeeProblem.IDENTITY_CHANGED)
                }
                val page = bridge.passes(credential, cursor)
                synchronized(lock) {
                    expireLocked()
                    if (generation != version) return@withTimeout null
                    val established = identity
                    if (established != null && (account.id != established.id || account.email != established.email)) {
                        throw AttendeeFailure(AttendeeProblem.IDENTITY_CHANGED)
                    }
                    if (!wallTime().isBefore(session.expiresAt) || session.expiresAt != lease?.expiresAt) {
                        throw AttendeeFailure(AttendeeProblem.EXPIRED)
                    }
                    if (!validPage(page, cursor) || previous.size + page.passes.size > 200 ||
                        page.passes.any { pass -> previous.any { it.id == pass.id } }) {
                        throw AttendeeFailure(AttendeeProblem.INVALID_RESPONSE)
                    }
                    identity = account
                    AttendeeSnapshot(account, previous + page.passes, page.moreResults, page.nextCursor, page.checkedAt)
                }
            }
            synchronized(lock) {
                if (generation == version && snapshot != null) {
                    readInFlight = false
                    mutable.value = AttendeeState.Ready(snapshot)
                }
            }
        } catch (failure: Exception) { fail(version, failure) }
    }

    private fun current(version: Long): Boolean = synchronized(lock) {
        expireLocked()
        foreground && generation == version && lease != null
    }

    private fun validPage(page: AttendeePassPage, cursor: String?): Boolean {
        if (page.passes.size > 20 || page.passes.map { it.id }.distinct().size != page.passes.size) return false
        val ids = page.passes.map { it.id.toLongOrNull()?.takeIf { id -> id > 0 && id.toString() == it.id } ?: return false }
        if (ids.zipWithNext().any { it.first >= it.second } || (cursor != null && ids.any { it <= cursor.toLong() })) return false
        if (page.moreResults) return ids.isNotEmpty() && page.nextCursor == ids.last().toString()
        return page.nextCursor == null
    }

    private fun fail(version: Long, failure: Exception) {
        synchronized(lock) {
            if (generation == version) {
                val problem = when (failure) {
                    is kotlinx.coroutines.TimeoutCancellationException -> AttendeeProblem.TIMEOUT
                    is AttendeeFailure -> failure.problem
                    is CancellationException -> AttendeeProblem.UNAVAILABLE
                    else -> AttendeeProblem.OFFLINE
                }
                clearLocked(AttendeeState.Failed(problem))
            }
        }
        if (failure is CancellationException && failure !is kotlinx.coroutines.TimeoutCancellationException) throw failure
    }

    suspend fun logout() {
        val old = synchronized(lock) {
            val credential = lease?.credential
            clearLocked(AttendeeState.SignedOutResult(null))
            generation to credential
        }
        if (old.second == null) return
        val confirmed = try { withTimeout(10_000L) { bridge.revoke(old.second!!) } }
            catch (failure: CancellationException) { if (failure is kotlinx.coroutines.TimeoutCancellationException) null else throw failure }
            catch (_: Exception) { null }
        synchronized(lock) {
            if (generation == old.first) mutable.value = AttendeeState.SignedOutResult(confirmed)
        }
    }
}
