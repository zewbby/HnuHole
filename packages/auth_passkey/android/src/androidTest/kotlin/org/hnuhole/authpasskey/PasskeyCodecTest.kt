package org.hnuhole.authpasskey

import android.util.Base64
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PasskeyCodecTest {
    private fun encoded(count: Int, value: Byte = 7) = Base64.encodeToString(ByteArray(count) { value }, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
    private fun get() = JSONObject().put("challenge", encoded(32)).put("rpId", "auth.example.invalid")
        .put("timeout", 60000).put("userVerification", "required")
    private fun create() = JSONObject().put("challenge", encoded(32)).put("timeout", 60000)
        .put("rp", JSONObject().put("id", "auth.example.invalid").put("name", "Hnuhole"))
        .put("user", JSONObject().put("id", encoded(32, 9)).put("name", encoded(32, 9)).put("displayName", "Hnuhole account"))
        .put("pubKeyCredParams", JSONArray().put(JSONObject().put("type", "public-key").put("alg", -7)))
        .put("excludeCredentials", JSONArray())
        .put("authenticatorSelection", JSONObject().put("residentKey", "required").put("requireResidentKey", true).put("userVerification", "required"))
        .put("attestation", "none")
    private fun response() = JSONObject().put("id", encoded(16)).put("rawId", encoded(16)).put("type", "public-key")
        .put("response", JSONObject().put("clientDataJSON", encoded(40)).put("authenticatorData", encoded(37))
            .put("signature", encoded(72)).put("userHandle", encoded(32, 9)))
    private fun rejects(action: () -> Unit) {
        try { action(); fail("Expected rejection") } catch (_: IllegalArgumentException) { } catch (_: org.json.JSONException) { }
    }

    @Test fun creationAcceptsOnlyRequiredUVResidentES256AndNoAttestation() {
        PasskeyCodec.options(create().toString(), true)
        rejects { PasskeyCodec.options(create().put("origin", "https://auth.example.invalid").toString(), true) }
        rejects { PasskeyCodec.options(create().put("attestation", "direct").toString(), true) }
        val weak = create(); weak.getJSONObject("authenticatorSelection").put("userVerification", "preferred")
        rejects { PasskeyCodec.options(weak.toString(), true) }
        val user = create(); user.getJSONObject("user").put("name", "private_username")
        rejects { PasskeyCodec.options(user.toString(), true) }
    }
    @Test fun getIsDiscoverableAndDoesNotAllowOriginOrClientHashOverrides() {
        PasskeyCodec.options(get().toString(), false)
        for (key in listOf("allowCredentials", "origin", "clientDataHash")) {
            rejects { PasskeyCodec.options(get().put(key, JSONArray()).toString(), false) }
        }
        rejects { PasskeyCodec.options(get().put("challenge", encoded(32) + "=").toString(), false) }
    }
    @Test fun selectedAcceptanceUsesOneCanonicalPublicIdAndKeepsOriginalChallenge() {
        val request = get()
        val result = JSONObject(PasskeyCodec.selectedAcceptanceOptions(request.toString(), encoded(16)))
        assertEquals(request.getString("challenge"), result.getString("challenge"))
        assertEquals("required", result.getString("userVerification"))
        assertEquals(1, result.getJSONArray("allowCredentials").length())
        assertEquals(encoded(16), result.getJSONArray("allowCredentials").getJSONObject(0).getString("id"))
        rejects { PasskeyCodec.selectedAcceptanceOptions(request.toString(), encoded(16)+"=") }
        rejects { PasskeyCodec.selectedAcceptanceOptions(request.put("origin", "https://auth.example.invalid").toString(), encoded(16)) }
    }
    @Test fun responseKeepsSignedBytesAndDropsProviderMetadata() {
        val source = response().put("authenticatorAttachment", "platform")
        source.getJSONObject("response").put("transports", JSONArray().put("internal"))
        val actual = JSONObject(PasskeyCodec.response(source.toString(), false))
        assertEquals(setOf("id", "rawId", "type", "response", "clientExtensionResults"), actual.keys().asSequence().toSet())
        assertEquals(source.getJSONObject("response").getString("clientDataJSON"), actual.getJSONObject("response").getString("clientDataJSON"))
        assertFalse(actual.getJSONObject("response").has("transports"))
        assertEquals(0, actual.getJSONObject("clientExtensionResults").length())
    }
    @Test fun responseRejectsMissingDiscoverableUserAndOversizedFields() {
        val missing = response(); missing.getJSONObject("response").put("userHandle", JSONObject.NULL)
        rejects { PasskeyCodec.response(missing.toString(), false) }
        val oversized = response(); oversized.getJSONObject("response").put("clientDataJSON", encoded(3073))
        rejects { PasskeyCodec.response(oversized.toString(), false) }
        rejects { PasskeyCodec.response(response().put("rawId", encoded(16, 8)).toString(), false) }
        rejects { PasskeyCodec.response(response().put("clientExtensionResults", JSONObject().put("appid", true)).toString(), false) }
    }
    @Test fun cancelAndNewOperationIgnoreLateCallbackWithoutTakingNewOwnership() {
        val pending = PendingOperation<Any>()
        val first = Any(); val second = Any()
        assertTrue(pending.begin(first))
        assertFalse(pending.begin(second))
        assertSame(first, pending.cancel())
        assertTrue(pending.begin(second))
        assertNull(pending.take(first))
        assertSame(second, pending.take(second))
        assertNull(pending.take(second))
        assertNull(pending.cancel())
    }
    @Test fun rejectedResponseDiagnosticDoesNotExposeSignedOrIdentifyingValues() {
        val missing = response(); missing.getJSONObject("response").put("userHandle", JSONObject.NULL)
        assertEquals("invalidResponseUserHandleAbsent", PasskeyCodec.rejectedResponseField(missing.toString(), false))
        rejects { PasskeyCodec.response(missing.toString(), false) }
        val badHandle = response(); badHandle.getJSONObject("response").put("userHandle", encoded(32, 9) + "==")
        assertEquals("invalidResponseUserHandleEncoding", PasskeyCodec.rejectedResponseField(badHandle.toString(), false))
        val envelope = response().put("rawId", encoded(16, 8))
        assertEquals("invalidResponseEnvelope", PasskeyCodec.rejectedResponseField(envelope.toString(), false))
        val signature = response(); signature.getJSONObject("response").put("signature", "invalid+encoding=")
        assertEquals("invalidResponseSignature", PasskeyCodec.rejectedResponseField(signature.toString(), false))
    }
    @Test fun providerPaddingNormalizesTransportWithoutChangingSignedBytesOrAcceptingBadPadBits() {
        val original = response()
        val padded = JSONObject(original.toString())
        fun pad(value: String) = value + "=".repeat((4 - value.length % 4) % 4)
        padded.put("id", pad(original.getString("id")))
        for (key in listOf("clientDataJSON", "authenticatorData", "signature", "userHandle")) {
            padded.getJSONObject("response").put(key, pad(original.getJSONObject("response").getString(key)))
        }
        val normalized = JSONObject(PasskeyCodec.response(padded.toString(), false))
        assertEquals(original.getString("id"), normalized.getString("id"))
        for (key in listOf("clientDataJSON", "authenticatorData", "signature", "userHandle")) {
            assertEquals(original.getJSONObject("response").getString(key), normalized.getJSONObject("response").getString(key))
            assertArrayEquals(Base64.decode(original.getJSONObject("response").getString(key), Base64.URL_SAFE),
                Base64.decode(normalized.getJSONObject("response").getString(key), Base64.URL_SAFE))
        }
        val badBits = response(); badBits.getJSONObject("response").put("userHandle", encoded(32, 9).dropLast(1) + "l")
        rejects { PasskeyCodec.response(badBits.toString(), false) }
        val badPadding = response(); badPadding.getJSONObject("response").put("signature", encoded(72) + "=")
        rejects { PasskeyCodec.response(badPadding.toString(), false) }
        val absent = response(); absent.getJSONObject("response").put("userHandle", JSONObject.NULL)
        rejects { PasskeyCodec.response(absent.toString(), false) }
        rejects { PasskeyCodec.options(get().put("challenge", encoded(32) + "=").toString(), false) }
    }
    @Test fun acceptanceLabelIsSyntheticAndLeavesAllAuthorizingCreationFieldsExact() {
        val original = create()
        val changed = JSONObject(PasskeyCodec.labeledAcceptanceOptions(original.toString(), "HnuHole test 1234abcd"))
        assertEquals("HnuHole test 1234abcd", changed.getJSONObject("user").getString("displayName"))
        assertEquals("HnuHole test 1234abcd", changed.getJSONObject("user").getString("name"))
        val request = androidx.credentials.CreatePublicKeyCredentialRequest(changed.toString())
        assertEquals("HnuHole test 1234abcd", request.displayInfo.userId.toString())
        assertEquals("HnuHole test 1234abcd", request.displayInfo.userDisplayName.toString())
        changed.getJSONObject("user").put("name", original.getJSONObject("user").getString("name"))
            .put("displayName", "Hnuhole account")
        assertEquals(original.toString(), changed.toString())
        rejects { PasskeyCodec.labeledAcceptanceOptions(original.toString(), "real@example.invalid") }
        rejects { PasskeyCodec.labeledAcceptanceOptions(original.put("origin", "https://auth.example.invalid").toString(), "HnuHole test 1234abcd") }
    }
}
