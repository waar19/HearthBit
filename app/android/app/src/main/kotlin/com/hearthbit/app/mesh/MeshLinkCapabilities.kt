package com.hearthbit.app.mesh

internal object MeshLinkCapabilities {
    fun bleCapabilities(
        id: String,
        mtu: Int,
        reliability: LinkReliability,
    ): LinkCapabilities = LinkCapabilities(
        id = id,
        kind = LinkKind.BLE,
        mtu = mtu,
        broadcast = false,
        unicast = true,
        reliability = reliability,
        background = true,
        maxConnections = MeshEngineConstants.MAX_BLE_CONNECTIONS,
        cost = MeshEngineConstants.BLE_LINK_COST,
    )

    fun LinkCapabilities.toEventMap(): Map<String, Any> = mapOf(
        "id" to id,
        "kind" to kind.name.lowercase(),
        "mtu" to mtu,
        "broadcast" to broadcast,
        "unicast" to unicast,
        "reliability" to reliability.name.lowercase(),
        "background" to background,
        "maxConnections" to maxConnections,
        "cost" to cost,
    )
}
