package com.tack.tack

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.tack.app/documents")
            .setMethodCallHandler { call, result ->
                if (call.method != "open") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val path = call.argument<String>("path") ?: throw IllegalArgumentException()
                    val mime = call.argument<String>("mimeType") ?: throw IllegalArgumentException()
                    val file = File(path).canonicalFile
                    val root = File(cacheDir, "tack_documents").canonicalFile.path + File.separator
                    if (!file.path.startsWith(root) || !file.isFile) throw IllegalArgumentException()
                    val uri = FileProvider.getUriForFile(this, "$packageName.documents", file)
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, mime)
                        clipData = ClipData.newRawUri("Document", uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    if (intent.resolveActivity(packageManager) == null) {
                        result.error("no_app", "No document reader is installed.", null)
                    } else {
                        startActivity(Intent.createChooser(intent, "Open with"))
                        result.success(null)
                    }
                } catch (_: ActivityNotFoundException) {
                    result.error("no_app", "No document reader is installed.", null)
                } catch (_: Exception) {
                    result.error("open_failed", "The document could not be opened.", null)
                }
            }
    }
}
