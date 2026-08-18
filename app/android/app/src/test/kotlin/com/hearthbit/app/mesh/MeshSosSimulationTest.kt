package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MeshSosSimulationTest {
    @Test
    fun `one hundred SOS packets keep relay fan out and queues bounded`() {
        val simulation = SosMeshSimulation(
            nodeCount = NODE_COUNT,
            maximumFanOut = MAXIMUM_FAN_OUT,
            copiesPerLink = COPIES_PER_LINK,
            knownPacketBudget = KNOWN_PACKET_BUDGET,
            unknownPacketBudget = UNKNOWN_PACKET_BUDGET,
        )

        val result = simulation.exchange(SOS_PACKET_COUNT)

        assertEquals(SOS_PACKET_COUNT, result.packetCount)
        assertEquals(MAXIMUM_FAN_OUT, result.maximumObservedFanOut)
        assertEquals(MAXIMUM_QUEUE_ITEMS, result.maximumObservedQueueItems)
        assertEquals(MAXIMUM_FAN_OUT, result.maximumObservedQueuePeers)
        assertEquals(MAXIMUM_COPIES_PER_PEER, result.maximumObservedItemsPerPeer)
        assertTrue(result.maximumRelaysForOnePacket < NODE_COUNT)
        assertTrue(result.suppressedRelays > 0)
        assertTrue(result.deduplicatedCopies > result.acceptedPackets)
        assertTrue(result.distinctDuplicateSources > 0)
        assertTrue(result.knownRateLimitedPackets > 0)
        assertTrue(result.unknownRateLimitedPackets > 0)
        result.nodeBudgets.forEach { budget ->
            assertTrue(budget.acceptedKnown <= KNOWN_PACKET_BUDGET)
            assertTrue(budget.acceptedUnknown <= UNKNOWN_PACKET_BUDGET)
        }
    }

    private class SosMeshSimulation(
        nodeCount: Int,
        private val maximumFanOut: Int,
        private val copiesPerLink: Int,
        private val knownPacketBudget: Int,
        private val unknownPacketBudget: Int,
    ) {
        private data class SosPacket(
            val sequence: Int,
            val fingerprint: String,
            val originIndex: Int,
        )

        private data class PendingRelay(
            val packet: SosPacket,
            val sources: MutableSet<String>,
        )

        data class NodeBudget(
            val acceptedKnown: Int,
            val acceptedUnknown: Int,
        )

        data class Result(
            val packetCount: Int,
            val acceptedPackets: Int,
            val deduplicatedCopies: Int,
            val distinctDuplicateSources: Int,
            val suppressedRelays: Int,
            val knownRateLimitedPackets: Int,
            val unknownRateLimitedPackets: Int,
            val maximumObservedFanOut: Int,
            val maximumObservedQueueItems: Int,
            val maximumObservedQueuePeers: Int,
            val maximumObservedItemsPerPeer: Int,
            val maximumRelaysForOnePacket: Int,
            val nodeBudgets: List<NodeBudget>,
        )

        private inner class Node(val index: Int) {
            val id = "node-${index.toString().padStart(2, '0')}"
            val fingerprints = EmergencyFingerprintCache(
                storage = InMemoryFingerprintStorage(),
                maximumEntries = SOS_PACKET_COUNT,
            )
            val rateLimiter = OpenEmergencyRateLimiter(
                knownMaximumPackets = knownPacketBudget,
                unknownMaximumPackets = unknownPacketBudget,
                windowMs = SIMULATION_WINDOW_MS,
            )
            val outgoing = BoundedPeerPendingQueue<SosPacket>(
                maximumPeers = maximumFanOut,
                maximumItemsPerPeer = MAXIMUM_COPIES_PER_PEER,
                maximumItems = maximumFanOut * MAXIMUM_COPIES_PER_PEER,
            )
            val pending = mutableMapOf<String, PendingRelay>()
            var acceptedKnown = 0
            var acceptedUnknown = 0
        }

        private val nodes = List(nodeCount, ::Node)
        private var acceptedPackets = 0
        private var deduplicatedCopies = 0
        private var distinctDuplicateSources = 0
        private var suppressedRelays = 0
        private var knownRateLimitedPackets = 0
        private var unknownRateLimitedPackets = 0
        private var maximumObservedFanOut = 0
        private var maximumObservedQueueItems = 0
        private var maximumObservedQueuePeers = 0
        private var maximumObservedItemsPerPeer = 0

        fun exchange(packetCount: Int): Result {
            var maximumRelaysForOnePacket = 0
            repeat(packetCount) { sequence ->
                val packet = SosPacket(
                    sequence = sequence,
                    fingerprint = sequence.toString(16).padStart(64, '0'),
                    originIndex = sequence % nodes.size,
                )
                val origin = nodes[packet.originIndex]
                check(!origin.fingerprints.seenOrRemember(packet.fingerprint, SIMULATION_NOW_MS))

                broadcast(origin, packet)
                maximumRelaysForOnePacket = maxOf(
                    maximumRelaysForOnePacket,
                    processPendingRelays(packet),
                )
            }

            return Result(
                packetCount = packetCount,
                acceptedPackets = acceptedPackets,
                deduplicatedCopies = deduplicatedCopies,
                distinctDuplicateSources = distinctDuplicateSources,
                suppressedRelays = suppressedRelays,
                knownRateLimitedPackets = knownRateLimitedPackets,
                unknownRateLimitedPackets = unknownRateLimitedPackets,
                maximumObservedFanOut = maximumObservedFanOut,
                maximumObservedQueueItems = maximumObservedQueueItems,
                maximumObservedQueuePeers = maximumObservedQueuePeers,
                maximumObservedItemsPerPeer = maximumObservedItemsPerPeer,
                maximumRelaysForOnePacket = maximumRelaysForOnePacket,
                nodeBudgets = nodes.map {
                    NodeBudget(
                        acceptedKnown = it.acceptedKnown,
                        acceptedUnknown = it.acceptedUnknown,
                    )
                },
            )
        }

        private fun processPendingRelays(packet: SosPacket): Int {
            val decidedNodes = mutableSetOf<String>()
            var relays = 0
            while (true) {
                val next = nodes
                    .filter { it.id !in decidedNodes && packet.fingerprint in it.pending }
                    .minWithOrNull(
                        compareBy<Node>(
                            {
                                RelayDampingPolicy.jitterMs(
                                    fingerprint = packet.fingerprint,
                                    localSalt = it.id,
                                    emergency = true,
                                )
                            },
                            Node::id,
                        ),
                    ) ?: break
                decidedNodes += next.id
                val pending = checkNotNull(next.pending.remove(packet.fingerprint))
                if (RelayDampingPolicy.shouldRelay(
                        additionalCopies = pending.sources.size - 1,
                        emergency = true,
                    )
                ) {
                    relays += 1
                    broadcast(next, pending.packet)
                } else {
                    suppressedRelays += 1
                }
            }
            return relays
        }

        private fun broadcast(sender: Node, packet: SosPacket) {
            nodes.asSequence()
                .filter { it !== sender }
                .sortedBy(Node::id)
                .forEach { receiver ->
                    repeat(copiesPerLink) {
                        sender.outgoing.offer(receiver.id, packet)
                    }
                }

            maximumObservedQueueItems = maxOf(maximumObservedQueueItems, sender.outgoing.size)
            maximumObservedQueuePeers = maxOf(maximumObservedQueuePeers, sender.outgoing.peerCount)
            val recipients = sender.outgoing.peerIds().sorted()
            maximumObservedFanOut = maxOf(maximumObservedFanOut, recipients.size)
            recipients.forEach { receiverId ->
                val queued = sender.outgoing.drain(receiverId)
                maximumObservedItemsPerPeer = maxOf(maximumObservedItemsPerPeer, queued.size)
                val receiver = nodes.single { it.id == receiverId }
                queued.forEach { receive(receiver, it, sender.id) }
            }
        }

        private fun receive(receiver: Node, packet: SosPacket, sourceId: String) {
            receiver.pending[packet.fingerprint]?.let { pending ->
                if (pending.sources.add(sourceId)) distinctDuplicateSources += 1
            }
            if (receiver.fingerprints.seenOrRemember(packet.fingerprint, SIMULATION_NOW_MS)) {
                deduplicatedCopies += 1
                return
            }

            val knownRelationship = (receiver.index + packet.originIndex) % 3 != 0
            if (!receiver.rateLimiter.allow(knownRelationship, SIMULATION_NOW_MS)) {
                if (knownRelationship) {
                    knownRateLimitedPackets += 1
                } else {
                    unknownRateLimitedPackets += 1
                }
                return
            }

            acceptedPackets += 1
            if (knownRelationship) {
                receiver.acceptedKnown += 1
            } else {
                receiver.acceptedUnknown += 1
            }
            receiver.pending[packet.fingerprint] = PendingRelay(
                packet = packet,
                sources = mutableSetOf(sourceId),
            )
        }
    }

    private class InMemoryFingerprintStorage : EmergencyFingerprintStorage {
        private val values = mutableMapOf<String, Set<String>>()

        override fun getStringSet(key: String): Set<String> = values[key].orEmpty()

        override fun putStringSet(key: String, value: Set<String>): Boolean {
            values[key] = value.toSet()
            return true
        }

        override fun clear(): Boolean {
            values.clear()
            return true
        }
    }

    private companion object {
        const val NODE_COUNT = 12
        const val SOS_PACKET_COUNT = 100
        const val MAXIMUM_FAN_OUT = 8
        const val COPIES_PER_LINK = 3
        const val MAXIMUM_COPIES_PER_PEER = 2
        const val MAXIMUM_QUEUE_ITEMS = MAXIMUM_FAN_OUT * MAXIMUM_COPIES_PER_PEER
        const val KNOWN_PACKET_BUDGET = 20
        const val UNKNOWN_PACKET_BUDGET = 10
        const val SIMULATION_NOW_MS = 1_000L
        const val SIMULATION_WINDOW_MS = 60_000L
    }
}
