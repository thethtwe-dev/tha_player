import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tha_player/tha_player.dart';
import 'package:video_player/video_player.dart';

class ControlBar extends StatefulWidget {
  final VideoPlayerController controller;
  final bool isLocked;
  final VoidCallback onToggleLock;
  final BoxFit boxFit;
  final ValueChanged<BoxFit> onBoxFitChange;
  final ThaPlayerController thaController;
  final ValueNotifier<BoxFit> boxFitNotifier;
  final Widget? overlay;
  final bool isFullscreen;

  const ControlBar({
    super.key,
    required this.controller,
    required this.isLocked,
    required this.onToggleLock,
    required this.boxFit,
    required this.onBoxFitChange,
    required this.thaController,
    required this.boxFitNotifier,
    this.overlay,
    this.isFullscreen = false,
  });

  @override
  State<ControlBar> createState() => _ControlBarState();
}

class _ControlBarState extends State<ControlBar> {
  late VoidCallback _listener;

  @override
  void initState() {
    super.initState();
    _listener = () {
      if (mounted) setState(() {});
    };
    widget.controller.addListener(_listener);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black45,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          if (widget.isFullscreen) SizedBox(width: 20),
          IconButton(
            icon: Icon(
              widget.controller.value.isPlaying
                  ? Icons.pause
                  : Icons.play_arrow,
              color: Colors.white,
            ),
            onPressed: () {
              widget.controller.value.isPlaying
                  ? widget.controller.pause()
                  : widget.controller.play();
            },
          ),
          Text(
            "${_format(widget.controller.value.position)} / ${_format(widget.controller.value.duration)}",
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          const Spacer(),

          PopupMenuButton<double>(
            icon: const Icon(Icons.speed, color: Colors.white),
            onSelected: (speed) => widget.controller.setPlaybackSpeed(speed),
            itemBuilder:
                (context) => [
                  for (final speed in [0.5, 1.0, 1.5, 2.0])
                    PopupMenuItem(value: speed, child: Text('${speed}x')),
                ],
          ),

          IconButton(
            icon: Icon(
              widget.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
              color: Colors.white,
            ),
            onPressed: () {
              if (widget.isFullscreen) {
                Navigator.pop(context); // ✅ Exit fullscreen
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => _FullScreenPlayer(
                          thaController: widget.thaController,
                          boxFitNotifier: widget.boxFitNotifier,
                          overlay: widget.overlay,
                        ),
                  ),
                );
              }
            },
          ),

          IconButton(
            icon: Icon(
              widget.isLocked ? Icons.lock : Icons.lock_open,
              color: widget.isLocked ? Colors.red : Colors.white,
            ),
            onPressed: widget.onToggleLock,
          ),

          PopupMenuButton<BoxFit>(
            tooltip: 'Resize',
            icon: const Icon(Icons.aspect_ratio, color: Colors.white),
            onSelected: widget.onBoxFitChange,
            itemBuilder:
                (context) => [
                  menuItem('Contain', BoxFit.contain),
                  menuItem('Cover', BoxFit.cover),
                  menuItem('Fill', BoxFit.fill),
                  menuItem('Fit Width', BoxFit.fitWidth),
                  menuItem('Fit Height', BoxFit.fitHeight),
                  menuItem('Scale Down', BoxFit.scaleDown),
                ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<BoxFit> menuItem(String label, BoxFit value) {
    return PopupMenuItem(
      value: value,
      child: Text(
        label,
        style: TextStyle(color: widget.boxFit == value ? Colors.blue : null),
      ),
    );
  }

  String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _FullScreenPlayer extends StatefulWidget {
  final ThaPlayerController thaController;
  final ValueNotifier<BoxFit> boxFitNotifier;
  final Widget? overlay;

  const _FullScreenPlayer({
    required this.thaController,
    required this.boxFitNotifier,
    this.overlay,
  });

  @override
  State<_FullScreenPlayer> createState() => _FullScreenPlayerState();
}

class _FullScreenPlayerState extends State<_FullScreenPlayer> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.leanBack);
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
      body: Stack(
        children: [
          Center(
            child: ThaPlayerView(
              thaController: widget.thaController,
              boxFitNotifier: widget.boxFitNotifier,
              aspectRatio: widget.thaController.controller.value.aspectRatio,
              overlay: widget.overlay,
              isFullscreen: true,
            ),
          ),
        ],
      ),
    );
  }
}
