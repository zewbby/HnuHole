package org.hnuhole.authvault

import android.content.Context
import android.util.AtomicFile
import java.io.File

/** 闭号 marker 先持久后擦除；只访问校验过的单一 scope 文件。 */
internal class AndroidBusinessStorage(context: Context) {
    private val parent = context.noBackupFilesDir
    val directory = File(parent, "hnuhole-business-v1")

    fun prepare(scope: String): File = synchronized(lock) {
        ensureDirectory(scope)
        check(!marker(scope).baseFile.exists() && !File(marker(scope).baseFile.path + ".bak").exists())
        File(directory, "$scope.sqlite3")
    }

    fun purgeClosedAccount(scope: String, vault: AndroidAuthVault) = synchronized(lock) {
        ensureDirectory(scope)
        val record = marker(scope)
        if (!record.baseFile.exists()) {
            val stream = record.startWrite()
            try {
                stream.write(byteArrayOf(1))
                SystemVaultCommitIO.syncFile(stream)
                record.finishWrite(stream)
            } catch (error: Exception) {
                record.failWrite(stream)
                throw error
            }
        }
        check(record.openRead().use { it.read() == 1 && it.read() == -1 })
        SystemVaultCommitIO.syncDirectory(directory)
        // 即使密文或 Keystore 已丢失也允许清理，绝不创建替代密钥。
        for (suffix in listOf(".sqlite3", ".sqlite3-journal", ".sqlite3-wal", ".sqlite3-shm")) {
            val file = File(directory, scope + suffix)
            check(!file.exists() || file.delete())
        }
        vault.delete(scope)
        SystemVaultCommitIO.syncDirectory(directory)
    }

    private fun marker(scope: String) = AtomicFile(File(directory, "$scope.closed"))
    private fun ensureDirectory(scope: String) {
        require(scope.matches(Regex("^[0-9a-f]{64}$")))
        check(directory.isDirectory || directory.mkdirs())
        check(directory.canonicalFile.parentFile == parent.canonicalFile)
        check(directory.canonicalFile.name == "hnuhole-business-v1")
        SystemVaultCommitIO.syncDirectory(directory)
        SystemVaultCommitIO.syncDirectory(parent)
    }
    companion object { private val lock = Any() }
}
