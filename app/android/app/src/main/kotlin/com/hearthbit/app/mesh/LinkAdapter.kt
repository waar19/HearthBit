package com.hearthbit.app.mesh

internal enum class LinkKind {
    BLE,
    LAN,
    LORA,
    IN_MEMORY,
}

internal enum class LinkReliability {
    BEST_EFFORT,
    ACKNOWLEDGED,
}

internal enum class LinkPriority {
    STANDARD,
    CRITICAL,
}

internal data class LinkCapabilities(
    val id: String,
    val kind: LinkKind,
    /** Largest frame accepted by [LinkAdapter.send], in bytes. */
    val mtu: Int,
    val broadcast: Boolean,
    val unicast: Boolean,
    val reliability: LinkReliability,
    val background: Boolean,
    val maxConnections: Int,
    /** Relative routing cost. Lower values are preferred. */
    val cost: Int,
) {
    init {
        require(id.isNotBlank())
        require(mtu > 0)
        require(broadcast || unicast)
        require(maxConnections > 0)
        require(cost >= 0)
    }
}

/**
 * Common opaque-frame link boundary. Implementations must not decode, mutate,
 * decrement TTL, or deduplicate BitChat frames.
 */
internal interface LinkAdapter {
    val capabilities: LinkCapabilities

    fun send(frame: ByteArray, priority: LinkPriority = LinkPriority.STANDARD): Boolean
}

internal class CallbackLinkAdapter(
    override val capabilities: LinkCapabilities,
    private val sender: (ByteArray, LinkPriority) -> Boolean,
) : LinkAdapter {
    override fun send(frame: ByteArray, priority: LinkPriority): Boolean {
        if (frame.size > capabilities.mtu) return false
        return sender(frame.copyOf(), priority)
    }
}

/** Deterministic adapter used by contract and mesh-routing tests. */
internal class InMemoryLinkAdapter(
    override val capabilities: LinkCapabilities = LinkCapabilities(
        id = "memory",
        kind = LinkKind.IN_MEMORY,
        mtu = 512,
        broadcast = true,
        unicast = true,
        reliability = LinkReliability.ACKNOWLEDGED,
        background = true,
        maxConnections = 1,
        cost = 0,
    ),
) : LinkAdapter {
    private val frames = mutableListOf<ByteArray>()

    override fun send(frame: ByteArray, priority: LinkPriority): Boolean {
        if (frame.size > capabilities.mtu) return false
        frames += frame.copyOf()
        return true
    }

    fun sentFrames(): List<ByteArray> = frames.map { it.copyOf() }
}
