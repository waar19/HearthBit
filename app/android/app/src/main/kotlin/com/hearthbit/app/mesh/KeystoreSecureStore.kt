package com.hearthbit.app.mesh

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import com.google.crypto.tink.Aead
import com.google.crypto.tink.DeterministicAead
import com.google.crypto.tink.KeyTemplates
import com.google.crypto.tink.aead.AeadConfig
import com.google.crypto.tink.daead.DeterministicAeadConfig
import com.google.crypto.tink.integration.android.AndroidKeysetManager
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import java.security.GeneralSecurityException
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
 * El lector Tink integrado conserva la migración desde
 * EncryptedSharedPreferences sin mantener la API security-crypto deprecada.
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

    @Synchronized
    fun replaceString(oldKey: String, newKey: String, value: String): Boolean =
        preferences.edit()
            .putString(oldKey, encrypt(oldKey, Value.string("retired-by-key-rotation")))
            .putString(newKey, encrypt(newKey, Value.string(value)))
            .commit()

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
        return preferences.edit().putString(key, encrypt(key, value)).commit()
    }

    private fun encrypt(key: String, value: Value): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey)
        cipher.updateAAD(aad(key))
        val encrypted = cipher.iv + cipher.doFinal(encode(value))
        return Base64.encodeToString(encrypted, Base64.NO_WRAP)
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
        private const val KEY_ALIAS = "hearthbit_secure_store_aes_v3"
        private const val LEGACY_V2_KEY_ALIAS = "hearthbit_secure_store_aes_v2"
        private const val BACKING_SUFFIX = "_keystore_v3"
        private const val LEGACY_V2_BACKING_SUFFIX = "_keystore_v2"
        private const val MIGRATION_MARKER_SUFFIX = "_migration"
        private const val KEY_MIGRATION_COMPLETE = "legacy_complete"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val AES_KEY_SIZE_BITS = 256
        private const val IV_SIZE = 12
        private const val GCM_TAG_BITS = 128
        private const val MAX_SET_ENTRIES = 10_000
        private const val MAX_STRING_BYTES = 2 * 1024 * 1024
        private const val TYPE_STRING = 1
        private const val TYPE_LONG = 2
        private const val TYPE_BOOLEAN = 3
        private const val TYPE_STRING_SET = 4
        private const val TAG = "KeystoreSecureStore"

        fun open(context: Context, namespace: String): KeystoreSecureStore {
            val appContext = context.applicationContext
            val store = KeystoreSecureStore(
                preferences = appContext.getSharedPreferences(
                    namespace + BACKING_SUFFIX,
                    Context.MODE_PRIVATE,
                ),
                namespace = namespace,
                secretKey = getOrCreateSecretKey(KEY_ALIAS),
            )
            migrateV2KeystoreStore(appContext, namespace, store)
            migrateLegacyEncryptedPreferences(appContext, namespace, store)
            return store
        }

        private fun getOrCreateSecretKey(alias: String): SecretKey {
            val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            (keyStore.getKey(alias, null) as? SecretKey)?.let { return it }
            return KeyGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_AES,
                "AndroidKeyStore",
            ).run {
                init(
                    KeyGenParameterSpec.Builder(
                        alias,
                        KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                    )
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .setKeySize(AES_KEY_SIZE_BITS)
                        .setRandomizedEncryptionRequired(true)
                        .build(),
                )
                generateKey()
            }
        }

        private fun migrateV2KeystoreStore(
            context: Context,
            namespace: String,
            destination: KeystoreSecureStore,
        ) {
            val legacyPreferences = context.getSharedPreferences(
                namespace + LEGACY_V2_BACKING_SUFFIX,
                Context.MODE_PRIVATE,
            )
            if (legacyPreferences.all.isEmpty()) {
                deleteLegacyV2KeyIfUnused(context)
                return
            }
            val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            val legacyKey = keyStore.getKey(LEGACY_V2_KEY_ALIAS, null) as? SecretKey
                ?: error("Falta la clave Keystore v2 para migrar $namespace")
            val legacy = KeystoreSecureStore(
                preferences = legacyPreferences,
                namespace = namespace,
                secretKey = legacyKey,
            )
            val entries = legacyPreferences.all.keys.associateWith { key ->
                checkNotNull(legacy.read(key)) {
                    "No se pudo leer $key durante la migración v2 de $namespace"
                }
            }
            entries.forEach { (key, value) ->
                check(destination.put(key, value)) {
                    "No se pudo reescribir $key con AES-256 para $namespace"
                }
            }
            check(legacyPreferences.edit().clear().commit()) {
                "No se pudo borrar el almacén Keystore v2 $namespace"
            }
            deleteLegacyV2KeyIfUnused(context)
        }

        private fun deleteLegacyV2KeyIfUnused(context: Context) {
            val sharedPreferencesDirectory = File(context.applicationInfo.dataDir, "shared_prefs")
            val hasPendingV2Store = sharedPreferencesDirectory.listFiles()
                ?.asSequence()
                ?.filter { it.name.endsWith("$LEGACY_V2_BACKING_SUFFIX.xml") }
                ?.map { it.name.removeSuffix(".xml") }
                ?.any { preferenceName ->
                    context.getSharedPreferences(preferenceName, Context.MODE_PRIVATE)
                        .all
                        .isNotEmpty()
                } == true
            if (hasPendingV2Store) return
            val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            if (keyStore.containsAlias(LEGACY_V2_KEY_ALIAS)) {
                keyStore.deleteEntry(LEGACY_V2_KEY_ALIAS)
            }
        }

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
                markLegacyMigrationComplete(migration, namespace)
                return
            }

            val legacyPreferences = context.getSharedPreferences(namespace, Context.MODE_PRIVATE)
            val entries = readLegacyOrDiscard(
                namespace = namespace,
                readLegacy = {
                    LegacyEncryptedPreferencesReader(context, namespace).readAll()
                },
                clearLegacy = { legacyPreferences.edit().clear().commit() },
                markComplete = {
                    migration.edit()
                        .putBoolean(KEY_MIGRATION_COMPLETE, true)
                        .commit()
                },
            ) ?: return

            entries.forEach { (key, value) ->
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
            check(legacyPreferences.edit().clear().commit()) {
                "No se pudo borrar el almacén legado $namespace"
            }
            markLegacyMigrationComplete(migration, namespace)
        }

        private fun markLegacyMigrationComplete(
            migration: SharedPreferences,
            namespace: String,
        ) {
            if (!migration.edit().putBoolean(KEY_MIGRATION_COMPLETE, true).commit()) {
                Log.e(TAG, "No se pudo marcar la migración completa para $namespace")
            }
        }
    }
}

