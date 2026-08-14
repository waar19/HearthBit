package com.hearthbit.app.mesh

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Almacén pequeño cifrado con AES-GCM y una clave no exportable del Android
 * Keystore. Los nombres lógicos no son secretos; valores, sets y claves de
 * identidad permanecen cifrados y autenticados.
 *
 * La dependencia security-crypto se conserva temporalmente solo para leer y
 * borrar el formato legado. Retirarla antes de que las instalaciones activas
 * hayan ejecutado esta migración perdería identidades existentes.
 */
internal class KeystoreSecureStore private constructor(
    private val preferences: SharedPreferences,
    private val namespace: String,
    private val secretKey: SecretKey,
) {
    fun getString(key: String, default: String? = null): String? =
        read(key)?.takeIf { it.type == TYPE_STRING }?.stringValue ?: default

    fun getLong(key: String, default: Long = 0L): Long =
        read(key)?.takeIf { it.type == TYPE_LONG }?.longValue ?: default

    fun getBoolean(key: String, default: Boolean = false): Boolean =
        read(key)?.takeIf { it.type == TYPE_BOOLEAN }?.booleanValue ?: default

    fun getStringSet(key: String, default: Set<String> = emptySet()): Set<String> =
        read(key)?.takeIf { it.type == TYPE_STRING_SET }?.stringSetValue?.toSet() ?: default

    fun contains(key: String): Boolean = preferences.contains(key)

    fun keys(): Set<String> = preferences.all.keys

    fun putString(key: String, value: String?): Boolean =
        if (value == null) remove(key) else put(key, Value.string(value))

    fun putLong(key: String, value: Long): Boolean = put(key, Value.long(value))

    fun putBoolean(key: String, value: Boolean): Boolean = put(key, Value.boolean(value))

    fun putStringSet(key: String, value: Set<String>): Boolean =
        put(key, Value.stringSet(value))

    fun remove(key: String): Boolean = preferences.edit().remove(key).commit()

    fun clear(): Boolean = preferences.edit().clear().commit()

    @Synchronized
    private fun read(key: String): Value? {
        val encoded = preferences.getString(key, null) ?: return null
        val encrypted = Base64.decode(encoded, Base64.NO_WRAP)
        require(encrypted.size > IV_SIZE) { "Entrada cifrada truncada en $namespace" }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            secretKey,
            GCMParameterSpec(GCM_TAG_BITS, encrypted, 0, IV_SIZE),
        )
        cipher.updateAAD(aad(key))
        return decode(cipher.doFinal(encrypted, IV_SIZE, encrypted.size - IV_SIZE))
    }

    @Synchronized
    private fun put(key: String, value: Value): Boolean {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey)
        cipher.updateAAD(aad(key))
        val encrypted = cipher.iv + cipher.doFinal(encode(value))
        return preferences.edit().putString(
            key,
            Base64.encodeToString(encrypted, Base64.NO_WRAP),
        ).commit()
    }

    private fun aad(key: String): ByteArray = "$namespace:$key".toByteArray(Charsets.UTF_8)

    private fun encode(value: Value): ByteArray = ByteArrayOutputStream().use { bytes ->
        DataOutputStream(bytes).use { output ->
            output.writeByte(value.type)
            when (value.type) {
                TYPE_STRING -> output.writeString(checkNotNull(value.stringValue))
                TYPE_LONG -> output.writeLong(value.longValue)
                TYPE_BOOLEAN -> output.writeBoolean(value.booleanValue)
                TYPE_STRING_SET -> {
                    val values = checkNotNull(value.stringSetValue).sorted()
                    output.writeInt(values.size)
                    values.forEach { output.writeString(it) }
                }
            }
        }
        bytes.toByteArray()
    }

    private fun decode(bytes: ByteArray): Value = DataInputStream(
        ByteArrayInputStream(bytes),
    ).use { input ->
        when (val type = input.readUnsignedByte()) {
            TYPE_STRING -> Value.string(input.readString())
            TYPE_LONG -> Value.long(input.readLong())
            TYPE_BOOLEAN -> Value.boolean(input.readBoolean())
            TYPE_STRING_SET -> {
                val size = input.readInt()
                require(size in 0..MAX_SET_ENTRIES) { "Set cifrado inválido en $namespace" }
                Value.stringSet(buildSet(size) { repeat(size) { add(input.readString()) } })
            }
            else -> error("Tipo cifrado desconocido $type en $namespace")
        }
    }

    private fun DataOutputStream.writeString(value: String) {
        val encoded = value.toByteArray(Charsets.UTF_8)
        require(encoded.size <= MAX_STRING_BYTES) { "Valor demasiado grande en $namespace" }
        writeInt(encoded.size)
        write(encoded)
    }

    private fun DataInputStream.readString(): String {
        val size = readInt()
        require(size in 0..MAX_STRING_BYTES) { "Longitud cifrada inválida en $namespace" }
        return ByteArray(size).also(::readFully).toString(Charsets.UTF_8)
    }

    private data class Value(
        val type: Int,
        val stringValue: String? = null,
        val longValue: Long = 0L,
        val booleanValue: Boolean = false,
        val stringSetValue: Set<String>? = null,
    ) {
        companion object {
            fun string(value: String) = Value(TYPE_STRING, stringValue = value)
            fun long(value: Long) = Value(TYPE_LONG, longValue = value)
            fun boolean(value: Boolean) = Value(TYPE_BOOLEAN, booleanValue = value)
            fun stringSet(value: Set<String>) = Value(TYPE_STRING_SET, stringSetValue = value)
        }
    }

    companion object {
        private const val KEY_ALIAS = "hearthbit_secure_store_aes_v2"
        private const val BACKING_SUFFIX = "_keystore_v2"
        private const val MIGRATION_MARKER_SUFFIX = "_migration"
        private const val KEY_MIGRATION_COMPLETE = "legacy_complete"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val IV_SIZE = 12
        private const val GCM_TAG_BITS = 128
        private const val MAX_SET_ENTRIES = 10_000
        private const val MAX_STRING_BYTES = 2 * 1024 * 1024
        private const val TYPE_STRING = 1
        private const val TYPE_LONG = 2
        private const val TYPE_BOOLEAN = 3
        private const val TYPE_STRING_SET = 4

        fun open(context: Context, namespace: String): KeystoreSecureStore {
            val appContext = context.applicationContext
            val store = KeystoreSecureStore(
                preferences = appContext.getSharedPreferences(
                    namespace + BACKING_SUFFIX,
                    Context.MODE_PRIVATE,
                ),
                namespace = namespace,
                secretKey = getOrCreateSecretKey(),
            )
            migrateLegacyEncryptedPreferences(appContext, namespace, store)
            return store
        }

        private fun getOrCreateSecretKey(): SecretKey {
            val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
            return KeyGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_AES,
                "AndroidKeyStore",
            ).run {
                init(
                    KeyGenParameterSpec.Builder(
                        KEY_ALIAS,
                        KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                    )
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .setRandomizedEncryptionRequired(true)
                        .build(),
                )
                generateKey()
            }
        }

        @Suppress("DEPRECATION")
        private fun migrateLegacyEncryptedPreferences(
            context: Context,
            namespace: String,
            destination: KeystoreSecureStore,
        ) {
            val migration = context.getSharedPreferences(
                namespace + MIGRATION_MARKER_SUFFIX,
                Context.MODE_PRIVATE,
            )
            if (migration.getBoolean(KEY_MIGRATION_COMPLETE, false)) return
            val legacyFile = File(
                context.applicationInfo.dataDir,
                "shared_prefs${File.separator}$namespace.xml",
            )
            if (!legacyFile.exists()) {
                check(migration.edit().putBoolean(KEY_MIGRATION_COMPLETE, true).commit())
                return
            }
            val legacy = EncryptedSharedPreferences.create(
                context,
                namespace,
                MasterKey.Builder(context)
                    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                    .build(),
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            )
            legacy.all.forEach { (key, value) ->
                val migrated = when (value) {
                    is String -> destination.putString(key, value)
                    is Long -> destination.putLong(key, value)
                    is Boolean -> destination.putBoolean(key, value)
                    is Set<*> -> destination.putStringSet(
                        key,
                        value.filterIsInstance<String>().toSet(),
                    )
                    is Int -> destination.putLong(key, value.toLong())
                    is Float -> false
                    null -> true
                    else -> false
                }
                check(migrated) { "No se pudo migrar $key desde $namespace" }
            }
            check(migration.edit().putBoolean(KEY_MIGRATION_COMPLETE, true).commit())
            check(legacy.edit().clear().commit()) {
                "No se pudo borrar el almacén legado $namespace"
            }
        }
    }
}
