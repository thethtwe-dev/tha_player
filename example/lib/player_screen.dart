import 'package:flutter/material.dart';
import 'package:tha_player/tha_player.dart';

class PlayerScreen extends StatefulWidget {
  final String url;
  final bool isLive;
  final bool autoFullscreen;
  const PlayerScreen({
    super.key,
    required this.url,
    this.isLive = false,
    this.autoFullscreen = false,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final ThaNativePlayerController controller;

  @override
  void initState() {
    super.initState();
    controller = ThaNativePlayerController.single(
      ThaMediaSource(widget.url, isLive: widget.isLive),
      autoPlay: true,
      loop: false,
      initialPreferences: const ThaPlayerPreferences(playbackSpeed: 1.0),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  String _formatDuration(Duration value) {
    final totalSeconds = value.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return hours > 0
        ? '${two(hours)}:${two(minutes)}:${two(seconds)}'
        : '${two(minutes)}:${two(seconds)}';
  }

  Widget _buildStatus() {
    return ValueListenableBuilder<ThaPlaybackState>(
      valueListenable: controller.playbackState,
      builder: (context, state, _) {
        final status = state.isBuffering
            ? 'Buffering'
            : (state.isPlaying ? 'Playing' : 'Paused');
        return Text(
          '${_formatDuration(state.position)} / ${_formatDuration(state.duration)} • $status',
          style: Theme.of(context).textTheme.bodySmall,
        );
      },
    );
  }

  Widget _buildErrorBanner() {
    return ValueListenableBuilder<ThaPlayerError?>(
      valueListenable: controller.errorDetails,
      builder: (context, error, _) {
        if (error == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Error: ${error.message} (${error.code})',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.redAccent),
            textAlign: TextAlign.center,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Player Screen')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          const aspectRatio = 16 / 9;
          const statusHeight = 44.0;
          const statusSpacing = 12.0;
          final maxWidth = constraints.maxWidth;
          final maxHeight = constraints.maxHeight;
          final minPlayerHeight = maxHeight - statusHeight - statusSpacing;
          final allowStatus = minPlayerHeight > 0;
          final usableHeight = allowStatus ? minPlayerHeight : maxHeight;

          var playerWidth = maxWidth;
          var playerHeight = playerWidth / aspectRatio;
          if (playerHeight > usableHeight) {
            playerHeight = usableHeight;
            playerWidth = playerHeight * aspectRatio;
          }

          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: playerWidth,
                  height: playerHeight,
                  child: ThaModernPlayer(
                    controller: controller,
                    autoFullscreen: widget.autoFullscreen,
                    onErrorDetails: (error) {
                      if (error != null) {
                        debugPrint(
                          'Playback error: ${error.code} • ${error.message}',
                        );
                      }
                    },
                    overlay: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.play_circle_fill,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'THA Player',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                          ),
                        ),
                        if (widget.isLive) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'LIVE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (allowStatus) ...[
                  const SizedBox(height: statusSpacing),
                  _buildStatus(),
                  _buildErrorBanner(),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
