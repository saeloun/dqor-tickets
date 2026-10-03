package `in`.dqor.staff.programme

import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.CookieJar
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class OfficialProgrammeTransport : ProgrammeTransport {
    private val client=OkHttpClient.Builder().cookieJar(CookieJar.NO_COOKIES).cache(null)
        .followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false)
        .connectTimeout(10,TimeUnit.SECONDS).readTimeout(15,TimeUnit.SECONDS).callTimeout(20,TimeUnit.SECONDS).build()
    override suspend fun fetch(request: ProgrammeRequest): ProgrammeResponse = suspendCancellableCoroutine {continuation ->
        val builder=Request.Builder().url(ENDPOINT).get().header("Accept","application/json")
            .header("User-Agent","DQOR-Android-Public/0.1").header("Cache-Control","no-cache")
        request.ifNoneMatch?.let {
            require(validProgrammeEtag(it))
            builder.header("If-None-Match",it)
        }
        val call=client.newCall(builder.build())
        continuation.invokeOnCancellation {call.cancel()}
        call.enqueue(object : Callback {
            override fun onFailure(call: Call,error: IOException) {if(continuation.isActive) continuation.resumeWithException(error)}
            override fun onResponse(call: Call,response: Response) {
                try {
                    val result=response.use {
                        val source=it.body?.source()
                        val body=if(source==null || it.code==304) "" else {
                            source.request(1_048_577)
                            if(source.buffer.size>1_048_576) throw IOException("Programme response exceeds limit")
                            source.readUtf8()
                        }
                        if(it.code==200 && it.body?.contentType()?.subtype?.contains("json")!=true) throw IOException("Unexpected programme content")
                        ProgrammeResponse(it.code,it.header("ETag"),body)
                    }
                    if(continuation.isActive) continuation.resume(result)
                } catch(error: Exception) {if(continuation.isActive) continuation.resumeWithException(error)}
            }
        })
    }
    companion object {
        const val ORIGIN="https://deccanqueenonrails.com"
        const val ENDPOINT="$ORIGIN/api/public/v1/dqor/programme"
        const val TICKETS="$ORIGIN/tickets/mine"
    }
}

internal fun validProgrammeEtag(value: String): Boolean {
    val start=if(value.startsWith("W/\"")) 3 else if(value.startsWith("\"")) 1 else return false
    return value.length in (start+1)..256 && value.endsWith("\"") &&
        value.substring(start,value.lastIndex).none {it=='\r' || it=='\n' || it=='"' || it=='\\'}
}
