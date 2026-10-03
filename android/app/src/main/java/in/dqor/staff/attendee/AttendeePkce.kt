package `in`.dqor.staff.attendee

import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

class AttendeeAuthorization internal constructor(val url: String, internal val state: String,
    internal val verifier: String, internal val startedAt: Long) {
    override fun toString() = "AttendeeAuthorization([redacted])"
}

object AttendeePkce {
    private val encoder = Base64.getUrlEncoder().withoutPadding()
    private val random = SecureRandom()
    private fun nonce() = encoder.encodeToString(ByteArray(32).also(random::nextBytes))
    fun challenge(verifier: String): String = encoder.encodeToString(
        MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(StandardCharsets.US_ASCII)))
    internal fun create(now: Long): AttendeeAuthorization {
        val state = nonce()
        val verifier = nonce()
        val parameters = linkedMapOf("client_id" to AttendeeIntegration.CLIENT_ID,
            "redirect_uri" to AttendeeIntegration.CALLBACK, "state" to state,
            "code_challenge" to challenge(verifier), "code_challenge_method" to "S256")
        val query = parameters.entries.joinToString("&") { (key, value) ->
            "$key=${URLEncoder.encode(value, StandardCharsets.UTF_8.name())}"
        }
        return AttendeeAuthorization("${AttendeeIntegration.ORIGIN}/account/native/authorize?$query", state, verifier, now)
    }
    internal fun code(callback: String, expectedState: String): String? = runCatching {
        if (callback.length > 8192) return null
        val uri = URI(callback)
        if (uri.scheme != "https" || uri.rawAuthority != "deccanqueenonrails.com" ||
            uri.rawPath != "/native/attendee/android/callback" || uri.rawFragment != null) return null
        val entries = (uri.rawQuery ?: return null).split('&')
        if (entries.size != 2) return null
        val values = mutableMapOf<String, String>()
        entries.forEach { item ->
            val parts = item.split('=', limit = 2)
            if (parts.size != 2) return null
            val key = URLDecoder.decode(parts[0], StandardCharsets.UTF_8.name())
            val value = URLDecoder.decode(parts[1], StandardCharsets.UTF_8.name())
            if (key !in setOf("state", "code") || values.put(key, value) != null) return null
        }
        val state = values["state"] ?: return null
        if (!MessageDigest.isEqual(state.toByteArray(StandardCharsets.UTF_8), expectedState.toByteArray(StandardCharsets.UTF_8))) return null
        val code = values["code"] ?: return null
        if (!code.matches(Regex("nac1_[A-Za-z0-9_-]{43}"))) return null
        code
    }.getOrNull()
}
