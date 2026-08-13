package com.hearthbit.app

internal enum class ApkInstallationKind {
    UNIVERSAL,
    SPLIT,
    INVALID,
}

internal object ApkInstallationPolicy {
    fun classify(sourceDir: String?, splitSourceDirs: Array<String>?): ApkInstallationKind {
        if (sourceDir.isNullOrBlank()) return ApkInstallationKind.INVALID
        if (!splitSourceDirs.isNullOrEmpty()) return ApkInstallationKind.SPLIT
        return ApkInstallationKind.UNIVERSAL
    }
}
