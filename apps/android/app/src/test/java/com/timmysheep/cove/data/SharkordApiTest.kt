package com.timmysheep.cove.data

import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Request
import org.junit.Assert.assertEquals
import org.junit.Test

class SharkordApiTest {
    @Test
    fun webSocketRequestUrlPreservesSupportedHttpSchemes() {
        listOf("http", "https").forEach { scheme ->
            val baseUrl = "$scheme://example.com/server".toHttpUrl()
            val requestUrl = SharkordApi.webSocketRequestUrl(baseUrl)
            val request = Request.Builder().url(requestUrl).build()

            assertEquals(scheme, request.url.scheme)
            assertEquals("/", request.url.encodedPath)
            assertEquals("connectionParams=1", request.url.encodedQuery)
        }
    }
}
