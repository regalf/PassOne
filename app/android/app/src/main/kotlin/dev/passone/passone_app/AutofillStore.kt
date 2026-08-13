package dev.passone.passone_app

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * App-private storage used by the autofill service.
 *
 * Security model (session-bound):
 *  - the snapshot (encrypted by Flutter with a random per-unlock key) is stored
 *    here as-is;
 *  - the session key is re-wrapped with a device-bound Android Keystore key so
 *    the service process can unwrap it while the vault is unlocked, and it is
 *    deleted on lock;
 *  - pending saves are wrapped with the Keystore key directly, so they survive
 *    a lock and can be imported at the next unlock.
 */
class AutofillStore(context: Context) {
    private val prefs = context.applicationContext
        .getSharedPreferences("passone_autofill", Context.MODE_PRIVATE)

    companion object {
        private const val KEYSTORE = "AndroidKeyStore"
        private const val MASTER_ALIAS = "passone_autofill_master"
        private const val KEY_SNAPSHOT = "snapshot"
        private const val KEY_SESSION = "session_key"
        private const val KEY_PENDING = "pending"
        private const val KEY_REQUIRE_AUTH = "require_auth"
    }

    private fun masterKey(): SecretKey {
        val ks = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (ks.getKey(MASTER_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                MASTER_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    /** AES-256-GCM with the Keystore master key. Returns base64(nonce || ciphertext+tag). */
    fun encrypt(value: ByteArray): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, masterKey())
        val ct = cipher.doFinal(value)
        val nonce = cipher.iv
        val out = ByteArray(nonce.size + ct.size)
        System.arraycopy(nonce, 0, out, 0, nonce.size)
        System.arraycopy(ct, 0, out, nonce.size, ct.size)
        return Base64.encodeToString(out, Base64.NO_WRAP)
    }

    /** Inverse of [encrypt]; returns null on any error (wrong key, corruption). */
    fun decrypt(b64: String): ByteArray? {
        return try {
            val raw = Base64.decode(b64, Base64.NO_WRAP)
            val nonce = raw.copyOfRange(0, 12)
            val ct = raw.copyOfRange(12, raw.size)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, masterKey(), GCMParameterSpec(128, nonce))
            cipher.doFinal(ct)
        } catch (e: Exception) {
            null
        }
    }

    /** Stores the Flutter-encrypted snapshot (base64 of nonce||blob). */
    fun saveSnapshot(blobB64: String) {
        prefs.edit().putString(KEY_SNAPSHOT, blobB64).commit()
    }

    /** The stored snapshot as raw bytes, or null. */
    fun loadSnapshot(): ByteArray? {
        val b64 = prefs.getString(KEY_SNAPSHOT, null) ?: return null
        return try {
            Base64.decode(b64, Base64.NO_WRAP)
        } catch (e: Exception) {
            null
        }
    }

    fun setSessionKey(keyB64: String) {
        prefs.edit()
            .putString(KEY_SESSION, encrypt(Base64.decode(keyB64, Base64.NO_WRAP)))
            .commit()
    }

    fun loadSessionKey(): ByteArray? {
        val wrapped = prefs.getString(KEY_SESSION, null) ?: return null
        return decrypt(wrapped)
    }

    fun clearSessionKey() {
        prefs.edit().remove(KEY_SESSION).commit()
    }

    /** Stores the master-wrapped pending-saves payload (base64). */
    fun savePending(masterWrappedB64: String) {
        prefs.edit().putString(KEY_PENDING, masterWrappedB64).apply()
    }

    fun loadPending(): String? = prefs.getString(KEY_PENDING, null)

    fun clearPending() {
        prefs.edit().remove(KEY_PENDING).apply()
    }

    /** Whether every fill must be confirmed with biometrics/PIN (user setting). */
    fun setRequireAuth(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_REQUIRE_AUTH, enabled).apply()
    }

    fun isRequireAuthEnabled(): Boolean = prefs.getBoolean(KEY_REQUIRE_AUTH, false)
}
