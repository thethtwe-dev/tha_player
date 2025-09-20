package com.example.tha_player

import okhttp3.OkHttpClient

/**
 * Provides the OkHttpClient used for network playback. A shared instance keeps
 * connection pools/warm DNS and allows host apps to inject a custom client with
 * interceptors, cache, etc. while staying within the 16 KB page-size limit.
 */
object ThaPlayerHttpClientProvider {
  @Volatile
  private var factory: (() -> OkHttpClient)? = null

  private val defaultClient: OkHttpClient by lazy {
    OkHttpClient.Builder().build()
  }

  fun obtainClient(): OkHttpClient = try {
    factory?.invoke() ?: defaultClient
  } catch (t: Throwable) {
    defaultClient
  }

  fun setFactory(newFactory: (() -> OkHttpClient)?) {
    factory = newFactory
  }
}
