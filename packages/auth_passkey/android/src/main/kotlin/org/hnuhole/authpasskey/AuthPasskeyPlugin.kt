package org.hnuhole.authpasskey

import android.app.Activity
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

class AuthPasskeyPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private var channel: MethodChannel? = null
    private var activity: Activity? = null
    private val handler = Handler(Looper.getMainLooper())
    private val executor = Executor { command -> handler.post(command) }
    private data class Operation(val result: MethodChannel.Result, val signal: CancellationSignal,
        val context: MutableContextWrapper, val fallback: android.content.Context,
        var deadline: Runnable? = null)
    private val pending = PendingOperation<Operation>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "hnuhole/auth_passkey").also { it.setMethodCallHandler(this) }
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        cancel()
        channel?.setMethodCallHandler(null)
        channel = null
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges() { cancel(); activity = null }
    override fun onDetachedFromActivity() { cancel(); activity = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "cancel") { cancel(); result.success(null); return }
        if (call.method != "create" && call.method != "get") { result.notImplemented(); return }
        val host = activity
        if (Build.VERSION.SDK_INT < 28 || host == null || host.isFinishing || host.isDestroyed) {
            error(result, "PASSKEY_UNAVAILABLE"); return
        }
        val create = call.method == "create"
        val raw = try {
            val arguments = call.arguments as? Map<*, *> ?: throw IllegalArgumentException()
            require(arguments.keys == setOf("publicKey"))
            val options = arguments["publicKey"] as? String ?: throw IllegalArgumentException()
            PasskeyCodec.options(options, create)
            options
        } catch (_: Exception) { error(result, "PASSKEY_INVALID_OPTIONS"); return }
        val operation = Operation(result, CancellationSignal(), MutableContextWrapper(host), host.applicationContext)
        if (!pending.begin(operation)) { error(result, "PASSKEY_BUSY"); return }
        // The server requests 60s. Bound providers that never callback as well.
        operation.deadline = Runnable { finishError(operation, "PASSKEY_CANCELLED", true) }
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
                            finishError(operation, when (e) {
                                is GetCredentialCancellationException -> "PASSKEY_CANCELLED"
                                is NoCredentialException -> "PASSKEY_NOT_FOUND"
                                else -> "PASSKEY_FAILED"
                            })
                        }
                    })
            }
        } catch (_: Exception) { finishError(operation, "PASSKEY_FAILED", true) }
    }
    private fun release(operation: Operation) {
        operation.deadline?.let { handler.removeCallbacks(it) }
        operation.context.baseContext = operation.fallback
    }
    private fun finish(operation: Operation, raw: String, create: Boolean) {
        if (pending.take(operation) == null) return
        release(operation)
        try { operation.result.success(PasskeyCodec.response(raw, create)) }
        catch (_: Exception) { error(operation.result, "PASSKEY_INVALID_RESPONSE") }
    }
    private fun finishError(operation: Operation, code: String, cancelSignal: Boolean = false) {
        if (pending.take(operation) == null) return
        release(operation)
        if (cancelSignal) { try { operation.signal.cancel() } catch (_: Exception) { } }
        error(operation.result, code)
    }
    private fun cancel() {
        val operation = pending.cancel() ?: return
        release(operation)
        try { operation.signal.cancel() } catch (_: Exception) { }
        error(operation.result, "PASSKEY_CANCELLED")
    }
    private fun error(result: MethodChannel.Result, code: String) {
        result.error(code, "Passkey operation unavailable or incomplete", null)
    }
}
