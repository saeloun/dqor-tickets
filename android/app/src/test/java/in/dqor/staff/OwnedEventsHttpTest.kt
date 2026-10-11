package `in`.dqor.staff

import `in`.dqor.staff.owned.*
import okhttp3.CookieJar
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test

class OwnedEventsHttpTest {
    @Test fun fixedAnonymousRequestsPreserveWeakValidatorAndHaveNoCredentials() {
        val transport = OwnedEventsHttp(); val request = transport.request(OwnedResource.Catalog(2), "W/\"synthetic\"")
        assertEquals("https://deccanqueenonrails.com/api/public/v1/events?page=2", request.url.toString())
        assertEquals("GET", request.method); assertNull(request.body)
        assertEquals("application/json", request.header("Accept")); assertEquals("W/\"synthetic\"", request.header("If-None-Match"))
        assertNull(request.header("Authorization")); assertNull(request.header("Cookie"))
        assertEquals(CookieJar.NO_COOKIES, transport.client.cookieJar); assertNull(transport.client.cache)
        assertFalse(transport.client.followRedirects); assertFalse(transport.client.followSslRedirects); assertFalse(transport.client.retryOnConnectionFailure)
        assertEquals("/api/public/v1/events/hosted-event-101", transport.request(OwnedResource.Detail("hosted-event-101"), null).url.encodedPath)
    }
    @Test fun malformedResourceAndHeaderCannotConstructRequest() {
        val transport = OwnedEventsHttp()
        for(resource in listOf(OwnedResource.Catalog(0), OwnedResource.Detail("external-1"))) {
            try { transport.request(resource, null); fail() } catch(_: IllegalArgumentException) { }
        }
        try { transport.request(OwnedResource.Catalog(), "\"a\r\nb\""); fail() } catch(_: IllegalArgumentException) { }
    }
    @Test fun decoderBoundsBodiesAndRequiresJSONAtExactURL() {
        val transport = OwnedEventsHttp(); val request = transport.request(OwnedResource.Catalog(), null)
        fun response(type: String, body: String) = Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("Synthetic").body(body.toResponseBody(type.toMediaType())).build()
        for(response in listOf(response("text/html", "{}"), response("application/json", " ".repeat(OwnedEventsHttp.MAX_BODY + 1)))) {
            try { transport.decode(response, request.url.toString()); fail() } catch(_: IllegalArgumentException) { }
        }
        try { transport.decode(response("application/json", "{}"), "https://example.invalid/api/public/v1/events"); fail() } catch(_: IllegalArgumentException) { }
        val result = transport.decode(response("application/json", "{}"), request.url.toString()); assertEquals(200, result.status); assertEquals("{}", result.body)
    }
    @Test fun bodyless304AndRedirectRemainStatusesWithoutInventedContent() {
        val transport = OwnedEventsHttp(); val request = transport.request(OwnedResource.Catalog(), null)
        for(status in listOf(304, 302, 404, 503)) {
            val response = Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(status).message("Synthetic").header("ETag", "W/\"synthetic\"").body("ignored".toResponseBody()).build()
            val result = transport.decode(response, request.url.toString()); assertEquals(status, result.status); assertTrue(result.body.isEmpty())
        }
    }
}
