package org.hnuhole.authpasskey

import androidx.credentials.exceptions.CreateCredentialCancellationException
import androidx.credentials.exceptions.CreateCredentialException
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import androidx.credentials.exceptions.domerrors.InvalidStateError
import androidx.credentials.exceptions.domerrors.NotAllowedError
import androidx.credentials.exceptions.domerrors.SecurityError
import androidx.credentials.exceptions.publickeycredential.CreatePublicKeyCredentialDomException
import androidx.credentials.exceptions.publickeycredential.GetPublicKeyCredentialDomException

/** Bounded diagnostics only; neither provider text nor signed data is exported. */
internal object PasskeyAcceptanceErrors {
    fun association(error: Throwable): Boolean {
        var current: Throwable? = error
        val seen = java.util.Collections.newSetFromMap(java.util.IdentityHashMap<Throwable, Boolean>())
        repeat(8) {
            val value = current ?: return false
            if (!seen.add(value)) return false
            if (value is CreatePublicKeyCredentialDomException && value.domError is SecurityError) return true
            val message = value.message?.lowercase().orEmpty()
            if (listOf("assetlinks", "not associated", "not linked", "digital asset link",
                "unable to verify the package", "cannot validate the package",
                "rp id cannot be validated", "relying party id cannot be validated",
                "incoming request cannot be validated", "应用签名验证失败", "域名验证失败")
                .any { message.contains(it) }) return true
            current = value.cause
        }
        return false
    }
    fun create(error: CreateCredentialException): String = when {
        error is CreateCredentialCancellationException -> "nativeCreateCancelled"
        error is CreatePublicKeyCredentialDomException -> when (error.domError) {
            is SecurityError -> "nativeCreateDomSecurityError"
            is InvalidStateError -> "nativeCreateDomInvalidStateError"
            is NotAllowedError -> "nativeCreateDomNotAllowedError"
            else -> "nativeCreateOtherDomError"
        }
        else -> "nativeCreateOtherFrameworkError"
    }
    fun get(error: GetCredentialException): String = when {
        error is NoCredentialException -> "nativeGetNoCredential"
        error is GetCredentialCancellationException -> "nativeGetCancelled"
        error is GetPublicKeyCredentialDomException -> when (error.domError) {
            is SecurityError -> "nativeGetDomSecurityError"
            is NotAllowedError -> "nativeGetDomNotAllowedError"
            else -> "nativeGetOtherDomError"
        }
        else -> "nativeGetOtherFrameworkError"
    }
}
