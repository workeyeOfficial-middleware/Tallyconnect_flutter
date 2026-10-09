package com.tallyconnect.tallyconnect_ui

import android.content.ComponentName
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tallyconnect/app_icon")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "current" -> result.success(currentIcon(call.argument<List<String>>("all") ?: emptyList()))
                        "set" -> result.success(
                            setIcon(
                                call.argument<String>("alias") ?: "",
                                call.argument<List<String>>("all") ?: emptyList()
                            )
                        )
                        "pinSupported" -> result.success(pinSupported())
                        "pin" -> result.success(
                            pinShortcut(
                                call.argument<ByteArray>("png"),
                                call.argument<String>("label") ?: "TallyConnect",
                                call.argument<Boolean>("updateOnly") ?: false
                            )
                        )
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("ICON", e.message, null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tallyconnect/downloads")
            .setMethodCallHandler { call, result ->
                if (call.method != "save") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val name = call.argument<String>("name") ?: "TallyConnect.pdf"
                val mime = call.argument<String>("mime") ?: "application/pdf"
                val bytes = call.argument<ByteArray>("bytes")
                if (bytes == null) {
                    result.error("ARG", "missing bytes", null)
                    return@setMethodCallHandler
                }
                try {
                    result.success(saveToDownloads(name, mime, bytes))
                } catch (e: Exception) {
                    result.error("IO", e.message, null)
                }
            }
    }

    // ------------------------------------------------ theme-matched app icon

    private fun alias(name: String) = ComponentName(this, "$packageName.$name")

    /** The launcher alias that is enabled now (null if none could be read). */
    private fun currentIcon(all: List<String>): String? {
        val pm = packageManager
        for (name in all) {
            val state = pm.getComponentEnabledSetting(alias(name))
            if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) return name
        }
        // Nothing set at runtime yet: the manifest default (IconBrand).
        return all.firstOrNull { name ->
            pm.getComponentEnabledSetting(alias(name)) ==
                PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && name == "IconBrand"
        }
    }

    /**
     * Shows [target] in the launcher and hides the other aliases. The new
     * one is enabled first, so the app is never left without a launcher
     * entry. DONT_KILL_APP keeps the running app alive.
     */
    private fun setIcon(target: String, all: List<String>): Boolean {
        if (target.isEmpty() || !all.contains(target)) return false
        val pm = packageManager
        pm.setComponentEnabledSetting(
            alias(target),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP
        )
        for (name in all) {
            if (name == target) continue
            pm.setComponentEnabledSetting(
                alias(name),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP
            )
        }
        return true
    }

    private fun pinSupported(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val sm = getSystemService(ShortcutManager::class.java) ?: return false
        return sm.isRequestPinShortcutSupported
    }

    /**
     * Home-screen shortcut with the exact theme colours (Android 8+). Updates
     * it when already pinned; otherwise asks the launcher to pin it (the
     * user confirms). Returns "updated", "requested", "none" (updateOnly and
     * not pinned) or "unsupported".
     */
    private fun pinShortcut(png: ByteArray?, label: String, updateOnly: Boolean): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || png == null) return "unsupported"
        val sm = getSystemService(ShortcutManager::class.java) ?: return "unsupported"
        val bmp = BitmapFactory.decodeByteArray(png, 0, png.size) ?: return "unsupported"
        val intent = Intent(Intent.ACTION_MAIN).apply {
            component = ComponentName(this@MainActivity, MainActivity::class.java)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val info = ShortcutInfo.Builder(this, "tc_theme_icon")
            .setShortLabel(label)
            .setIcon(Icon.createWithAdaptiveBitmap(bmp))
            .setIntent(intent)
            .build()
        val pinned = sm.pinnedShortcuts.any { it.id == "tc_theme_icon" }
        if (pinned) {
            sm.updateShortcuts(listOf(info))
            return "updated"
        }
        if (updateOnly) return "none"
        if (!sm.isRequestPinShortcutSupported) return "unsupported"
        return if (sm.requestPinShortcut(info, null)) "requested" else "unsupported"
    }

    /** Saves into the public Downloads folder; returns a display path. */
    private fun saveToDownloads(name: String, mime: String, bytes: ByteArray): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mime)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Could not create download")
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return "Download/$name"
        }
        return try {
            @Suppress("DEPRECATION")
            val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            dir.mkdirs()
            val file = File(dir, name)
            file.writeBytes(bytes)
            file.absolutePath
        } catch (e: Exception) {
            // No storage permission on API 24–28: use the app's own Downloads folder.
            val dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: filesDir
            val file = File(dir, name)
            file.writeBytes(bytes)
            file.absolutePath
        }
    }
}
