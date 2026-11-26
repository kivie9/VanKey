package com.vankey.vankey

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Mở khóa bằng vân tay **gắn với khóa phần cứng**: vault key được mã hóa bằng một khóa AES trong Android Keystore
 * mà hệ điều hành chỉ cho dùng sau khi BiometricPrompt xác thực thành công (mỗi lần dùng phải xác thực lại).
 *
 * Khác với chặn bằng giao diện (local_auth): app bị vá hay máy bị root cũng không lấy được vault key nếu không có
 * vân tay, vì khóa giải mã không rời khỏi Keystore và chỉ mở cho đúng phép tính đã được xác thực.
 * Đăng ký thêm vân tay mới làm khóa mất hiệu lực vĩnh viễn (người dùng phải nhập mật khẩu rồi bật lại).
 */
class BiometricVault(private val activity: FragmentActivity) {
    companion object {
        private const val ALIAS = "vankey.bio.v1"
        private const val KEYSTORE = "AndroidKeyStore"
        private const val TRANSFORM = "AES/GCM/NoPadding"
        private const val IV_LEN = 12
        private const val TAG_BITS = 128
        private const val AUTHENTICATORS = BiometricManager.Authenticators.BIOMETRIC_STRONG
    }

    fun available(): Boolean =
        BiometricManager.from(activity).canAuthenticate(AUTHENTICATORS) == BiometricManager.BIOMETRIC_SUCCESS

    /** Tạo khóa mới (thay khóa cũ), hỏi vân tay, trả về `iv || bản mã`. */
    fun encrypt(plain: ByteArray, title: String, cancel: String, result: MethodChannel.Result) {
        val cipher: Cipher
        try {
            deleteKey()
            cipher = Cipher.getInstance(TRANSFORM)
            cipher.init(Cipher.ENCRYPT_MODE, createKey())
        } catch (e: Exception) {
            result.error("unavailable", e.message, null)
            return
        }
        prompt(cipher, title, cancel, result) { c ->
            val ct = c.doFinal(plain)
            c.iv + ct
        }
    }

    /** Hỏi vân tay rồi giải mã `iv || bản mã` do [encrypt] tạo. */
    fun decrypt(blob: ByteArray, title: String, cancel: String, result: MethodChannel.Result) {
        if (blob.size <= IV_LEN) {
            result.error("corrupt", "dữ liệu quá ngắn", null)
            return
        }
        val cipher: Cipher
        try {
            val key = loadKey() ?: run {
                result.error("invalidated", "không còn khóa", null)
                return
            }
            cipher = Cipher.getInstance(TRANSFORM)
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, blob.copyOfRange(0, IV_LEN)))
        } catch (e: KeyPermanentlyInvalidatedException) {
            deleteKey()
            result.error("invalidated", "vân tay trên máy đã thay đổi", null)
            return
        } catch (e: Exception) {
            result.error("unavailable", e.message, null)
            return
        }
        prompt(cipher, title, cancel, result) { c -> c.doFinal(blob.copyOfRange(IV_LEN, blob.size)) }
    }

    fun deleteKey() {
        try {
            val ks = KeyStore.getInstance(KEYSTORE).apply { load(null) }
            if (ks.containsAlias(ALIAS)) ks.deleteEntry(ALIAS)
        } catch (_: Exception) {
            // Không xóa được thì lần bật sau sẽ ghi đè.
        }
    }

    private fun loadKey(): SecretKey? {
        val ks = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        return ks.getKey(ALIAS, null) as SecretKey?
    }

    private fun createKey(): SecretKey {
        val spec = KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // 0 giây = mỗi lần dùng khóa phải xác thực, và chỉ chấp nhận sinh trắc mạnh.
            spec.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
        } else {
            @Suppress("DEPRECATION")
            spec.setUserAuthenticationValidityDurationSeconds(-1)
        }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        gen.init(spec.build())
        return gen.generateKey()
    }

    private fun prompt(cipher: Cipher, title: String, cancel: String, result: MethodChannel.Result, op: (Cipher) -> ByteArray) {
        var answered = false
        fun reply(block: () -> Unit) {
            if (answered) return
            answered = true
            block()
        }
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(res: BiometricPrompt.AuthenticationResult) {
                val c = res.cryptoObject?.cipher
                if (c == null) {
                    reply { result.error("unavailable", "không nhận được cipher", null) }
                    return
                }
                try {
                    val out = op(c)
                    reply { result.success(out) }
                } catch (e: Exception) {
                    reply { result.error("failed", e.message, null) }
                }
            }

            override fun onAuthenticationError(code: Int, msg: CharSequence) {
                val canceled = code == BiometricPrompt.ERROR_USER_CANCELED || code == BiometricPrompt.ERROR_NEGATIVE_BUTTON || code == BiometricPrompt.ERROR_CANCELED
                reply { result.error(if (canceled) "canceled" else "failed", msg.toString(), null) }
            }
            // onAuthenticationFailed (vân tay không khớp): BiometricPrompt tự cho thử lại, không trả kết quả.
        }
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setNegativeButtonText(cancel)
            .setAllowedAuthenticators(AUTHENTICATORS)
            .build()
        BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), callback)
            .authenticate(info, BiometricPrompt.CryptoObject(cipher))
    }
}
