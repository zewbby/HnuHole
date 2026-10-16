package org.hnuhole.hnuhole_mobile;

/** Host JVM policy checks; no Android/device/system prompt involved. */
public final class GoogleFidoDiagnosticPolicyTest {
    private static int count;
    private static void check(boolean condition) { count++; if (!condition) throw new AssertionError("Policy check " + count); }
    public static void main(String[] args) {
        String run = "gfd-" + "1".repeat(32), nonce = "2".repeat(64);
        check(GoogleFidoDiagnosticPolicy.admitted(true, GoogleFidoDiagnosticPolicy.PACKAGE,
            GoogleFidoDiagnosticPolicy.OWNER, "ni-d02", "control", run, nonce, nonce));
        check(!GoogleFidoDiagnosticPolicy.admitted(false, GoogleFidoDiagnosticPolicy.PACKAGE,
            GoogleFidoDiagnosticPolicy.OWNER, "ni-d02", "control", run, nonce, nonce));
        check(!GoogleFidoDiagnosticPolicy.admitted(true, "org.hnuhole.hnuhole_mobile",
            GoogleFidoDiagnosticPolicy.OWNER, "ni-d02", "control", run, nonce, nonce));
        check(!GoogleFidoDiagnosticPolicy.admitted(true, GoogleFidoDiagnosticPolicy.PACKAGE,
            "UNKNOWN", "ni-d02", "control", run, nonce, nonce));
        check(!GoogleFidoDiagnosticPolicy.admitted(true, GoogleFidoDiagnosticPolicy.PACKAGE,
            GoogleFidoDiagnosticPolicy.OWNER, "ni-d03", "control", run, nonce, nonce));
        check(!GoogleFidoDiagnosticPolicy.admitted(true, GoogleFidoDiagnosticPolicy.PACKAGE,
            GoogleFidoDiagnosticPolicy.OWNER, "ni-d02", "bad-signature", run, nonce, nonce));
        check(!GoogleFidoDiagnosticPolicy.admitted(true, GoogleFidoDiagnosticPolicy.PACKAGE,
            GoogleFidoDiagnosticPolicy.OWNER, "ni-d02", "control", "../secret", nonce, nonce));
        check(!GoogleFidoDiagnosticPolicy.admitted(true, GoogleFidoDiagnosticPolicy.PACKAGE,
            GoogleFidoDiagnosticPolicy.OWNER, "ni-d02", "control", run, nonce, "3".repeat(64)));
        check(!GoogleFidoDiagnosticPolicy.launchAllowed(false, false));
        check(!GoogleFidoDiagnosticPolicy.launchAllowed(true, false));
        check(!GoogleFidoDiagnosticPolicy.launchAllowed(false, true));
        check(GoogleFidoDiagnosticPolicy.launchAllowed(true, true));
        String options = GoogleFidoDiagnosticPolicy.options("A".repeat(43), "B".repeat(43), "abcd0123");
        check(options.contains("\"id\":\"zewbby.github.io\""));
        check(options.contains("\"alg\":-7"));
        check(options.contains("\"residentKey\":\"required\""));
        check(options.contains("\"requireResidentKey\":true"));
        check(options.contains("\"userVerification\":\"required\""));
        check(options.contains("\"attestation\":\"none\""));
        check(!options.contains("allowCredentials") && !options.contains("excludeCredentials"));
        try { GoogleFidoDiagnosticPolicy.options("bad\"", "B".repeat(43), "abcd0123"); check(false); }
        catch (IllegalArgumentException expected) { check(true); }
        check(GoogleFidoDiagnosticPolicy.apiClassification(10).equals("API_DEVELOPER_ERROR_UNATTRIBUTED"));
        check(GoogleFidoDiagnosticPolicy.authenticatorClassification("NOT_ALLOWED_ERR").endsWith("UNATTRIBUTED"));
        check(GoogleFidoDiagnosticPolicy.messageHash(null) == null);
        check(GoogleFidoDiagnosticPolicy.messageHash("abc").equals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"));
        System.out.println("PASS: " + count + " host JVM policy checks; device API/ceremony NOT_RUN");
    }
}
