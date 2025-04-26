import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'tha_player_method_channel.dart';

abstract class ThaPlayerPlatform extends PlatformInterface {
  /// Constructs a ThaPlayerPlatform.
  ThaPlayerPlatform() : super(token: _token);

  static final Object _token = Object();

  static ThaPlayerPlatform _instance = MethodChannelThaPlayer();

  /// The default instance of [ThaPlayerPlatform] to use.
  ///
  /// Defaults to [MethodChannelThaPlayer].
  static ThaPlayerPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ThaPlayerPlatform] when
  /// they register themselves.
  static set instance(ThaPlayerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
