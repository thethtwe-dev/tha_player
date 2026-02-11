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
import java.lang.ref.WeakReference

class ThaPlayerPlatformView(
  context: Context,
  messenger: BinaryMessenger,
  private val viewId: Int,
  args: Map<*, *>?,
) : PlatformView {
  private val container: FrameLayout = FrameLayout(context)
  private val playerView: PlayerView = PlayerView(context)
  private val channel: MethodChannel = MethodChannel(messenger, "thaplayer/view_${viewId}")
  private val eventChannel: EventChannel = EventChannel(messenger, "thaplayer/events_${viewId}")
  private val mainHandler = Handler(Looper.getMainLooper())
  private var eventsSink: EventChannel.EventSink? = null
  private var progressRunnable: Runnable? = null
  private val controllerId: Long =
    (args?.get("controllerId") as? Number)?.toLong() ?: viewId.toLong()
  private val playbackOptions: PlaybackOptions
  private val sharedEntry: SharedPlayerEntry
  private val player: ExoPlayer

  init {
    container.addView(playerView, FrameLayout.LayoutParams(
      FrameLayout.LayoutParams.MATCH_PARENT,
      FrameLayout.LayoutParams.MATCH_PARENT
    ))
    playbackOptions = PlaybackOptions.fromMap(args?.get("playbackOptions") as? Map<*, *>)
    sharedEntry = SharedPlayerRegistry.acquire(context, controllerId, playbackOptions, args)
    player = sharedEntry.player
    sharedEntry.attachView(playerView)
    playerView.useController = false
    playerView.resizeMode = androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FIT

    channel.setMethodCallHandler { call, result ->
      when (call.method) {
        "play" -> {
          if (sharedEntry.hasRenderedFirstFrame) {
            sharedEntry.pendingPlayOnceReady = false
            restoreAudio()
            player.play()
          } else {
            sharedEntry.pendingPlayOnceReady = true
            player.playWhenReady = false
            suppressAudio()
            if (player.playbackState == Player.STATE_READY) {
              scheduleReadyFallback()
            }
          }
          result.success(null)
        }
        "pause" -> {
          sharedEntry.pendingPlayOnceReady = false
          cancelReadyFallback()
          restoreAudio()
          player.pause()
          result.success(null)
        }
        "seekTo" -> {
          val ms = (call.argument<Int>("millis") ?: 0).toLong()
          val wasPlaying = sharedEntry.pendingPlayOnceReady || player.isPlaying || player.playWhenReady
          sharedEntry.pendingPlayOnceReady = wasPlaying
          sharedEntry.hasRenderedFirstFrame = false
          cancelReadyFallback()
          if (wasPlaying) {
            player.playWhenReady = false
            suppressAudio()
          } else {
            restoreAudio()
          }
          player.seekTo(ms)
          if (!wasPlaying) {
            player.pause()
          }
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
            val shouldAutoPlay = sharedEntry.pendingPlayOnceReady || player.playWhenReady || player.isPlaying
            sharedEntry.pendingPlayOnceReady = shouldAutoPlay
            sharedEntry.hasRenderedFirstFrame = false
            cancelReadyFallback()
            player.playWhenReady = false
            suppressAudio()
            player.prepare()
            if (!shouldAutoPlay) {
              player.pause()
              restoreAudio()
            }
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
        val errorCode = error.errorCodeName ?: "UNKNOWN"
        val message = error.message ?: "Playback error"
        val recoverable = sharedEntry.playbackOptions.autoRetry && isRecoverableError(error)
        // Emit error event with a concise message
        eventsSink?.success(mapOf(
          "positionMs" to player.currentPosition.coerceAtLeast(0L),
          "durationMs" to (if (player.duration > 0) player.duration else 0L),
          "isBuffering" to false,
          "isPlaying" to false,
          "error" to message,
          "errorCode" to errorCode,
          "errorMessage" to message,
          "errorRecoverable" to recoverable,
          "errorDetails" to mapOf(
            "code" to error.errorCode,
            "name" to errorCode,
            "cause" to (error.cause?.javaClass?.simpleName ?: "unknown")
          )
        ))
        cancelReadyFallback()
        sharedEntry.pendingPlayOnceReady = false
        restoreAudio()
      }

      override fun onIsPlayingChanged(isPlaying: Boolean) {
        if (!isPlaying && player.playbackState != Player.STATE_BUFFERING) {
          cancelReadyFallback()
        }
        sendPlaybackEvent()
      }

      override fun onPlaybackStateChanged(playbackState: Int) {
        when (playbackState) {
          Player.STATE_BUFFERING -> {
            if (!sharedEntry.hasRenderedFirstFrame && sharedEntry.pendingPlayOnceReady) {
              suppressAudio()
            }
          }
          Player.STATE_READY -> {
            if (sharedEntry.hasRenderedFirstFrame) {
              restoreAudio()
              maybeStartPlayback()
            } else {
              scheduleReadyFallback()
            }
          }
          Player.STATE_ENDED -> {
            sharedEntry.pendingPlayOnceReady = false
            cancelReadyFallback()
            restoreAudio()
          }
          Player.STATE_IDLE -> {
            sharedEntry.hasRenderedFirstFrame = false
            cancelReadyFallback()
            restoreAudio()
          }
        }
        sendPlaybackEvent()
      }

      override fun onRenderedFirstFrame() {
        sharedEntry.hasRenderedFirstFrame = true
        cancelReadyFallback()
        restoreAudio()
        maybeStartPlayback()
      }
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

  override fun getView(): View = container

  override fun dispose() {
    val isCurrentSurface = sharedEntry.attachedView?.get() === playerView
    if (isCurrentSurface) {
      cancelReadyFallback()
      restoreAudio()
      sharedEntry.pendingPlayOnceReady = false
    }
    stopProgress()
    SharedPlayerRegistry.release(controllerId, playerView)
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

  private fun isRecoverableError(error: PlaybackException): Boolean {
    return when (error.errorCode) {
      PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
      PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT,
      PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS,
      PlaybackException.ERROR_CODE_IO_INVALID_HTTP_CONTENT_TYPE,
      PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW -> true
      else -> false
    }
  }

  private fun applyDataSaver(enable: Boolean) {
    sharedEntry.applyDataSaverInternal(enable)
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
    sharedEntry.mediaSession.setPlaybackState(playbackState)
  }

  private fun suppressAudio() {
    sharedEntry.suppressAudioInternal()
  }

  private fun restoreAudio() {
    sharedEntry.restoreAudioInternal()
  }

  private fun scheduleReadyFallback() {
    if (sharedEntry.hasRenderedFirstFrame || sharedEntry.pendingPlayOnceReady.not()) return
    if (sharedEntry.readyFallbackRunnable != null) return
    val runnable = Runnable {
      sharedEntry.readyFallbackRunnable = null
      if (!sharedEntry.hasRenderedFirstFrame) {
        restoreAudio()
        maybeStartPlayback(force = true)
      }
    }
    sharedEntry.readyFallbackRunnable = runnable
    sharedEntry.handler.postDelayed(runnable, 700)
  }

  private fun cancelReadyFallback() {
    sharedEntry.readyFallbackRunnable?.let(sharedEntry.handler::removeCallbacks)
    sharedEntry.readyFallbackRunnable = null
  }

  private fun maybeStartPlayback(force: Boolean = false) {
    if (!sharedEntry.pendingPlayOnceReady) return
    if (!sharedEntry.hasRenderedFirstFrame && !force) return
    sharedEntry.pendingPlayOnceReady = false
    player.play()
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
    val signatureCounts = mutableMapOf<String, Int>()
    groups.forEach { group ->
      if (group.type != C.TRACK_TYPE_AUDIO) return@forEach
      val trackGroup = group.mediaTrackGroup
      for (trackIndex in 0 until trackGroup.length) {
        val format = trackGroup.getFormat(trackIndex)
        val signature = audioTrackSignature(format)
        val occurrence = signatureCounts[signature] ?: 0
        signatureCounts[signature] = occurrence + 1
        val entry = mutableMapOf<String, Any?>()
        entry["id"] = stableTrackId("audio", signature, occurrence)
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
    val selection = resolveAudioSelection(id) ?: return
    val override = TrackSelectionOverride(selection.first, listOf(selection.second))
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

  private fun resolveAudioSelection(id: String): Pair<androidx.media3.common.TrackGroup, Int>? {
    parseGroupTrackIndex(id)?.let { pair ->
      val groupIndex = pair.first
      val trackIndex = pair.second
      val groups = player.currentTracks.groups
      if (groupIndex in groups.indices) {
        val group = groups[groupIndex]
        val trackGroup = group.mediaTrackGroup
        if (group.type == C.TRACK_TYPE_AUDIO && trackIndex in 0 until trackGroup.length) {
          return trackGroup to trackIndex
        }
      }
    }

    val stable = parseStableTrackId(id, "audio") ?: return null
    val groups = player.currentTracks.groups
    val signatureCounts = mutableMapOf<String, Int>()
    for (group in groups) {
      if (group.type != C.TRACK_TYPE_AUDIO) continue
      val trackGroup = group.mediaTrackGroup
      for (trackIndex in 0 until trackGroup.length) {
        val format = trackGroup.getFormat(trackIndex)
        val signature = audioTrackSignature(format)
        val occurrence = signatureCounts[signature] ?: 0
        signatureCounts[signature] = occurrence + 1
        if (signature == stable.first && occurrence == stable.second) {
          return trackGroup to trackIndex
        }
      }
    }
    return null
  }

  private fun audioTrackSignature(format: Format): String {
    val normalizedBitrate = if (format.bitrate != Format.NO_VALUE) format.bitrate else -1
    val normalizedChannels = if (format.channelCount != Format.NO_VALUE) format.channelCount else -1
    val normalizedSampleRate = if (format.sampleRate != Format.NO_VALUE) format.sampleRate else -1
    val raw = listOf(
      format.id.orEmpty(),
      format.language.orEmpty(),
      format.label.orEmpty(),
      format.codecs.orEmpty(),
      format.sampleMimeType.orEmpty(),
      normalizedBitrate.toString(),
      normalizedChannels.toString(),
      normalizedSampleRate.toString(),
      format.roleFlags.toString(),
      format.selectionFlags.toString(),
    ).joinToString("|")
    return Base64.encodeToString(raw.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
  }

  private fun stableTrackId(prefix: String, signature: String, occurrence: Int): String {
    return "$prefix:$signature:$occurrence"
  }

  private fun parseStableTrackId(id: String, prefix: String): Pair<String, Int>? {
    val parts = id.split(":", limit = 3)
    if (parts.size != 3 || parts[0] != prefix) return null
    val occurrence = parts[2].toIntOrNull() ?: return null
    return parts[1] to occurrence
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
private data class SharedPlayerEntry(
  val controllerId: Long,
  val player: ExoPlayer,
  val mediaSession: MediaSessionCompat,
  val handler: Handler,
  var refs: Int = 0,
  var initialized: Boolean = false,
  var playbackOptions: PlaybackOptions,
  var pendingPlayOnceReady: Boolean = false,
  var hasRenderedFirstFrame: Boolean = false,
  var audioSuppressed: Boolean = false,
  var storedVolume: Float = 1f,
  var readyFallbackRunnable: Runnable? = null,
  var attachedView: WeakReference<PlayerView?>? = null,
  val viewRefs: MutableList<WeakReference<PlayerView>> = mutableListOf(),
)

private object SharedPlayerRegistry {
  private val entries = mutableMapOf<Long, SharedPlayerEntry>()

  fun acquire(
    context: Context,
    controllerId: Long,
    options: PlaybackOptions,
    args: Map<*, *>?,
  ): SharedPlayerEntry {
    val existing = entries[controllerId]
    return if (existing != null) {
      existing.refs += 1
      existing.playbackOptions = options
      existing.mediaSession.isActive = true
      existing.ensureInitialized(context, args)
      existing
    } else {
      val player = ExoPlayer.Builder(context).build()
      val mediaSession = MediaSessionCompat(context, "ThaPlayer_$controllerId").apply {
        setCallback(object : MediaSessionCompat.Callback() {
          override fun onPlay() { player.play() }
          override fun onPause() { player.pause() }
        })
        isActive = true
      }
      val entry = SharedPlayerEntry(
        controllerId = controllerId,
        player = player,
        mediaSession = mediaSession,
        handler = Handler(Looper.getMainLooper()),
        refs = 1,
        playbackOptions = options,
      )
      entries[controllerId] = entry
      entry.ensureInitialized(context, args)
      entry
    }
  }

  fun release(controllerId: Long, view: PlayerView) {
    val entry = entries[controllerId] ?: return
    entry.detachView(view)
    entry.refs -= 1
    if (entry.refs <= 0) {
      entry.readyFallbackRunnable?.let(entry.handler::removeCallbacks)
      entry.attachedView?.get()?.let {
        it.player = null
        it.keepScreenOn = false
      }
      entry.attachedView = null
      entry.mediaSession.isActive = false
      entry.mediaSession.release()
      entry.player.release()
      entries.remove(controllerId)
    }
  }
}

private fun SharedPlayerEntry.attachView(view: PlayerView) {
  // Remove stale references and duplicates for this view
  viewRefs.removeAll { ref ->
    val existing = ref.get()
    existing == null || existing === view
  }
  // Detach current, if different
  val current = attachedView?.get()
  if (current != null && current !== view) {
    current.player = null
    current.keepScreenOn = false
  }
  viewRefs.add(WeakReference(view))
  attachedView = WeakReference(view)
  view.player = player
  view.keepScreenOn = true
}

private fun SharedPlayerEntry.detachView(view: PlayerView) {
  viewRefs.removeAll { ref ->
    val existing = ref.get()
    existing == null || existing === view
  }
  if (attachedView?.get() === view) {
    val fallback = viewRefs.lastOrNull { it.get() != null }?.get()
    attachedView = fallback?.let { WeakReference(it) }
    fallback?.let {
      it.player = player
      it.keepScreenOn = true
    } ?: run {
      attachedView = null
    }
  }
  view.player = null
  view.keepScreenOn = false
}

private fun SharedPlayerEntry.suppressAudioInternal() {
  if (audioSuppressed) return
  storedVolume = player.volume
  player.volume = 0f
  audioSuppressed = true
}

private fun SharedPlayerEntry.restoreAudioInternal() {
  if (!audioSuppressed) return
  player.volume = storedVolume
  audioSuppressed = false
}

private fun SharedPlayerEntry.ensureInitialized(
  context: Context,
  args: Map<*, *>?,
) {
  if (initialized) return
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

  pendingPlayOnceReady = startAutoPlay
  hasRenderedFirstFrame = false
  readyFallbackRunnable?.let(handler::removeCallbacks)
  readyFallbackRunnable = null
  player.playWhenReady = false
  suppressAudioInternal()

  player.setMediaSources(items)
  player.prepare()
  player.repeatMode = if (loop) Player.REPEAT_MODE_ALL else Player.REPEAT_MODE_OFF
  if (startMs > 0L) player.seekTo(startMs)
  applyDataSaverInternal(dataSaver)

  if (!startAutoPlay) {
    player.pause()
    restoreAudioInternal()
  }

  initialized = true
}

private fun SharedPlayerEntry.applyDataSaverInternal(enable: Boolean) {
  val builder = player.trackSelectionParameters.buildUpon()
  if (enable) {
    builder.clearOverridesOfType(C.TRACK_TYPE_VIDEO)
    builder.setMaxVideoBitrate(800_000)
  } else {
    builder.setMaxVideoBitrate(Int.MAX_VALUE)
  }
  player.trackSelectionParameters = builder.build()
}
