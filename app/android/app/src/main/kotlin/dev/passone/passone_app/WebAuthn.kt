package dev.passone.passone_app

import android.util.Base64
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.PublicKey
import java.math.BigInteger
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import org.json.JSONArray
import org.json.JSONObject

/**
 * WebAuthn (passkey) primitives implemented natively.
 *
 * All the public-key crypto lives here in Kotlin: `package:cryptography`'s
 * `Ecdsa.p256()` throws `UnimplementedError` on the Flutter VM, so no
 * WebAuthn operation can run in Dart. Keys are generated with
 * `KeyPairGenerator` (EC P-256), the COSE public key and the attestation
 * object are hand-encoded with a minimal CBOR writer, and the ECDSA signature
 * is converted from DER to the raw r||s form WebAuthn expects.
 */
object WebAuthn {

    private const val EC_CURVE = "secp256r1"

    // ---- encoding helpers ------------------------------------------------

    /** Base64url without padding (the form WebAuthn JSON uses). */
    fun b64url(bytes: ByteArray): String =
        Base64.encodeToString(bytes, Base64.NO_WRAP or Base64.URL_SAFE or Base64.NO_PADDING)

    fun b64urlDecode(s: String): ByteArray =
        Base64.decode(s, Base64.NO_WRAP or Base64.URL_SAFE or Base64.NO_PADDING)

    private fun b64(bytes: ByteArray): String =
        Base64.encodeToString(bytes, Base64.NO_WRAP)

    private fun sha256(data: ByteArray): ByteArray =
        MessageDigest.getInstance("SHA-256").digest(data)

    // ---- key handling ----------------------------------------------------

    fun generateKeyPair(): KeyPair {
        val gen = KeyPairGenerator.getInstance("EC")
        gen.initialize(ECGenParameterSpec(EC_CURVE))
        return gen.generateKeyPair()
    }

    fun privateKeyToPkcs8(privateKey: PrivateKey): ByteArray = privateKey.encoded

    fun publicKeyToSpki(publicKey: PublicKey): ByteArray = publicKey.encoded

    fun privateKeyFromPkcs8(pkcs8: ByteArray): PrivateKey =
        KeyFactory.getInstance("EC").generatePrivate(PKCS8EncodedKeySpec(pkcs8))

    /** Stable credential id: SHA-256 of the SPKI public key, base64url-encoded. */
    fun credentialId(publicKey: PublicKey): ByteArray = sha256(publicKey.encoded)

    // ---- CBOR ------------------------------------------------------------

    private fun cborUInt(major: Int, value: Long): ByteArray = when {
        value < 24 -> byteArrayOf((major shl 5 or value.toInt()).toByte())
        value < 0x100 -> byteArrayOf((major shl 5 or 24).toByte(), value.toByte())
        value < 0x10000 -> byteArrayOf(
            (major shl 5 or 25).toByte(),
            (value shr 8).toByte(),
            value.toByte(),
        )
        value < 0x100000000L -> byteArrayOf(
            (major shl 5 or 26).toByte(),
            (value shr 24).toByte(),
            (value shr 16).toByte(),
            (value shr 8).toByte(),
            value.toByte(),
        )
        else -> byteArrayOf(
            (major shl 5 or 27).toByte(),
            (value shr 56).toByte(),
            (value shr 48).toByte(),
            (value shr 40).toByte(),
            (value shr 32).toByte(),
            (value shr 24).toByte(),
            (value shr 16).toByte(),
            (value shr 8).toByte(),
            value.toByte(),
        )
    }

    /** Major type 0 for non-negative values, major type 1 for negative ones. */
    private fun cborInt(value: Long): ByteArray =
        if (value < 0) cborUInt(1, -1 - value) else cborUInt(0, value)

    private fun cborText(s: String): ByteArray {
        val bytes = s.toByteArray(Charsets.UTF_8)
        return cborUInt(3, bytes.size.toLong()) + bytes
    }

    private fun cborBytes(bytes: ByteArray): ByteArray =
        cborUInt(2, bytes.size.toLong()) + bytes

    private fun cborArray(items: List<ByteArray>): ByteArray =
        cborUInt(4, items.size.toLong()) + items.reduce { acc, it -> acc + it }

    /** Map with int/text keys and int/text/bytes values (enough for COSE and attestation). */
    private fun cborMap(entries: List<Pair<ByteArray, ByteArray>>): ByteArray {
        val head = cborUInt(5, entries.size.toLong())
        val body = entries.fold(ByteArray(0)) { acc, (k, v) -> acc + k + v }
        return head + body
    }

