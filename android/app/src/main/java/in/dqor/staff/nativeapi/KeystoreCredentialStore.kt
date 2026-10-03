package `in`.dqor.staff.nativeapi

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.util.Base64
import java.io.File
import java.security.KeyStore
import java.time.Instant
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

/** AES-GCM ciphertext in noBackupFilesDir; non-exportable per-app Android Keystore key.
 * No plaintext fallback. Passwords never enter this store. Hardware backing varies by device. */
class KeystoreCredentialStore(context: Context) : CredentialStore {
    private val file=AtomicFile(File(context.noBackupFilesDir,"native-staff-session.enc"))
    private val alias="dqor.native.staff.session.v1"
    private val aad="dqor-native-session-v1".toByteArray(Charsets.UTF_8)
    private fun keys()=KeyStore.getInstance("AndroidKeyStore").apply {load(null)}
    private fun key(create: Boolean): SecretKey {
        (keys().getKey(alias,null) as? SecretKey)?.let {return it}
        check(create)
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias,KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).setRandomizedEncryptionRequired(true).build())
        }.generateKey()
    }
    override suspend fun read(): StoredCredential? = withContext(Dispatchers.IO) {
        if(!file.baseFile.exists()) return@withContext null
        try {
            val bytes=file.openRead().use { input -> val buffer=ByteArray(16385); var count=0; while(count<buffer.size) { val read=input.read(buffer,count,buffer.size-count); if(read<0) break; count+=read }; check(count<=16384); buffer.copyOf(count) }
            val envelope=JSONObject(String(bytes,Charsets.UTF_8))
            check(envelope.getInt("version")==1)
            val iv=Base64.decode(envelope.string("iv"),Base64.NO_WRAP); check(iv.size==12)
            val cipher=Cipher.getInstance("AES/GCM/NoPadding").apply {init(Cipher.DECRYPT_MODE,key(false),GCMParameterSpec(128,iv)); updateAAD(aad)}
            val plaintext=cipher.doFinal(Base64.decode(envelope.string("ciphertext"),Base64.NO_WRAP))
            try { val json=JSONObject(String(plaintext,Charsets.UTF_8)); StoredCredential(json.string("origin"),json.string("token"),Instant.parse(json.string("expires_at"))) }
            finally {plaintext.fill(0)}
        } catch(_: Exception) { clear(); throw NativeFailure(NativeFailure.Kind.STORAGE) }
    }
    override suspend fun write(value: StoredCredential) = withContext(Dispatchers.IO) {
        try {
            val cipher=Cipher.getInstance("AES/GCM/NoPadding").apply {init(Cipher.ENCRYPT_MODE,key(true)); updateAAD(aad)}
            val plaintext=JSONObject().put("origin",value.origin).put("token",value.token).put("expires_at",value.expiresAt.toString()).toString().toByteArray(Charsets.UTF_8)
            val encrypted=try {cipher.doFinal(plaintext)} finally {plaintext.fill(0)}
            val envelope=JSONObject().put("version",1).put("iv",Base64.encodeToString(cipher.iv,Base64.NO_WRAP)).put("ciphertext",Base64.encodeToString(encrypted,Base64.NO_WRAP)).toString().toByteArray(Charsets.UTF_8)
            val output=file.startWrite()
            try {output.write(envelope); file.finishWrite(output)} catch(e: Exception) {file.failWrite(output); throw e}
        } catch(_: Exception) {clear(); throw NativeFailure(NativeFailure.Kind.STORAGE)}
    }
    override suspend fun clear() = withContext(Dispatchers.IO + NonCancellable) {
        // Destroying the key renders any orphaned ciphertext unusable.
        keys().deleteEntry(alias)
        file.delete()
        if(file.baseFile.exists()) throw NativeFailure(NativeFailure.Kind.STORAGE)
    }
}
