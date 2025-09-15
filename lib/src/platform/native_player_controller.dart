import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/media_source.dart';
import '../core/drm.dart';
import 'native_events.dart';

class ThaNativePlayerController {
  final List<ThaMediaSource> playlist;
  final bool autoPlay;
  final bool loop;
  MethodChannel? _channel;
  ThaNativeEvents? _events;
  int _resumePositionMs = 0;
  bool _wasPlaying = false;
  VoidCallback? _eventsListener;

  ThaNativePlayerController.single(
    ThaMediaSource source, {
    this.autoPlay = true,
    this.loop = false,
  }) : playlist = [source];

  ThaNativePlayerController.playlist(
    this.playlist, {
    this.autoPlay = true,
    this.loop = false,
  });

  Map<String, dynamic> get creationParams => {
    'autoPlay': autoPlay,
    'loop': loop,
    'startPositionMs': _resumePositionMs,
    'startAutoPlay': _wasPlaying,
    'playlist':
        playlist
            .map(
              (s) => {
                'url': s.url,
                'headers': s.headers ?? {},
                'isLive': s.isLive,
                'drm': _drmToMap(s.drm),
              },
            )
            .toList(),
  };

  void attachViewId(int id) {
    _channel = MethodChannel('thaplayer/view_$id');
    // Rebind events; dispose previous to avoid leaks
    _events?.dispose();
    final ev = ThaNativeEvents(id);
    ev.start();
    _events = ev;
    _eventsListener?.call();
    _eventsListener = () {
      final v = ev.state.value;
      _resumePositionMs = v.position.inMilliseconds;
      _wasPlaying = v.isPlaying;
    };
    ev.state.addListener(_eventsListener!);
  }

  Map<String, dynamic> _drmToMap(ThaDrmConfig drm) => {
    'type': drm.type.name,
    'licenseUrl': drm.licenseUrl,
    'headers': drm.headers ?? {},
    'clearKey': drm.clearKey,
    'contentId': drm.contentId,
  };

  Future<void> play() async => _invoke('play');
  Future<void> pause() async => _invoke('pause');
  Future<void> seekTo(Duration position) async =>
      _invoke('seekTo', {'millis': position.inMilliseconds});
  Future<void> setSpeed(double speed) async =>
      _invoke('setSpeed', {'speed': speed});
  Future<void> setLooping(bool looping) async =>
      _invoke('setLooping', {'loop': looping});
  Future<void> setBoxFit(BoxFit fit) async => _invoke('setBoxFit', {
    'fit': switch (fit) {
      BoxFit.contain => 'contain',
      BoxFit.cover => 'cover',
      BoxFit.fill => 'fill',
      BoxFit.fitWidth => 'fitWidth',
      BoxFit.fitHeight => 'fitHeight',
      BoxFit.none => 'contain',
      BoxFit.scaleDown => 'contain',
    },
  });

  Future<void> dispose() async {
    await _invoke('dispose');
    _events?.dispose();
  }

  ThaNativeEvents? get events => _events;

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async {
    final ch = _channel;
    if (ch == null) return;
    try {
      await ch.invokeMethod(method, args);
    } catch (_) {}
  }
}
