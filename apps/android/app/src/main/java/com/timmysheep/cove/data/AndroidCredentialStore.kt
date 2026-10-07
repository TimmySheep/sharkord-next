package com.timmysheep.cove.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal data class SavedLoginCredentials(
    val host: String,
    val identity: String,
    val password: String,
    val serverPassword: String
)

internal object SavedLoginCodec {
    fun encode(credentials: SavedLoginCredentials): ByteArray = ByteArrayOutputStream().use { bytes ->
        DataOutputStream(bytes).use { output ->
            output.writeUTF(credentials.host)
            output.writeUTF(credentials.identity)
            output.writeUTF(credentials.password)
            output.writeUTF(credentials.serverPassword)
        }
        bytes.toByteArray()
    }

    fun decode(payload: ByteArray): SavedLoginCredentials = DataInputStream(ByteArrayInputStream(payload)).use { input ->
        val credentials = SavedLoginCredentials(
            host = input.readUTF(),
            identity = input.readUTF(),
            password = input.readUTF(),
            serverPassword = input.readUTF()
        )
        if (input.read() != -1) throw IOException("Unexpected data after saved credentials")
        credentials
    }
}

internal class AndroidCredentialStore(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    fun load(): SavedLoginCredentials? {
        val stored = preferences.getString(CREDENTIALS_KEY, null) ?: return null
        return try {
            val encrypted = Base64.decode(stored, Base64.URL_SAFE or Base64.NO_WRAP)
            val ivLength = encrypted.firstOrNull()?.toInt()?.and(0xff) ?: throw IOException("Missing encryption IV")
            if (ivLength != GCM_IV_LENGTH || encrypted.size <= ivLength + 1) {
                throw IOException("Invalid encrypted credentials")
            }
            val iv = encrypted.copyOfRange(1, ivLength + 1)
            val ciphertext = encrypted.copyOfRange(ivLength + 1, encrypted.size)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv))
            SavedLoginCodec.decode(cipher.doFinal(ciphertext))
        } catch (_: Exception) {
            clear()
            null
        }
    }

    fun save(credentials: SavedLoginCredentials): Boolean = try {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val encrypted = byteArrayOf(cipher.iv.size.toByte()) + cipher.iv + cipher.doFinal(SavedLoginCodec.encode(credentials))
        preferences.edit()
            .putString(CREDENTIALS_KEY, Base64.encodeToString(encrypted, Base64.URL_SAFE or Base64.NO_WRAP))
            .commit()
    } catch (_: Exception) {
        false
    }

    fun clear(): Boolean = preferences.edit().remove(CREDENTIALS_KEY).commit()

    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }

        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEY_STORE).run {
            init(
                KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build()
            )
            generateKey()
        }
    }

    private companion object {
        const val PREFERENCES_NAME = "secure_login"
        const val CREDENTIALS_KEY = "credentials"
        const val KEY_ALIAS = "cove.saved-login.aes"
        const val ANDROID_KEY_STORE = "AndroidKeyStore"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val GCM_IV_LENGTH = 12
        const val GCM_TAG_LENGTH_BITS = 128
    }
}