    /** COSE_Key (kty=2 EC2, crv=1 P-256, alg=-7 ES256) from an EC public key. */
    private fun coseKey(publicKey: PublicKey): ByteArray {
        val ec = publicKey as ECPublicKey
        val x = fixSize(ec.w.affineX.toByteArray(), 32)
        val y = fixSize(ec.w.affineY.toByteArray(), 32)
        return cborMap(
            listOf(
                cborInt(1) to cborInt(2), // kty: EC2
                cborInt(3) to cborInt(-7), // alg: ES256
                cborInt(-1) to cborInt(1), // crv: P-256
                cborInt(-2) to cborBytes(x),
                cborInt(-3) to cborBytes(y),
            ),
        )
    }

    /** Trims/pads a big-endian integer (e.g. a coordinate or DER r/s) to [size] bytes. */
    private fun fixSize(bytes: ByteArray, size: Int): ByteArray {
        if (bytes.size == size) return bytes
        val out = ByteArray(size)
        if (bytes.size > size) {
            bytes.copyInto(out, 0, bytes.size - size, bytes.size)
        } else {
            bytes.copyInto(out, size - bytes.size)
        }
        return out
    }

    // ---- authenticator data ----------------------------------------------

    /**
     * Create request authenticator data:
     * rpIdHash(32) || flags(0x45 = UP|UV|AT) || counter(4, 0) || AAGUID(16, zero) ||
     * credIdLen(2) || credentialId || COSE public key.
     */
    private fun buildCreateAuthData(
        rpIdHash: ByteArray,
        credentialId: ByteArray,
        publicKey: PublicKey,
    ): ByteArray {
        val cose = coseKey(publicKey)
        val out = ByteArray(55 + credentialId.size + cose.size)
        rpIdHash.copyInto(out, 0)
        out[32] = 0x45
        // counter (33-36) and AAGUID (37-52) stay zero
        out[53] = (credentialId.size shr 8).toByte()
        out[54] = credentialId.size.toByte()
        credentialId.copyInto(out, 55)
        cose.copyInto(out, 55 + credentialId.size)
        return out
    }

    /** Get request authenticator data: rpIdHash(32) || flags(0x05 = UP|UV) || counter(4). */
    private fun buildGetAuthData(rpIdHash: ByteArray, counter: Int): ByteArray {
        val out = ByteArray(37)
        rpIdHash.copyInto(out, 0)
        out[32] = 0x05
        out[33] = (counter shr 24).toByte()
        out[34] = (counter shr 16).toByte()
        out[35] = (counter shr 8).toByte()
        out[36] = counter.toByte()
        return out
    }

    private fun clientDataJSON(type: String, challenge: String, origin: String): ByteArray =
        JSONObject()
            .put("type", type)
            .put("challenge", challenge)
            .put("origin", origin)
            .put("crossOrigin", false)
            .toString()
            .toByteArray(Charsets.UTF_8)

    // ---- create ----------------------------------------------------------

    data class CreateOutcome(
        val credentialId: ByteArray,
        val credentialIdB64: String,
        val privateKeyPkcs8B64: String,
        val publicKeySpkiB64: String,
        val responseJson: String,
    )

    /** Generates a new key pair and builds the registration ("none") response. */
    fun createKeyAndResponse(
        requestJson: String,
        rpId: String,
        username: String,
        userHandle: String,
    ): CreateOutcome {
        val req = JSONObject(requestJson)
        val challenge = req.getString("challenge")
        val origin = req.optString("origin").ifBlank { "https://$rpId" }
        val keyPair = generateKeyPair()
        val id = credentialId(keyPair.public)
        val authData = buildCreateAuthData(sha256(rpId.toByteArray(Charsets.UTF_8)), id, keyPair.public)
        // attestationObject = CBOR map {fmt, attStmt, authData} (none attestation)
        val attestationObject = cborMap(
            listOf(
                cborText("fmt") to cborText("none"),
                cborText("attStmt") to cborMap(emptyList()),
                cborText("authData") to cborBytes(authData),
            ),
        )
        val clientData = clientDataJSON("webauthn.create", challenge, origin)
        val response = JSONObject()
            .put("id", b64url(id))
            .put("rawId", b64url(id))
            .put("type", "public-key")
            .put(
                "response",
                JSONObject()
                    .put("clientDataJSON", b64url(clientData))
                    .put("attestationObject", b64url(attestationObject))
                    .put("authenticatorData", b64url(authData))
                    .put("publicKeyAlgorithm", -7)
                    .put("publicKey", b64url(keyPair.public.encoded))
                    .put("transports", JSONArray().put("internal")),
            )
            .put("clientExtensionResults", JSONObject())
        return CreateOutcome(
            credentialId = id,
            credentialIdB64 = b64url(id),
            privateKeyPkcs8B64 = b64(keyPair.private.encoded),
            publicKeySpkiB64 = b64(keyPair.public.encoded),
            responseJson = response.toString(),
        )
    }

    // ---- assertion (get) -------------------------------------------------

