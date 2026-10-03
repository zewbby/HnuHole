package org.hnuhole.authpasskey

// Used only from the main thread. Taking ownership before invoking cancellation
// makes a synchronous or late provider callback harmless.
internal class PendingOperation<T> {
    private var value: T? = null
    fun begin(candidate: T): Boolean {
        if (value != null) return false
        value = candidate
        return true
    }
    fun take(candidate: T): T? {
        if (value !== candidate) return null
        value = null
        return candidate
    }
    fun cancel(): T? = value.also { value = null }
}
