package com.tallyconnect.tallyconnect_ui

import android.content.ContentValues
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
