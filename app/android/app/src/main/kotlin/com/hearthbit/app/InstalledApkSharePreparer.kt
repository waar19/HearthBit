package com.hearthbit.app

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

internal class InstalledApkSharePreparer(
    private val context: Context,
) {
    fun prepare(): Map<String, Any> {
        val packageInfo = packageInfo()
        val applicationInfo = packageInfo.applicationInfo
            ?: error("Installed application information is unavailable")
        val sourcePath = applicationInfo.sourceDir
        val splitPaths = applicationInfo.splitSourceDirs
        return when (ApkInstallationPolicy.classify(sourcePath, splitPaths)) {
            ApkInstallationKind.SPLIT -> mapOf(
                "status" to "splitInstallation",
                "splitCount" to (splitPaths?.size ?: 0),
            )
            ApkInstallationKind.INVALID -> error("Installed APK path is unavailable")
            ApkInstallationKind.UNIVERSAL -> copyUniversalApk(
                sourcePath = requireNotNull(sourcePath),
                version = packageInfo.versionName.orEmpty().ifBlank { "unknown" },
            )
        }
    }

    private fun copyUniversalApk(sourcePath: String, version: String): Map<String, Any> {
        val source = File(sourcePath)
        require(source.isFile && source.canRead()) {
            "Installed APK is not readable"
        }
        val shareDirectory = File(context.cacheDir, "apk_share").apply {
            mkdirs()
        }
        val canonicalCache = context.cacheDir.canonicalFile
        val canonicalShareDirectory = shareDirectory.canonicalFile
        require(canonicalShareDirectory.path.startsWith(canonicalCache.path + File.separator)) {
            "Unsafe APK cache destination"
        }

        val safeVersion = version.replace(Regex("[^A-Za-z0-9._-]"), "_")
        val fileName = "HearthBit-$safeVersion.apk"
        val destination = File(canonicalShareDirectory, fileName)
        canonicalShareDirectory.listFiles()
            ?.filter { it.name.startsWith("HearthBit-") && it.extension == "apk" && it != destination }
            ?.forEach(File::delete)

        val temporary = File(canonicalShareDirectory, "$fileName.tmp")
        temporary.delete()
        try {
            FileInputStream(source).use { input ->
                FileOutputStream(temporary).use { output ->
                    input.copyTo(output)
                    output.fd.sync()
                }
            }
            require(temporary.length() == source.length() && temporary.length() > 0) {
                "APK cache copy is incomplete"
            }
            destination.delete()
            if (!temporary.renameTo(destination)) {
                FileInputStream(temporary).use { input ->
                    FileOutputStream(destination).use { output ->
                        input.copyTo(output)
                        output.fd.sync()
                    }
                }
                temporary.delete()
            }
            require(destination.isFile && destination.length() == source.length()) {
                "Prepared APK is incomplete"
            }
        } finally {
            temporary.delete()
        }

        return mapOf(
            "status" to "ready",
            "path" to destination.absolutePath,
            "fileName" to fileName,
            "size" to destination.length(),
            "version" to version,
        )
    }

    private fun packageInfo(): PackageInfo =
        if (Build.VERSION.SDK_INT >= 33) {
            context.packageManager.getPackageInfo(
                context.packageName,
                PackageManager.PackageInfoFlags.of(0),
            )
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageInfo(context.packageName, 0)
        }
}
