import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/media_source.dart';
import '../core/drm.dart';
import 'native_events.dart';
import 'native_tracks.dart';
import 'playback_options.dart';

/// Bridge between Flutter and the native player implementation.
///
/// The controller manages the playlist, lifecycle, and exposes convenience
/// methods like [play], [pause], [seekTo], and track selection.
class ThaNativePlayerController {
  final List<ThaMediaSource> playlist;
  final bool autoPlay;
  final bool loop;
  final ThaPlaybackOptions playbackOptions;
  static int _nextControllerId = 1;
  final int _controllerId;
  MethodChannel? _channel;
  ThaNativeEvents? _events;
  int _resumePositionMs = 0;
  bool _wasPlaying = false;
  VoidCallback? _eventsListener;
  bool _dataSaver = false;

  /// Create a controller with a single media item.
  ThaNativePlayerController.single(
    ThaMediaSource source, {
    this.autoPlay = true,
    this.loop = false,
    this.playbackOptions = const ThaPlaybackOptions(),
  })  : playlist = [source],
        _controllerId = _nextControllerId++ {
    _wasPlaying = autoPlay;
  }

  /// Create a controller for a custom playlist.
  ThaNativePlayerController.playlist(
    this.playlist, {
    this.autoPlay = true,
    this.loop = false,
    this.playbackOptions = const ThaPlaybackOptions(),
  }) : _controllerId = _nextControllerId++ {
    _wasPlaying = autoPlay;
  }

  /// Serialized arguments that are passed to the platform view.
  Map<String, dynamic> get creationParams => {
    'autoPlay': autoPlay,
    'loop': loop,
    'startPositionMs': _resumePositionMs,
    'startAutoPlay': _wasPlaying,
    'dataSaver': _dataSaver,
    'playbackOptions': playbackOptions.toMap(),
    'controllerId': _controllerId,
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

  /// Bind the controller to a platform view id.
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

  /// Begin playback if ready.
  Future<void> play() async => _invoke('play');

  /// Pause playback while retaining the buffer.
  Future<void> pause() async => _invoke('pause');

  /// Seek to a new [position].
  Future<void> seekTo(Duration position) async =>
      _invoke('seekTo', {'millis': position.inMilliseconds});

  /// Adjust the playback [speed].
  Future<void> setSpeed(double speed) async =>
      _invoke('setSpeed', {'speed': speed});

  /// Toggle looping for the current item or playlist.
  Future<void> setLooping(bool looping) async =>
      _invoke('setLooping', {'loop': looping});

  /// Update the content scaling of the platform view.
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

  /// Re-prepares the media source and attempts to resume playback.
  Future<void> retry() async => _invoke('retry');

  /// Caps the bitrate when [enable] is true in order to save data.
  Future<void> setDataSaver(bool enable) async {
    _dataSaver = enable;
    await _invoke('setDataSaver', {'enable': enable});
  }

  /// Retrieves the available video tracks from the native player.
  Future<List<ThaVideoTrack>> getVideoTracks() async {
    final raw = await _invokeResult<List<dynamic>>('getVideoTracks');
    if (raw == null) return const [];
    return raw
        .map((e) => e is Map ? Map<dynamic, dynamic>.from(e) : null)
        .whereType<Map<dynamic, dynamic>>()
        .map(ThaVideoTrack.fromMap)
        .toList();
  }

  /// Select a specific video track by [trackId].
  Future<void> selectVideoTrack(String trackId) async {
    await _invoke('setVideoTrack', {'id': trackId});
  }

  /// Clears manual track overrides and returns to automatic selection.
  Future<void> clearVideoTrackSelection() async {
    await _invoke('setVideoTrack', {'id': null});
  }

  /// Retrieves the available audio tracks.
  Future<List<ThaAudioTrack>> getAudioTracks() async {
    final raw = await _invokeResult<List<dynamic>>('getAudioTracks');
    if (raw == null) return const [];
    return raw
        .map((e) => e is Map ? Map<dynamic, dynamic>.from(e) : null)
        .whereType<Map<dynamic, dynamic>>()
        .map(ThaAudioTrack.fromMap)
        .toList();
  }

  /// Selects an audio track. Passing `null` restores the default selection.
  Future<void> selectAudioTrack(String? trackId) async {
    await _invoke('setAudioTrack', {'id': trackId});
  }

  /// Retrieves legible subtitle / caption tracks.
  Future<List<ThaSubtitleTrack>> getSubtitleTracks() async {
    final raw = await _invokeResult<List<dynamic>>('getSubtitleTracks');
    if (raw == null) return const [];
    return raw
        .map((e) => e is Map ? Map<dynamic, dynamic>.from(e) : null)
        .whereType<Map<dynamic, dynamic>>()
        .map(ThaSubtitleTrack.fromMap)
        .toList();
  }

  /// Selects a subtitle track. Passing `null` disables text rendering.
  Future<void> selectSubtitleTrack(String? trackId) async {
    await _invoke('setSubtitleTrack', {'id': trackId});
  }

  /// Requests picture-in-picture mode where supported.
  Future<bool> enterPictureInPicture() async {
    final ok = await _invokeResult<bool>('enterPip');
    return ok ?? false;
  }

  /// Release native resources.
  Future<void> dispose() async {
    await _invoke('dispose');
    _events?.dispose();
  }

  /// Playback events emitted by the native layer.
  ThaNativeEvents? get events => _events;

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async {
    final ch = _channel;
    if (ch == null) return;
    try {
      await ch.invokeMethod(method, args);
    } catch (_) {}
  }

  Future<T?> _invokeResult<T>(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    final ch = _channel;
    if (ch == null) return null;
    try {
      return await ch.invokeMethod<T>(method, args);
    } catch (_) {
      return null;
    }
  }
}
