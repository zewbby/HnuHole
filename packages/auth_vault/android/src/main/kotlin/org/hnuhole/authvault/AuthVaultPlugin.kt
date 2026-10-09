package org.hnuhole.authvault

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** 密文只存放在 noBackupFilesDir，密钥不会离开 Android Keystore。
 * 原生串行队列、文件同步、原子替换和目录同步全部完成后才返回成功，
 * 不使用异步 SharedPreferences.apply 作为确认。 */
class AuthVaultPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var vault: AndroidAuthVault
    private lateinit var businessVault: AndroidAuthVault
    private lateinit var businessStorage: AndroidBusinessStorage
    private lateinit var channel: MethodChannel
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        vault = AndroidAuthVault(binding.applicationContext)
        // 独立文件目录和 Keystore alias，认证状态及其安装语义保持原入口。
        businessStorage = AndroidBusinessStorage(binding.applicationContext)
        businessVault = AndroidAuthVault(binding.applicationContext,
            directory = businessStorage.directory, aliasPrefix = "hnuhole.business.v1.")
        channel = MethodChannel(binding.binaryMessenger, "hnuhole/auth_vault")
        channel.setMethodCallHandler(this)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val business = call.method in setOf("businessRead", "businessWrite", "businessDatabasePath", "businessPurgeClosedAccount")
        if (!business && call.method != "read" && call.method != "write") { result.notImplemented(); return }
        executor.execute {
            try {
                val namespace = call.argument<String>("namespace") ?: throw IllegalArgumentException()
                val value = if (business) {
                    if (call.method == "businessPurgeClosedAccount") {
                        businessStorage.purgeClosedAccount(namespace, businessVault)
                        null
                    } else businessStorage.withPreparedScope(namespace) { path ->
                        when (call.method) {
                            "businessDatabasePath" -> path.absolutePath
                            "businessRead" -> businessVault.read(namespace)
                            "businessWrite" -> {
                                val text = call.argument<String>("value") ?: throw IllegalArgumentException()
                                // CLOSED check and writeOnce share purge's lock across engines.
                                businessVault.writeOnce(namespace, text)
                                null
                            }
                            else -> throw IllegalArgumentException()
                        }
                    }
                } else if (call.method == "read") vault.read(namespace) else {
                    val text = call.argument<String>("value") ?: throw IllegalArgumentException()
                    vault.write(namespace, text)
                    null
                }
                main.post { result.success(value) }
            } catch (_: Exception) {
                // 请求值、文件名、密文和原生异常文本不得写入平台错误或 Android 日志。
                val code = if (business) "BUSINESS_STORAGE_UNAVAILABLE" else "AUTH_STORAGE_UNAVAILABLE"
                val message = if (business) "Business storage unavailable" else "Authentication storage unavailable"
                main.post { result.error(code, message, null) }
            }
        }
    }
}
