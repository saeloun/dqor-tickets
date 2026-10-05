package `in`.dqor.staff.nativeapi

import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.CookieJar
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody

internal object NativeIntegrationGate { const val ENABLED = false }

class ApprovedNativeTransport(private val config: NativeConfig) : NativeTransport {
    init { check(NativeIntegrationGate.ENABLED && config.enabled) { "Native transport disabled pending staging approval" } }
    private val client=OkHttpClient.Builder()
        .cookieJar(CookieJar.NO_COOKIES).cache(null)
        .followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false)
        .connectTimeout(10,TimeUnit.SECONDS).readTimeout(15,TimeUnit.SECONDS).callTimeout(20,TimeUnit.SECONDS)
        .build()
    override suspend fun execute(request: NativeRequest): NativeResponse = withContext(Dispatchers.IO) {
        val route=request.path.substringBefore('?')
        require(route in setOf("/api/staff/session","/api/staff/checkins","/api/staff/checkins/resolve","/api/staff/checkins/confirm"))
        require(request.method in setOf("GET","POST","DELETE") && !request.path.contains('#'))
        val builder=Request.Builder().url(config.origin+request.path)
            .header("Accept","application/json").header("Cache-Control","no-store")
        request.bearer?.let {builder.header("Authorization","Bearer $it")}
        builder.method(request.method,request.body?.toRequestBody("application/json; charset=utf-8".toMediaType()))
        // Default platform TLS validation; no permissive hostname verifier/trust manager.
        client.newCall(builder.build()).execute().use { response ->
            val source=response.body?.source()
            val body=if(source == null) "" else {
                source.request(1_048_577)
                if(source.buffer.size>1_048_576) throw IOException("Response exceeds limit")
                source.readUtf8()
            }
            NativeResponse(response.code,body)
        }
    }
}
