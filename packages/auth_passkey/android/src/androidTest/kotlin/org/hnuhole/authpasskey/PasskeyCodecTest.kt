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
}
