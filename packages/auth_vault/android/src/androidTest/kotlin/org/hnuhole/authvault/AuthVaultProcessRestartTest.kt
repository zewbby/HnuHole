package org.hnuhole.authvault

import android.util.AtomicFile
import android.os.Process
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.io.FileOutputStream
import java.security.KeyStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in two-instrumentation-run probe. Invoke with vault_restart_phase=write,
 * let instrumentation finish, force-stop the test target package, then invoke
 * with vault_restart_phase=read and the same vault_restart_namespace. Unlike
 * constructing another object, this crosses an actual Android process exit.
 * kill-before-replace/kill-after-sync deliberately kill this test process; a
 * subsequent read-before/read-after run must verify the old/new whole state.
 * These are app-process interruption probes, not power-loss durability claims. */
@RunWith(AndroidJUnit4::class)
class AuthVaultProcessRestartTest {
    @Test fun acknowledgedStateSurvivesActualProcessRestart() {
        val arguments = InstrumentationRegistry.getArguments()
        val phase = arguments.getString("vault_restart_phase")
        assumeTrue("Only runs with an explicit external process-restart phase", phase != null)
        val namespace = arguments.getString("vault_restart_namespace") ?: throw IllegalArgumentException()
        require(namespace.matches(Regex("^native\\.restart\\.[A-Za-z0-9_.-]{1,80}$")))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val vault = AndroidAuthVault(context)
        val state = "{\"phase\":\"revocation_pending\",\"test\":true}"
        val record = AtomicFile(File(context.noBackupFilesDir, "$namespace.auth"))
        val keys = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        fun prepare() {
            record.delete()
            keys.deleteEntry("hnuhole.auth.$namespace")
        }
        fun stopProcess(): Nothing {
            Process.killProcess(Process.myPid())
            // If the platform unexpectedly returns, leave a hard failure and
            // bypass Exception rollback instead of reporting a successful run.
            throw AssertionError("Test process kill unexpectedly returned")
        }
        if (phase == "read-fresh-after-reinstall") {
            assertFalse(record.baseFile.exists())
            assertFalse(keys.containsAlias("hnuhole.auth.$namespace"))
            assertNull(vault.read(namespace))
        } else if (phase == "read-restored-without-device-key") {
            assertTrue(record.baseFile.exists())
            assertFalse(keys.containsAlias("hnuhole.auth.$namespace"))
            val original = record.baseFile.readBytes()
            fun rejected(action: () -> Unit) {
                try { action(); fail("Copied ciphertext cannot grant authority without its device key") }
                catch (_: Exception) { /* Expected platform crypto rejection. */ }
            }
            try {
                rejected { vault.read(namespace) }
                rejected { vault.write(namespace, "must not overwrite unknown state") }
                assertTrue(original.contentEquals(record.baseFile.readBytes()))
                assertFalse(keys.containsAlias("hnuhole.auth.$namespace"))
            } finally { record.delete() }
        } else if (phase == "write") {
            prepare()
            vault.write(namespace, state)
            assertTrue(record.baseFile.exists())
        } else if (phase == "kill-before-replace") {
            prepare()
            vault.write(namespace, "acknowledged old marker")
            val stop = object : VaultCommitIO by SystemVaultCommitIO {
                override fun finishWrite(record: AtomicFile, stream: FileOutputStream) { stopProcess() }
            }
            AndroidAuthVault(context, stop).write(namespace, state)
            throw AssertionError("Interruption did not stop the write")
        } else if (phase == "kill-after-sync") {
            prepare()
            vault.write(namespace, "acknowledged old marker")
            val stop = object : VaultCommitIO by SystemVaultCommitIO {
                override fun syncDirectory(directory: File) {
                    SystemVaultCommitIO.syncDirectory(directory)
                    stopProcess()
                }
            }
            AndroidAuthVault(context, stop).write(namespace, state)
            throw AssertionError("Interruption did not stop the acknowledgement")
        } else {
            require(phase == "read" || phase == "read-before" || phase == "read-after")
            val expected = if (phase == "read-before") "acknowledged old marker" else state
            try { assertEquals(expected, vault.read(namespace)) }
            finally {
                record.delete()
                keys.deleteEntry("hnuhole.auth.$namespace")
            }
        }
    }
}
