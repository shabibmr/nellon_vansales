package com.nellon.vansales.van_sales

import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val INSTALLER_CHANNEL = "com.algoray.nellon/app_installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALLER_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "installApk") {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        try {
                            val apkFile = File(filePath)
                            if (!apkFile.exists()) {
                                result.error("FILE_NOT_FOUND", "APK file not found: $filePath", null)
                                return@setMethodCallHandler
                            }

                            val contentUri: Uri = FileProvider.getUriForFile(
                                context,
                                "${context.packageName}.fileprovider",
                                apkFile
                            )

                            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(contentUri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
                            }

                            val resInfoList = context.packageManager.queryIntentActivities(
                                installIntent,
                                android.content.pm.PackageManager.MATCH_DEFAULT_ONLY
                            )
                            for (resolveInfo in resInfoList) {
                                context.grantUriPermission(
                                    resolveInfo.activityInfo.packageName,
                                    contentUri,
                                    Intent.FLAG_GRANT_READ_URI_PERMISSION
                                )
                            }

                            context.startActivity(installIntent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", e.localizedMessage, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "filePath is required", null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
