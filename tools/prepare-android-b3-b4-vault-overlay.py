#!/usr/bin/env python3
"""Build-only isolated App IO fault seam; production crypto/AtomicFile unchanged."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT=Path('/var/tmp/hnuhole-android-live-faults-20261005')
PLUGIN=Path('packages/auth_vault/android/src/main/kotlin/org/hnuhole/authvault/AuthVaultPlugin.kt')
SOURCE=Path('/mnt/c/Users/Administrator/Documents/ChatGPT/HnuHole')
SEAM='''
// Generated only for the owned, debuggable isolated acceptance package.
internal class OwnedB3B4CommitIO(private val context: android.content.Context) : VaultCommitIO {
    private var armed: String? = null
    fun arm(namespace: String) {
        armed = null
        if (context.packageName != "org.hnuhole.hnuhole_mobile.acceptance" ||
            context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE == 0 ||
            !namespace.startsWith("hnuhole.auth.v1.")) return
        val file = java.io.File(context.filesDir, "owned-b3b4-vault-fault.json")
        if (!file.exists()) return
        val value = org.json.JSONObject(file.readText())
        require(value.getString("owner") == "HNUHOLE_B3B4_NATIVE_IO_V1")
        require(value.getInt("pid") == android.os.Process.myPid())
        val mode = value.getString("mode")
        require(mode in setOf("write-failure", "write-unknown"))
        check(file.delete())
        armed = mode
    }
    private fun fail(mode: String) {
        armed = null
        val result = org.json.JSONObject().put("pid", android.os.Process.myPid())
            .put("owner", "HNUHOLE_B3B4_NATIVE_IO_V1").put("mode", mode).put("fired", true)
        java.io.File(context.filesDir, "owned-b3b4-vault-fault-result.json").writeText(result.toString())
        throw java.io.IOException("Owned IO acceptance fault")
    }
    override fun syncFile(stream: java.io.FileOutputStream) {
        if (armed == "write-failure") fail("write-failure")
        SystemVaultCommitIO.syncFile(stream)
    }
    override fun finishWrite(record: android.util.AtomicFile, stream: java.io.FileOutputStream) {
        SystemVaultCommitIO.finishWrite(record, stream)
    }
    override fun syncDirectory(directory: java.io.File) {
        SystemVaultCommitIO.syncDirectory(directory)
        if (armed == "write-unknown") fail("write-unknown")
    }
}
'''


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--restore',action='store_true');args=p.parse_args()
    assert ROOT.resolve()==ROOT and (ROOT/'OWNER').read_text().strip()=='HNUHOLE_ANDROID_LIVE_DEV_V1'
    original=(SOURCE/PLUGIN).read_text();target=ROOT/'repo'/PLUGIN
    if args.restore:target.write_text(original);print('RESTORED: original plugin factory in owned build mirror');return
    assert target.read_text()==original
    revised=original.replace('private lateinit var vault: AndroidAuthVault',
        'private lateinit var vault: AndroidAuthVault\n    private lateinit var ownedIO: OwnedB3B4CommitIO')
    revised=revised.replace('vault = AndroidAuthVault(binding.applicationContext)',
        'ownedIO = OwnedB3B4CommitIO(binding.applicationContext)\n        vault = AndroidAuthVault(binding.applicationContext, ownedIO)')
    revised=revised.replace('vault.write(namespace, text)','ownedIO.arm(namespace)\n                    vault.write(namespace, text)')
    assert revised!=original
    target.write_text(revised+SEAM)
    evidence=dict(result='PREPARED_NOT_RUN',productionSourceUnchanged=True,cryptoAndAtomicFileSourceUnchanged=True,
        isolatedApplicationId='org.hnuhole.hnuhole_mobile.acceptance',faults=['write-failure','write-unknown'],
        originalPluginSha256=hashlib.sha256(original.encode()).hexdigest(),
        isolatedOverlaySha256=hashlib.sha256(target.read_bytes()).hexdigest(),
        boundarySourceSha256=hashlib.sha256((SOURCE/PLUGIN.parent/'AndroidAuthVault.kt').read_bytes()).hexdigest())
    (ROOT/'matrix/b3b4-vault-overlay.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print('PREPARED: isolated native IO seam; actual device acceptance NOT_RUN')


if __name__=='__main__':main()
