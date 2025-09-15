library;

export 'src/core/media_source.dart';
export 'src/core/drm.dart';
export 'src/platform/native_player_controller.dart';
export 'src/platform/native_player_view.dart';
export 'src/ui/native_fullscreen.dart';
export 'src/ui/native_controls.dart';
export 'src/ui/modern_player.dart';
import 'tha_player_platform_interface.dart';

class ThaPlayer {
  Future<String?> getPlatformVersion() {
    return ThaPlayerPlatform.instance.getPlatformVersion();
  }
}
