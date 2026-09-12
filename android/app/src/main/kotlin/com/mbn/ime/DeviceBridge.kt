package com.mbn.ime

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.provider.DocumentsContract
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class DeviceBridge(private val activity: FlutterActivity) {
    private var installPermissionResult: MethodChannel.Result? = null
    private val installPermissionRequestCode = 4119

    fun onActivityResult(requestCode: Int) {
        if (requestCode != installPermissionRequestCode) return
        val pending = installPermissionResult
        installPermissionResult = null
        pending?.success(Build.VERSION.SDK_INT < 26 || activity.packageManager.canRequestPackageInstalls())
    }

    @Suppress("DEPRECATION")
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "requestInstallPermission" -> {
                    if (Build.VERSION.SDK_INT < 26 || activity.packageManager.canRequestPackageInstalls()) {
                        result.success(true)
                    } else if (installPermissionResult != null) {
                        result.success(false)
                    } else {
                        installPermissionResult = result
                        try {
                            activity.startActivityForResult(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:${activity.packageName}")), installPermissionRequestCode)
                        } catch (_: Exception) {
                            installPermissionResult = null
                            result.success(false)
                        }
                    }
                }
                "abi" -> result.success(when {
                    Build.SUPPORTED_ABIS.contains("arm64-v8a") -> "arm64-v8a"
                    Build.SUPPORTED_ABIS.contains("armeabi-v7a") -> "armeabi-v7a"
                    else -> "unsupported"
                })
                "wirelessDisplay" -> {
                    val intents = listOf(Intent(Settings.ACTION_CAST_SETTINGS), Intent(Settings.ACTION_DISPLAY_SETTINGS))
                    var opened = false
                    for (intent in intents) {
                        try { activity.startActivity(intent); opened = true; break }
                        catch (_: android.content.ActivityNotFoundException) { }
                    }
                    result.success(opened)
                }
                "storageGranted" -> result.success(storageGranted())
                "requestStorage" -> {
                    if (Build.VERSION.SDK_INT >= 30) {
                        activity.startActivity(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                            Uri.parse("package:${activity.packageName}")))
                    } else {
                        ActivityCompat.requestPermissions(activity,
                            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 4110)
                    }
                    result.success(null)
                }
                "downloadsDirectory" -> result.success(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).absolutePath)
                "openDownloads" -> {
                    val folder = DocumentsContract.buildDocumentUri(
                        "com.android.externalstorage.documents", "primary:Download/MBNime")
                    val intents = listOf(
                        Intent(Intent.ACTION_VIEW).setDataAndType(folder, DocumentsContract.Document.MIME_TYPE_DIR)
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                        Intent(android.app.DownloadManager.ACTION_VIEW_DOWNLOADS))
                    var opened = false
                    for (intent in intents) {
                        try { activity.startActivity(intent); opened = true; break }
                        catch (_: android.content.ActivityNotFoundException) { }
                    }
                    result.success(opened)
                }
                "installApk" -> result.success(installApk(call.argument<String>("path") ?: ""))
                "playLocalVideo" -> {
                    val file = File(call.argument<String>("path") ?: "").canonicalFile
                    val root = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "MBNime").canonicalFile
                    require(file.isFile && file.path.startsWith(root.path + File.separator))
                    val target = when (call.argument<String>("player")) {
                        "vlc" -> "org.videolan.vlc"
                        "mxPlayer" -> "com.mxtech.videoplayer.ad"
                        "mxPlayerPro" -> "com.mxtech.videoplayer.pro"
                        else -> throw IllegalArgumentException("Unknown player")
                    }
                    val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", file)
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "video/*")
                        setPackage(target)
                        clipData = android.content.ClipData.newRawUri("video", uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        putExtra("title", call.argument<String>("title"))
                    }
                    try { activity.startActivity(intent); result.success("launched") }
                    catch (_: android.content.ActivityNotFoundException) { result.success("missing") }
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) { result.error("DEVICE", e.javaClass.simpleName, null) }
    }

    private fun storageGranted(): Boolean = if (Build.VERSION.SDK_INT >= 30)
        Environment.isExternalStorageManager()
    else ContextCompat.checkSelfPermission(activity, Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED

    @Suppress("DEPRECATION")
    private fun installApk(path: String): String {
        if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) return "permission"
        val file = File(path).canonicalFile
        val updates = File(activity.filesDir, "updates").canonicalFile
        if (!file.path.startsWith(updates.path + File.separator) || !file.isFile || file.extension != "apk") return "invalid"
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val pm = activity.packageManager
        val archive = pm.getPackageArchiveInfo(file.path, flags) ?: return "invalid"
        val current = pm.getPackageInfo(activity.packageName, flags)
        if (archive.packageName != activity.packageName) return "invalid"
        val newCode = if (Build.VERSION.SDK_INT >= 28) archive.longVersionCode else archive.versionCode.toLong()
        val oldCode = if (Build.VERSION.SDK_INT >= 28) current.longVersionCode else current.versionCode.toLong()
        if (newCode <= oldCode) return "invalid"
        val incoming = if (Build.VERSION.SDK_INT >= 28) archive.signingInfo?.apkContentsSigners else archive.signatures
        val installed = if (Build.VERSION.SDK_INT >= 28) current.signingInfo?.apkContentsSigners else current.signatures
        if (incoming.isNullOrEmpty() || installed.isNullOrEmpty() || incoming.toSet() != installed.toSet()) return "signature"
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", file)
        activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        })
        return "launched"
    }
}
