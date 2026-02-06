import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/media_source.dart';
import '../core/drm.dart';
import 'native_events.dart';
import 'native_tracks.dart';
import 'playback_options.dart';

/// User-facing playback preferences that persist on the controller.
@immutable
class ThaPlayerPreferences {
  static const Object _unset = Object();

  /// Whether data saver mode is enabled.
  final bool dataSaver;

  /// Manually selected video track id (or null for auto).
  final String? manualVideoTrackId;

  /// Manually selected audio track id (or null for auto).
  final String? manualAudioTrackId;

  /// Manually selected subtitle track id (or null for off/auto).
  final String? manualSubtitleTrackId;

  /// Playback speed (1.0 = normal).
  final double playbackSpeed;

  const ThaPlayerPreferences({
    this.dataSaver = false,
    this.manualVideoTrackId,
    this.manualAudioTrackId,
    this.manualSubtitleTrackId,
    this.playbackSpeed = 1.0,
  });

  ThaPlayerPreferences copyWith({
    bool? dataSaver,
    Object? manualVideoTrackId = _unset,
    Object? manualAudioTrackId = _unset,
    Object? manualSubtitleTrackId = _unset,
    double? playbackSpeed,
  }) {
    return ThaPlayerPreferences(
      dataSaver: dataSaver ?? this.dataSaver,
      manualVideoTrackId: manualVideoTrackId == _unset
          ? this.manualVideoTrackId
          : manualVideoTrackId as String?,
      manualAudioTrackId: manualAudioTrackId == _unset
          ? this.manualAudioTrackId
          : manualAudioTrackId as String?,
      manualSubtitleTrackId: manualSubtitleTrackId == _unset
          ? this.manualSubtitleTrackId
          : manualSubtitleTrackId as String?,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ThaPlayerPreferences &&
        other.dataSaver == dataSaver &&
        other.manualVideoTrackId == manualVideoTrackId &&
        other.manualAudioTrackId == manualAudioTrackId &&
        other.manualSubtitleTrackId == manualSubtitleTrackId &&
        other.playbackSpeed == playbackSpeed;
  }

  @override
  int get hashCode => Object.hash(
    dataSaver,
    manualVideoTrackId,
    manualAudioTrackId,
    manualSubtitleTrackId,
    playbackSpeed,
  );
}

/// Bridge between Flutter and the native player implementation.
///
/// The controller manages the playlist, lifecycle, and exposes convenience
/// methods like [play], [pause], [seekTo], and track selection.
class ThaNativePlayerController {
  final List<ThaMediaSource> playlist;
  final bool autoPlay;
  final bool loop;
  final ThaPlaybackOptions playbackOptions;

  /// Controller-wide preferences that persist across fullscreen swaps.
  final ValueNotifier<ThaPlayerPreferences> preferences;

  /// Shared BoxFit state for inline and fullscreen views.
  final ValueNotifier<BoxFit> boxFitNotifier;
  static int _nextControllerId = 1;
  final int _controllerId;
  MethodChannel? _channel;
  ThaNativeEvents? _events;
  final ThaPlayerPreferences _initialPreferences;
  final ValueNotifier<ThaPlaybackState> _playbackState = ValueNotifier(
    const ThaPlaybackState(
      position: Duration.zero,
      duration: Duration.zero,
      isPlaying: false,
      isBuffering: true,
    ),
  );
  final ValueNotifier<ThaPlayerError?> _errorDetails = ValueNotifier(null);
  bool _boxFitUserSet = false;
  int _resumePositionMs = 0;
  bool _wasPlaying = false;
  VoidCallback? _eventsListener;
  VoidCallback? _errorListener;

  /// Create a controller with a single media item.
  ThaNativePlayerController.single(
    ThaMediaSource source, {
    this.autoPlay = true,
    this.loop = false,
    this.playbackOptions = const ThaPlaybackOptions(),
    ThaPlayerPreferences initialPreferences = const ThaPlayerPreferences(),
    BoxFit initialBoxFit = BoxFit.contain,
  }) : playlist = [source],
       preferences = ValueNotifier(initialPreferences),
       boxFitNotifier = ValueNotifier(initialBoxFit),
       _initialPreferences = initialPreferences,
       _controllerId = _nextControllerId++ {
    _wasPlaying = autoPlay;
  }

  /// Create a controller for a custom playlist.
  ThaNativePlayerController.playlist(
    this.playlist, {
    this.autoPlay = true,
    this.loop = false,
    this.playbackOptions = const ThaPlaybackOptions(),
    ThaPlayerPreferences initialPreferences = const ThaPlayerPreferences(),
    BoxFit initialBoxFit = BoxFit.contain,
  }) : preferences = ValueNotifier(initialPreferences),
       boxFitNotifier = ValueNotifier(initialBoxFit),
       _initialPreferences = initialPreferences,
       _controllerId = _nextControllerId++ {
    _wasPlaying = autoPlay;
  }

