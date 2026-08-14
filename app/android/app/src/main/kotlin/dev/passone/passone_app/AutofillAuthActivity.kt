package dev.passone.passone_app

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.service.autofill.Dataset
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity

/**
 * Authentication gate used by the autofill datasets when "always ask" is
 * enabled. It shows a system biometric prompt and, on success, returns the
 * populated [Dataset] via [AutofillManager.EXTRA_AUTHENTICATION_RESULT]: the
 * framework then fills the selected fields immediately. `RESULT_OK` without the
 * dataset would leave the fields untouched (the dataset replaces the original
 * one, whose values the framework does not fill on its own).
 */
class AutofillAuthActivity : FragmentActivity() {

    companion object {
        const val EXTRA_USERNAME_ID = "passone.autofill.username_id"
        const val EXTRA_USERNAME = "passone.autofill.username"
        const val EXTRA_PASSWORD_ID = "passone.autofill.password_id"
        const val EXTRA_PASSWORD = "passone.autofill.password"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val prompt = BiometricPrompt(
                this,
                ContextCompat.getMainExecutor(this),
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                        finishAuthenticated()
                    }

                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                        setResult(Activity.RESULT_CANCELED)
                        finish()
                    }

                    override fun onAuthenticationFailed() {
                        // Wrong finger: the user can retry or cancel via the dialog.
                    }
                },
            )
            prompt.authenticate(
                BiometricPrompt.PromptInfo.Builder()
                    .setTitle(getString(R.string.autofill_auth_title))
                    .setSubtitle(getString(R.string.autofill_auth_subtitle))
                    .setNegativeButtonText(getString(R.string.autofill_auth_cancel))
                    .build(),
            )
        } catch (e: Exception) {
            PLog.w("PassOneAutofill", "Biometric gate unavailable: ${e.message}")
            setResult(Activity.RESULT_CANCELED)
            finish()
        }
    }

    private fun finishAuthenticated() {
        val usernameId = parcelable(EXTRA_USERNAME_ID)
        val passwordId = parcelable(EXTRA_PASSWORD_ID)
        val username = intent.getStringExtra(EXTRA_USERNAME)
        val password = intent.getStringExtra(EXTRA_PASSWORD)
        val builder = Dataset.Builder()
        if (usernameId != null && username != null) {
            builder.setValue(usernameId, AutofillValue.forText(username))
        }
        if (passwordId != null && password != null) {
            builder.setValue(passwordId, AutofillValue.forText(password))
        }
        val data = Intent()
        data.putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, builder.build())
        setResult(Activity.RESULT_OK, data)
        finish()
    }

    private fun parcelable(name: String): AutofillId? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(name, AutofillId::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(name)
        }
}
