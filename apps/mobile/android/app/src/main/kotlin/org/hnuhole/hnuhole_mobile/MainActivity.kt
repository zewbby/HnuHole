package org.hnuhole.hnuhole_mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterJNI
import android.content.pm.ApplicationInfo
import android.app.KeyguardManager
import android.content.res.Configuration
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Process
import org.json.JSONObject
import java.io.File
import java.net.URI
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val driverHandler = Handler(Looper.getMainLooper())
    private var driverChannel: MethodChannel? = null

    private fun driverEnabled(): Boolean =
        applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0 &&
            intent.getBooleanExtra("hnuhole-device-driver", false)

    private fun acceptanceEnabled(): Boolean = driverEnabled() &&
        intent.getStringExtra("hnuhole-device-phase")?.matches(Regex("ni-[a-z][0-9]{2}(-read)?")) == true

    private fun lifecycleRecord(event: String? = null): JSONObject {
        val file = File(filesDir, "owned-acceptance-lifecycle.json")
        val previous = runCatching { JSONObject(file.readText()) }.getOrNull()
        val value = if (previous != null && previous.optInt("pid") == Process.myPid()) previous else JSONObject().put("pid", Process.myPid())
        value.put("activityId", System.identityHashCode(this))
        value.put("phase", intent.getStringExtra("hnuhole-device-phase"))
        value.put("orientation", resources.configuration.orientation)
        value.put("fontScale", resources.configuration.fontScale.toDouble())
        if (event != null) value.put(event, value.optInt(event) + 1)
        file.writeText(value.toString())
        return value
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!driverEnabled()) return
        if (acceptanceEnabled()) lifecycleRecord("engineAttached")
        driverChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "hnuhole/owned_device_driver").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (!driverEnabled()) { result.notImplemented(); return@setMethodCallHandler }
                when (call.method) {
                    "phase" -> {
                        val phase = intent.getStringExtra("hnuhole-device-phase")
                        if (phase != null && Regex("[a-z][a-z0-9-]{0,39}").matches(phase)) result.success(phase)
                        else result.error("DRIVER_PHASE_REQUIRED", "Explicit bounded test phase required", null)
                    }
                    "variant" -> {
                        val variant = intent.getStringExtra("hnuhole-device-variant")
                        val phase = intent.getStringExtra("hnuhole-device-phase")
                        if (acceptanceEnabled() && phase in setOf("ni-c01", "ni-d01", "ni-d02", "ni-d03", "ni-d04", "ni-d05", "ni-k01", "ni-k02") &&
                            variant in setOf("main", "control", "bad-signature", "missing-package", "source", "restart", "fresh", "no-key", "write-failure", "write-failure-read", "write-unknown", "write-unknown-read")) {
                            result.success(variant)
                        } else result.notImplemented()
                    }
                    "deviceState" -> {
                        val keyguard = getSystemService(KEYGUARD_SERVICE) as KeyguardManager
                        result.success(mapOf("pid" to Process.myPid(),
                            "deviceSecure" to keyguard.isDeviceSecure,
                            "deviceLocked" to keyguard.isDeviceLocked,
                            "keyguardLocked" to keyguard.isKeyguardLocked))
                    }
                    "acceptanceLifecycle" -> {
                        if (!acceptanceEnabled()) result.notImplemented()
                        else {
                            val value = lifecycleRecord()
                            result.success(value.keys().asSequence().associateWith { value.get(it) })
                        }
                    }
                    "acceptanceRecreate" -> {
                        if (!acceptanceEnabled() || intent.getStringExtra("hnuhole-device-phase") != "ni-l02") {
                            result.notImplemented()
                        } else {
                            lifecycleRecord("recreateRequested")
                            intent.putExtra("hnuhole-device-phase", "ni-l02-read")
                            result.success(null)
                            // Normal FlutterActivity teardown destroys the old engine;
                            // do not cache it or change production lifecycle semantics.
                            driverHandler.postDelayed({ recreate() }, 100)
                        }
                    }
                    "stage" -> {
                        val stage = call.arguments as? String
                        if (stage == null || !Regex("[a-z][a-z0-9-]{0,59}").matches(stage)) {
                            result.error("DRIVER_STAGE_INVALID", "Bounded nonsecret stage required", null)
                        } else {
                            // No credentials, text input or OS secrets are accepted here.
                            File(filesDir, "owned-device-driver-stage.json").writeText(
                                JSONObject().put("pid", Process.myPid()).put("stage", stage).toString())
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (acceptanceEnabled()) lifecycleRecord("activityCreated")
        // An opt-in debug driver can discover the authenticated loopback VM
        // without collecting OEM system logs. Never enable this in release.
        if (!driverEnabled()) return
        val destination = File(filesDir, "owned-device-driver-vm.json")
        destination.delete()
        var remaining = 100
        val discover = object : Runnable {
            override fun run() {
                val value = FlutterJNI.getVMServiceUri()
                val address = value?.let { runCatching { URI(it) }.getOrNull() }
                if (address != null && address.scheme == "http" &&
                    address.host == "127.0.0.1" && address.port in 1024..65535 &&
                    address.userInfo == null && address.query == null && address.fragment == null) {
                    // filesDir is app-private; keep the VM auth code out of
                    // logcat, external storage and acceptance reports.
                    destination.writeText(JSONObject().put("pid", Process.myPid())
                        .put("uri", value).toString())
                } else if (--remaining > 0) {
                    driverHandler.postDelayed(this, 100)
                }
            }
        }
        driverHandler.post(discover)
    }

    override fun onDestroy() {
        if (acceptanceEnabled()) lifecycleRecord("activityDestroyed")
        driverHandler.removeCallbacksAndMessages(null)
        driverChannel?.setMethodCallHandler(null)
        driverChannel = null
        super.onDestroy()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (acceptanceEnabled()) lifecycleRecord("configurationChanged")
    }

    override fun onResume() {
        super.onResume()
        if (acceptanceEnabled()) lifecycleRecord("resumed")
    }

    override fun onPause() {
        if (acceptanceEnabled()) lifecycleRecord("paused")
        super.onPause()
    }
}