/**
 * Lee el formato legado o lo invalida de forma permanente si su keyset ya no
 * puede abrirse (por ejemplo, después de restaurar datos sin su clave Keystore).
 */
internal fun readLegacyOrDiscard(
    namespace: String,
    readLegacy: () -> Map<String, Any?>,
    clearLegacy: () -> Boolean,
    markComplete: () -> Boolean,
    logWarning: (String, Throwable) -> Unit = { message, error ->
        Log.w("KeystoreSecureStore", message, error)
    },
): Map<String, Any?>? {
    val entries = try {
        readLegacy()
    } catch (error: GeneralSecurityException) {
        discardUnreadableLegacy(
            namespace,
            clearLegacy,
            markComplete,
            error,
            logWarning,
        )
        return null
    } catch (error: IOException) {
        discardUnreadableLegacy(
            namespace,
            clearLegacy,
            markComplete,
            error,
            logWarning,
        )
        return null
    } catch (error: RuntimeException) {
        discardUnreadableLegacy(
            namespace,
            clearLegacy,
            markComplete,
            error,
            logWarning,
        )
        return null
    }
    return entries
}

private fun discardUnreadableLegacy(
    namespace: String,
    clearLegacy: () -> Boolean,
    markComplete: () -> Boolean,
    error: Exception,
    logWarning: (String, Throwable) -> Unit,
) {
    logWarning("Descartando almacén legado indescifrable $namespace", error)
    if (!clearLegacy()) {
        logWarning(
            "No se pudo borrar el almacén legado $namespace",
            IllegalStateException("SharedPreferences.clear() devolvió false"),
        )
    }
    if (!markComplete()) {
        logWarning(
            "No se pudo marcar la migración completa para $namespace",
            IllegalStateException("SharedPreferences.commit() devolvió false"),
        )
    }
}

/**
 * Lector de migración para el formato de EncryptedSharedPreferences.
 *
 * Usa los mismos keysets Tink y AAD del formato AndroidX, pero solo expone una
 * lectura única seguida de borrado. Nunca crea ni escribe datos en el formato
 * legado.
 */
