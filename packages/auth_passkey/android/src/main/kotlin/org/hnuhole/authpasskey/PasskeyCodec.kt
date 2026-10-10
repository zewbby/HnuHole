package org.hnuhole.authpasskey

import android.util.Base64
import org.json.JSONObject

internal object PasskeyCodec {
    private const val LIMIT = 32768
    fun labeledAcceptanceOptions(raw: String, label: String): String {
        require(Regex("HnuHole test [a-f0-9]{8}").matches(label))
        val value = options(raw, true)
        // AndroidX uses user.name as DisplayInfo.userId. Set both presentation
        // names for this guarded synthetic test; the binary account handle,
        // challenge, RP, algorithms, exclusions and required UV stay exact.
        value.getJSONObject("user").put("name", label).put("displayName", label)
        return value.toString()
    }
    // Device acceptance may select a known public ID. Normal recovery options
    // remain discoverable and still reject allowCredentials.
    fun selectedAcceptanceOptions(raw: String, credentialId: String): String {
        val value = options(raw, false)
        encoded(credentialId, 1, 1023)
        return value.put("allowCredentials", org.json.JSONArray().put(
            JSONObject().put("type", "public-key").put("id", credentialId))).toString()
    }
    fun options(raw: String, create: Boolean): JSONObject {
        require(raw.toByteArray(Charsets.UTF_8).size <= LIMIT)
        val value = JSONObject(raw)
        keys(value, if (create) setOf("challenge", "rp", "user", "pubKeyCredParams", "timeout",
            "excludeCredentials", "authenticatorSelection", "attestation")
            else setOf("challenge", "rpId", "timeout", "userVerification"))
        encoded(value.get("challenge"), 32, 32)
        require(value.get("timeout") is Int && value.getInt("timeout") == 60000)
        if (!create) {
            rp(value.get("rpId"))
            require(value.get("userVerification") == "required")
            return value
        }
        val relyingParty = value.getJSONObject("rp")
        keys(relyingParty, setOf("id", "name"))
        rp(relyingParty.get("id"))
        require(relyingParty.get("name") == "Hnuhole")
        val user = value.getJSONObject("user")
        keys(user, setOf("id", "name", "displayName"))
        encoded(user.get("id"), 32, 32)
        require(user.get("name") == user.get("id") && user.get("displayName") == "Hnuhole account")
        val parameters = value.getJSONArray("pubKeyCredParams")
        require(parameters.length() == 1)
        val algorithm = parameters.getJSONObject(0)
        keys(algorithm, setOf("type", "alg"))
        require(algorithm.get("type") == "public-key" && algorithm.get("alg") is Int && algorithm.getInt("alg") == -7)
        val selection = value.getJSONObject("authenticatorSelection")
        keys(selection, setOf("residentKey", "requireResidentKey", "userVerification"))
        require(selection.get("residentKey") == "required" && selection.get("requireResidentKey") == true &&
            selection.get("userVerification") == "required" && value.get("attestation") == "none")
        val exclude = value.getJSONArray("excludeCredentials")
        require(exclude.length() <= 10)
        val seen = mutableSetOf<String>()
        for (i in 0 until exclude.length()) {
            val item = exclude.getJSONObject(i)
            keys(item, setOf("id", "type"))
            require(item.get("type") == "public-key" && seen.add(encoded(item.get("id"), 1, 1023)))
        }
        return value
    }

