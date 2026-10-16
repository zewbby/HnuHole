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

/** 确认状态是 noBackupFilesDir 中的加密原子文件。
 * 密钥始终来自 AndroidKeyStore；内部 IO 接缝只允许原生集成测试模拟真实文件系统故障，不能替代加密实现。 */
internal class AndroidAuthVault(
    context: Context,
    private val io: VaultCommitIO = SystemVaultCommitIO,
    private val directory: File = context.noBackupFilesDir,
    private val aliasPrefix: String = "hnuhole.auth.",
) {

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
            // 解码器拒绝非法 UTF-8，不把非法字节替换成其他字符。
            Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(clear)).toString()
        } finally { clear.fill(0) }
    }

    fun write(namespace: String, value: String) = synchronized(processLock) {
        val record = record(namespace)
            // 拒绝覆盖损坏或恢复出的状态。Dart 存储也会在每次事务前读取，
            // 但这一不变量必须位于原生持久化边界，包括新接入 engine 的调用。
        if (exists(record)) read(namespace)
        require(value.length <= MAX_CLEAR_BYTES)
        val clear = value.toByteArray(Charsets.UTF_8)
        val encrypted = try {
            require(clear.size <= MAX_CLEAR_BYTES)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            // 恢复或损坏的记录若没有设备密钥，绝不能悄悄创建新密钥覆盖未知状态。
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
            // Android AtomicFile 可能只记录替换失败而不抛异常。
            // 只有确认精确的加密记录已存在时才能返回成功。
            check(boundedRead(record).contentEquals(encrypted))
            io.syncDirectory(directory)
        } catch (error: Exception) {
            record.failWrite(stream)
            throw error
        }
    }

    // 业务密钥的首次创建跨 engine 串行；已有密钥只允许相同值确认。
    fun writeOnce(namespace: String, value: String) = synchronized(processLock) {
        val previous = read(namespace)
        check(previous == null || previous == value)
        if (previous == null) write(namespace, value)
    }

    fun delete(namespace: String) = synchronized(processLock) {
        val record = record(namespace)
        record.delete()
        check(!exists(record) && !File(record.baseFile.path + ".new").exists())
        val keys = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        keys.deleteEntry("$aliasPrefix$namespace")
        check(!keys.containsAlias("$aliasPrefix$namespace"))
        io.syncDirectory(directory)
    }

    private fun record(namespace: String): AtomicFile {
        require(namespace.matches(Regex("^[A-Za-z0-9_.-]{1,128}$")))
        return AtomicFile(File(directory, "$namespace.auth"))
    }

    private fun exists(record: AtomicFile): Boolean =
        record.baseFile.exists() || File(record.baseFile.path + ".bak").exists()

    private fun boundedRead(record: AtomicFile): ByteArray = record.openRead().use { input ->
        require(input.channel.size() in MIN_RECORD_BYTES.toLong()..MAX_RECORD_BYTES.toLong())
        // 即使外部写入者在 stat 和 read 之间扩大文件，也要限制内存分配。
        // 合法的最大负载只需要 65,565 字节。
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
        val alias = "$aliasPrefix$namespace"
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
        private const val MIN_RECORD_BYTES = 29 // 版本号 + IV + GCM 标签；空内容也是合法的。
        private const val MAX_RECORD_BYTES = MAX_CLEAR_BYTES + MIN_RECORD_BYTES
        // MethodChannel 已经会排队；这里还要串行化同一进程不同 engine
        // 对同一 AtomicFile 的访问。
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
        // Android SDK 没有导出 O_DIRECTORY。同步目录前通过公开 fstat API
        // 验证已打开描述符确实是目录。
        val descriptor = Os.open(directory.path, OsConstants.O_RDONLY, 0)
        try {
            check(OsConstants.S_ISDIR(Os.fstat(descriptor).st_mode))
            Os.fsync(descriptor)
        } finally { Os.close(descriptor) }
    }
}
