package `in`.dqor.staff

internal class RehearsalScanGuard {
    private var last: String?=null
    fun accept(value: String,enabled: Boolean): Boolean {
        if(!enabled || value.isBlank() || value.length>8_192 || value==last) return false
        last=value;return true
    }
    fun clear() {last=null}
}
