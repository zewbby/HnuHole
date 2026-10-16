package org.hnuhole.authvault

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.system.Os
import android.system.OsConstants
import android.util.AtomicFile
import java.io.File
import java.io.FileOutputStream
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** The acknowledged state is an encrypted, synced atomic file in noBackupFilesDir.
 * The key always comes from AndroidKeyStore. The internal IO seam allows native
 * integration tests to fail real filesystem boundaries, never replace crypto. */
internal class AndroidAuthVault(
    context: Context,
    private val io: VaultCommitIO = SystemVaultCommitIO,
) {
    private val directory = context.noBackupFilesDir

    fun read(namespace: String): String? = synchronized(processLock) {
        val record = record(namespace)
        if (!exists(record)) return@synchronized null
        val encrypted = boundedRead(record)
        require(encrypted[0] == 1.toByte())
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(namespace, false),
            GCMParameterSpec(128, encrypted.copyOfRange(1, 13)))
        cipher.updateAAD(namespace.toByteArray(Charsets.UTF_8))
        val clear = cipher.doFinal(encrypted.copyOfRange(13, encrypted.size))
        try {
            // The decoder rejects invalid UTF-8 instead of replacing bytes.
            Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(clear)).toString()
        } finally { clear.fill(0) }
    }

    fun write(namespace: String, value: String) = synchronized(processLock) {
        val record = record(namespace)
        // Refuse to overwrite damaged/restored state. The Dart store also reads
        // before each transaction, but this invariant belongs at the native
        // persistence boundary, including calls from a newly attached engine.
        if (exists(record)) read(namespace)
        require(value.length <= MAX_CLEAR_BYTES)
        val clear = value.toByteArray(Charsets.UTF_8)
        val encrypted = try {
            require(clear.size <= MAX_CLEAR_BYTES)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            // A restored or damaged record without its device key must never
            // silently create a new key and overwrite the unknown state.
            cipher.init(Cipher.ENCRYPT_MODE, key(namespace, !exists(record)))
            cipher.updateAAD(namespace.toByteArray(Charsets.UTF_8))
            require(cipher.iv.size == 12)
            byteArrayOf(1) + cipher.iv + cipher.doFinal(clear)
        } finally { clear.fill(0) }
        val stream = record.startWrite()
        try {
            stream.write(encrypted)
            io.syncFile(stream)
            io.finishWrite(record, stream)
            // Android AtomicFile can log replacement failures without throwing.
            // Do not acknowledge unless the exact encrypted record is present.
            check(boundedRead(record).contentEquals(encrypted))
            io.syncDirectory(directory)
        } catch (error: Exception) {
            record.failWrite(stream)
            throw error
        }
    }

    private fun record(namespace: String): AtomicFile {
        require(namespace.matches(Regex("^[A-Za-z0-9_.-]{1,128}$")))
        return AtomicFile(File(directory, "$namespace.auth"))
    }

    private fun exists(record: AtomicFile): Boolean =
        record.baseFile.exists() || File(record.baseFile.path + ".bak").exists()

    private fun boundedRead(record: AtomicFile): ByteArray = record.openRead().use { input ->
        require(input.channel.size() in MIN_RECORD_BYTES.toLong()..MAX_RECORD_BYTES.toLong())
        // Keep the allocation bounded even if an outside writer grows the file
        // between stat and read. A valid maximum payload needs only 65,565 bytes.
        val bytes = ByteArray(MAX_RECORD_BYTES + 1)
        var count = 0
        while (count < bytes.size) {
            val read = input.read(bytes, count, bytes.size - count)
            if (read < 0) break
            count += read
        }
        require(count in MIN_RECORD_BYTES..MAX_RECORD_BYTES)
        bytes.copyOf(count)
    }

    private fun key(namespace: String, create: Boolean): SecretKey {
        val keys = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val alias = "hnuhole.auth.$namespace"
        if (keys.containsAlias(alias)) return keys.getKey(alias, null) as SecretKey
        check(create)
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256).build())
        return generator.generateKey()
    }

    companion object {
        private const val MAX_CLEAR_BYTES = 65536
        private const val MIN_RECORD_BYTES = 29 // version + IV + GCM tag; empty is valid.
        private const val MAX_RECORD_BYTES = MAX_CLEAR_BYTES + MIN_RECORD_BYTES
        // MethodChannel already queues requests. This also serializes separate
        // engine instances in this app process against the same AtomicFile.
        private val processLock = Any()
    }
}

internal interface VaultCommitIO {
    fun syncFile(stream: FileOutputStream)
    fun finishWrite(record: AtomicFile, stream: FileOutputStream)
    fun syncDirectory(directory: File)
}

internal object SystemVaultCommitIO : VaultCommitIO {
    override fun syncFile(stream: FileOutputStream) { stream.fd.sync() }
    override fun finishWrite(record: AtomicFile, stream: FileOutputStream) { record.finishWrite(stream) }
    override fun syncDirectory(directory: File) {
        // O_DIRECTORY is not exported by the Android SDK. Verify the opened
        // descriptor's type through the public fstat API before syncing it.
        val descriptor = Os.open(directory.path, OsConstants.O_RDONLY, 0)
        try {
            check(OsConstants.S_ISDIR(Os.fstat(descriptor).st_mode))
            Os.fsync(descriptor)
        } finally { Os.close(descriptor) }
    }
}
