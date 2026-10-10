package org.hnuhole.hnuhole_mobile;

import android.app.Activity;
import android.app.KeyguardManager;
import android.app.PendingIntent;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.Process;
import android.util.AtomicFile;
import android.util.Base64;
import com.google.android.gms.common.api.ApiException;
import com.google.android.gms.fido.Fido;
import com.google.android.gms.fido.fido2.Fido2ApiClient;
import com.google.android.gms.fido.fido2.api.common.AuthenticatorErrorResponse;
import com.google.android.gms.fido.fido2.api.common.AuthenticatorAttestationResponse;
import com.google.android.gms.fido.fido2.api.common.AuthenticatorResponse;
import com.google.android.gms.fido.fido2.api.common.PublicKeyCredential;
import com.google.android.gms.fido.fido2.api.common.PublicKeyCredentialCreationOptions;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Arrays;
import org.json.JSONArray;
import org.json.JSONObject;

/** Debug-only contrast probe. Does not open Flutter, read its vault, or submit to C. */
public final class GoogleFidoDiagnosticActivity extends Activity {
    private static final int REGISTER_REQUEST = 7101;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final JSONArray stages = new JSONArray();
    private JSONObject report;
    private AtomicFile reportFile;
    private String runId;
    private String stage;
    private boolean done;
    private boolean launch;
    private final Runnable timeout = () -> complete(stage + "_TIMEOUT", "LOCAL_BOUNDED_TIMEOUT", null);

    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        // Restoration must never repeat a preparation or pending-intent ceremony.
        if (saved != null || android.os.Build.VERSION.SDK_INT < 28) { finish(); return; }
        Intent start = getIntent();
        String requestedRun = start == null ? null : start.getStringExtra("runId");
        String suppliedNonce = start == null ? null : start.getStringExtra("nonce");
        boolean explicitLaunch = start != null && start.getBooleanExtra("launchPendingIntent", false);
        if (!GoogleFidoDiagnosticPolicy.validRunId(requestedRun)
            || suppliedNonce == null || !suppliedNonce.matches("[a-f0-9]{64}")) { finish(); return; }
        // APK hashing and private admission parsing are off the UI thread.
        new Thread(() -> {
            try {
                JSONObject admission = consumeAdmission(requestedRun, suppliedNonce, explicitLaunch);
                handler.post(() -> begin(admission));
            } catch (Exception rejected) {
                // Unadmitted starts have no diagnostic API calls and export no raw exception.
                handler.post(this::finish);
            }
        }, "owned-google-fido-admission").start();
    }

    private JSONObject consumeAdmission(String requestedRun, String nonce, boolean explicitLaunch) throws Exception {
        File directory = getNoBackupFilesDir().getCanonicalFile();
        File file = new File(directory, "google-fido-diagnostic-admission.json");
        if (!file.getCanonicalFile().equals(file.getAbsoluteFile()) || !file.isFile()
            || file.length() < 100 || file.length() > 2048) throw new IllegalStateException("Admission rejected");
        long age = System.currentTimeMillis() - file.lastModified();
        if (age < 0 || age > 120000) throw new IllegalStateException("Admission expired");
        byte[] content;
        try (FileInputStream input = new FileInputStream(file)) {
            byte[] bounded = new byte[2049]; int used = 0, count;
            while (used < bounded.length && (count = input.read(bounded, used, bounded.length - used)) != -1) used += count;
            if (used > 2048) throw new IllegalStateException("Admission oversized");
            content = Arrays.copyOf(bounded, used);
            Arrays.fill(bounded, (byte) 0);
        }
        JSONObject value = new JSONObject(new String(content, StandardCharsets.UTF_8));
        if (value.length() != 8 || !value.has("owner") || !value.has("phase") || !value.has("variant")
            || !value.has("runId") || !value.has("nonce") || !value.has("apkSha256")
            || !value.has("launchPendingIntent") || !value.has("schemaVersion")
            || value.getInt("schemaVersion") != 1 || !requestedRun.equals(value.getString("runId"))
            || !(value.get("launchPendingIntent") instanceof Boolean)
            || value.getBoolean("launchPendingIntent") != explicitLaunch
            || !GoogleFidoDiagnosticPolicy.admitted(
                (getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0, getPackageName(),
                value.getString("owner"), value.getString("phase"), value.getString("variant"),
                requestedRun, value.getString("nonce"), nonce)) throw new IllegalStateException("Admission rejected");
        Signature[] signers = getPackageManager().getPackageInfo(getPackageName(),
            PackageManager.GET_SIGNING_CERTIFICATES).signingInfo.getApkContentsSigners();
        if (signers.length != 1 || !GoogleFidoDiagnosticPolicy.CERT.equals(
            GoogleFidoDiagnosticPolicy.sha256(signers[0].toByteArray()))) throw new IllegalStateException("Certificate rejected");
        String expectedHash = value.getString("apkSha256");
        if (!expectedHash.matches("[a-f0-9]{64}")) throw new IllegalStateException("APK rejected");
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (FileInputStream input = new FileInputStream(getApplicationInfo().sourceDir)) {
            byte[] buffer = new byte[65536]; int count;
            while ((count = input.read(buffer)) != -1) digest.update(buffer, 0, count);
        }
        StringBuilder actual = new StringBuilder(64);
        for (byte item : digest.digest()) actual.append(String.format(java.util.Locale.ROOT, "%02x", item & 255));
        if (!expectedHash.equals(actual.toString()) || new File(directory,
            "google-fido-diagnostic-" + requestedRun + ".json").exists() || !file.delete())
            throw new IllegalStateException("APK or one-use admission rejected");
        Arrays.fill(content, (byte) 0);
        return value;
    }

    private void begin(JSONObject admission) {
        if (isFinishing() || isDestroyed()) return;
        try {
            runId = admission.getString("runId");
            launch = GoogleFidoDiagnosticPolicy.launchAllowed(admission.getBoolean("launchPendingIntent"),
                getIntent().getBooleanExtra("launchPendingIntent", false));
            reportFile = new AtomicFile(new File(getNoBackupFilesDir(), "google-fido-diagnostic-" + runId + ".json"));
            KeyguardManager keyguard = (KeyguardManager) getSystemService(KEYGUARD_SERVICE);
            report = new JSONObject().put("schemaVersion", 1).put("owner", GoogleFidoDiagnosticPolicy.OWNER)
                .put("runId", runId).put("pid", Process.myPid()).put("phase", GoogleFidoDiagnosticPolicy.PHASE)
                .put("variant", GoogleFidoDiagnosticPolicy.VARIANT).put("applicationId", getPackageName())
                .put("apkSha256", admission.getString("apkSha256")).put("prepareOnly", !launch)
                .put("finished", false)
                .put("nativeOutcomeUnknown", false)
                .put("pendingIntentLaunched", false).put("keyguardSecure", keyguard != null && keyguard.isDeviceSecure())
                .put("actualCSubmission", false).put("fixedCaseAcceptancePassed", false).put("stages", stages);
            Fido2ApiClient client = Fido.getFido2ApiClient(this);
            emit("UV_CHECK_STARTED", "QUERYING", null);
            armTimeout(30000);
            client.isUserVerifyingPlatformAuthenticatorAvailable()
                .addOnSuccessListener(available -> {
                    if (done || !"UV_CHECK_STARTED".equals(stage)) return;
                    try {
                        report.put("uvPlatformAuthenticatorAvailable", Boolean.TRUE.equals(available));
                        emit("UV_CHECK_COMPLETED", Boolean.TRUE.equals(available) ? "UV_AVAILABLE" : "UV_UNAVAILABLE", null);
                        prepare(client);
                    } catch (Exception local) { exception("LOCAL_PREPARATION_FAILED", local); }
                }).addOnFailureListener(error -> {
                    if (done || !"UV_CHECK_STARTED".equals(stage)) return;
                    try {
                        emitException("UV_CHECK_FAILED", error);
                        prepare(client);
                    } catch (Exception local) { exception("LOCAL_PREPARATION_FAILED", local); }
                });
        } catch (Exception local) { exception("LOCAL_SETUP_FAILED", local); }
    }

    private void prepare(Fido2ApiClient client) throws Exception {
        SecureRandom random = new SecureRandom();
        byte[] challenge = new byte[32], userId = new byte[32], label = new byte[4];
        random.nextBytes(challenge); random.nextBytes(userId); random.nextBytes(label);
        String suffix = String.format(java.util.Locale.ROOT, "%02x%02x%02x%02x",
            label[0] & 255, label[1] & 255, label[2] & 255, label[3] & 255);
        String optionsJson = GoogleFidoDiagnosticPolicy.options(
            Base64.encodeToString(challenge, Base64.URL_SAFE | Base64.NO_WRAP | Base64.NO_PADDING),
            Base64.encodeToString(userId, Base64.URL_SAFE | Base64.NO_WRAP | Base64.NO_PADDING), suffix);
        PublicKeyCredentialCreationOptions options = new PublicKeyCredentialCreationOptions(optionsJson);
        Arrays.fill(challenge, (byte) 0); Arrays.fill(userId, (byte) 0); Arrays.fill(label, (byte) 0);
        emit("REGISTER_PREPARATION_STARTED", "PREPARING", null);
        armTimeout(30000);
        client.getRegisterPendingIntent(options).addOnSuccessListener(pending -> {
            if (done || !"REGISTER_PREPARATION_STARTED".equals(stage)) return;
            if (pending == null) { complete("REGISTER_PREPARATION_FAILED", "NULL_PENDING_INTENT", null); return; }
            if (!launch) { complete("REGISTER_PREPARED", "PREPARED_WITHOUT_UI", null); return; }
            launch(pending);
        }).addOnFailureListener(error -> {
            if (!done && "REGISTER_PREPARATION_STARTED".equals(stage)) exception("REGISTER_PREPARATION_FAILED", error);
        });
    }

    private void launch(PendingIntent pending) {
        try {
            // No default path can reach this: both one-use admission and explicit Intent must say true.
            if (!launch || !getIntent().getBooleanExtra("launchPendingIntent", false))
                throw new IllegalStateException("Launch not authorized");
            report.put("pendingIntentLaunched", true);
            report.put("nativeOutcomeUnknown", true);
            emit("REGISTER_UI_STARTED", "EXPLICIT_DIAGNOSTIC_UI", null);
            armTimeout(150000);
            startIntentSenderForResult(pending.getIntentSender(), REGISTER_REQUEST, null, 0, 0, 0);
        } catch (Exception error) { exception("REGISTER_UI_LAUNCH_FAILED", error); }
    }

    @SuppressWarnings("deprecation")
    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REGISTER_REQUEST || done || !launch || !"REGISTER_UI_STARTED".equals(stage)) return;
        byte[] serialized = null;
        try {
            JSONObject fields = new JSONObject().put("activityResultCode", resultCode);
            AuthenticatorErrorResponse error = null;
            if (data != null && data.hasExtra(Fido.FIDO2_KEY_CREDENTIAL_EXTRA)) {
                serialized = data.getByteArrayExtra(Fido.FIDO2_KEY_CREDENTIAL_EXTRA);
                if (serialized != null) {
                    AuthenticatorResponse response = PublicKeyCredential.deserializeFromBytes(serialized).getResponse();
                    if (response instanceof AuthenticatorErrorResponse) error = (AuthenticatorErrorResponse) response;
                    else if (resultCode == RESULT_OK && response instanceof AuthenticatorAttestationResponse) {
                        // Only boolean presence is retained. Never read id, clientData, attestation or user fields.
                        fields.put("credentialResponsePresent", true);
                        report.put("nativeOutcomeUnknown", false);
                        complete("REGISTER_UI_COMPLETED", "DIAGNOSTIC_CREDENTIAL_CREATED_NO_C_SUBMISSION", fields);
                        return;
                    }
                }
            }
            if (error == null && data != null && data.hasExtra(Fido.FIDO2_KEY_ERROR_EXTRA)) {
                if (serialized != null) Arrays.fill(serialized, (byte) 0);
                serialized = data.getByteArrayExtra(Fido.FIDO2_KEY_ERROR_EXTRA);
                if (serialized != null) error = AuthenticatorErrorResponse.deserializeFromBytes(serialized);
            }
            if (error != null) {
                report.put("nativeOutcomeUnknown", false);
                String enumName = error.getErrorCode().name();
                fields.put("authenticatorErrorCode", error.getErrorCodeAsInt()).put("errorEnum", enumName);
                messageFields(fields, error.getErrorMessage());
                complete("REGISTER_UI_ERROR", GoogleFidoDiagnosticPolicy.authenticatorClassification(enumName), fields);
            } else {
                complete("REGISTER_UI_RESULT_WITHOUT_TYPED_ERROR", resultCode == RESULT_CANCELED
                    ? "ACTIVITY_CANCELED_UNATTRIBUTED" : "ACTIVITY_RESULT_UNATTRIBUTED", fields);
            }
        } catch (Exception error) { exception("REGISTER_UI_RESULT_DECODE_FAILED", error); }
        finally { if (serialized != null) Arrays.fill(serialized, (byte) 0); }
    }

    private void messageFields(JSONObject fields, String message) throws Exception {
        fields.put("messageLength", message == null ? 0 : message.length())
            .put("messageSha256", message == null ? JSONObject.NULL : GoogleFidoDiagnosticPolicy.messageHash(message));
    }

    private void emitException(String nextStage, Exception error) throws Exception {
        Integer code = error instanceof ApiException ? ((ApiException) error).getStatusCode() : null;
        JSONObject fields = new JSONObject().put("exceptionClass", error.getClass().getName())
            .put("apiStatusCode", code == null ? JSONObject.NULL : code);
        messageFields(fields, error.getMessage());
        emit(nextStage, GoogleFidoDiagnosticPolicy.apiClassification(code), fields);
    }

    private void exception(String nextStage, Exception error) {
        if (done) return;
        try { report.put("finished", true); emitException(nextStage, error); }
        catch (Exception ignored) { /* no raw logging; an old unfinished report is not completion evidence */ }
        finishOnce();
    }

    private void complete(String nextStage, String classification, JSONObject fields) {
        if (done) return;
        try { report.put("finished", true); emit(nextStage, classification, fields); }
        catch (Exception ignored) { /* no raw logging; an old unfinished report is not completion evidence */ }
        finishOnce();
    }

    private void emit(String nextStage, String classification, JSONObject fields) throws Exception {
        handler.removeCallbacks(timeout);
        stage = nextStage;
        JSONObject event = new JSONObject().put("stage", nextStage).put("classification", classification)
            .put("pid", Process.myPid()).put("elapsedRealtimeMs", android.os.SystemClock.elapsedRealtime());
        if (fields != null) {
            java.util.Iterator<String> names = fields.keys();
            while (names.hasNext()) { String name = names.next(); event.put(name, fields.get(name)); }
        }
        stages.put(event);
        report.put("stage", nextStage).put("classification", classification);
        FileOutputStream output = null;
        try {
            output = reportFile.startWrite();
            output.write(report.toString().getBytes(StandardCharsets.UTF_8));
            reportFile.finishWrite(output);
        } catch (Exception error) { if (output != null) reportFile.failWrite(output); throw error; }
    }

    private void armTimeout(long durationMs) { handler.removeCallbacks(timeout); handler.postDelayed(timeout, durationMs); }
    private void finishOnce() { done = true; handler.removeCallbacks(timeout); finish(); }
    @Override public void onDestroy() { handler.removeCallbacks(timeout); done = true; super.onDestroy(); }
}
