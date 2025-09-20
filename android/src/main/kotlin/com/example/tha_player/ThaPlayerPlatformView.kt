package com.example.tha_player

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Context
import android.content.ContextWrapper
import android.net.Uri
import android.view.View
import android.widget.FrameLayout
import android.os.Build
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
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
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import okhttp3.OkHttpClient
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.util.Locale
import android.util.Rational
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import kotlin.math.min

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
  private val playbackOptions: PlaybackOptions
  private val mediaSession: MediaSessionCompat

  init {
    container.addView(playerView, FrameLayout.LayoutParams(
      FrameLayout.LayoutParams.MATCH_PARENT,
      FrameLayout.LayoutParams.MATCH_PARENT
    ))
    playerView.player = player
    playerView.useController = false
    playerView.resizeMode = androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FIT
    playerView.keepScreenOn = true

    playbackOptions = PlaybackOptions.fromMap(args?.get("playbackOptions") as? Map<*, *>)

    setupFromArgs(args)

    mediaSession = MediaSessionCompat(context, "ThaPlayer_$viewId").apply {
      setCallback(object : MediaSessionCompat.Callback() {
        override fun onPlay() {
          player.play()
        }

        override fun onPause() {
          player.pause()
        }
      })
      isActive = true
    }

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
        "retry" -> {
          try {
            player.prepare()
            player.play()
            result.success(null)
          } catch (e: Exception) {
            result.error("RETRY_FAILED", e.message, null)
          }
        }
        "getVideoTracks" -> {
          result.success(collectVideoTracks())
        }
        "setVideoTrack" -> {
          val id = call.argument<String>("id")
          selectVideoTrack(id)
          result.success(null)
        }
        "getAudioTracks" -> result.success(collectAudioTracks())
        "setAudioTrack" -> {
          selectAudioTrack(call.argument("id"))
          result.success(null)
        }
        "getSubtitleTracks" -> result.success(collectSubtitleTracks())
        "setSubtitleTrack" -> {
          selectSubtitleTrack(call.argument("id"))
          result.success(null)
        }
        "enterPip" -> {
          result.success(requestPictureInPicture())
        }
        "setDataSaver" -> {
          val enable = call.argument<Boolean>("enable") ?: false
          applyDataSaver(enable)
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
        // Emit error event with a concise message
        eventsSink?.success(mapOf(
          "positionMs" to player.currentPosition.coerceAtLeast(0L),
          "durationMs" to (if (player.duration > 0) player.duration else 0L),
          "isBuffering" to false,
          "isPlaying" to false,
          "error" to (error.errorCodeName ?: (error.message ?: "Playback error"))
        ))
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
    val dataSaver = args?.get("dataSaver") as? Boolean ?: false

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
        val drmHeaders = (it["headers"] as? Map<*, *>)?.mapNotNull { (k, v) ->
          if (k is String && v is String) k to v else null
        }?.toMap() ?: emptyMap()
        when (type) {
          "widevine" -> {
            if (licenseUrl != null) {
              val drmBuilder = MediaItem.DrmConfiguration.Builder(C.WIDEVINE_UUID)
              drmBuilder.setLicenseUri(licenseUrl)
              val reqHeaders = mutableMapOf<String, String>()
              if (contentId != null) reqHeaders["Content-ID"] = contentId
              if (drmHeaders.isNotEmpty()) reqHeaders.putAll(drmHeaders)
              if (reqHeaders.isNotEmpty()) drmBuilder.setLicenseRequestHeaders(reqHeaders)
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
            if (drmHeaders.isNotEmpty()) {
              drmBuilder.setLicenseRequestHeaders(drmHeaders)
            }
            builder.setDrmConfiguration(drmBuilder.build())
          }
        }
      }
      val isLive = entry["isLive"] as? Boolean ?: false
      if (isLive) {
        val live = MediaItem.LiveConfiguration.Builder()
          .setTargetOffsetMs(3000)
          .setMinPlaybackSpeed(0.97f)
          .setMaxPlaybackSpeed(1.03f)
          .build()
        builder.setLiveConfiguration(live)
      }
      val mediaItem = builder.build()
      // Per-item headers via OkHttpDataSource
      val okClient = ThaPlayerHttpClientProvider.obtainClient()
      val httpFactory: DataSource.Factory = OkHttpDataSource.Factory(okClient)
        .setDefaultRequestProperties(headers)
      val msFactory = DefaultMediaSourceFactory(httpFactory)
        .setLoadErrorHandlingPolicy(
          ConfigurableLoadErrorPolicy(playbackOptions)
        )
      val mediaSource = msFactory.createMediaSource(mediaItem)
      items.add(mediaSource)
    }

    player.setMediaSources(items)
    player.prepare()
    player.repeatMode = if (loop) Player.REPEAT_MODE_ALL else Player.REPEAT_MODE_OFF
    if (startMs > 0L) player.seekTo(startMs)
    applyDataSaver(dataSaver)
    if (startAutoPlay) player.play() else player.pause()
  }

  override fun getView(): View = container

  override fun dispose() {
    playerView.player = null
    playerView.keepScreenOn = false
    player.release()
    stopProgress()
    mediaSession.release()
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
    updateMediaSessionState(playing, buffering)
  }

  private fun applyDataSaver(enable: Boolean) {
    val builder = player.trackSelectionParameters.buildUpon()
    if (enable) {
      builder.clearOverridesOfType(C.TRACK_TYPE_VIDEO)
      builder.setMaxVideoBitrate(800_000) // ~0.8 Mbps cap
    } else {
      builder.setMaxVideoBitrate(Int.MAX_VALUE)
    }
    player.trackSelectionParameters = builder.build()
  }

  private fun updateMediaSessionState(isPlaying: Boolean, isBuffering: Boolean) {
    val position = player.currentPosition.coerceAtLeast(0L)
    val state = when {
      isBuffering -> PlaybackStateCompat.STATE_BUFFERING
      isPlaying -> PlaybackStateCompat.STATE_PLAYING
      else -> PlaybackStateCompat.STATE_PAUSED
    }
    val playbackState = PlaybackStateCompat.Builder()
      .setActions(
        PlaybackStateCompat.ACTION_PLAY or
          PlaybackStateCompat.ACTION_PAUSE or
          PlaybackStateCompat.ACTION_PLAY_PAUSE
      )
      .setState(state, position, if (isPlaying) player.playbackParameters.speed else 0f)
      .build()
    mediaSession.setPlaybackState(playbackState)
  }

  private fun collectVideoTracks(): List<Map<String, Any?>> {
    val tracks = mutableListOf<Map<String, Any?>>()
    val groups: List<Tracks.Group> = player.currentTracks.groups
    groups.forEachIndexed { groupIndex, group ->
      if (group.type != C.TRACK_TYPE_VIDEO) return@forEachIndexed
      val trackGroup = group.mediaTrackGroup
      for (trackIndex in 0 until trackGroup.length) {
        val format = trackGroup.getFormat(trackIndex)
        val bitrate = if (format.bitrate != Format.NO_VALUE) format.bitrate else null
        val width = if (format.width != Format.NO_VALUE) format.width else null
        val height = if (format.height != Format.NO_VALUE) format.height else null
        tracks.add(
          mapOf(
            "id" to "$groupIndex:$trackIndex",
            "bitrate" to bitrate,
            "width" to width,
            "height" to height,
            "label" to formatTrackLabel(format, width, height, bitrate, trackIndex),
            "selected" to group.isTrackSelected(trackIndex)
          )
        )
      }
    }
    return tracks
  }

  private fun formatTrackLabel(
    format: Format,
    width: Int?,
    height: Int?,
    bitrate: Int?,
    trackIndex: Int,
  ): String {
    val parts = mutableListOf<String>()
    val label = format.label
    if (!label.isNullOrBlank()) {
      parts.add(label)
    }
    if (height != null && height > 0) {
      parts.add("${height}p")
    }
    val frameRate = format.frameRate
    if (!frameRate.isNaN() && frameRate > 0f && frameRate != Format.NO_VALUE.toFloat()) {
      parts.add(String.format(Locale.US, "%.0f fps", frameRate))
    }
    if (bitrate != null && bitrate > 0) {
      val mbps = bitrate / 1_000_000.0
      val pattern = if (mbps >= 10) "%.0f Mbps" else "%.1f Mbps"
      parts.add(String.format(Locale.US, pattern, mbps))
    }
    if (parts.isEmpty()) {
      parts.add("Track ${trackIndex + 1}")
    }
    return parts.joinToString(" • ")
  }

  private fun selectVideoTrack(id: String?) {
    val builder = player.trackSelectionParameters.buildUpon()
    if (id.isNullOrEmpty()) {
      builder.clearOverridesOfType(C.TRACK_TYPE_VIDEO)
      player.trackSelectionParameters = builder.build()
      return
    }

    val parts = id.split(":")
    if (parts.size != 2) return
    val groupIndex = parts[0].toIntOrNull() ?: return
    val trackIndex = parts[1].toIntOrNull() ?: return

    val groups = player.currentTracks.groups
    if (groupIndex < 0 || groupIndex >= groups.size) return
    val group = groups[groupIndex]
    val trackGroup = group.mediaTrackGroup
    if (trackIndex < 0 || trackIndex >= trackGroup.length) return

    val override = TrackSelectionOverride(
      trackGroup,
      listOf(trackIndex)
    )
    builder.clearOverridesOfType(C.TRACK_TYPE_VIDEO)
    builder.setOverrideForType(override)
    player.trackSelectionParameters = builder.build()
  }

  private fun collectAudioTracks(): List<Map<String, Any?>> {
    val tracks = mutableListOf<Map<String, Any?>>()
    val groups = player.currentTracks.groups
    groups.forEachIndexed { groupIndex, group ->
      if (group.type != C.TRACK_TYPE_AUDIO) return@forEachIndexed
      val trackGroup = group.mediaTrackGroup
      for (trackIndex in 0 until trackGroup.length) {
        val format = trackGroup.getFormat(trackIndex)
        val entry = mutableMapOf<String, Any?>()
        entry["id"] = "$groupIndex:$trackIndex"
        entry["label"] = format.label ?: format.codecs ?: "Audio ${trackIndex + 1}"
        entry["language"] = format.language
        entry["selected"] = group.isTrackSelected(trackIndex)
        tracks.add(entry)
      }
    }
    return tracks
  }

  private fun selectAudioTrack(id: String?) {
    val builder = player.trackSelectionParameters.buildUpon()
    if (id.isNullOrEmpty()) {
      builder.clearOverridesOfType(C.TRACK_TYPE_AUDIO)
      player.trackSelectionParameters = builder.build()
      return
    }
    val pair = parseGroupTrackIndex(id) ?: return
    val groupIndex = pair.first
    val trackIndex = pair.second
    val groups = player.currentTracks.groups
    if (groupIndex !in groups.indices) return
    val group = groups[groupIndex]
    val trackGroup = group.mediaTrackGroup
    if (trackIndex < 0 || trackIndex >= trackGroup.length) return
    val override = TrackSelectionOverride(trackGroup, listOf(trackIndex))
    builder.clearOverridesOfType(C.TRACK_TYPE_AUDIO)
    builder.setOverrideForType(override)
    player.trackSelectionParameters = builder.build()
  }

  private fun collectSubtitleTracks(): List<Map<String, Any?>> {
    val tracks = mutableListOf<Map<String, Any?>>()
    val groups = player.currentTracks.groups
    groups.forEachIndexed { groupIndex, group ->
      if (group.type != C.TRACK_TYPE_TEXT) return@forEachIndexed
      val trackGroup = group.mediaTrackGroup
      for (trackIndex in 0 until trackGroup.length) {
        val format = trackGroup.getFormat(trackIndex)
        val entry = mutableMapOf<String, Any?>()
        entry["id"] = "$groupIndex:$trackIndex"
        entry["label"] = format.label ?: "Sub ${trackIndex + 1}"
        entry["language"] = format.language
        entry["selected"] = group.isTrackSelected(trackIndex)
        entry["forced"] = ((format.selectionFlags and C.SELECTION_FLAG_FORCED) != 0)
        tracks.add(entry)
      }
    }
    return tracks
  }

  private fun selectSubtitleTrack(id: String?) {
    val builder = player.trackSelectionParameters.buildUpon()
    if (id.isNullOrEmpty()) {
      builder.clearOverridesOfType(C.TRACK_TYPE_TEXT)
      builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
      player.trackSelectionParameters = builder.build()
      return
    }
    val pair = parseGroupTrackIndex(id) ?: return
    val groupIndex = pair.first
    val trackIndex = pair.second
    val groups = player.currentTracks.groups
    if (groupIndex !in groups.indices) return
    val group = groups[groupIndex]
    val trackGroup = group.mediaTrackGroup
    if (trackIndex < 0 || trackIndex >= trackGroup.length) return
    val override = TrackSelectionOverride(trackGroup, listOf(trackIndex))
    builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
    builder.clearOverridesOfType(C.TRACK_TYPE_TEXT)
    builder.setOverrideForType(override)
    player.trackSelectionParameters = builder.build()
  }

  private fun parseGroupTrackIndex(id: String): Pair<Int, Int>? {
    val parts = id.split(":")
    if (parts.size != 2) return null
    val groupIndex = parts[0].toIntOrNull() ?: return null
    val trackIndex = parts[1].toIntOrNull() ?: return null
    return groupIndex to trackIndex
  }

  private fun requestPictureInPicture(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
    val activity = ThaPlayerPlugin.currentActivity() ?: findActivity(container.context) ?: return false
    val builder = PictureInPictureParams.Builder()
    val size = player.videoSize
    if (size.width > 0 && size.height > 0) {
      builder.setAspectRatio(Rational(size.width, size.height))
    } else {
      builder.setAspectRatio(Rational(16, 9))
    }
    return try {
      activity.enterPictureInPictureMode(builder.build())
    } catch (t: Throwable) {
      false
    }
  }

  private fun findActivity(context: Context): Activity? {
    var currentContext = context
    while (currentContext is ContextWrapper) {
      if (currentContext is Activity) return currentContext
      currentContext = currentContext.baseContext
    }
    return null
  }
}