private class LegacyEncryptedPreferencesReader(
    context: Context,
    private val fileName: String,
) {
    private val preferences = context.getSharedPreferences(fileName, Context.MODE_PRIVATE)
    private val keyAead: DeterministicAead
    private val valueAead: Aead

    init {
        check(preferences.contains(KEY_KEYSET_ALIAS) && preferences.contains(VALUE_KEYSET_ALIAS)) {
            "El almacén legado $fileName no contiene sus keysets"
        }
        AeadConfig.register()
        DeterministicAeadConfig.register()
        keyAead = AndroidKeysetManager.Builder()
            .withSharedPref(context, KEY_KEYSET_ALIAS, fileName)
            .withKeyTemplate(KeyTemplates.get("AES256_SIV"))
            .withMasterKeyUri(MASTER_KEY_URI)
            .build()
            .keysetHandle
            .getPrimitive(DeterministicAead::class.java)
        valueAead = AndroidKeysetManager.Builder()
            .withSharedPref(context, VALUE_KEYSET_ALIAS, fileName)
            .withKeyTemplate(KeyTemplates.get("AES256_GCM"))
            .withMasterKeyUri(MASTER_KEY_URI)
            .build()
            .keysetHandle
            .getPrimitive(Aead::class.java)
    }

    fun readAll(): Map<String, Any?> = buildMap {
        preferences.all.forEach { (encryptedKey, encryptedValue) ->
            if (encryptedKey == KEY_KEYSET_ALIAS || encryptedKey == VALUE_KEYSET_ALIAS) return@forEach
            try {
                check(encryptedValue is String) { "Valor legado no cifrado en $fileName" }
                val encryptedKeyBytes = Base64.decode(encryptedKey, Base64.DEFAULT)
                val key = keyAead.decryptDeterministically(
                    encryptedKeyBytes,
                    fileName.toByteArray(Charsets.UTF_8),
                ).toString(Charsets.UTF_8)
                if (key == NULL_VALUE) return@forEach
                val clearValue = valueAead.decrypt(
                    Base64.decode(encryptedValue, Base64.DEFAULT),
                    encryptedKeyBytes,
                )
                put(key, decodeValue(clearValue))
            } catch (error: GeneralSecurityException) {
                Log.w(TAG, "Omitiendo entrada legado indescifrable en $fileName", error)
            } catch (error: RuntimeException) {
                Log.w(TAG, "Omitiendo entrada legado inválida en $fileName", error)
            }
        }
    }

    fun clear(): Boolean = preferences.edit().clear().commit()

    private fun decodeValue(clearValue: ByteArray): Any? {
        val input = ByteBuffer.wrap(clearValue)
        return when (val type = input.int) {
            TYPE_STRING -> input.readString().takeUnless { it == NULL_VALUE }
            TYPE_STRING_SET -> buildSet {
                while (input.hasRemaining()) add(input.readString())
            }.takeUnless { it.size == 1 && it.single() == NULL_VALUE }
            TYPE_INT -> input.int
            TYPE_LONG -> input.long
            TYPE_FLOAT -> input.float
            TYPE_BOOLEAN -> input.get().toInt() != 0
            else -> error("Tipo legado desconocido $type en $fileName")
        }
    }

    private fun ByteBuffer.readString(): String {
        val length = int
        require(length in 0..remaining()) { "Longitud legado inválida en $fileName" }
        return ByteArray(length).also(::get).toString(Charsets.UTF_8)
    }

    companion object {
        private const val KEY_KEYSET_ALIAS =
            "__androidx_security_crypto_encrypted_prefs_key_keyset__"
        private const val VALUE_KEYSET_ALIAS =
            "__androidx_security_crypto_encrypted_prefs_value_keyset__"
        private const val MASTER_KEY_URI = "android-keystore://_androidx_security_master_key_"
        private const val NULL_VALUE = "__NULL__"
        private const val TYPE_STRING = 0
        private const val TYPE_STRING_SET = 1
        private const val TYPE_INT = 2
        private const val TYPE_LONG = 3
        private const val TYPE_FLOAT = 4
        private const val TYPE_BOOLEAN = 5
        private const val TAG = "LegacyEncryptedPrefs"
    }
}
