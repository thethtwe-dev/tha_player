package com.example.tha_player

import android.content.Context
import android.net.Uri
import android.view.View
import android.widget.FrameLayout
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.Util
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.EventChannel
import android.os.Handler
import android.os.Looper
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import okhttp3.OkHttpClient
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

class ThaPlayerPlatformView(
  context: Context,
  messenger: BinaryMessenger,
  private val viewId: Int,
  args: Map<*, *>?,
) : PlatformView {
  private val container: FrameLayout = FrameLayout(context)
  private val playerView: PlayerView = PlayerView(context)
  private val player: ExoPlayer = ExoPlayer.Builder(context).build()
  private val channel: MethodChannel = MethodChannel(messenger, "thaplayer/view_${viewId}")
  private val eventChannel: EventChannel = EventChannel(messenger, "thaplayer/events_${viewId}")
  private val mainHandler = Handler(Looper.getMainLooper())
  private var eventsSink: EventChannel.EventSink? = null
  private var progressRunnable: Runnable? = null

  init {
    container.addView(playerView, FrameLayout.LayoutParams(
      FrameLayout.LayoutParams.MATCH_PARENT,
      FrameLayout.LayoutParams.MATCH_PARENT
    ))
    playerView.player = player
    playerView.useController = false
    playerView.resizeMode = androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FIT
    playerView.keepScreenOn = true

    setupFromArgs(args)

    channel.setMethodCallHandler { call, result ->
      when (call.method) {
        "play" -> { player.play(); result.success(null) }
        "pause" -> { player.pause(); result.success(null) }
        "seekTo" -> {
          val ms = (call.argument<Int>("millis") ?: 0).toLong()
          player.seekTo(ms)
          result.success(null)
        }
        "setSpeed" -> {
          val speed = call.argument<Double>("speed")?.toFloat() ?: 1.0f
          player.setPlaybackSpeed(speed)
          result.success(null)
        }
        "setLooping" -> {
          val loop = call.argument<Boolean>("loop") ?: false
          player.repeatMode = if (loop) Player.REPEAT_MODE_ALL else Player.REPEAT_MODE_OFF
          result.success(null)
        }
        "setBoxFit" -> {
          when (call.argument<String>("fit")) {
            "contain" -> playerView.resizeMode = androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FIT
            "cover" -> playerView.resizeMode = androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            "fill" -> playerView.resizeMode = androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FILL
            "fitWidth" -> playerView.resizeMode = androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FIXED_WIDTH
            "fitHeight" -> playerView.resizeMode = androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FIXED_HEIGHT
            else -> playerView.resizeMode = androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FIT
          }
          result.success(null)
        }
        "dispose" -> {
          dispose()
          result.success(null)
        }
        else -> result.notImplemented()
      }
    }

    player.addListener(object: Player.Listener {
      override fun onPlayerError(error: PlaybackException) {
        // TODO: Optionally send error to Dart via EventChannel
      }
      override fun onIsPlayingChanged(isPlaying: Boolean) { sendPlaybackEvent() }
      override fun onPlaybackStateChanged(playbackState: Int) { sendPlaybackEvent() }
    })

    eventChannel.setStreamHandler(object: EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventsSink = events
        startProgress()
      }
      override fun onCancel(arguments: Any?) {
        stopProgress()
        eventsSink = null
      }
    })
  }

  private fun setupFromArgs(args: Map<*, *>?) {
    val autoPlay = args?.get("autoPlay") as? Boolean ?: true
    val loop = args?.get("loop") as? Boolean ?: false
    val playlist = args?.get("playlist") as? List<*>
    val startMs = (args?.get("startPositionMs") as? Int ?: 0).toLong()
    val startAutoPlay = args?.get("startAutoPlay") as? Boolean ?: autoPlay

    val items = mutableListOf<MediaSource>()
    playlist?.forEach { entryAny ->
      val entry = entryAny as? Map<*, *> ?: return@forEach
      val url = entry["url"] as? String ?: return@forEach
      val headers = (entry["headers"] as? Map<*, *>)?.mapNotNull { (k, v) ->
        if (k is String && v is String) k to v else null
      }?.toMap() ?: emptyMap()
      val drmMap = entry["drm"] as? Map<*, *>

      val builder = MediaItem.Builder().setUri(Uri.parse(url))
      // DRM

      drmMap?.let {
        val type = (it["type"] as? String)?.lowercase()
        val licenseUrl = it["licenseUrl"] as? String
        val contentId = it["contentId"] as? String
        val clearKeyJson = it["clearKey"] as? String
        when (type) {
          "widevine" -> {
            if (licenseUrl != null) {
              val drmBuilder = MediaItem.DrmConfiguration.Builder(C.WIDEVINE_UUID)
              drmBuilder.setLicenseUri(licenseUrl)
              if (contentId != null) drmBuilder.setLicenseRequestHeaders(mapOf("Content-ID" to contentId))
              builder.setDrmConfiguration(drmBuilder.build())
            }
          }
          "clearkey" -> {
            val drmBuilder = MediaItem.DrmConfiguration.Builder(C.CLEARKEY_UUID)
            // If clearKey JSON provided, pass via data URI
            if (clearKeyJson != null) {
              val b64 = Base64.encodeToString(clearKeyJson.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
              drmBuilder.setLicenseUri("data:application/json;base64,$b64")
            } else if (licenseUrl != null) {
              drmBuilder.setLicenseUri(licenseUrl)
            }
            builder.setDrmConfiguration(drmBuilder.build())
          }
        }
      }
      val mediaItem = builder.build()
      // Per-item headers via OkHttpDataSource
      val okClient = OkHttpClient.Builder().build()
      val httpFactory: DataSource.Factory = OkHttpDataSource.Factory(okClient)
        .setDefaultRequestProperties(headers)
      val msFactory = DefaultMediaSourceFactory(httpFactory)
      val mediaSource = msFactory.createMediaSource(mediaItem)
      items.add(mediaSource)
    }

    player.setMediaSources(items)
    player.prepare()
    player.repeatMode = if (loop) Player.REPEAT_MODE_ALL else Player.REPEAT_MODE_OFF
    if (startMs > 0L) player.seekTo(startMs)
    if (startAutoPlay) player.play() else player.pause()
  }

  override fun getView(): View = container

  override fun dispose() {
    playerView.player = null
    playerView.keepScreenOn = false
    player.release()
    stopProgress()
  }

  private fun startProgress() {
    if (progressRunnable != null) return
    progressRunnable = object: Runnable {
      override fun run() {
        sendPlaybackEvent()
        mainHandler.postDelayed(this, 500)
      }
    }
    mainHandler.post(progressRunnable!!)
  }

  private fun stopProgress() {
    progressRunnable?.let { mainHandler.removeCallbacks(it) }
    progressRunnable = null
  }

  private fun sendPlaybackEvent() {
    val sink = eventsSink ?: return
    val pos = player.currentPosition.coerceAtLeast(0L)
    val dur = if (player.duration > 0) player.duration else 0L
    val buffering = player.playbackState == Player.STATE_BUFFERING
    val playing = player.isPlaying
    sink.success(mapOf(
      "positionMs" to pos,
      "durationMs" to dur,
      "isBuffering" to buffering,
      "isPlaying" to playing,
    ))
  }
}
