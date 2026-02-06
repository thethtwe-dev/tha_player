/// Top-level library export for tha_player.
///
/// Import `package:tha_player/tha_player.dart` for the public API that bundles
/// media sources, controllers, and ready-made widgets.
// ignore: unnecessary_library_name
library tha_player;

export 'src/core/media_source.dart';
export 'src/core/drm.dart';
export 'src/platform/native_player_controller.dart';
export 'src/platform/native_player_view.dart';
export 'src/platform/native_events.dart';
export 'src/platform/native_tracks.dart';
export 'src/platform/playback_options.dart';
export 'src/ui/native_fullscreen.dart';
export 'src/ui/native_controls.dart';
export 'src/ui/modern_player.dart';
import 'tha_player_platform_interface.dart';

/// Simple facade around the platform interface. Primarily used by the
/// federated example tests; most clients should use the controller APIs
/// directly instead of this class.
class ThaPlayer {
  /// Returns the platform version reported by the host platform plugin.
  Future<String?> getPlatformVersion() {
    return ThaPlayerPlatform.instance.getPlatformVersion();
  }
}
