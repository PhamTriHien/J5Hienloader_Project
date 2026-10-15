package com.j2hienloader.universal.ui_app

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingPick: MethodChannel.Result? = null
    private var pendingExport: MethodChannel.Result? = null
    private var exportSource: File? = null

    // Cho phép cửa sổ ứng dụng mở rộng tràn viền vào vùng tai thỏ / đục lỗ trên Android 9 (API 28) trở lên
    override fun onCreate(savedInstanceState: Bundle?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        super.onCreate(savedInstanceState)
    }

    // Kênh giao tiếp "j2me/platform": cung cấp thư mục dữ liệu, trình chọn tệp và điều khiển dịch vụ chạy nền
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "j2me/platform").setMethodCallHandler { call, result ->
            when (call.method) {
                "dataDir" -> result.success(filesDir.absolutePath)
                "pickJar" -> pickJar(result)
                "exportFile" -> exportFile(call.argument<String>("path"),
                    call.argument<String>("name"), result)
                "updateBackgroundRunning" -> {
                    val count = call.argument<Int>("count") ?: 0
                    val desc = call.argument<String>("description") ?: ""
                    handleBackgroundRunning(count, desc)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun handleBackgroundRunning(count: Int, description: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIF_PERMISSION)
            }
        }

        val serviceIntent = Intent(this, J2meBackgroundService::class.java).apply {
            if (count > 0) {
                putExtra(J2meBackgroundService.EXTRA_ACTION, J2meBackgroundService.ACTION_UPDATE)
                putExtra(J2meBackgroundService.EXTRA_DESC, description)
            } else {
                putExtra(J2meBackgroundService.EXTRA_ACTION, J2meBackgroundService.ACTION_STOP)
            }
        }

        if (count > 0) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
        } else {
            stopService(serviceIntent)
        }
    }

    private fun pickJar(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.success(null)
            return
        }
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            // .jar / .jad have no reliable MIME type on Android, so accept any file and check the name in Dart
            type = "*/*"
        }
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQUEST_PICK_JAR)
    }

    private fun exportFile(path: String?, name: String?, result: MethodChannel.Result) {
        if (pendingExport != null || path == null || !File(path).isFile) {
            result.error("export_failed", "File missing or export already in progress", null)
            return
        }
        pendingExport = result
        exportSource = File(path)
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, name ?: File(path).name)
        }
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQUEST_EXPORT_FILE)
        } catch (e: Exception) {
            pendingExport = null
            exportSource = null
            result.error("export_failed", e.message, null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_EXPORT_FILE) {
            val result = pendingExport ?: return
            val source = exportSource
            pendingExport = null
            exportSource = null
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null || source == null) {
                result.success(null)
                return
            }
            Thread {
                try {
                    contentResolver.openOutputStream(uri)?.use { output ->
                        source.inputStream().use { it.copyTo(output) }
                    } ?: throw IllegalStateException("Cannot write destination")
                    runOnUiThread { result.success(uri.toString()) }
                } catch (e: Exception) {
                    runOnUiThread { result.error("export_failed", e.message, null) }
                }
            }.start()
            return
        }
        if (requestCode != REQUEST_PICK_JAR) return
        val result = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        // Content URIs are not file paths; copy into the cache so the native installer can open it
        Thread {
            try {
                val path = copyToCache(uri)
                runOnUiThread { result.success(path) }
            } catch (e: Exception) {
                runOnUiThread { result.error("copy_failed", e.message, null) }
            }
        }.start()
    }

    private fun copyToCache(uri: Uri): String {
        var name = "picked.jar"
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst() && !c.isNull(0)) name = c.getString(0)
        }
        name = name.replace(Regex("[\\\\/:*?\"<>|]"), "_")
        val dir = File(cacheDir, "picked").apply { mkdirs() }
        val dst = File(dir, name)
        contentResolver.openInputStream(uri)?.use { input ->
            dst.outputStream().use { input.copyTo(it) }
        } ?: throw IllegalStateException("Cannot open $uri")
        return dst.absolutePath
    }

    companion object {
        private const val REQUEST_PICK_JAR = 0x4A32
        private const val REQUEST_EXPORT_FILE = 0x4A34
        private const val REQUEST_NOTIF_PERMISSION = 0x4A33
    }
}
