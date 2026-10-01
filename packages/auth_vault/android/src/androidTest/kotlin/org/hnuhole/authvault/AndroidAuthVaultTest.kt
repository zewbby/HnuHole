package org.hnuhole.authvault

import android.util.AtomicFile
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.RandomAccessFile
import java.security.KeyStore
import java.util.UUID
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** These tests run on Android. Keys, ciphers, AtomicFile and fsync are real;
 * only chosen filesystem failure boundaries are injected. They do not prove
 * physical power-loss behavior, iOS Keychain behavior or hardware-backed keys. */
@RunWith(AndroidJUnit4::class)
class AndroidAuthVaultTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val namespaces = mutableListOf<String>()
    private fun namespace(): String = "native.test.${UUID.randomUUID()}".also { namespaces.add(it) }
    private fun file(namespace: String) = File(context.noBackupFilesDir, "$namespace.auth")
    private fun keys() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    private fun unavailable(action: () -> Unit) {
        try {
            action()
            fail("Storage must reject the operation instead of acknowledging success")
        } catch (_: Exception) { /* The platform channel maps this to a fixed error. */ }
    }

    @After fun removeOnlyTestRecordsAndKeys() {
        namespaces.forEach {
            AtomicFile(file(it)).delete()
            keys().deleteEntry("hnuhole.auth.$it")
        }
    }

    @Test fun committedCiphertextSurvivesNewVaultInstanceAndStaysOutsideBackup() {
        val namespace = namespace()
        val clear = "{\"logout\":\"private revocation capability\"}"
        AndroidAuthVault(context).write(namespace, clear)

        assertEquals(clear, AndroidAuthVault(context).read(namespace))
        assertEquals(context.noBackupFilesDir.canonicalFile, file(namespace).canonicalFile.parentFile)
        assertFalse(File(context.filesDir, "$namespace.auth").exists())
        assertFalse(String(file(namespace).readBytes(), Charsets.ISO_8859_1).contains(clear))
        assertNull("AndroidKeyStore AES key must not be exportable", keys().getKey("hnuhole.auth.$namespace", null).encoded)
    }

    @Test fun emptyAndMaximumUtf8ValuesRoundTripButOversizeNeverReplacesState() {
        val namespace = namespace()
        val vault = AndroidAuthVault(context)
        vault.write(namespace, "")
        assertEquals("", AndroidAuthVault(context).read(namespace))
        val maximum = "界".repeat(21845) + "a" // 65,536 UTF-8 bytes.
        vault.write(namespace, maximum)
        assertEquals(maximum, AndroidAuthVault(context).read(namespace))
        unavailable { vault.write(namespace, maximum + "b") }
        assertEquals(maximum, AndroidAuthVault(context).read(namespace))
    }

    @Test fun syncedReplacementChangesWholeStateAndUsesFreshCiphertext() {
        val namespace = namespace()
        val vault = AndroidAuthVault(context)
        vault.write(namespace, "old marker")
        val before = file(namespace).readBytes()
        vault.write(namespace, "converted revocation capability")
        assertEquals("converted revocation capability", AndroidAuthVault(context).read(namespace))
        assertFalse(before.contentEquals(file(namespace).readBytes()))
        assertFalse(File(file(namespace).path + ".new").exists())
        assertFalse(File(file(namespace).path + ".bak").exists())
    }

    @Test fun fileSyncFailureDoesNotAcknowledgeOrReplaceCommittedMarker() {
        val namespace = namespace()
        AndroidAuthVault(context).write(namespace, "old marker")
        val failure = object : VaultCommitIO by SystemVaultCommitIO {
            override fun syncFile(stream: FileOutputStream) { throw IOException("controlled disk failure") }
        }
        unavailable { AndroidAuthVault(context, failure).write(namespace, "new capability") }
        assertEquals("old marker", AndroidAuthVault(context).read(namespace))
    }

    @Test fun replacementFailureDoesNotAcknowledgeOrReplaceCommittedMarker() {
        val namespace = namespace()
        AndroidAuthVault(context).write(namespace, "old marker")
        val failure = object : VaultCommitIO by SystemVaultCommitIO {
            override fun finishWrite(record: AtomicFile, stream: FileOutputStream) {
                throw IOException("controlled replacement failure")
            }
        }
        unavailable { AndroidAuthVault(context, failure).write(namespace, "new capability") }
        assertEquals("old marker", AndroidAuthVault(context).read(namespace))
    }

    @Test fun silentAtomicReplacementFailureCannotProduceSuccess() {
        val namespace = namespace()
        AndroidAuthVault(context).write(namespace, "old marker")
        val failure = object : VaultCommitIO by SystemVaultCommitIO {
            override fun finishWrite(record: AtomicFile, stream: FileOutputStream) { stream.close() }
        }
        unavailable { AndroidAuthVault(context, failure).write(namespace, "new capability") }
        assertEquals("old marker", AndroidAuthVault(context).read(namespace))
    }

    @Test fun directorySyncFailureReportsUnknownWhileRestartReadsWholeCommittedState() {
        val namespace = namespace()
        AndroidAuthVault(context).write(namespace, "old marker")
        val failure = object : VaultCommitIO by SystemVaultCommitIO {
            override fun syncDirectory(directory: File) { throw IOException("controlled directory sync failure") }
        }
        unavailable { AndroidAuthVault(context, failure).write(namespace, "new capability") }
        assertEquals("new capability", AndroidAuthVault(context).read(namespace))
    }

    @Test fun lostAcknowledgementAfterAllSyncsRetainsCommittedCapabilityOnRestart() {
        val namespace = namespace()
        AndroidAuthVault(context).write(namespace, "old marker")
        val failure = object : VaultCommitIO by SystemVaultCommitIO {
            override fun syncDirectory(directory: File) {
                SystemVaultCommitIO.syncDirectory(directory)
                throw IOException("controlled lost acknowledgement")
            }
        }
        unavailable { AndroidAuthVault(context, failure).write(namespace, "new capability") }
        assertEquals("new capability", AndroidAuthVault(context).read(namespace))
    }

    @Test fun abandonedWriteBeforeReplacementDoesNotResurrectNewState() {
        val namespace = namespace()
        AndroidAuthVault(context).write(namespace, "old marker")
        val stop = object : VaultCommitIO by SystemVaultCommitIO {
            override fun finishWrite(record: AtomicFile, stream: FileOutputStream) {
                stream.close()
                // A process death has no Exception rollback. The test leaves
                // the real AtomicFile sidecar and reconstructs the native core.
                throw SimulatedAbruptStop()
            }
        }
        try {
            AndroidAuthVault(context, stop).write(namespace, "uncommitted new state")
            fail("Abrupt stop must interrupt the write")
        } catch (_: SimulatedAbruptStop) { }
        assertEquals("old marker", AndroidAuthVault(context).read(namespace))
    }

    @Test fun abandonedFirstWriteCannotBecomeAcknowledgedStateOnRestart() {
        val namespace = namespace()
        val stop = object : VaultCommitIO by SystemVaultCommitIO {
            override fun finishWrite(record: AtomicFile, stream: FileOutputStream) {
                stream.close()
                throw SimulatedAbruptStop()
            }
        }
        try {
            AndroidAuthVault(context, stop).write(namespace, "uncommitted first state")
            fail("Abrupt stop must interrupt the first write")
        } catch (_: SimulatedAbruptStop) { }
        assertNull(AndroidAuthVault(context).read(namespace))
        AndroidAuthVault(context).write(namespace, "acknowledged retry state")
        assertEquals("acknowledged retry state", AndroidAuthVault(context).read(namespace))
    }

    @Test fun ciphertextTamperAndUnsupportedVersionFailClosed() {
        val namespace = namespace()
        val vault = AndroidAuthVault(context)
        vault.write(namespace, "private state")
        val original = file(namespace).readBytes()
        val tampered = original.copyOf().apply { this[lastIndex] = (this[lastIndex].toInt() xor 1).toByte() }
        file(namespace).writeBytes(tampered)
        unavailable { vault.read(namespace) }
        unavailable { vault.write(namespace, "unsafe fresh state") }
        assertArrayEquals(tampered, file(namespace).readBytes())
        val unsupported = original.copyOf().apply { this[0] = 2 }
        file(namespace).writeBytes(unsupported)
        unavailable { vault.read(namespace) }
        unavailable { vault.write(namespace, "unsafe fresh state") }
    }

    @Test fun truncatedAndHugeRecordsFailClosedWithoutResettingKeyOrState() {
        val namespace = namespace()
        val vault = AndroidAuthVault(context)
        vault.write(namespace, "private state")
        file(namespace).writeBytes(byteArrayOf(1, 2))
        unavailable { vault.read(namespace) }
        // Sparse file verifies size rejection without allocating a huge input.
        RandomAccessFile(file(namespace), "rw").use { it.setLength(32L * 1024 * 1024) }
        unavailable { vault.read(namespace) }
        unavailable { vault.write(namespace, "unsafe fresh state") }
        assertTrue(keys().containsAlias("hnuhole.auth.$namespace"))
        assertEquals(32L * 1024 * 1024, file(namespace).length())
    }

    @Test fun missingDeviceKeyCannotDecryptOrOverwriteAnExistingRecord() {
        val namespace = namespace()
        val vault = AndroidAuthVault(context)
        vault.write(namespace, "restored old marker")
        val encrypted = file(namespace).readBytes()
        keys().deleteEntry("hnuhole.auth.$namespace")
        unavailable { vault.read(namespace) }
        unavailable { vault.write(namespace, "unsafe fresh state") }
        assertArrayEquals(encrypted, file(namespace).readBytes())
        assertFalse(keys().containsAlias("hnuhole.auth.$namespace"))
    }

    @Test fun backupSidecarWithoutDeviceKeyCannotBeOverwrittenAsEmptyState() {
        val namespace = namespace()
        AndroidAuthVault(context).write(namespace, "restored old marker")
        val encrypted = file(namespace).readBytes()
        val backup = File(file(namespace).path + ".bak")
        assertTrue(file(namespace).renameTo(backup))
        keys().deleteEntry("hnuhole.auth.$namespace")
        unavailable { AndroidAuthVault(context).write(namespace, "unsafe fresh state") }
        assertArrayEquals(encrypted, AtomicFile(file(namespace)).openRead().use { it.readBytes() })
        assertFalse(keys().containsAlias("hnuhole.auth.$namespace"))
    }

    @Test fun namespacesCannotReadCopiedCiphertextAndKeepIndependentStates() {
        val first = namespace()
        val second = namespace()
        val vault = AndroidAuthVault(context)
        assertNull(vault.read(first))
        vault.write(first, "first private state")
        vault.write(second, "second private state")
        assertEquals("first private state", vault.read(first))
        assertEquals("second private state", vault.read(second))
        file(second).writeBytes(file(first).readBytes())
        unavailable { vault.read(second) }
        assertEquals("first private state", AndroidAuthVault(context).read(first))
    }

    @Test fun invalidNamespaceCannotEscapeNoBackupDirectory() {
        unavailable { AndroidAuthVault(context).write("../escaped", "private state") }
        unavailable { AndroidAuthVault(context).read("../escaped") }
        assertFalse(File(context.noBackupFilesDir.parentFile, "escaped.auth").exists())
    }

    private class SimulatedAbruptStop : Error()
}
