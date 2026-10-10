package org.hnuhole.authpasskey

import android.app.Activity
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.MutableContextWrapper
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import androidx.credentials.CreateCredentialResponse
import androidx.credentials.CreatePublicKeyCredentialRequest
import androidx.credentials.CreatePublicKeyCredentialResponse
import androidx.credentials.CredentialManager
import androidx.credentials.CredentialManagerCallback
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetCredentialResponse
import androidx.credentials.GetPublicKeyCredentialOption
import androidx.credentials.PublicKeyCredential
import androidx.credentials.exceptions.CreateCredentialCancellationException
import androidx.credentials.exceptions.CreateCredentialException
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor
import java.io.File
import org.json.JSONObject

class AuthPasskeyPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private var channel: MethodChannel? = null
    private var activity: Activity? = null
    private val handler = Handler(Looper.getMainLooper())
    private val executor = Executor { command -> handler.post(command) }
    private data class Operation(val result: MethodChannel.Result, val signal: CancellationSignal,
        val context: MutableContextWrapper, val fallback: android.content.Context,
        var deadline: Runnable? = null)
    private val pending = PendingOperation<Operation>()
    private var acceptanceContext: Context? = null
    private var acceptancePhase: String? = null
    private var acceptancePrevious: Operation? = null
    private var acceptanceCreationLabel: String? = null

    private fun observeAcceptance(event: String? = null): Map<String, Any>? {
        val context = acceptanceContext ?: return null
        val file = File(context.filesDir, "owned-acceptance-passkey.json")
        val previous = runCatching { JSONObject(file.readText()) }.getOrNull()
        val value = if (previous != null && previous.optInt("pid") == android.os.Process.myPid()) previous else
            JSONObject().put("pid", android.os.Process.myPid())
        if (event != null) value.put(event, value.optInt(event) + 1)
        file.writeText(value.toString())
        return value.keys().asSequence().associateWith { value.get(it) }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "hnuhole/auth_passkey").also { it.setMethodCallHandler(this) }
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        observeAcceptance("engineDetached")
        cancel()
        acceptancePrevious = null
        acceptanceCreationLabel = null
        channel?.setMethodCallHandler(null)
        channel = null
    }
    private fun attach(host: Activity) {
        activity = host
        val phase = host.intent.getStringExtra("hnuhole-device-phase")
        if (host.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0 &&
            host.intent.getBooleanExtra("hnuhole-device-driver", false) &&
            phase?.matches(Regex("ni-[a-z][0-9]{2}(-read)?")) == true) {
            acceptanceContext = host.applicationContext
            acceptancePhase = phase
            observeAcceptance("activityAttached")
        } else {
            acceptanceContext = null
            acceptancePhase = null
            acceptancePrevious = null
            acceptanceCreationLabel = null
        }
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) { attach(binding.activity) }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { attach(binding.activity) }
    override fun onDetachedFromActivityForConfigChanges() { observeAcceptance("activityDetached"); cancel(); activity = null }
    override fun onDetachedFromActivity() { observeAcceptance("activityDetached"); cancel(); activity = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "acceptanceCreationLabel" && acceptanceContext != null && activity != null &&
            acceptancePhase in setOf("ni-c01", "ni-d01", "ni-d02", "ni-d03", "ni-d05")) {
            val label = call.arguments as? String
            if (label == null || !Regex("HnuHole test [a-f0-9]{8}").matches(label) || pending.active()) {
                error(result, "PASSKEY_INVALID_OPTIONS"); return
            }
            acceptanceCreationLabel = label
            result.success(null); return
        }
        if (call.method == "acceptanceState" && acceptanceContext != null && activity != null) {
            result.success(observeAcceptance()); return
        }
        if (call.method == "acceptanceLateCallback" && acceptancePhase == "ni-l04" && activity != null) {
            val old = acceptancePrevious
            if (old == null || call.arguments !in setOf("success", "error")) {
                result.error("ACCEPTANCE_NO_OLD_OPERATION", "Owned cancelled operation required", null); return
            }
            // Deterministic test injection into the real ownership gate. No raw
            // credential or proof can be supplied; old success is discarded
            // before parsing this deliberately empty response.
            if (call.arguments == "success") finish(old, "{}", true)
            else finishError(old, "PASSKEY_FAILED")
            result.success(null); return
        }
        if (call.method == "cancel") { cancel(); result.success(null); return }
        val selectedAcceptance = call.method == "acceptanceGetSelected" &&
            acceptanceContext != null && acceptancePhase in setOf("ni-c01", "ni-d05") && activity != null
        if (call.method != "create" && call.method != "get" && !selectedAcceptance) { result.notImplemented(); return }
        val host = activity
        if (Build.VERSION.SDK_INT < 28 || host == null || host.isFinishing || host.isDestroyed) {
            error(result, "PASSKEY_UNAVAILABLE"); return
        }
        val create = call.method == "create"
        val raw = try {
            val arguments = call.arguments as? Map<*, *> ?: throw IllegalArgumentException()
            require(arguments.keys == if (selectedAcceptance) setOf("publicKey", "credentialId") else setOf("publicKey"))
            val options = arguments["publicKey"] as? String ?: throw IllegalArgumentException()
            if (selectedAcceptance) {
                val id = arguments["credentialId"] as? String ?: throw IllegalArgumentException()
                PasskeyCodec.selectedAcceptanceOptions(options, id)
            } else {
                PasskeyCodec.options(options, create)
                val label = acceptanceCreationLabel
                if (create && label != null) PasskeyCodec.labeledAcceptanceOptions(options, label) else options
            }
        } catch (_: Exception) { error(result, "PASSKEY_INVALID_OPTIONS"); return }
        val operation = Operation(result, CancellationSignal(), MutableContextWrapper(host), host.applicationContext)
        if (!pending.begin(operation)) { error(result, "PASSKEY_BUSY"); return }
        observeAcceptance("nativeBegun")
        // The server requests 60s. Bound providers that never callback as well.
        operation.deadline = Runnable {
            observeAcceptance("nativeTimeout")
            finishError(operation, "PASSKEY_CANCELLED", true)
        }
        handler.postDelayed(operation.deadline!!, 60000)
        try {
            val manager = CredentialManager.create(host.applicationContext)
            if (create) {
                // origin/clientDataHash remain unset: only the OS chooses them.
                val request = CreatePublicKeyCredentialRequest(requestJson = raw,
                    preferImmediatelyAvailableCredentials = false)
                manager.createCredentialAsync(operation.context, request, operation.signal, executor,
                    object : CredentialManagerCallback<CreateCredentialResponse, CreateCredentialException> {
                        override fun onResult(response: CreateCredentialResponse) {
                            val credential = response as? CreatePublicKeyCredentialResponse
                            if (credential == null) finishError(operation, "PASSKEY_INVALID_RESPONSE")
                            else finish(operation, credential.registrationResponseJson, true)
                        }
                        override fun onError(e: CreateCredentialException) {
                            observeAcceptance(PasskeyAcceptanceErrors.create(e))
                            // Owned negative tests expose a bounded category;
                            // provider message/type are never stored or logged.
                            if (acceptancePhase in setOf("ni-d01", "ni-d02", "ni-d03")) {
                                if (PasskeyAcceptanceErrors.association(e)) {
                                    observeAcceptance("actualAssociationRejected")
                                } else observeAcceptance("actualOtherCreateError")
                            }
                            finishError(operation, if (e is CreateCredentialCancellationException) "PASSKEY_CANCELLED" else "PASSKEY_FAILED")
                        }
                    })
            } else {
                val request = GetCredentialRequest(listOf(GetPublicKeyCredentialOption(requestJson = raw)))
                manager.getCredentialAsync(operation.context, request, operation.signal, executor,
                    object : CredentialManagerCallback<GetCredentialResponse, GetCredentialException> {
                        override fun onResult(response: GetCredentialResponse) {
                            val credential = response.credential as? PublicKeyCredential
                            if (credential == null) finishError(operation, "PASSKEY_INVALID_RESPONSE")
                            else finish(operation, credential.authenticationResponseJson, false)
                        }
                        override fun onError(e: GetCredentialException) {
                            observeAcceptance(PasskeyAcceptanceErrors.get(e))
                            when (e.javaClass.simpleName) {
                                "NoCredentialException" -> observeAcceptance("actualNoCredential")
                                "GetCredentialProviderConfigurationException", "GetCredentialUnsupportedException" ->
                                    observeAcceptance("actualProviderUnavailable")
                            }
                            finishError(operation, when (e) {
                                is GetCredentialCancellationException -> "PASSKEY_CANCELLED"
                                is NoCredentialException -> "PASSKEY_NOT_FOUND"
                                else -> "PASSKEY_FAILED"
                            })
                        }
                    })
            }
        } catch (_: Exception) {
            observeAcceptance(if (create) "nativeCreateSynchronousError" else "nativeGetSynchronousError")
            finishError(operation, "PASSKEY_FAILED", true)
        }
    }
    private fun release(operation: Operation) {
        operation.deadline?.let { handler.removeCallbacks(it) }
        operation.context.baseContext = operation.fallback
    }
    private fun finish(operation: Operation, raw: String, create: Boolean) {
        if (pending.take(operation) == null) { observeAcceptance("lateIgnored"); return }
        observeAcceptance("nativeSucceeded")
        release(operation)
        try { operation.result.success(PasskeyCodec.response(raw, create)) }
        catch (_: Exception) {
            if (acceptanceContext != null) observeAcceptance(PasskeyCodec.rejectedResponseField(raw, create))
            error(operation.result, "PASSKEY_INVALID_RESPONSE")
        }
    }
    private fun finishError(operation: Operation, code: String, cancelSignal: Boolean = false) {
        if (pending.take(operation) == null) { observeAcceptance("lateIgnored"); return }
        observeAcceptance("nativeErrored")
        release(operation)
        if (cancelSignal) { try { operation.signal.cancel() } catch (_: Exception) { } }
        error(operation.result, code)
    }
    private fun cancel() {
        val operation = pending.cancel() ?: return
        if (acceptancePhase == "ni-l04") acceptancePrevious = operation
        observeAcceptance("nativeCancelled")
        release(operation)
        try { operation.signal.cancel() } catch (_: Exception) { }
        error(operation.result, "PASSKEY_CANCELLED")
    }
    private fun error(result: MethodChannel.Result, code: String) {
        result.error(code, "Passkey operation unavailable or incomplete", null)
    }
}
