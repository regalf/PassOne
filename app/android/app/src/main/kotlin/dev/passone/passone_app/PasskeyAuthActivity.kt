package dev.passone.passone_app

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.service.credentials.CredentialProviderService
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.credentials.PublicKeyCredential
import androidx.fragment.app.FragmentActivity

/**
 * Authentication + signing gate for passkey assertions (get flow) when the
 * vault is unlocked. Shows a system biometric prompt and, on success, signs
 * the assertion with the stored key and returns it to the Credential Manager
 * framework via [CredentialProviderService.EXTRA_GET_CREDENTIAL_RESPONSE].
 */
class PasskeyAuthActivity : FragmentActivity() {

    companion object {
        const val EXTRA_REQUEST_JSON = "passone.passkey.request_json"
        const val EXTRA_CLIENT_DATA_HASH = "passone.passkey.client_data_hash"
        const val EXTRA_PRIVATE_KEY = "passone.passkey.private_key"
        const val EXTRA_PUBLIC_KEY = "passone.passkey.public_key"
        const val EXTRA_CREDENTIAL_ID = "passone.passkey.credential_id"
        const val EXTRA_RP_ID = "passone.passkey.rp_id"
        const val EXTRA_USER_HANDLE = "passone.passkey.user_handle"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        PLog.d("PassOnePasskey", "auth: onCreate rpId=${intent.getStringExtra(EXTRA_RP_ID)}")
        try {
            val prompt = BiometricPrompt(
                this,
                ContextCompat.getMainExecutor(this),
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                        PLog.d("PassOnePasskey", "auth: biometric succeeded")
                        signAndFinish()
                    }

                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                        PLog.d("PassOnePasskey", "auth: biometric error $errorCode $errString")
                        setResult(Activity.RESULT_CANCELED)
                        finish()
                    }

                    override fun onAuthenticationFailed() {
                        // Wrong finger: the user can retry or cancel via the dialog.
                        PLog.d("PassOnePasskey", "auth: biometric failed (retry)")
                    }
                },
            )
            prompt.authenticate(
                BiometricPrompt.PromptInfo.Builder()
                    .setTitle(getString(R.string.passkey_auth_title))
                    .setSubtitle(getString(R.string.passkey_auth_subtitle))
                    .setNegativeButtonText(getString(R.string.passkey_auth_cancel))
                    .build(),
            )
        } catch (e: Exception) {
            PLog.w("PassOnePasskey", "Biometric gate unavailable: ${e.message}")
            setResult(Activity.RESULT_CANCELED)
            finish()
        }
    }

    private fun signAndFinish() {
        try {
            val requestJson = intent.getStringExtra(EXTRA_REQUEST_JSON)
                ?: throw IllegalStateException("missing request JSON")
            val clientDataHash = intent.getByteArrayExtra(EXTRA_CLIENT_DATA_HASH)
                ?: ByteArray(32)
            val privateKey = intent.getByteArrayExtra(EXTRA_PRIVATE_KEY)
                ?: throw IllegalStateException("missing private key")
            val credentialId =
                WebAuthn.b64urlDecode(requireNotNull(intent.getStringExtra(EXTRA_CREDENTIAL_ID)))
            val publicKeySpki = intent.getByteArrayExtra(EXTRA_PUBLIC_KEY)
            val rpId = intent.getStringExtra(EXTRA_RP_ID)
                ?: throw IllegalStateException("missing rpId")
            val userHandle = intent.getStringExtra(EXTRA_USER_HANDLE)
            PLog.d("PassOnePasskey", "auth: requestJson=$requestJson")
            PLog.d("PassOnePasskey", "auth: clientDataHash=${WebAuthn.b64url(clientDataHash)}")
            val responseJson = WebAuthn.createAssertionResponse(
                requestJson = requestJson,
                clientDataHash = clientDataHash,
                privateKeyPkcs8 = privateKey,
                credentialId = credentialId,
                rpId = rpId,
                userHandle = userHandle,
                counter = 0,
            )
            PLog.d("PassOnePasskey", "auth: signed assertion ok")
            PLog.d("PassOnePasskey", "auth: responseJson=$responseJson")
            if (publicKeySpki != null) {
                PLog.d(
                    "PassOnePasskey",
                    "auth: storedSpkiHash=${WebAuthn.publicKeyHash(publicKeySpki)}",
                )
                PLog.d(
                    "PassOnePasskey",
                    "auth: selfVerifyWithStoredSpki=${WebAuthn.verifyAssertion(responseJson, clientDataHash, publicKeySpki)}",
                )
            } else {
                PLog.w("PassOnePasskey", "auth: no stored SPKI in snapshot, skipping self-verify")
            }
            val credential = PublicKeyCredential(responseJson)
            val result = android.credentials.GetCredentialResponse(
                android.credentials.Credential(
                    PublicKeyCredential.TYPE_PUBLIC_KEY_CREDENTIAL,
                    credential.data,
                ),
            )
            val data = Intent().putExtra(
                CredentialProviderService.EXTRA_GET_CREDENTIAL_RESPONSE,
                result,
            )
            setResult(Activity.RESULT_OK, data)
        } catch (e: Exception) {
            PLog.w("PassOnePasskey", "auth: sign failed: ${e.message}")
            setResult(Activity.RESULT_CANCELED)
        }
        finish()
    }
}
