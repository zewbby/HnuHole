package org.hnuhole.authpasskey

import android.util.Base64
import org.json.JSONObject

internal object PasskeyCodec {
    private const val LIMIT = 32768
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
        val id = encoded(value.get("id"), 1, 1023)
        require(value.get("rawId") == id && value.get("type") == "public-key")
        if (value.has("clientExtensionResults")) require(value.getJSONObject("clientExtensionResults").length() == 0)
        val source = value.getJSONObject("response")
        val response = JSONObject().put("clientDataJSON", encoded(source.get("clientDataJSON"), 1, 3072))
        if (create) response.put("attestationObject", encoded(source.get("attestationObject"), 1, 4096))
        else {
            response.put("authenticatorData", encoded(source.get("authenticatorData"), 37, 2048))
            response.put("signature", encoded(source.get("signature"), 8, 1024))
            response.put("userHandle", encoded(source.get("userHandle"), 32, 32))
        }
        return JSONObject().put("id", id).put("rawId", id).put("type", "public-key")
            .put("response", response).put("clientExtensionResults", JSONObject()).toString()
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
}
