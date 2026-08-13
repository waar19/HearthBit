package com.hearthbit.app

import org.junit.Assert.assertEquals
import org.junit.Test

class ApkInstallationPolicyTest {
    @Test
    fun `clasifica una instalacion universal sin splits`() {
        assertEquals(
            ApkInstallationKind.UNIVERSAL,
            ApkInstallationPolicy.classify("/data/app/base.apk", null),
        )
        assertEquals(
            ApkInstallationKind.UNIVERSAL,
            ApkInstallationPolicy.classify("/data/app/base.apk", emptyArray()),
        )
    }

    @Test
    fun `rechaza base apk incompleto de una instalacion split`() {
        assertEquals(
            ApkInstallationKind.SPLIT,
            ApkInstallationPolicy.classify(
                "/data/app/base.apk",
                arrayOf("/data/app/split_config.arm64_v8a.apk"),
            ),
        )
    }

    @Test
    fun `rechaza una instalacion sin ruta base`() {
        assertEquals(
            ApkInstallationKind.INVALID,
            ApkInstallationPolicy.classify(null, null),
        )
    }
}
