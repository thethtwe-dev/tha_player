library;

export 'src/core/thaplayer_controller.dart';
export 'src/ui/thaplayer_view.dart';
import 'tha_player_platform_interface.dart';

class ThaPlayer {
  Future<String?> getPlatformVersion() {
    return ThaPlayerPlatform.instance.getPlatformVersion();
  }
}
