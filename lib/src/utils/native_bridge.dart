import 'package:flutter/services.dart';

class NativeBridge {
  static const _channel = MethodChannel('thaplayer/channel');

  static Future<double> setVolume(double delta) async {
    final result = await _channel.invokeMethod<double>('setVolume', {
      'value': delta,
    });
    return (result ?? 0.0).clamp(0.0, 1.0);
  }

  static Future<double> setBrightness(double delta) async {
    final result = await _channel.invokeMethod<double>('setBrightness', {
      'value': delta,
    });
    return (result ?? 0.0).clamp(0.0, 1.0);
  }
}
