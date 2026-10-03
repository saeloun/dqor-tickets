package `in`.dqor.staff

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import `in`.dqor.staff.nativeapi.*
import java.io.File
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KeystoreCredentialStoreTest {
    private val context=ApplicationProvider.getApplicationContext<Context>()
    private val store=KeystoreCredentialStore(context)
    private val fake=StoredCredential("https://staging.example.test","synthetic-only-no-real-token-123456789",Instant.parse("2026-10-02T20:00:00Z"))
    private val file get()=File(context.noBackupFilesDir,"native-staff-session.enc")
    @Before fun setup()=runBlocking {store.clear()}
    @After fun cleanup()=runBlocking {store.clear()}
    @Test fun encryptedSessionSurvivesStoreRecreation()=runBlocking {
        store.write(fake)
        assertFalse(file.readText().contains(fake.token))
        assertFalse(file.readText().contains(fake.origin))
        val restored=KeystoreCredentialStore(context).read()!!
        assertEquals(fake.token,restored.token); assertEquals(fake.expiresAt,restored.expiresAt)
    }
    @Test fun clearRemovesCredentialAndCiphertext()=runBlocking {
        store.write(fake); store.clear(); assertNull(store.read()); assertFalse(file.exists())
    }
    @Test fun corruptedCiphertextFailsClosedAndIsCleared()=runBlocking {
        store.write(fake); file.writeText("corrupted")
        try {store.read(); fail("Expected storage failure")} catch(e: NativeFailure) {assertEquals(NativeFailure.Kind.STORAGE,e.kind)}
        assertFalse(file.exists()); assertNull(store.read())
    }
    @Test fun rewriteUsesFreshGcmNonce()=runBlocking {
        store.write(fake); val first=file.readText(); store.write(fake)
        assertNotEquals(first,file.readText()); assertEquals(fake.token,store.read()!!.token)
    }
}
