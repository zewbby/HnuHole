package org.hnuhole.authvault

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Ciphertext lives only in noBackupFilesDir; keys never leave Android Keystore.
 * A native serial queue, file sync, atomic replacement and directory sync finish
 * before success. No asynchronous SharedPreferences.apply acknowledgement. */
class AuthVaultPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var vault: AndroidAuthVault
    private lateinit var channel: MethodChannel
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        vault = AndroidAuthVault(binding.applicationContext)
        channel = MethodChannel(binding.binaryMessenger, "hnuhole/auth_vault")
        channel.setMethodCallHandler(this)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "read" && call.method != "write") { result.notImplemented(); return }
        executor.execute {
            try {
                val namespace = call.argument<String>("namespace") ?: throw IllegalArgumentException()
                val value = if (call.method == "read") vault.read(namespace) else {
                    val text = call.argument<String>("value") ?: throw IllegalArgumentException()
                    vault.write(namespace, text)
                    null
                }
                main.post { result.success(value) }
            } catch (_: Exception) {
                // Never put request values, filenames, ciphertext or native
                // exception messages into platform errors or Android logs.
                main.post { result.error("AUTH_STORAGE_UNAVAILABLE", "Authentication storage unavailable", null) }
            }
        }
    }
}
