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

class ThaPlayerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
  private lateinit var channel: MethodChannel
  private lateinit var context: Context
  private var activity: Activity? = null

  override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(binding.binaryMessenger, "thaplayer/channel")
    context = binding.applicationContext
    channel.setMethodCallHandler(this)

    // Register platform view for native player surface
    binding.platformViewRegistry.registerViewFactory(
      "thaplayer/native_view",
      ThaPlayerViewFactory(binding.binaryMessenger, context)
    )
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivity() {
    activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "setVolume" -> {
        val delta = call.argument<Double>("value") ?: 0.0
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        val newVol = (current + delta * max).toInt().coerceIn(0, max)
        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, newVol, 0)
        result.success(null)
      }
      "setBrightness" -> {
        val delta = call.argument<Double>("value")?.toFloat() ?: 0f
        val window = activity?.window
        if (window != null) {
          val attributes = window.attributes
          val newBrightness = (attributes.screenBrightness + delta).coerceIn(0.01f, 1.0f)
          attributes.screenBrightness = newBrightness
          window.attributes = attributes
          result.success(null)
        } else {
          result.error("NO_ACTIVITY", "Activity is null", null)
        }
      }
      else -> result.notImplemented()
    }
  }
}
