package com.example.tha_player

import android.app.Activity
import android.content.Context
import android.media.AudioManager
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import okhttp3.OkHttpClient
import java.lang.ref.WeakReference

class ThaPlayerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
  private lateinit var versionChannel: MethodChannel
  private lateinit var utilChannel: MethodChannel
  private lateinit var context: Context
  private var activity: Activity? = null

  companion object {
    @Volatile
    private var activityRef: WeakReference<Activity?> = WeakReference(null)

    @JvmStatic
    fun setHttpClientFactory(factory: (() -> OkHttpClient)?) {
      ThaPlayerHttpClientProvider.setFactory(factory)
    }

    @JvmStatic
    internal fun currentActivity(): Activity? = activityRef.get()
  }

  override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    versionChannel = MethodChannel(binding.binaryMessenger, "tha_player")
    utilChannel = MethodChannel(binding.binaryMessenger, "thaplayer/channel")
    context = binding.applicationContext
    versionChannel.setMethodCallHandler(this)
    utilChannel.setMethodCallHandler(this)

    // Register platform view for native player surface
    binding.platformViewRegistry.registerViewFactory(
      "thaplayer/native_view",
      ThaPlayerViewFactory(binding.binaryMessenger, context)
    )
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    versionChannel.setMethodCallHandler(null)
    utilChannel.setMethodCallHandler(null)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
    activityRef = WeakReference(activity)
  }

  override fun onDetachedFromActivity() {
    activity = null
    activityRef = WeakReference(null)
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
    activityRef = WeakReference(activity)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
    activityRef = WeakReference(null)
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "getPlatformVersion" -> {
        result.success("Android " + android.os.Build.VERSION.RELEASE)
      }
      "setVolume" -> {
        val delta = call.argument<Double>("value") ?: 0.0
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        val newVol = (current + delta * max).toInt().coerceIn(0, max)
        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, newVol, 0)
        val normalized = if (max > 0) newVol.toDouble() / max else 0.0
        result.success(normalized)
      }
      "setBrightness" -> {
        val delta = call.argument<Double>("value")?.toFloat() ?: 0f
        val window = activity?.window
        if (window != null) {
          val attributes = window.attributes
          val currentBrightness = if (attributes.screenBrightness >= 0f) {
            attributes.screenBrightness
          } else {
            0.5f
          }
          val newBrightness = (currentBrightness + delta).coerceIn(0.01f, 1.0f)
          attributes.screenBrightness = newBrightness
          window.attributes = attributes
          result.success(newBrightness.toDouble())
        } else {
          result.error("NO_ACTIVITY", "Activity is null", null)
        }
      }
      else -> result.notImplemented()
    }
  }
}
