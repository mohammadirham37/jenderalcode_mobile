package com.jenderalcode.mobile

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * In-app updater bridge ("jenderalcode/updates"). Dart downloads and verifies
 * the APK; this side only checks the install permission and hands the file
 * to PackageInstaller. Results come back as "installStatus" calls.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var receiverRegistered = false

    private val statusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
            val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
            if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
                // The system (and on HyperOS, MIUI's own screen) asks the user.
                @Suppress("DEPRECATION")
                val confirm: Intent? = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                if (confirm != null) {
                    confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    try {
                        startActivity(confirm)
                        report("pending_user_action", null)
                    } catch (e: Exception) {
                        report("failure", e.message)
                    }
                }
                return
            }
            val name = when (status) {
                PackageInstaller.STATUS_SUCCESS -> "success"
                PackageInstaller.STATUS_FAILURE_ABORTED -> "cancelled"
                PackageInstaller.STATUS_FAILURE_BLOCKED -> "blocked"
                PackageInstaller.STATUS_FAILURE_CONFLICT -> "conflict"
                PackageInstaller.STATUS_FAILURE_INCOMPATIBLE -> "incompatible"
                PackageInstaller.STATUS_FAILURE_INVALID -> "invalid"
                PackageInstaller.STATUS_FAILURE_STORAGE -> "storage"
                else -> "failure"
            }
            report(name, message)
        }
    }

    private fun report(status: String, message: String?) {
        runOnUiThread {
            channel?.invokeMethod("installStatus", mapOf("status" to status, "message" to message))
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "updatesDir" -> {
                    val dir = File(cacheDir, "updates")
                    dir.mkdirs()
                    result.success(dir.absolutePath)
                }
                "canRequestPackageInstalls" ->
                    // Before Android 8 the global "Unknown sources" switch applies instead.
                    result.success(Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls())
                "openInstallSettings" -> {
                    try {
                        startActivity(
                            if (Build.VERSION.SDK_INT >= 26) {
                                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                            } else {
                                Intent(Settings.ACTION_SECURITY_SETTINGS)
                            }
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("bad_args", "path is required", null)
                        return@setMethodCallHandler
                    }
                    // Only the verified download in cacheDir/updates may be installed.
                    val updatesDir = File(cacheDir, "updates").canonicalFile
                    val apkFile = File(path).canonicalFile
                    if (apkFile.parentFile != updatesDir || !apkFile.name.endsWith(".apk")) {
                        result.error("bad_args", "only downloaded updates can be installed", null)
                        return@setMethodCallHandler
                    }
                    try {
                        installWithSession(File(path))
                        result.success("session")
                    } catch (e: Exception) {
                        // Fall back to the system installer screen.
                        try {
                            installWithView(File(path))
                            result.success("view")
                        } catch (e2: Exception) {
                            result.error("install_failed", e2.message ?: e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun ensureReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter(ACTION_INSTALL_STATUS)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(statusReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(statusReceiver, filter)
        }
        receiverRegistered = true
    }

    private fun installWithSession(apk: File) {
        require(apk.isFile) { "APK not found" }
        ensureReceiver()
        val installer = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setAppPackageName(packageName)
        if (Build.VERSION.SDK_INT >= 31) {
            params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }
        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
            apk.inputStream().use { input ->
                session.openWrite("base.apk", 0, apk.length()).use { out ->
                    input.copyTo(out)
                    session.fsync(out)
                }
            }
            val intent = Intent(ACTION_INSTALL_STATUS).setPackage(packageName)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
            val pending = PendingIntent.getBroadcast(this, sessionId, intent, flags)
            session.commit(pending.intentSender)
        }
    }

    private fun installWithView(apk: File) {
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", apk)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    override fun onDestroy() {
        if (receiverRegistered) {
            try {
                unregisterReceiver(statusReceiver)
            } catch (_: Exception) {
            }
            receiverRegistered = false
        }
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "jenderalcode/updates"
        private const val ACTION_INSTALL_STATUS = "com.jenderalcode.mobile.INSTALL_STATUS"
    }
}
