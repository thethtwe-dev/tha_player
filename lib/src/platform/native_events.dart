import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class ThaPlaybackState {
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool isBuffering;

  const ThaPlaybackState({
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.isBuffering,
  });
}

class ThaNativeEvents {
  final int viewId;
  late final EventChannel _eventChannel;
  StreamSubscription? _sub;

  final ValueNotifier<ThaPlaybackState> state = ValueNotifier(
    const ThaPlaybackState(
      position: Duration.zero,
      duration: Duration.zero,
      isPlaying: false,
      isBuffering: true,
    ),
  );

  ThaNativeEvents(this.viewId) {
    _eventChannel = EventChannel('thaplayer/events_$viewId');
  }

  void start() {
    _sub?.cancel();
    _sub = _eventChannel.receiveBroadcastStream().listen(
      _onEvent,
      onError: (_) {},
    );
  }

  void _onEvent(dynamic evt) {
    if (evt is Map) {
      final posMs = (evt['positionMs'] as num?)?.toInt() ?? 0;
      final durMs = (evt['durationMs'] as num?)?.toInt() ?? 0;
      final playing = evt['isPlaying'] == true;
      final buffering = evt['isBuffering'] == true;
      state.value = ThaPlaybackState(
        position: Duration(milliseconds: posMs),
        duration: Duration(milliseconds: durMs),
        isPlaying: playing,
        isBuffering: buffering,
      );
    }
  }

  void dispose() {
    _sub?.cancel();
    state.dispose();
  }
}
