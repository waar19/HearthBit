package com.hearthbit.app.mesh

import android.content.Context
import android.util.Base64
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.bitchat.android.noise.southernstorm.protocol.Noise
import org.bouncycastle.crypto.generators.Ed25519KeyPairGenerator
import org.bouncycastle.crypto.params.Ed25519KeyGenerationParameters
import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters
import org.bouncycastle.crypto.signers.Ed25519Signer
import java.security.SecureRandom

internal class MeshIdentity(context: Context) {
    private val preferences = EncryptedSharedPreferences.create(
        context,
        "hearthbit_identity",
        MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    // «SOS-XXXX» como nombre por defecto: neutro y comprensible en cualquier
    // idioma, clave ahora que la app está localizada en varios idiomas.
    var nickname: String
        get() = preferences.getString(KEY_NICKNAME, null)
            ?: "SOS-${peerIdHex.takeLast(4)}"
        set(value) {
            preferences.edit().putString(KEY_NICKNAME, value.take(31)).apply()
        }

    var radarConsentUntil: Long
        get() = preferences.getLong(KEY_RADAR_CONSENT_UNTIL, 0L)
        set(value) {
            preferences.edit().putLong(KEY_RADAR_CONSENT_UNTIL, value).apply()
        }

    var nodeRole: MeshNodeRole
        get() = MeshNodeRole.fromWireName(
            preferences.getString(KEY_NODE_ROLE, null),
        ) ?: MeshNodeRole.PHONE_RELAY
        set(value) {
            preferences.edit().putString(KEY_NODE_ROLE, value.wireName).apply()
        }

    val noisePrivateKey: ByteArray
    val noisePublicKey: ByteArray
    val signingPrivateKey: ByteArray
    val signingPublicKey: ByteArray
    val peerId: ByteArray
    val peerIdHex: String

    init {
        val existingNoisePrivate = read(KEY_NOISE_PRIVATE)
        val existingNoisePublic = read(KEY_NOISE_PUBLIC)
        if (existingNoisePrivate?.size == 32 && existingNoisePublic?.size == 32) {
            noisePrivateKey = existingNoisePrivate
            noisePublicKey = existingNoisePublic
        } else {
            val dh = Noise.createDH("25519")
            dh.generateKeyPair()
            noisePrivateKey = ByteArray(32).also { dh.getPrivateKey(it, 0) }
            noisePublicKey = ByteArray(32).also { dh.getPublicKey(it, 0) }
            dh.destroy()
            write(KEY_NOISE_PRIVATE, noisePrivateKey)
            write(KEY_NOISE_PUBLIC, noisePublicKey)
        }

        val existingSigningPrivate = read(KEY_SIGNING_PRIVATE)
        val existingSigningPublic = read(KEY_SIGNING_PUBLIC)
        if (existingSigningPrivate?.size == 32 && existingSigningPublic?.size == 32) {
            signingPrivateKey = existingSigningPrivate
            signingPublicKey = existingSigningPublic
        } else {
            val generator = Ed25519KeyPairGenerator()
            generator.init(Ed25519KeyGenerationParameters(SecureRandom()))
            val pair = generator.generateKeyPair()
            signingPrivateKey = (pair.private as Ed25519PrivateKeyParameters).encoded
            signingPublicKey = (pair.public as Ed25519PublicKeyParameters).encoded
            write(KEY_SIGNING_PRIVATE, signingPrivateKey)
            write(KEY_SIGNING_PUBLIC, signingPublicKey)
        }

        peerId = MeshProtocol.peerIdFromNoiseKey(noisePublicKey)
        peerIdHex = MeshProtocol.hex(peerId)
    }

    fun sign(packet: MeshProtocol.Packet): MeshProtocol.Packet {
        val signer = Ed25519Signer()
        signer.init(true, Ed25519PrivateKeyParameters(signingPrivateKey, 0))
        val canonical = packet.canonicalForSigning()
        signer.update(canonical, 0, canonical.size)
        return packet.copy(signature = signer.generateSignature())
    }

    fun verify(packet: MeshProtocol.Packet, publicKey: ByteArray): Boolean {
        val signature = packet.signature ?: return false
        if (publicKey.size != 32 || signature.size != 64) return false
        val verifier = Ed25519Signer()
        verifier.init(false, Ed25519PublicKeyParameters(publicKey, 0))
        val canonical = packet.canonicalForSigning()
        verifier.update(canonical, 0, canonical.size)
        return verifier.verifySignature(signature)
    }

    /** Firma Ed25519 de bytes arbitrarios (ofertas de transferencia, boletines). */
    fun signBytes(data: ByteArray): ByteArray {
        val signer = Ed25519Signer()
        signer.init(true, Ed25519PrivateKeyParameters(signingPrivateKey, 0))
        signer.update(data, 0, data.size)
        return signer.generateSignature()
    }

    fun verifyBytes(data: ByteArray, signature: ByteArray, publicKey: ByteArray): Boolean {
        if (publicKey.size != 32 || signature.size != 64) return false
        val verifier = Ed25519Signer()
        verifier.init(false, Ed25519PublicKeyParameters(publicKey, 0))
        verifier.update(data, 0, data.size)
        return verifier.verifySignature(signature)
    }

    fun clear() {
        preferences.edit().clear().apply()
    }

    private fun read(key: String): ByteArray? = preferences.getString(key, null)?.let {
        runCatching { Base64.decode(it, Base64.NO_WRAP) }.getOrNull()
    }

    private fun write(key: String, value: ByteArray) {
        preferences.edit().putString(key, Base64.encodeToString(value, Base64.NO_WRAP)).apply()
    }

    private companion object {
        const val KEY_NICKNAME = "nickname"
        const val KEY_NOISE_PRIVATE = "noise_private"
        const val KEY_NOISE_PUBLIC = "noise_public"
        const val KEY_SIGNING_PRIVATE = "signing_private"
        const val KEY_SIGNING_PUBLIC = "signing_public"
        const val KEY_RADAR_CONSENT_UNTIL = "radar_consent_until"
        const val KEY_NODE_ROLE = "node_role"
    }
}
