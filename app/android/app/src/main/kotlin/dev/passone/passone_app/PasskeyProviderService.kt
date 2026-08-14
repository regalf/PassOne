package dev.passone.passone_app

import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.CancellationSignal
import android.os.OutcomeReceiver
import android.os.Build
import android.util.Base64
import androidx.credentials.PublicKeyCredential
import androidx.credentials.exceptions.ClearCredentialException
import androidx.credentials.exceptions.CreateCredentialException
import androidx.credentials.exceptions.CreateCredentialNoCreateOptionException
import androidx.credentials.exceptions.CreateCredentialUnknownException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.GetCredentialUnknownException
import androidx.credentials.provider.BeginCreateCredentialRequest
import androidx.credentials.provider.BeginCreateCredentialResponse
import androidx.credentials.provider.BeginGetCredentialRequest
import androidx.credentials.provider.BeginGetCredentialResponse
import androidx.credentials.provider.BeginGetPublicKeyCredentialOption
import androidx.credentials.provider.CreateEntry
import androidx.credentials.provider.CredentialProviderService
import androidx.credentials.provider.PublicKeyCredentialEntry
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Credential Manager provider for passkeys (API 34+).
 *
 * Two paths:
 *  - vault locked: the request is stashed and a single "unlock" entry is
 *    offered; after the user unlocks, the app completes the flow itself
 *    (Flutter UI + native signing, see MainActivity and WebAuthn);
 *  - vault unlocked: matching passkeys are offered as one [PublicKeyCredentialEntry]
 *    each; selecting one launches [PasskeyAuthActivity], which shows a
 *    biometric prompt and returns the signed assertion.
 *
 * Registration always goes through MainActivity/Flutter so the new key pair is
 * persisted into the encrypted vault (native code cannot write it).
 */
class PasskeyProviderService : CredentialProviderService() {

    private companion object {
        const val TAG = "PassOnePasskey"
        private const val REQ_CREATE = 2001
        private const val REQ_GET = 2002
        private const val REQ_AUTH = 2003
        private const val KEY_REQUEST_JSON = "androidx.credentials.BUNDLE_KEY_REQUEST_JSON"
        private const val KEY_CLIENT_DATA_HASH = "androidx.credentials.BUNDLE_KEY_CLIENT_DATA_HASH"
    }

    private class Passkey(
        val id: String,
        val username: String,
        val rpId: String,
        val privateKeyPkcs8: ByteArray,
        val publicKeySpki: ByteArray?,
        val userHandle: String?,
        val counter: Int,
    )

    override fun onBeginCreateCredentialRequest(
        request: BeginCreateCredentialRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<BeginCreateCredentialResponse, CreateCredentialException>,
    ) {
        try {
            if (request.type != PublicKeyCredential.TYPE_PUBLIC_KEY_CREDENTIAL) {
                PLog.d(TAG, "create: type=${request.type} not supported")
                callback.onError(CreateCredentialNoCreateOptionException())
                return
            }
            val requestJson = request.candidateQueryData.getString(KEY_REQUEST_JSON)
            PLog.d(TAG, "create: received requestJson=$requestJson")
            if (requestJson.isNullOrBlank()) {
                callback.onError(CreateCredentialNoCreateOptionException())
                return
            }
            AutofillStore(this).savePasskeyCreateRequest(requestJson)
            val req = JSONObject(requestJson)
            val rpName = req.optJSONObject("rp")?.optString("name")?.ifBlank { null }
                ?: req.optJSONObject("rp")?.optString("id")
                ?: getString(R.string.passkey_create_entry_title)
            val pending = PendingIntent.getActivity(
                this,
                REQ_CREATE,
                Intent(this, MainActivity::class.java)
                    .putExtra(MainActivity.EXTRA_PASSKEY_CREATE, true)
                    .putExtra(MainActivity.EXTRA_AUTOFILL_UNLOCK, true)
                    .setAction("passone.passkey.create"),
                PendingIntent.FLAG_UPDATE_CURRENT or mutableFlag(),
            )
            val entry = CreateEntry(
                accountName = rpName,
                pendingIntent = pending,
                icon = Icon.createWithResource(this, R.mipmap.ic_launcher),
                description = getString(R.string.passkey_create_entry_subtitle),
                lastUsedTime = Instant.now(),
            )
            callback.onResult(BeginCreateCredentialResponse(listOf(entry)))
        } catch (e: Exception) {
            PLog.w(TAG, "create: ${e.message}")
            callback.onError(CreateCredentialUnknownException("Create failed"))
        }
    }