    // Providers may return attachment/transport metadata. Send only the exact
    // server contract; never re-encode or fabricate the signed clientData bytes.
    fun response(raw: String, create: Boolean): String {
        require(raw.toByteArray(Charsets.UTF_8).size <= LIMIT)
        val value = JSONObject(raw)
        val id = providerEncoded(value.get("id"), 1, 1023)
        require(providerEncoded(value.get("rawId"), 1, 1023) == id && value.get("type") == "public-key")
        if (value.has("clientExtensionResults")) require(value.getJSONObject("clientExtensionResults").length() == 0)
        val source = value.getJSONObject("response")
        val response = JSONObject().put("clientDataJSON", providerEncoded(source.get("clientDataJSON"), 1, 3072))
        if (create) response.put("attestationObject", providerEncoded(source.get("attestationObject"), 1, 4096))
        else {
            response.put("authenticatorData", providerEncoded(source.get("authenticatorData"), 37, 2048))
            response.put("signature", providerEncoded(source.get("signature"), 8, 1024))
            response.put("userHandle", providerEncoded(source.get("userHandle"), 32, 32))
        }
        return JSONObject().put("id", id).put("rawId", id).put("type", "public-key")
            .put("response", response).put("clientExtensionResults", JSONObject()).toString()
    }

    // Acceptance diagnostics expose only fixed field categories, never values,
    // provider messages, signed bytes, identifiers, or user handles.
    fun rejectedResponseField(raw: String, create: Boolean): String {
        if (raw.toByteArray(Charsets.UTF_8).size > LIMIT) return "invalidResponseSize"
        val value = runCatching { JSONObject(raw) }.getOrNull() ?: return "invalidResponseJson"
        val id = runCatching { providerEncoded(value.get("id"), 1, 1023) }.getOrNull()
            ?: return "invalidResponseId"
        if (runCatching { providerEncoded(value.get("rawId"), 1, 1023) }.getOrNull() != id || value.opt("type") != "public-key") return "invalidResponseEnvelope"
        if (value.has("clientExtensionResults") && runCatching {
            value.getJSONObject("clientExtensionResults").length() == 0
        }.getOrDefault(false).not()) return "invalidResponseExtensions"
        val response = runCatching { value.getJSONObject("response") }.getOrNull()
            ?: return "invalidResponseBody"
        fun valid(name: String, minimum: Int, maximum: Int) =
            runCatching { providerEncoded(response.get(name), minimum, maximum); true }.getOrDefault(false)
        if (!valid("clientDataJSON", 1, 3072)) return "invalidResponseClientData"
        if (create) return if (valid("attestationObject", 1, 4096)) "invalidResponseOther" else "invalidResponseAttestation"
        if (!valid("authenticatorData", 37, 2048)) return "invalidResponseAuthenticatorData"
        if (!valid("signature", 8, 1024)) return "invalidResponseSignature"
        if (response.isNull("userHandle")) return "invalidResponseUserHandleAbsent"
        if (!valid("userHandle", 32, 32)) return "invalidResponseUserHandleEncoding"
        return "invalidResponseOther"
    }

    private fun keys(value: JSONObject, required: Set<String>) {
        require(value.keys().asSequence().toSet() == required)
    }
    private fun rp(value: Any) {
        require(value is String && value.length <= 253 &&
            Regex("^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$").matches(value) &&
            value.split('.').all { it.length <= 63 } && !Regex("^[0-9.]+$").matches(value))
    }
    private fun encoded(value: Any, minimum: Int, maximum: Int): String {
        require(value is String && value.length <= (maximum * 4 + 2) / 3 && Regex("^[A-Za-z0-9_-]+$").matches(value))
        val bytes = Base64.decode(value, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
        require(bytes.size in minimum..maximum &&
            Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING) == value)
        return value
    }

    private fun providerEncoded(value: Any, minimum: Int, maximum: Int): String {
        require(value is String && value.length <= ((maximum + 2) / 3) * 4 &&
            Regex("^[A-Za-z0-9_-]+={0,2}$").matches(value))
        val bytes = Base64.decode(value, Base64.URL_SAFE or Base64.NO_WRAP)
        require(bytes.size in minimum..maximum)
        val canonical = Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
        val padded = canonical + "=".repeat((4 - canonical.length % 4) % 4)
        require(value == canonical || value == padded)
        // Normalize the transport spelling only; signed binary bytes are exact.
        return canonical
    }
}
