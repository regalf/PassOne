package dev.passone.passone_app

import android.app.PendingIntent
import android.app.assist.AssistStructure
import android.content.Intent
import android.content.IntentSender
import android.os.Build
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveInfo
import android.service.autofill.SaveRequest
import android.util.Log
import android.view.autofill.AutofillId
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.net.URL
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Android Autofill service for PassOne (API 26+).
 *
 * Runs in the app process and reads the encrypted snapshot + session key stored
 * by [AutofillStore]. Credentials are decrypted only when a fill request arrives
 * and the vault is unlocked (session key present); nothing is persisted in
 * plaintext on the device.
 */
class PassAutofillService : AutofillService() {

    private companion object {
        const val TAG = "PassOneAutofill"
        private const val REQ_UNLOCK = 1001
        private const val REQ_AUTH = 1002
    }

    private data class Credential(
        val name: String,
        val username: String,
        val password: String,
        val url: String,
    )

    private class FieldIds {
        var username: AutofillId? = null
        var password: AutofillId? = null
        var webDomain: String? = null
    }

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback,
    ) {
        val store = AutofillStore(this)
        val sessionKey = store.loadSessionKey()
        val snapshot = store.loadSnapshot()
        Log.d(TAG, "fill: id=${request.id} flags=${request.flags} sessionKey=${sessionKey != null} snapshot=${snapshot != null}")
        if (sessionKey == null || snapshot == null) {
            val structure = request.fillContexts.lastOrNull()?.structure
            val ids = structure?.let { collectFields(it) }
            // Vault locked: offer an "unlock" prompt instead of nothing, but only
            // when there is actually a fillable field (never pollute arbitrary
            // fields such as a search bar).
            if (snapshot != null && (ids?.username != null || ids?.password != null)) {
                val target = ids?.username ?: ids?.password!!
                val pending = PendingIntent.getActivity(
                    this,
                    REQ_UNLOCK,
                    Intent(this, MainActivity::class.java)
                        .putExtra(MainActivity.EXTRA_AUTOFILL_UNLOCK, true)
                        .setAction("passone.autofill.unlock"),
                    PendingIntent.FLAG_UPDATE_CURRENT or mutableFlag(),
                )
                val dataset = Dataset.Builder(
                    datasetPresentation(
                        getString(R.string.autofill_locked_title),
                        getString(R.string.autofill_locked_subtitle),
                    ),
                )
                    .setAuthentication(pending.intentSender)
                    // We have no value (vault locked); the framework only needs
                    // the field id to accept the dataset.
                    .setValue(target, null)
                    .build()
                callback.onSuccess(FillResponse.Builder().addDataset(dataset).build())
            } else {
                callback.onSuccess(null)
            }
            return
        }
        val entries = decryptSnapshot(sessionKey, snapshot)
        Log.d(TAG, "fill: snapshot entries=${entries.size}")
        if (entries.isEmpty()) {
            callback.onSuccess(null)
            return
        }

        val structure = request.fillContexts.lastOrNull()?.structure
        val ids = structure?.let { collectFields(it) } ?: FieldIds()
        val usernameId = ids.username
        val passwordId = ids.password
        Log.d(TAG, "fill: usernameId=${usernameId != null} passwordId=${passwordId != null} webDomain=${ids.webDomain}")
        // No fillable field in this structure: nothing we can fill or save.
        if (usernameId == null && passwordId == null) {
            callback.onSuccess(null)
            return
        }
        val manual = (request.flags and FillRequest.FLAG_MANUAL_REQUEST) != 0
        val response = FillResponse.Builder()
        if (usernameId != null || passwordId != null) {
            // Always advertise what should be saved, so the system offers the
            // "Save password?" prompt even when we have no dataset to fill.
            val saveBuilder = SaveInfo.Builder(
                if (usernameId != null) SaveInfo.SAVE_DATA_TYPE_USERNAME else SaveInfo.SAVE_DATA_TYPE_PASSWORD,
                if (usernameId != null) arrayOf(usernameId) else arrayOf(passwordId!!),
            )
            if (usernameId != null && passwordId != null) {
                saveBuilder.setOptionalIds(arrayOf(passwordId))
            }
            response.setSaveInfo(saveBuilder.build())
        }
        val domain = resolveDomain(structure)
        val requireAuth = store.isRequireAuthEnabled()
        val matches = if (manual) entries else entries.filter { matchesEntry(it, domain) }
        Log.d(TAG, "fill: domain=$domain manual=$manual requireAuth=$requireAuth matches=${matches.size}/${entries.size}")
        if (usernameId != null || passwordId != null) {
            for (entry in matches) {
                val title = entry.name.ifBlank { domain ?: "PassOne" }
                val subtitle = entry.username
                val builder = Dataset.Builder(datasetPresentation(title, subtitle))
                if (usernameId != null) {
                    builder.setValue(usernameId, AutofillValue.forText(entry.username))
                }
                if (passwordId != null) {
                    builder.setValue(passwordId, AutofillValue.forText(entry.password))
                }
                if (requireAuth) {
                    builder.setAuthentication(
                        authGate(usernameId, passwordId, entry.username, entry.password),
                    )
                }
                response.addDataset(builder.build())
            }
        }
        callback.onSuccess(response.build())
    }

    /**
     * A biometric gate for datasets, used when "always ask" is enabled. The
     * field ids and values are passed through the intent so the auth activity
     * can return the populated dataset (see AutofillAuthActivity).
     */
    private fun authGate(
        usernameId: AutofillId?,
        passwordId: AutofillId?,
        username: String?,
        password: String?,
    ): IntentSender {
        val intent = Intent(this, AutofillAuthActivity::class.java)
            .setAction("passone.autofill.auth")
        if (usernameId != null) {
            intent.putExtra(AutofillAuthActivity.EXTRA_USERNAME_ID, usernameId)
            intent.putExtra(AutofillAuthActivity.EXTRA_USERNAME, username)
        }
        if (passwordId != null) {
            intent.putExtra(AutofillAuthActivity.EXTRA_PASSWORD_ID, passwordId)
            intent.putExtra(AutofillAuthActivity.EXTRA_PASSWORD, password)
        }
        return PendingIntent.getActivity(
            this,
            REQ_AUTH,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or mutableFlag(),
        ).intentSender
    }

    private fun mutableFlag(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE
        } else {
            0
        }

    /** Two-line presentation: site (title) on top, username (subtitle) below. */
    private fun datasetPresentation(title: String, subtitle: String): RemoteViews {
        val view = RemoteViews(packageName, R.layout.autofill_dataset)
        view.setTextViewText(R.id.autofill_label, title)
        view.setTextViewText(R.id.autofill_subtitle, subtitle)
        return view
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        val structure = request.fillContexts.lastOrNull()?.structure
        val (username, password) = collectValues(structure)
        if (username.isNullOrBlank() || password.isNullOrBlank()) {
            callback.onSuccess()
            return
        }
        val domain = resolveDomain(structure) ?: "passone"
        val store = AutofillStore(this)
        try {
            val clear = store.loadPending()?.let { store.decrypt(it) }
            val array =
                if (clear != null) JSONArray(String(clear, Charsets.UTF_8)) else JSONArray()
            val entry = JSONObject().apply {
                put("id", UUID.randomUUID().toString())
                put("name", domain)
                put("username", username)
                put("password", password)
                put("url", if (domain.startsWith("http")) domain else "https://$domain")
                put("notes", "")
                put("createdAt", System.currentTimeMillis())
                put("updatedAt", System.currentTimeMillis())
            }
            array.put(entry)
            store.savePending(store.encrypt(array.toString().toByteArray(Charsets.UTF_8)))
        } catch (e: Exception) {
            // Never fail the host app because of storage problems.
        }
        callback.onSuccess()
    }

    // ---- snapshot decryption ---------------------------------------------

    /** The snapshot is nonce(12) || AES-GCM ciphertext+tag, keyed with the session key. */
    private fun decryptSnapshot(sessionKey: ByteArray, blob: ByteArray): List<Credential> {
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
            val array = json.optJSONArray("entries") ?: JSONArray()
            buildList {
                for (i in 0 until array.length()) {
                    val o = array.getJSONObject(i)
                    val username = o.optString("username")
                    val password = o.optString("password")
                    if (username.isNotEmpty() && password.isNotEmpty()) {
                        add(
                            Credential(
                                name = o.optString("name"),
                                username = username,
                                password = password,
                                url = o.optString("url"),
                            ),
                        )
                    }
                }
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    // ---- structure inspection --------------------------------------------

    /** The package of the app being filled (from the activity component). */
    private fun packageOf(structure: AssistStructure?): String? =
        structure?.activityComponent?.packageName

    private fun collectFields(structure: AssistStructure): FieldIds {
        val ids = FieldIds()
        for (i in 0 until structure.windowNodeCount) {
            walk(structure.getWindowNodeAt(i).rootViewNode, ids)
        }
        return ids
    }

    private fun walk(node: AssistStructure.ViewNode, ids: FieldIds) {
        val id = node.autofillId
        val hints = node.autofillHints
        val text = node.text?.toString()?.trim()
        if (id != null && hints != null) {
            for (hint in hints) {
                val h = hint.lowercase()
                when {
                    ids.username == null && (h.contains("username") || h == "emailaddress" || h.contains("email")) ->
                        ids.username = id
                    h.contains("password") && ids.password == null -> ids.password = id
                }
            }
        }
        // Browsers expose the page domain on any node via getWebDomain().
        if (ids.webDomain.isNullOrBlank() && !node.webDomain.isNullOrBlank()) {
            ids.webDomain = node.webDomain
        }
        // Fallback for webviews that carry the URL in the node text instead.
        if (ids.webDomain == null && text != null && text.contains("://")) {
            ids.webDomain = text
        }
        for (i in 0 until node.childCount) {
            walk(node.getChildAt(i), ids)
        }
    }

    /** Returns (username, password) values found in the structure (save flow). */
    private fun collectValues(structure: AssistStructure?): Pair<String?, String?> {
        if (structure == null) return null to null
        var username: String? = null
        var password: String? = null
        fun walkValues(node: AssistStructure.ViewNode) {
            val value = node.text?.toString()
            val hints = node.autofillHints
            if (hints != null && value != null) {
                for (hint in hints) {
                    val h = hint.lowercase()
                    if (username == null && (h.contains("username") || h == "emailaddress" || h.contains("email")) && value.isNotBlank()) {
                        username = value
                    } else if (h.contains("password") && password == null && value.isNotBlank()) {
                        password = value
                    }
                }
            }
            for (i in 0 until node.childCount) {
                walkValues(node.getChildAt(i))
            }
        }
        for (i in 0 until structure.windowNodeCount) {
            walkValues(structure.getWindowNodeAt(i).rootViewNode)
        }
        return username to password
    }

    // ---- matching ---------------------------------------------------------

    private fun resolveDomain(structure: AssistStructure?): String? {
        val web = structure?.let { collectFields(it).webDomain }
        if (web != null) {
            hostOf(web)?.let { return it }
            // getWebDomain() usually carries the bare host (no scheme).
            if (web.isNotBlank() && !web.contains(" ")) return web.lowercase()
        }
        return domainFromPackage(packageOf(structure))
    }

    private fun hostOf(url: String): String? = try {
        URL(url).host?.lowercase()
    } catch (e: Exception) {
        null
    }

    /** Best-effort domain from an app package, e.g. com.instagram.android -> instagram. */
    private fun domainFromPackage(packageName: String?): String? {
        if (packageName.isNullOrBlank()) return null
        val generic = setOf("com", "org", "net", "io", "app", "dev", "me", "android", "google")
        return packageName.split(".")
            .firstOrNull { it !in generic && it.isNotBlank() && it.length > 2 }
            ?.lowercase()
    }

    private fun matchesEntry(entry: Credential, domain: String?): Boolean {
        val d = domain ?: return false
        val host = hostOf(entry.url) ?: return false
        val hostL = host.removePrefix("www.")
        val dL = d.removePrefix("www.")
        return hostL == dL ||
            hostL.endsWith(".$dL") ||
            dL.endsWith(".$hostL") ||
            hostL.contains(".$dL") ||
            dL.contains(".$hostL")
    }
}
