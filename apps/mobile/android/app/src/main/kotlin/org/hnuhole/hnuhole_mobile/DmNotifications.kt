package org.hnuhole.hnuhole_mobile

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.UUID

/** Local notifications for durably received messages; no remote push claim. */
class DmNotifications(private val activity: FlutterActivity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "hnuhole/dm_notifications")
    private val manager = activity.getSystemService(NotificationManager::class.java)
    private val prefs = activity.getSharedPreferences("dm-notification-targets", 0)
    private var scope: String? = null
    private var bound = false
    private val id = "private-messages-v1"
    init {
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(id, "私信", NotificationManager.IMPORTANCE_DEFAULT))
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "bind" -> {
                        val next = call.argument<String>("scope")
                        require(next == null || next.matches(Regex("[a-f0-9]{64}")))
                        // NotificationManager outlives this process. First bind
                        // must also withdraw previous private notifications when logged out.
                        if (!bound || scope != next) clear()
                        bound = true
                        scope = next
                        result.success(null)
                    }
                    "show" -> {
                        val owner = call.argument<String>("scope")
                        val identity = call.argument<String>("identityId")!!
                        val conversation = call.argument<String>("conversationId")!!
                        UUID.fromString(identity); UUID.fromString(conversation)
                        if (owner != scope || owner == null || !allowed()) result.success(false)
                        else {
                            val tag = "$owner:$identity:$conversation"
                            val nonce = UUID.randomUUID().toString()
                            // Only a minted, app-private nonce can become a click target.
                            prefs.edit().putString(nonce, JSONObject().put("scope", owner)
                                .put("identityId", identity).put("conversationId", conversation).toString()).apply()
                            val intent = Intent(activity, MainActivity::class.java)
                                .setAction("org.hnuhole.DM_NOTIFICATION")
                                .setData(Uri.parse("hnuhole-private://notification/$nonce"))
                                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                            val pending = PendingIntent.getActivity(activity, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
                            val preview = call.argument<Boolean>("preview") == true
                            val title = if (preview) call.argument<String>("sender")!!.take(80) else "HnuHole"
                            val text = if (preview) call.argument<String>("text")!!.lineSequence().first().take(160) else "你有一条新私信"
                            val publicVersion = builder().setSmallIcon(R.drawable.ic_dm_notification)
                                .setContentTitle("HnuHole").setContentText("你有一条新私信").build()
                            manager.notify(tag, 1, builder()
                                .setSmallIcon(R.drawable.ic_dm_notification).setContentTitle(title).setContentText(text)
                                .setVisibility(Notification.VISIBILITY_PRIVATE).setPublicVersion(publicVersion)
                                .setContentIntent(pending).setAutoCancel(true).setOnlyAlertOnce(true).build())
                            // Bound click metadata; it contains no message text, names or tokens.
                            if (prefs.all.size > 256) prefs.all.keys.take(prefs.all.size - 256).forEach { prefs.edit().remove(it).apply() }
                            result.success(true)
                        }
                    }
                    "takeTap" -> result.success(takeTap(activity.intent))
                    "permission" -> result.success(allowed())
                    "requestPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33 && !allowed()) activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 603)
                        result.success(allowed())
                    }
                    "retain" -> {
                        val owner = call.argument<String>("scope")
                        val targets = call.argument<List<String>>("targets")!!.toSet()
                        if (owner == scope && owner != null) manager.activeNotifications
                            .filter { it.tag?.startsWith("$owner:") == true && it.tag !in targets }
                            .forEach { manager.cancel(it.tag, it.id) }
                        result.success(null)
                    }
                    "clear" -> { clear(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) { result.error("DM_NOTIFICATION_FAILED", "Notification unavailable", null) }
        }
    }
    @Suppress("DEPRECATION")
    private fun builder() = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(activity, id) else Notification.Builder(activity)
    private fun allowed() = manager.areNotificationsEnabled() &&
        (Build.VERSION.SDK_INT < 33 || activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
    private fun clear() {
        // Only this channel's notifications, not other app notifications.
        manager.activeNotifications.filter { if (Build.VERSION.SDK_INT >= 26) it.notification.channelId == id else it.tag?.matches(Regex("[a-f0-9]{64}:[a-f0-9-]{36}:[a-f0-9-]{36}")) == true }.forEach { manager.cancel(it.tag, it.id) }
        prefs.edit().clear().apply()
    }
    private fun takeTap(intent: Intent?): Map<String, String>? {
        if (intent?.action != "org.hnuhole.DM_NOTIFICATION") return null
        val uri = intent.data ?: return null
        if (uri.scheme != "hnuhole-private" || uri.host != "notification") return null
        val nonce = uri.lastPathSegment ?: return null
        val raw = prefs.getString(nonce, null) ?: return null
        prefs.edit().remove(nonce).apply()
        intent.data = null
        val value = JSONObject(raw)
        return listOf("scope", "identityId", "conversationId").associateWith { value.getString(it) }
    }
    fun onIntent(intent: Intent) { takeTap(intent)?.let { channel.invokeMethod("tap", it) } }
    fun dispose() { channel.setMethodCallHandler(null) }
}
