package org.hnuhole.authvault

import android.util.AtomicFile
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import java.util.UUID
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** 源码覆盖原生路径／KeyStore／闭号边界；T3 未运行设备，不计设备 PASS。 */
@RunWith(AndroidJUnit4::class)
class AndroidBusinessStorageTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val storage = AndroidBusinessStorage(context)
    private val scopes = mutableListOf<String>()
    private fun scope(): String = MessageDigest.getInstance("SHA-256")
        .digest(UUID.randomUUID().toString().toByteArray())
        .joinToString("") { "%02x".format(it) }.also { scopes.add(it) }
    private fun vault() = AndroidAuthVault(context, directory = storage.directory,
        aliasPrefix = "hnuhole.business.v1.")
    private fun keys() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    private fun unavailable(action: () -> Unit) {
        try { action(); fail("Business storage must reject this operation") }
        catch (_: Exception) { /* 不打印命名空间、密文或原生异常。 */ }
    }

    @After fun removeOnlyOwnedRecords() {
        for (scope in scopes) {
            for (suffix in listOf(".auth", ".closed")) AtomicFile(File(storage.directory, scope + suffix)).delete()
            for (suffix in listOf(".sqlite3", ".sqlite3-journal", ".sqlite3-wal", ".sqlite3-shm")) {
                File(storage.directory, scope + suffix).delete()
            }
            AtomicFile(File(context.noBackupFilesDir, "$scope.auth")).delete()
            keys().deleteEntry("hnuhole.business.v1.$scope")
            keys().deleteEntry("hnuhole.auth.$scope")
        }
    }

    @Test fun databaseAndKeyAreOutsideBackupAndDoNotReplaceAuthenticationNamespace() {
        val scope = scope()
        val path = storage.prepare(scope)
        assertEquals(context.noBackupFilesDir.canonicalFile, path.canonicalFile.parentFile?.parentFile)
        AndroidAuthVault(context).write(scope, "authentication state")
        vault().writeOnce(scope, "business key")
        assertEquals("business key", vault().read(scope))
        assertEquals("authentication state", AndroidAuthVault(context).read(scope))
        assertNull(keys().getKey("hnuhole.business.v1.$scope", null).encoded)
        assertFalse(String(File(storage.directory, "$scope.auth").readBytes()).contains("business key"))
    }

    @Test fun existingBusinessKeyCannotBeSilentlyRotatedAndSameValueRetryIsSafe() {
        val scope = scope()
        storage.prepare(scope)
        vault().writeOnce(scope, "first key")
        vault().writeOnce(scope, "first key")
        unavailable { vault().writeOnce(scope, "second key") }
        assertEquals("first key", vault().read(scope))
    }

    @Test fun closedMarkerSurvivesNewInstanceAndScopePurgeLeavesOtherAccountAndAuthUntouched() {
        val closed = scope()
        val active = scope()
        storage.prepare(closed).writeText("encrypted database fixture")
        storage.prepare(active).writeText("other account fixture")
        vault().writeOnce(closed, "closed key")
        vault().writeOnce(active, "active key")
        AndroidAuthVault(context).write(closed, "authentication state")
        File(storage.directory, "$closed.sqlite3-journal").writeText("journal fixture")
        storage.purgeClosedAccount(closed, vault())
        AndroidBusinessStorage(context).purgeClosedAccount(closed, vault())
        unavailable { AndroidBusinessStorage(context).prepare(closed) }
        assertFalse(File(storage.directory, "$closed.sqlite3").exists())
        assertFalse(File(storage.directory, "$closed.sqlite3-journal").exists())
        assertFalse(keys().containsAlias("hnuhole.business.v1.$closed"))
        assertEquals("active key", vault().read(active))
        assertEquals("other account fixture", storage.prepare(active).readText())
        assertEquals("authentication state", AndroidAuthVault(context).read(closed))
    }

    @Test fun lostDeviceKeyStillAllowsAuthoritativeScopePurgeWithoutRegeneration() {
        val scope = scope()
        storage.prepare(scope).writeText("encrypted fixture")
        vault().writeOnce(scope, "lost key")
        keys().deleteEntry("hnuhole.business.v1.$scope")
        unavailable { vault().read(scope) }
        storage.purgeClosedAccount(scope, vault())
        assertFalse(File(storage.directory, "$scope.auth").exists())
        assertFalse(keys().containsAlias("hnuhole.business.v1.$scope"))
        unavailable { storage.prepare(scope) }
    }

    @Test fun invalidScopeDoesNotEscapeTheBusinessDirectory() {
        unavailable { storage.prepare("../authentication") }
        unavailable { storage.purgeClosedAccount("../../", vault()) }
    }
}
