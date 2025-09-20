import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/native_player_controller.dart';
import 'modern_player.dart';

/// Fullscreen route that reuses the underlying controller.
class ThaNativeFullscreenPage extends StatefulWidget {
  final ThaNativePlayerController controller;
  final ValueNotifier<BoxFit> boxFitNotifier;
  final Widget? overlay;

  const ThaNativeFullscreenPage({
    super.key,
    required this.controller,
    required this.boxFitNotifier,
    this.overlay,
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
        child: ThaModernPlayer(
          controller: widget.controller,
          overlay: widget.overlay,
          isFullscreen: true,
          autoFullscreen: false,
        ),
      ),
    );
  }
}