private data class PlaybackOptions(
  val maxRetryCount: Int,
  val initialRetryDelayMs: Long,
  val maxRetryDelayMs: Long,
  val autoRetry: Boolean,
  val rebufferTimeoutMs: Long?,
) {
  companion object {
    fun fromMap(map: Map<*, *>?): PlaybackOptions {
      val maxRetry = (map?.get("maxRetryCount") as? Number)?.toInt() ?: 3
      val initialDelay = (map?.get("initialRetryDelayMs") as? Number)?.toLong() ?: 1000L
      val maxDelay = (map?.get("maxRetryDelayMs") as? Number)?.toLong() ?: 10000L
      val autoRetry = map?.get("autoRetry") as? Boolean ?: true
      val rebuffer = (map?.get("rebufferTimeoutMs") as? Number)?.toLong()
      return PlaybackOptions(maxRetry, initialDelay, maxDelay, autoRetry, rebuffer)
    }
  }
}

private class ConfigurableLoadErrorPolicy(
  private val options: PlaybackOptions,
) : DefaultLoadErrorHandlingPolicy() {
  override fun getRetryDelayMsFor(
    loadErrorInfo: LoadErrorHandlingPolicy.LoadErrorInfo
  ): Long {
    if (!options.autoRetry) return C.TIME_UNSET
    val attempt = loadErrorInfo.errorCount.coerceAtLeast(1)
    if (options.maxRetryCount >= 0 && attempt > options.maxRetryCount) {
      return C.TIME_UNSET
    }
    val delay = options.initialRetryDelayMs * attempt
    return delay.coerceAtMost(options.maxRetryDelayMs)
  }

  override fun getMinimumLoadableRetryCount(dataType: Int): Int {
    return if (options.maxRetryCount >= 0) options.maxRetryCount else super.getMinimumLoadableRetryCount(dataType)
  }
}