    override fun onBeginGetCredentialRequest(
        request: BeginGetCredentialRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<BeginGetCredentialResponse, GetCredentialException>,
    ) {
        try {
            val options = request.beginGetCredentialOptions
                .filter { it.type == PublicKeyCredential.TYPE_PUBLIC_KEY_CREDENTIAL }
            PLog.d(TAG, "get: options=${options.size}")
            if (options.isEmpty()) {
                callback.onResult(BeginGetCredentialResponse())
                return
            }
            val store = AutofillStore(this)
            val sessionKey = store.loadSessionKey()
            val snapshot = store.loadSnapshot()
            PLog.d(TAG, "get: locked=${sessionKey == null || snapshot == null}")
            if (sessionKey == null || snapshot == null) {
                // Vault locked: offer a single unlock entry; the request stays
                // stashed for the app to complete after the unlock.
                val decodedOptions = options.mapNotNull { decodeOption(it) }
                if (decodedOptions.isEmpty()) {
                    callback.onResult(BeginGetCredentialResponse())
                    return
                }
                store.savePasskeyGetRequests(
                    decodedOptions.map { Triple(it.requestJson, it.clientDataHash, it.rpId) },
                )
                val pending = PendingIntent.getActivity(
                    this,
                    REQ_GET,
                    Intent(this, MainActivity::class.java)
                        .putExtra(MainActivity.EXTRA_PASSKEY_GET, true)
                        .putExtra(MainActivity.EXTRA_AUTOFILL_UNLOCK, true)
                        .setAction("passone.passkey.get"),
                    PendingIntent.FLAG_UPDATE_CURRENT or mutableFlag(),
                )
                val entry = PublicKeyCredentialEntry.Builder(
                    this,
                    getString(R.string.passkey_unlock_title),
                    pending,
                    beginOption(options.first(), decodedOptions.first()),
                )
                    .setIcon(Icon.createWithResource(this, R.mipmap.ic_launcher))
                    .setLastUsedTime(Instant.now())
                    .build()
                callback.onResult(BeginGetCredentialResponse(listOf(entry)))
                return
            }
            val passkeys = decryptSnapshot(sessionKey, snapshot)
            PLog.d(TAG, "get: unlocked, passkeys=${passkeys.size}")
            val entries = mutableListOf<PublicKeyCredentialEntry>()
            val seen = mutableSetOf<String>()
            for (option in options) {
                val decoded = decodeOption(option) ?: continue
                PLog.d(TAG, "get: option rpId=${decoded.rpId}")
                for (pk in passkeys) {
                    if (!seen.add(pk.id)) continue
                    if (pk.rpId != decoded.rpId) continue
                    if (!allowListAllows(decoded.requestJson, pk.id)) continue
                    PLog.d(TAG, "get: matching passkey id=${pk.id} rpId=${pk.rpId}")
                    val intent = Intent(this, PasskeyAuthActivity::class.java)
                        .setAction("passone.passkey.auth")
                        .putExtra(PasskeyAuthActivity.EXTRA_REQUEST_JSON, decoded.requestJson)
                        .putExtra(PasskeyAuthActivity.EXTRA_CLIENT_DATA_HASH, decoded.clientDataHash)
                        .putExtra(PasskeyAuthActivity.EXTRA_PRIVATE_KEY, pk.privateKeyPkcs8)
                        .putExtra(PasskeyAuthActivity.EXTRA_PUBLIC_KEY, pk.publicKeySpki)
                        .putExtra(PasskeyAuthActivity.EXTRA_CREDENTIAL_ID, pk.id)
                        .putExtra(PasskeyAuthActivity.EXTRA_RP_ID, pk.rpId)
                        .putExtra(PasskeyAuthActivity.EXTRA_USER_HANDLE, pk.userHandle)
                    val pending = PendingIntent.getActivity(
                        this,
                        REQ_AUTH,
                        intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or mutableFlag(),
                    )
                    entries.add(
                        PublicKeyCredentialEntry.Builder(
                            this,
                            pk.username,
                            pending,
                            beginOption(option, decoded),
                        )
                            .setIcon(Icon.createWithResource(this, R.mipmap.ic_launcher))
                            .setLastUsedTime(Instant.now())
                            .build(),
                    )
                }
            }
            callback.onResult(BeginGetCredentialResponse(entries))
        } catch (e: Exception) {
            PLog.w(TAG, "get: ${e.message}")
            callback.onError(GetCredentialUnknownException("Get failed"))
        }
    }

