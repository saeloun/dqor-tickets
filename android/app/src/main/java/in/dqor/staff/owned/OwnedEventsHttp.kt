package `in`.dqor.staff.owned

import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.CookieJar
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class OwnedEventsHttp: OwnedTransport {
    internal val client = OkHttpClient.Builder().cookieJar(CookieJar.NO_COOKIES).cache(null).followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false).connectTimeout(15, TimeUnit.SECONDS).readTimeout(20, TimeUnit.SECONDS).callTimeout(30, TimeUnit.SECONDS).build()
    internal fun request(resource: OwnedResource, validator: String?): Request = Request.Builder().url(ORIGIN + resource.path()).get().header("Accept", "application/json").apply {
            validator?.let { require(OwnedEventsClient.validEtag(it)); header("If-None-Match", it) }
        }.build()
    override suspend fun fetch(resource: OwnedResource, validator: String?): OwnedResponse {
        val request = request(resource, validator)
        val url = request.url.toString()
        return suspendCancellableCoroutine { continuation ->
            val call = client.newCall(request)
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(object: Callback {
                override fun onFailure(call: Call, e: IOException) { if(continuation.isActive) continuation.resumeWithException(e) }
                override fun onResponse(call: Call, response: Response) {
                    try {
                        val result = decode(response, url)
                        if(continuation.isActive) continuation.resume(result)
                    } catch(error: Exception) { if(continuation.isActive) continuation.resumeWithException(error) }
                }
            })
        }
    }
    internal fun decode(response: Response, url: String): OwnedResponse = response.use {
        require(it.request.url.toString() == url)
        val tag = it.header("ETag")
        if(it.code != 200) OwnedResponse(it.code, tag)
        else {
            val body = requireNotNull(it.body)
            require(body.contentLength() <= MAX_BODY && body.contentType()?.let { type -> type.type == "application" && type.subtype == "json" } == true)
            val source = body.source(); source.request(MAX_BODY.toLong() + 1); require(source.buffer.size <= MAX_BODY)
            OwnedResponse(200, tag, source.readUtf8())
        }
    }
    companion object { const val ORIGIN = "https://deccanqueenonrails.com"; const val MAX_BODY = 1_048_576 }
}
