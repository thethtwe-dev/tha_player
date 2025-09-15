package com.example.tha_player

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class ThaPlayerViewFactory(
  private val messenger: BinaryMessenger,
  private val context: Context,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

  override fun create(context: Context?, viewId: Int, args: Any?): PlatformView {
    val map = args as? Map<*, *>
    return ThaPlayerPlatformView(
      this.context,
      messenger,
      viewId,
      map
    )
  }
}

