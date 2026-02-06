import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/native_player_controller.dart';
import '../platform/native_events.dart';
import 'modern_player.dart';

/// Fullscreen route that reuses the underlying controller.
class ThaNativeFullscreenPage extends StatefulWidget {
  final ThaNativePlayerController controller;
  final ValueNotifier<BoxFit> boxFitNotifier;
  final Widget? overlay;
  final Duration doubleTapSeek;
  final Duration longPressSeek;
  final Duration autoHideAfter;
  final bool startLocked;
  final ValueChanged<ThaPlaybackState>? onStateChanged;
  final ValueChanged<String?>? onError;
  final ValueChanged<ThaPlayerError?>? onErrorDetails;

  const ThaNativeFullscreenPage({
    super.key,
    required this.controller,
    required this.boxFitNotifier,
    this.overlay,
    this.doubleTapSeek = const Duration(seconds: 10),
    this.longPressSeek = const Duration(seconds: 3),
    this.autoHideAfter = const Duration(seconds: 3),
    this.startLocked = false,
    this.onStateChanged,
    this.onError,
    this.onErrorDetails,
  });

  @override
  State<ThaNativeFullscreenPage> createState() =>
      _ThaNativeFullscreenPageState();
}

class _ThaNativeFullscreenPageState extends State<ThaNativeFullscreenPage> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: false,
        bottom: false,
        left: false,
        right: false,
        child: ThaModernPlayer(
          controller: widget.controller,
          overlay: widget.overlay,
          isFullscreen: true,
          autoFullscreen: false,
          doubleTapSeek: widget.doubleTapSeek,
          longPressSeek: widget.longPressSeek,
          autoHideAfter: widget.autoHideAfter,
          startLocked: widget.startLocked,
          boxFitNotifier: widget.boxFitNotifier,
          onStateChanged: widget.onStateChanged,
          onError: widget.onError,
          onErrorDetails: widget.onErrorDetails,
        ),
      ),
    );
  }
}
