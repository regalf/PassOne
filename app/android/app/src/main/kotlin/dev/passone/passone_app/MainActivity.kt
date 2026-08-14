package dev.passone.passone_app

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.provider.Settings
import android.service.credentials.CredentialProviderService
import android.view.WindowManager
import androidx.credentials.CreatePublicKeyCredentialResponse
import androidx.credentials.PublicKeyCredential
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterFragmentActivity() {
    private val channel = "passone/save_file"
    private var pendingBytes: ByteArray? = null
    private var pendingResult: Result? = null
    private var pendingExtension: String? = null

    /// True when this instance was launched by the autofill flow ("vault
    /// locked" prompt) to unlock the vault and return to the host app.
    private var autofillUnlockLaunch = false

    /// True when launched by the Credential Manager to register a passkey.
    private var passkeyCreateLaunch = false

    /// True when launched by the Credential Manager to authenticate a passkey
    /// while the vault was locked.
    private var passkeyGetLaunch = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        readLaunchFlags()
        // Block screenshots, screen recordings and the app-switcher preview
        // for the whole app (same behaviour as Bitwarden and other password
        // managers).
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readLaunchFlags()
    }

    private fun readLaunchFlags() {
        autofillUnlockLaunch = intent.getBooleanExtra(EXTRA_AUTOFILL_UNLOCK, false)
        passkeyCreateLaunch = intent.getBooleanExtra(EXTRA_PASSKEY_CREATE, false)
        passkeyGetLaunch = intent.getBooleanExtra(EXTRA_PASSKEY_GET, false)
        PLog.d("PassOnePasskey", "readLaunchFlags: unlock=$autofillUnlockLaunch create=$passkeyCreateLaunch get=$passkeyGetLaunch")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveFile" -> {
                        val name = call.argument<String>("suggestedName") ?: "export"
                        val mime = call.argument<String>("mimeType") ?: "application/octet-stream"
                        val extension = call.argument<String>("extension")
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes == null) {
                            result.error("no_bytes", "No content to save", null)
                            return@setMethodCallHandler
                        }
                        pendingBytes = bytes
                        pendingResult = result
                        pendingExtension = extension
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = mime
                            putExtra(Intent.EXTRA_TITLE, name)
                        }
                        startActivityForResult(intent, REQUEST_SAVE_FILE)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "passone/autofill")
            .setMethodCallHandler { call, result ->
                val store = AutofillStore(this)
                when (call.method) {
                    "setSessionKey" -> {
                        val key = call.argument<String>("key")
                        if (key == null) result.error("bad_key", "Missing key", null)
                        else {
                            store.setSessionKey(key)
                            result.success(null)
                        }
                    }
                    "clearSessionKey" -> {
                        store.clearSessionKey()
                        result.success(null)
                    }
                    "syncSnapshot" -> {
                        val blob = call.argument<String>("blob")
                        if (blob == null) result.error("bad_blob", "Missing blob", null)
                        else {
                            store.saveSnapshot(blob)
                            result.success(null)
                        }
                    }
                    "pullPendingSaves" -> {
                        val raw = store.loadPending()
                        val list: List<Any> = if (raw == null) emptyList() else {
                            val clear = store.decrypt(raw)
                            if (clear == null) {
                                emptyList()
                            } else {
                                val array = JSONArray(String(clear, Charsets.UTF_8))
                                (0 until array.length()).map { i ->
                                    val o = array.getJSONObject(i)
                                    mapOf(
                                        "id" to o.optString("id"),
                                        "name" to o.optString("name"),
                                        "username" to o.optString("username"),
                                        "password" to o.optString("password"),
                                        "url" to o.optString("url"),
                                        "notes" to o.optString("notes"),
                                        "createdAt" to o.optLong("createdAt"),
                                        "updatedAt" to o.optLong("updatedAt"),
                                    )
                                }
                            }
                        }
                        result.success(list)
                    }
                    "confirmPendingSaves" -> {
                        store.clearPending()
                        result.success(null)
                    }
                    "isEnabled" -> result.success(isAutofillServiceEnabled())
                    "setRequireAuth" -> {
                        store.setRequireAuth(call.argument<Boolean>("enabled") == true)
                        result.success(null)
                    }
                    "getRequireAuth" -> result.success(store.isRequireAuthEnabled())
                    "autofillUnlockFinished" -> {
                        // The user just unlocked the vault from the autofill
                        // "vault locked" prompt: return to the host app. For
                        // passkey launches the finish is deferred: the app
                        // drives the create/get flow and returns the credential
                        // result explicitly (passkeyCreateDone / passkeyGetDone).
                        if (autofillUnlockLaunch && !passkeyCreateLaunch && !passkeyGetLaunch) {
                            setResult(Activity.RESULT_OK)
                            finish()
                        }
                        result.success(null)
                    }
                    "getPasskeyLaunch" -> result.success(
                        when {
                            passkeyCreateLaunch -> "create"
                            passkeyGetLaunch -> "get"
                            autofillUnlockLaunch -> "unlock"
                            else -> "none"
                        },
                    )
                    "takePendingPasskeyCreate" -> {
                        val raw = store.getPasskeyCreateRequest()
                        PLog.d("PassOnePasskey", "takePendingPasskeyCreate: present=${raw != null}")
                        if (raw == null) {
                            result.success(null)
                        } else {
                            val req = JSONObject(raw)
                            val rp = req.optJSONObject("rp")
                            val user = req.optJSONObject("user")
                            result.success(
                                mapOf(
                                    "requestJson" to raw,
                                    "rpId" to (rp?.optString("id") ?: ""),
                                    "rpName" to (rp?.optString("name") ?: ""),
                                    "userName" to (user?.optString("name") ?: ""),
                                    "userDisplayName" to (user?.optString("displayName")
                                        ?: user?.optString("name") ?: ""),
                                    "userHandle" to (user?.optString("id") ?: ""),
                                ),
                            )
                        }
                    }
                    "takePendingPasskeyGet" -> {
                        val requests = store.getPasskeyGetRequests()
                        PLog.d("PassOnePasskey", "takePendingPasskeyGet: count=${requests.size}")
                        if (requests.isEmpty()) {
                            result.success(null)
                        } else {
                            val first = requests.first()
                            result.success(
                                mapOf(
                                    "requestJson" to first.first,
                                    "clientDataHash" to WebAuthn.b64url(first.second),
                                    "rpId" to first.third,
                                ),
                            )
                        }
                    }
                    "passkeyCreateGenerate" -> {
                        val requestJson = call.argument<String>("requestJson")
                        val username = call.argument<String>("username")
                        val userHandle = call.argument<String>("userHandle")
                        if (requestJson == null || username == null) {
                            result.error("bad_args", "Missing create arguments", null)
                        } else {
                            try {
                                val req = JSONObject(requestJson)
                                val rpId = req.getJSONObject("rp").getString("id")
                                val outcome = WebAuthn.createKeyAndResponse(
                                    requestJson,
                                    rpId,
                                    username,
                                    userHandle ?: "",
                                )
                                PLog.d("PassOnePasskey", "createGenerate: credentialId=${outcome.credentialIdB64.take(16)} rpId=$rpId")
                                result.success(
                                    mapOf(
                                        "credentialId" to outcome.credentialIdB64,
                                        "privateKeyPkcs8" to outcome.privateKeyPkcs8B64,
                                        "publicKeySpki" to outcome.publicKeySpkiB64,
                                        "responseJson" to outcome.responseJson,
                                        "rpId" to rpId,
                                    ),
                                )
                            } catch (e: Exception) {
                                result.error("generate_failed", e.message, null)
                            }
                        }
                    }
                    "passkeyCreateDone" -> {
                        store.clearPasskeyCreateRequest()
                        val responseJson = call.argument<String>("responseJson")
                        PLog.d("PassOnePasskey", "passkeyCreateDone: launch=$passkeyCreateLaunch response=${responseJson != null}")
                        if (passkeyCreateLaunch && responseJson != null) {
                            val data = Intent().putExtra(
                                CredentialProviderService.EXTRA_CREATE_CREDENTIAL_RESPONSE,
                                android.credentials.CreateCredentialResponse(
                                    CreatePublicKeyCredentialResponse(responseJson).data,
                                ),
                            )
                            setResult(Activity.RESULT_OK, data)
                            finish()
                        } else if (passkeyCreateLaunch) {
                            setResult(Activity.RESULT_CANCELED)
                            finish()
                        }
                        result.success(null)
                    }
                    "passkeyCreateCancel" -> {
                        store.clearPasskeyCreateRequest()
                        if (passkeyCreateLaunch) {
                            setResult(Activity.RESULT_CANCELED)
                            finish()
                        }
                        result.success(null)
                    }
                    "passkeyGetDone" -> {
                        store.clearPasskeyGetRequest()
                        PLog.d("PassOnePasskey", "passkeyGetDone: launch=$passkeyGetLaunch")
                        try {
                            val requestJson = call.argument<String>("requestJson")
                            val clientDataHash = call.argument<String>("clientDataHash")
                            val privateKey = call.argument<String>("privateKey")
                            val credentialId = call.argument<String>("credentialId")
                            val rpId = call.argument<String>("rpId")
                            val userHandle = call.argument<String>("userHandle")
                            val publicKey = call.argument<String>("publicKey")
                            if (requestJson == null || clientDataHash == null ||
                                privateKey == null || credentialId == null || rpId == null
                            ) {
                                result.error("bad_args", "Missing get arguments", null)
                            } else {
                                val clientDataHashBytes = WebAuthn.b64urlDecode(clientDataHash)
                                val responseJson = WebAuthn.createAssertionResponse(
                                    requestJson = requestJson,
                                    clientDataHash = clientDataHashBytes,
                                    privateKeyPkcs8 = android.util.Base64.decode(
                                        privateKey,
                                        android.util.Base64.NO_WRAP,
                                    ),
                                    credentialId = WebAuthn.b64urlDecode(credentialId),
                                    rpId = rpId,
                                    userHandle = userHandle,
                                    counter = 0,
                                )
                                PLog.d("PassOnePasskey", "getDone: credentialId=$credentialId")
                                PLog.d("PassOnePasskey", "getDone: clientDataHash=$clientDataHash")
                                PLog.d("PassOnePasskey", "getDone: responseJson=$responseJson")
                                if (publicKey != null) {
                                    val spki = android.util.Base64.decode(
                                        publicKey,
                                        android.util.Base64.NO_WRAP,
                                    )
                                    PLog.d(
                                        "PassOnePasskey",
                                        "getDone: storedSpkiHash=${WebAuthn.publicKeyHash(spki)}",
                                    )
                                    PLog.d(
                                        "PassOnePasskey",
                                        "getDone: selfVerifyWithStoredSpki=${WebAuthn.verifyAssertion(responseJson, clientDataHashBytes, spki)}",
                                    )
                                } else {
                                    PLog.w("PassOnePasskey", "getDone: no stored SPKI, skipping self-verify")
                                }
                                if (passkeyGetLaunch) {
                                    val credential = PublicKeyCredential(responseJson)
                                    val data = Intent().putExtra(
                                        CredentialProviderService.EXTRA_GET_CREDENTIAL_RESPONSE,
                                        android.credentials.GetCredentialResponse(
                                            android.credentials.Credential(
                                                PublicKeyCredential.TYPE_PUBLIC_KEY_CREDENTIAL,
                                                credential.data,
                                            ),
                                        ),
                                    )
                                    setResult(Activity.RESULT_OK, data)
                                    finish()
                                }
                                result.success(null)
                            }
                        } catch (e: Exception) {
                            result.error("sign_failed", e.message, null)
                        }
                    }
                    "passkeyGetCancel" -> {
                        store.clearPasskeyGetRequest()
                        if (passkeyGetLaunch) {
                            setResult(Activity.RESULT_CANCELED)
                            finish()
                        }
                        result.success(null)
                    }
                    "openSettings" -> {
                        try {
                            startActivity(
                                Intent(Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE).apply {
                                    data = Uri.parse("package:$packageName")
                                },
                            )
                        } catch (e: Exception) {
                            // Some OEMs block the request intent; open the general
                            // accessibility/autofill settings screen instead.
                            runCatching {
                                startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// True when PassOne is the active system autofill service.
    private fun isAutofillServiceEnabled(): Boolean {
        val component = ComponentName(this, PassAutofillService::class.java).flattenToString()
        // Settings.Secure.AUTOFILL_SERVICE is a hidden constant: use the literal.
        val current = Settings.Secure.getString(contentResolver, "autofill_service")
        return current?.split(":")?.any { it.equals(component, ignoreCase = true) } == true
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_SAVE_FILE) return
        val res = pendingResult
        pendingResult = null
        val bytes = pendingBytes
        pendingBytes = null
        val extension = pendingExtension
        pendingExtension = null
        if (resultCode == Activity.RESULT_OK && data?.data != null && bytes != null) {
            val uri: Uri = data.data!!
            try {
                contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                ensureExtension(uri, extension)
                res?.success(displayName(uri) ?: uri.lastPathSegment)
            } catch (e: Exception) {
                res?.error("write_failed", e.message, null)
            }
        } else {
            res?.success(null) // user cancelled
        }
    }

    /// Appends the expected dot-extension to the file name when missing, so
    /// exports always keep a proper extension even if the user typed a name
    /// without one in the save dialog.
    private fun ensureExtension(uri: Uri, extension: String?) {
        if (extension.isNullOrEmpty()) return
        val name = displayName(uri) ?: return
        if (name.endsWith(".$extension", ignoreCase = true)) return
        try {
            DocumentsContract.renameDocument(
                contentResolver,
                uri,
                "$name.$extension",
            )
        } catch (e: Exception) {
            // Some providers do not support renaming: keep the file as-is.
        }
    }

    private fun displayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
        } catch (e: Exception) {
            null
        }
    }

    companion object {
        private const val REQUEST_SAVE_FILE = 4410

        /// Intent extra set by the autofill service when launching the app to
        /// unlock the vault from the "vault locked" autofill prompt.
        const val EXTRA_AUTOFILL_UNLOCK = "passone.autofill_unlock"

        /// Set by the Credential Manager provider when launching the app to
        /// register a passkey (see PasskeyProviderService).
        const val EXTRA_PASSKEY_CREATE = "passone.passkey_create"

        /// Set by the Credential Manager provider when launching the app to
        /// authenticate a passkey while the vault was locked.
        const val EXTRA_PASSKEY_GET = "passone.passkey_get"
    }
}
