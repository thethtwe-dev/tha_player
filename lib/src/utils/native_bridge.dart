import 'package:flutter/services.dart';

class NativeBridge {
  static const _channel = MethodChannel('thaplayer/channel');

  static Future<void> setVolume(double value) async {
    await _channel.invokeMethod('setVolume', {'value': value});
  }

  static Future<void> setBrightness(double value) async {
    await _channel.invokeMethod('setBrightness', {'value': value});
  }
}
