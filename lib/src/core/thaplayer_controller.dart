import 'package:video_player/video_player.dart';

class ThaPlayerController {
  final String videoUrl;
  final bool autoPlay;
  final bool loop;

  late VideoPlayerController _controller;
  bool _initialized = false;

  ThaPlayerController.network(
    this.videoUrl, {
    this.autoPlay = true,
    this.loop = false,
  });

  // ignore: unnecessary_getters_setters
  VideoPlayerController get controller => _controller;
  bool get isInitialized => _initialized;

  set controller(VideoPlayerController c) => _controller = c;
  set initialized(bool v) => _initialized = v;

  Future<void> initialize() async {
    _controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
    await _controller.initialize();
    _controller.setLooping(loop);
    if (autoPlay) _controller.play();
    _initialized = true;
  }

  void play() => _controller.play();
  void pause() => _controller.pause();
  void seekTo(Duration position) => _controller.seekTo(position);
  Duration get position => _controller.value.position;
  Duration get duration => _controller.value.duration;

  void dispose() => _controller.dispose();
}
