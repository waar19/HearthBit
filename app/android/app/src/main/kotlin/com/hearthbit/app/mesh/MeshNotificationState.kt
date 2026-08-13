package com.hearthbit.app.mesh

internal data class MeshNotificationState(
    val status: String,
    val nearbyPeerCount: Int,
    val errorMessage: String? = null,
)

internal enum class MeshNotificationContent {
    STARTING,
    ACTIVE,
    ERROR,
}

internal object MeshNotificationStateReducer {
    fun contentFor(state: MeshNotificationState): MeshNotificationContent = when {
        state.errorMessage != null || state.status == "error" || state.status == "degraded" ->
            MeshNotificationContent.ERROR
        state.status == "starting" -> MeshNotificationContent.STARTING
        else -> MeshNotificationContent.ACTIVE
    }
}
