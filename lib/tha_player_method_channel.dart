import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'tha_player_platform_interface.dart';

/// An implementation of [ThaPlayerPlatform] that uses method channels.
class MethodChannelThaPlayer extends ThaPlayerPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('tha_player');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