    /**
     * Builds the authentication response. [clientDataHash] is the SHA-256 of the
     * clientDataJSON computed by the platform (Chrome): the signature covers
     * authenticatorData || clientDataHash.
     */
    fun createAssertionResponse(
        requestJson: String,
        clientDataHash: ByteArray,
        privateKeyPkcs8: ByteArray,
        credentialId: ByteArray,
        rpId: String,
        userHandle: String?,
        counter: Int,
    ): String {
        val req = JSONObject(requestJson)
        val challenge = req.getString("challenge")
        val origin = req.optString("origin").ifBlank { "https://$rpId" }
        val authData = buildGetAuthData(sha256(rpId.toByteArray(Charsets.UTF_8)), counter)
        val clientData = clientDataJSON("webauthn.get", challenge, origin)
        val signer = Signature.getInstance("SHA256withECDSA").apply {
            initSign(privateKeyFromPkcs8(privateKeyPkcs8))
            update(authData)
            update(clientDataHash)
        }
        val signature = rawToDer(derToRaw(signer.sign()))
        val response = JSONObject()
            .put("id", b64url(credentialId))
            .put("rawId", b64url(credentialId))
            .put("type", "public-key")
            .put(
                "response",
                JSONObject()
                    .put("authenticatorData", b64url(authData))
                    .put("clientDataJSON", b64url(clientData))
                    .put("signature", b64url(signature))
                    .apply { if (userHandle != null) put("userHandle", userHandle) },
            )
            .put("clientExtensionResults", JSONObject())
        return response.toString()
    }

    /** Base64url SHA-256 of a SPKI public key (equals the credential id when consistent). */
    fun publicKeyHash(spki: ByteArray): String = b64url(sha256(spki))

    /**
     * Re-verifies an assertion we built: the signature must verify over
     * authenticatorData || clientDataHash with [publicKeySpki]. Used to prove
     * the stored public key matches the key used for signing.
     */
    fun verifyAssertion(
        responseJson: String,
        clientDataHash: ByteArray,
        publicKeySpki: ByteArray,
    ): Boolean {
        return try {
            val response = JSONObject(responseJson).getJSONObject("response")
            val authData = b64urlDecode(response.getString("authenticatorData"))
            val signature = b64urlDecode(response.getString("signature"))
            val signer = Signature.getInstance("SHA256withECDSA").apply {
                initVerify(KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(publicKeySpki)))
                update(authData)
                update(clientDataHash)
            }
            // The signature in the response is DER-encoded (ASN.1 SEQUENCE of r,s),
            // as required by verifiers like go-webauthn.
            signer.verify(signature)
        } catch (e: Exception) {
            false
        }
    }

    /** Converts a raw r||s ECDSA signature (64 bytes) to DER for java Signature. */
    private fun rawToDer(raw: ByteArray): ByteArray {
        val seq = derInt(fixSize(raw.copyOfRange(0, 32), 32)) +
            derInt(fixSize(raw.copyOfRange(32, 64), 32))
        return byteArrayOf(0x30, seq.size.toByte()) + seq
    }

    private fun derInt(v: ByteArray): ByteArray {
        var start = 0
        while (start < v.size && v[start] == 0.toByte()) start++
        val body = v.copyOfRange(start, v.size)
        val needsZero = (body[0].toInt() and 0x80) != 0
        val out = ByteArray(body.size + 2 + if (needsZero) 1 else 0)
        out[0] = 0x02
        if (needsZero) {
            out[1] = (body.size + 1).toByte()
            out[2] = 0
            body.copyInto(out, 3)
        } else {
            out[1] = body.size.toByte()
            body.copyInto(out, 2)
        }
        return out
    }

    private val P256_ORDER: BigInteger =
        BigInteger("FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551", 16)

    /** Low-S normalization: s' = min(s, n - s). Required by some strict verifiers. */
    private fun normalizeLowS(s: ByteArray): ByteArray {
        val value = BigInteger(1, s)
        return if (value.compareTo(P256_ORDER.shiftRight(1)) > 0) {
            fixSize(P256_ORDER.subtract(value).toByteArray(), 32)
        } else {
            s
        }
    }

    /** Converts a DER-encoded ECDSA signature to the raw r||s (64 bytes) form WebAuthn uses. */
    fun derToRaw(der: ByteArray): ByteArray {
        var i = 0
        require(der[i++] == 0x30.toByte()) { "not a DER sequence" }
        i++ // sequence length
        require(der[i++] == 0x02.toByte()) { "not an INTEGER" }
        val rLen = der[i++].toInt() and 0xff
        val r = der.copyOfRange(i, i + rLen)
        i += rLen
        require(der[i++] == 0x02.toByte()) { "not an INTEGER" }
        val sLen = der[i++].toInt() and 0xff
        val s = der.copyOfRange(i, i + sLen)
        val rFixed = fixSize(r, 32)
        val sFixed = fixSize(s, 32)
        return rFixed + normalizeLowS(sFixed)
    }
}