  /// Serialized arguments that are passed to the platform view.
  Map<String, dynamic> get creationParams => {
    'autoPlay': autoPlay,
    'loop': loop,
    'startPositionMs': _resumePositionMs,
    'startAutoPlay': _wasPlaying,
    'dataSaver': preferences.value.dataSaver,
    'playbackOptions': playbackOptions.toMap(),
    'controllerId': _controllerId,
    'playlist': playlist
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
    // Capture last known state before we dispose the old stream.
    final previousState = _events?.state.value;
    if (previousState != null) {
      _resumePositionMs = previousState.position.inMilliseconds;
      _wasPlaying = previousState.isPlaying;
    }
    if (_eventsListener != null) {
      _events?.state.removeListener(_eventsListener!);
    }
    if (_errorListener != null) {
      _events?.errorDetails.removeListener(_errorListener!);
    }
    // Rebind events; dispose previous to avoid leaks
    _events?.dispose();
    final ev = ThaNativeEvents(id);
    ev.start();
    _events = ev;
    _eventsListener = () {
      final v = ev.state.value;
      _playbackState.value = v;
      _resumePositionMs = v.position.inMilliseconds;
      _wasPlaying = v.isPlaying;
    };
    _errorListener = () {
      _errorDetails.value = ev.errorDetails.value;
    };
    ev.state.addListener(_eventsListener!);
    ev.errorDetails.addListener(_errorListener!);
    _playbackState.value = ev.state.value;
    _errorDetails.value = ev.errorDetails.value;
    _applyPreferencesToNative();
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
      setPlaybackSpeed(speed, persist: true);

  /// Adjust the playback speed. Set [persist] to false for temporary boosts.
  Future<void> setPlaybackSpeed(double speed, {bool persist = true}) async {
    if (persist) {
      _updatePreferences(preferences.value.copyWith(playbackSpeed: speed));
    }
    await _invoke('setSpeed', {'speed': speed});
  }

  /// Toggle looping for the current item or playlist.
  Future<void> setLooping(bool looping) async =>
      _invoke('setLooping', {'loop': looping});

  /// Update the content scaling of the platform view.
  ///
  /// When [updatePreference] is true, the value is stored on the controller so
  /// fullscreen swaps keep the user's choice.
  Future<void> setBoxFit(BoxFit fit, {bool updatePreference = true}) async {
    if (updatePreference && boxFitNotifier.value != fit) {
      boxFitNotifier.value = fit;
      _boxFitUserSet = true;
    }
    await _invoke('setBoxFit', {
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
  }

  /// Apply an initial fit only when no user choice has been stored yet.
  ///
  /// This is used by widgets to keep a controller-wide BoxFit in sync without
  /// overriding a user-set value.
  void setInitialBoxFit(BoxFit fit) {
    if (_boxFitUserSet) return;
    if (boxFitNotifier.value != fit) {
      boxFitNotifier.value = fit;
    }
  }

  /// Re-prepares the media source and attempts to resume playback.
  Future<void> retry() async => _invoke('retry');

  /// Caps the bitrate when [enable] is true in order to save data.
  Future<void> setDataSaver(bool enable) async {
    _updatePreferences(preferences.value.copyWith(dataSaver: enable));
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
    _updatePreferences(preferences.value.copyWith(manualVideoTrackId: trackId));
    await _invoke('setVideoTrack', {'id': trackId});
  }

  /// Clears manual track overrides and returns to automatic selection.
  Future<void> clearVideoTrackSelection() async {
    _updatePreferences(preferences.value.copyWith(manualVideoTrackId: null));
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
    _updatePreferences(preferences.value.copyWith(manualAudioTrackId: trackId));
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
    _updatePreferences(
      preferences.value.copyWith(manualSubtitleTrackId: trackId),
    );
    await _invoke('setSubtitleTrack', {'id': trackId});
  }

  /// Requests picture-in-picture mode where supported.
  Future<bool> enterPictureInPicture() async {
    final ok = await _invokeResult<bool>('enterPip');
    return ok ?? false;
  }

  /// Reset playback preferences to the initial values passed to the controller.
  ///
  /// When [applyToNative] is true, the current native player is updated
  /// immediately.
  void resetPreferences({bool applyToNative = true}) {
    _updatePreferences(_initialPreferences);
    if (applyToNative) {
      _applyPreferencesToNative();
    }
  }

  /// Release native resources.
  Future<void> dispose() async {
    await _invoke('dispose');
    _events?.dispose();
    _playbackState.dispose();
    _errorDetails.dispose();
    preferences.dispose();
    boxFitNotifier.dispose();
  }

  /// Playback events emitted by the native layer.
  ThaNativeEvents? get events => _events;

  /// Current playback state exposed as a listenable.
  ///
  /// Listen to this instead of reaching into platform events directly.
  ValueListenable<ThaPlaybackState> get playbackState => _playbackState;

  /// Structured error details emitted by the native layer.
  ValueListenable<ThaPlayerError?> get errorDetails => _errorDetails;

  void _updatePreferences(ThaPlayerPreferences next) {
    if (preferences.value == next) return;
    preferences.value = next;
  }

  void _applyPreferencesToNative() {
    final prefs = preferences.value;
    unawaited(setPlaybackSpeed(prefs.playbackSpeed, persist: false));
    unawaited(setDataSaver(prefs.dataSaver));
    if (prefs.manualVideoTrackId == null) {
      unawaited(clearVideoTrackSelection());
    } else {
      unawaited(selectVideoTrack(prefs.manualVideoTrackId!));
    }
    unawaited(selectAudioTrack(prefs.manualAudioTrackId));
    unawaited(selectSubtitleTrack(prefs.manualSubtitleTrackId));
  }

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
