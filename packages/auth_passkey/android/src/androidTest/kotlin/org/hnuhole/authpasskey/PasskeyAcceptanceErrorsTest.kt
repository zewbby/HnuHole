package org.hnuhole.authpasskey

import androidx.credentials.exceptions.CreateCredentialUnknownException
import androidx.credentials.exceptions.CreateCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialUnknownException
import androidx.credentials.exceptions.NoCredentialException
import androidx.credentials.exceptions.domerrors.InvalidStateError
import androidx.credentials.exceptions.domerrors.SecurityError
import androidx.credentials.exceptions.publickeycredential.CreatePublicKeyCredentialDomException
import androidx.credentials.exceptions.publickeycredential.GetPublicKeyCredentialDomException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import org.junit.Test

class PasskeyAcceptanceErrorsTest {
    @Test fun typedSecurityAndExistingCredentialFailuresRemainDistinct() {
        assertEquals("nativeCreateDomSecurityError", PasskeyAcceptanceErrors.create(CreatePublicKeyCredentialDomException(SecurityError())))
        assertEquals("nativeCreateDomInvalidStateError", PasskeyAcceptanceErrors.create(CreatePublicKeyCredentialDomException(InvalidStateError())))
        assertEquals("nativeCreateOtherFrameworkError", PasskeyAcceptanceErrors.create(CreateCredentialUnknownException("assetlinks secret sentinel")))
    }
    @Test fun getDiagnosticsDoNotTurnGenericFailureIntoMissingCredential() {
        assertEquals("nativeGetNoCredential", PasskeyAcceptanceErrors.get(NoCredentialException()))
        assertEquals("nativeGetDomSecurityError", PasskeyAcceptanceErrors.get(GetPublicKeyCredentialDomException(SecurityError())))
        assertEquals("nativeGetOtherFrameworkError", PasskeyAcceptanceErrors.get(GetCredentialUnknownException("private sentinel")))
    }
    @Test fun associationDiagnosisReadsBoundedNestedCauseAndNeverGenericCancellation() {
        assertTrue(PasskeyAcceptanceErrors.association(CreatePublicKeyCredentialDomException(SecurityError())))
        assertTrue(PasskeyAcceptanceErrors.association(IllegalStateException("wrapper", IllegalArgumentException("The incoming request cannot be validated"))))
        assertFalse(PasskeyAcceptanceErrors.association(CreateCredentialCancellationException("Passkey registration was canceled by the user")))
        assertFalse(PasskeyAcceptanceErrors.association(CreateCredentialUnknownException("private sentinel")))
        assertFalse(PasskeyAcceptanceErrors.association(CreatePublicKeyCredentialDomException(InvalidStateError())))
    }
}