    override fun onClearCredentialStateRequest(
        request: androidx.credentials.provider.ProviderClearCredentialStateRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<Void?, ClearCredentialException>,
    ) {
        callback.onResult(null)
    }

    // ---- option decoding -------------------------------------------------

    private class DecodedOption(
        val requestJson: String,
        val clientDataHash: ByteArray,
        val rpId: String,
    )

    private fun decodeOption(option: androidx.credentials.provider.BeginGetCredentialOption): DecodedOption? {
        return try {
            val data = option.candidateQueryData
            val requestJson = data.getString(KEY_REQUEST_JSON)
            if (requestJson.isNullOrBlank()) return null
            var clientDataHash = data.getByteArray(KEY_CLIENT_DATA_HASH)
            PLog.d(
                TAG,
                "decode: keys=${data.keySet()} hashProvided=${clientDataHash != null}",
            )
            if (clientDataHash == null || clientDataHash.all { it == 0.toByte() }) {
                // Platform did not provide the client data hash (native-app
                // flows like Discord). Compute it from the clientDataJSON we
                // will return so the RP can verify the signature.
                clientDataHash = WebAuthn.computedClientDataHashForGet(requestJson)
                PLog.d(
                    TAG,
                    "decode: clientDataHash missing/zero, computed " +
                        "hash=${WebAuthn.b64url(clientDataHash)}",
                )
            }
            val rpId = JSONObject(requestJson).getString("rpId")
            DecodedOption(requestJson, clientDataHash, rpId)
        } catch (e: Exception) {
            null
        }
    }

    private fun beginOption(
        option: androidx.credentials.provider.BeginGetCredentialOption,
        decoded: DecodedOption,
    ): BeginGetPublicKeyCredentialOption =
        BeginGetPublicKeyCredentialOption(
            option.candidateQueryData,
            option.id,
            decoded.requestJson,
            decoded.clientDataHash,
        )

    /** Returns true when the request's allowCredentials list matches [credentialIdB64] or is empty. */
    private fun allowListAllows(requestJson: String, credentialIdB64: String): Boolean {
        return try {
            val allow = JSONObject(requestJson).optJSONArray("allowCredentials") ?: return true
            for (i in 0 until allow.length()) {
                val id = allow.getJSONObject(i).optString("id")
                if (id == credentialIdB64) return true
            }
            false
        } catch (e: Exception) {
            true
        }
    }

    // ---- snapshot --------------------------------------------------------

    private fun decryptSnapshot(sessionKey: ByteArray, blob: ByteArray): List<Passkey> {
        return try {
            val nonce = blob.copyOfRange(0, 12)
            val ct = blob.copyOfRange(12, blob.size)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                SecretKeySpec(sessionKey, "AES"),
                GCMParameterSpec(128, nonce),
            )
            val json = JSONObject(String(cipher.doFinal(ct), Charsets.UTF_8))
            val array = json.optJSONArray("passkeys") ?: JSONArray()
            buildList {
                for (i in 0 until array.length()) {
                    val o = array.getJSONObject(i)
                    val privateKeyB64 = o.optString("privateKey")
                    val credentialId = o.optString("credentialId")
                    if (privateKeyB64.isEmpty() || credentialId.isEmpty()) continue
                    val publicKeyB64 = o.optString("publicKey").ifBlank { null }
                    add(
                        Passkey(
                            id = credentialId,
                            username = o.optString("username"),
                            rpId = o.optString("rpId"),
                            privateKeyPkcs8 = Base64.decode(privateKeyB64, Base64.NO_WRAP),
                            publicKeySpki = publicKeyB64?.let {
                                runCatching { Base64.decode(it, Base64.NO_WRAP) }.getOrNull()
                            },
                            userHandle = o.optString("userHandle").ifBlank { null },
                            counter = o.optInt("counter"),
                        ),
                    )
                }
            }
        } catch (e: Exception) {
            PLog.w(TAG, "decrypt passkeys: ${e.message}")
            emptyList()
        }
    }

    private fun mutableFlag(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE
        } else {
            0
        }
}
