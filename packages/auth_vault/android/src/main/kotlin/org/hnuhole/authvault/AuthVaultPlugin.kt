package org.hnuhole.authvault

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.system.Os
import android.system.OsConstants
import android.util.AtomicFile
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Ciphertext lives only in noBackupFilesDir; keys never leave Android Keystore.
 * A native serial queue, file sync, atomic replacement and directory sync finish
 * before success. No asynchronous SharedPreferences.apply acknowledgement. */
class AuthVaultPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
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
                require(namespace.matches(Regex("^[A-Za-z0-9_.-]{1,128}$")))
                val record = AtomicFile(File(context.noBackupFilesDir, "$namespace.auth"))
                val value = if (call.method == "read") read(record, namespace) else {
                    val text = call.argument<String>("value") ?: throw IllegalArgumentException()
                    write(record, namespace, text)
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
    private fun key(namespace: String, create: Boolean): SecretKey {
        val keys = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val alias = "hnuhole.auth.$namespace"
        if (keys.containsAlias(alias)) return keys.getKey(alias, null) as SecretKey
        check(create)
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256).build())
        return generator.generateKey()
    }
    private fun read(record: AtomicFile, namespace: String): String? {
        if (!record.baseFile.exists() && !File(record.baseFile.path + ".bak").exists()) return null
        val bytes = record.openRead().use { input ->
            require(input.channel.size() in 30..65600)
            val data = input.readBytes()
            require(data.size in 30..65600)
            data
        }
        require(bytes[0] == 1.toByte())
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(namespace, false), GCMParameterSpec(128, bytes.copyOfRange(1, 13)))
        cipher.updateAAD(namespace.toByteArray(Charsets.UTF_8))
        val clear = cipher.doFinal(bytes.copyOfRange(13, bytes.size))
        try {
            val decoder = Charsets.UTF_8.newDecoder()
            return decoder.decode(java.nio.ByteBuffer.wrap(clear)).toString()
        } finally { clear.fill(0) }
    }
    private fun write(record: AtomicFile, namespace: String, value: String) {
        val clear = value.toByteArray(Charsets.UTF_8)
        require(clear.size <= 65536)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key(namespace, !record.baseFile.exists() && !File(record.baseFile.path + ".bak").exists()))
        cipher.updateAAD(namespace.toByteArray(Charsets.UTF_8))
        val encrypted = try { byteArrayOf(1) + cipher.iv + cipher.doFinal(clear) } finally { clear.fill(0) }
        require(cipher.iv.size == 12)
        val stream = record.startWrite()
        try {
            stream.write(encrypted)
            stream.fd.sync()
            record.finishWrite(stream)
            // finishWrite logs some rename failures instead of throwing, so
            // verify the ciphertext before acknowledging this commit.
            check(record.baseFile.readBytes().contentEquals(encrypted))
            val directory = Os.open(context.noBackupFilesDir.path, OsConstants.O_RDONLY or OsConstants.O_DIRECTORY, 0)
            try { Os.fsync(directory) } finally { Os.close(directory) }
        } catch (error: Exception) { record.failWrite(stream); throw error }
    }
}
