package com.hearthbit.app.mesh

internal object MeshInteropPolicy {
    fun shouldProcessPublicMessage(
        privateMode: Boolean,
        hearthbitVerified: Boolean,
        emergency: Boolean,
    ): Boolean = !privateMode || hearthbitVerified || emergency

    fun isExternalEmergency(
        privateMode: Boolean,
        hearthbitVerified: Boolean,
        emergency: Boolean,
    ): Boolean = privateMode && !hearthbitVerified && emergency

    fun canSendIdentityToLink(
        privateMode: Boolean,
        hearthbitProven: Boolean,
        emergencyException: Boolean,
    ): Boolean = !privateMode || hearthbitProven || emergencyException
}
