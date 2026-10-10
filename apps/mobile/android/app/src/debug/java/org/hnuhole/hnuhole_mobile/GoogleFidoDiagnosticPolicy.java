package org.hnuhole.hnuhole_mobile;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

/** Pure policy shared with the small host JVM test; never packaged in release. */
final class GoogleFidoDiagnosticPolicy {
    static final String PACKAGE = "org.hnuhole.hnuhole_mobile.acceptance";
    static final String OWNER = "HNUHOLE_GOOGLE_FIDO_DIAGNOSTIC_V1";
    static final String PHASE = "ni-d02";
    static final String VARIANT = "control";
    static final String CERT = "fd26b276cb170bf084a932d3b3919bd3aa44874395809968bdd74ddab87389dc";
    static final String RP = "zewbby.github.io";

    static boolean admitted(boolean debug, String pkg, String owner, String phase,
                            String variant, String runId, String nonce, String suppliedNonce) {
        return debug && PACKAGE.equals(pkg) && OWNER.equals(owner) && PHASE.equals(phase)
            && VARIANT.equals(variant) && validRunId(runId)
            && nonce != null && nonce.matches("[a-f0-9]{64}") && nonce.equals(suppliedNonce);
    }

    static boolean validRunId(String value) {
        return value != null && value.matches("gfd-[a-f0-9]{32}");
    }

    static boolean launchAllowed(boolean admissionLaunch, boolean explicitIntentLaunch) {
        return admissionLaunch && explicitIntentLaunch;
    }

    static String options(String challenge, String userId, String suffix) {
        if (challenge == null || !challenge.matches("[A-Za-z0-9_-]{43}")
            || userId == null || !userId.matches("[A-Za-z0-9_-]{43}")
            || suffix == null || !suffix.matches("[a-f0-9]{8}")) {
            throw new IllegalArgumentException("Invalid synthetic diagnostic input");
        }
        String label = "HnuHole Google diagnostic " + suffix;
        return "{\"challenge\":\"" + challenge + "\",\"rp\":{\"id\":\"" + RP
            + "\",\"name\":\"HnuHole Google diagnostic\"},\"user\":{\"id\":\"" + userId
            + "\",\"name\":\"" + label + "\",\"displayName\":\"" + label
            + "\"},\"pubKeyCredParams\":[{\"type\":\"public-key\",\"alg\":-7}],"
            + "\"authenticatorSelection\":{\"authenticatorAttachment\":\"platform\","
            + "\"residentKey\":\"required\",\"requireResidentKey\":true,\"userVerification\":\"required\"},"
            + "\"timeout\":120000,\"attestation\":\"none\"}";
    }

    static String apiClassification(Integer code) {
        if (code == null) return "SDK_EXCEPTION_WITHOUT_API_STATUS";
        switch (code) {
            case 7: return "API_NETWORK_ERROR";
            case 8: return "API_INTERNAL_ERROR";
            case 10: return "API_DEVELOPER_ERROR_UNATTRIBUTED";
            case 15: return "API_TIMEOUT";
            case 16: return "API_CANCELED_UNATTRIBUTED";
            case 17: return "API_NOT_CONNECTED";
            default: return "API_STATUS_UNATTRIBUTED";
        }
    }

    static String authenticatorClassification(String error) {
        if ("SECURITY_ERR".equals(error)) return "AUTHENTICATOR_SECURITY_ERROR";
        if ("NOT_ALLOWED_ERR".equals(error)) return "AUTHENTICATOR_NOT_ALLOWED_UNATTRIBUTED";
        if ("NETWORK_ERR".equals(error)) return "AUTHENTICATOR_NETWORK_ERROR";
        if ("TIMEOUT_ERR".equals(error)) return "AUTHENTICATOR_TIMEOUT";
        if ("CONSTRAINT_ERR".equals(error)) return "AUTHENTICATOR_CONSTRAINT_ERROR";
        return "AUTHENTICATOR_ERROR_UNATTRIBUTED";
    }

    static String sha256(byte[] value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(value);
            StringBuilder output = new StringBuilder(64);
            for (byte item : digest) output.append(String.format(java.util.Locale.ROOT, "%02x", item & 255));
            return output.toString();
        } catch (java.security.NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 unavailable");
        }
    }

    static String messageHash(String value) {
        return value == null ? null : sha256(value.getBytes(StandardCharsets.UTF_8));
    }
}
