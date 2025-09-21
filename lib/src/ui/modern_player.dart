import 'dart:async';
import 'package:flutter/material.dart';
import '../platform/native_player_controller.dart';
import '../platform/native_player_view.dart';
import '../platform/native_events.dart';
import '../platform/native_tracks.dart';
import '../utils/native_bridge.dart';
import 'native_fullscreen.dart';
import '../utils/thumbnails.dart';

/// High-level Flutter widget that renders the modern gesture driven UI.
class ThaModernPlayer extends StatefulWidget {
  final ThaNativePlayerController controller;
  final Widget? overlay;
  final Duration doubleTapSeek;
  final Duration longPressSeek;
  final Duration autoHideAfter;
  final BoxFit initialBoxFit;
  final bool startLocked;
  final bool isFullscreen;
  final bool autoFullscreen;
  final ValueChanged<ThaPlaybackState>? onStateChanged;
  final ValueChanged<String?>? onError;

  const ThaModernPlayer({
    super.key,
    required this.controller,
    this.overlay,
    this.doubleTapSeek = const Duration(seconds: 10),
    this.longPressSeek = const Duration(seconds: 3),
    this.autoHideAfter = const Duration(seconds: 3),
    this.initialBoxFit = BoxFit.contain,
    this.startLocked = false,
    this.isFullscreen = false,
    this.autoFullscreen = false,
    this.onStateChanged,
    this.onError,
  });

  @override
  State<ThaModernPlayer> createState() => _ThaModernPlayerState();
}

class _ThaModernPlayerState extends State<ThaModernPlayer> {
  static const Duration _longPressTick = Duration(milliseconds: 200);
  static const List<BoxFit> _boxFitChoices = <BoxFit>[
    BoxFit.contain,
    BoxFit.cover,
    BoxFit.fill,
    BoxFit.fitWidth,
    BoxFit.fitHeight,
  ];
  static const double _dialogCornerRadius = 5;
  late final ValueNotifier<BoxFit> _fit = ValueNotifier(widget.initialBoxFit);
  bool _showControls = true;
  Timer? _hide;
  Duration? _preview;
  Offset? _hStart;
  bool _showVol = false;
  bool _showBri = false;
  double _volLevel = 0.5;
  double _briLevel = 0.5;
  Timer? _vbHide;
  bool _locked = false;
  bool _lockHint = false;
  Timer? _lockHintTimer;
  String? _seekFlash;
  Alignment _seekFlashAlign = Alignment.center;
  Timer? _seekFlashTimer;
  Timer? _seekRepeat;
  Duration _longPressAccumulated = Duration.zero;
  Duration? _longPressTarget;
  int _longPressDirection = 0;
  List<ThumbCue>? _thumbs;
  bool _thumbsLoading = false;
  bool _dataSaver = false;
  List<ThaVideoTrack> _videoTracks = const <ThaVideoTrack>[];
  String? _manualTrackId;
  Future<void>? _pendingTrackFetch;
  int _trackFetchTicket = 0;
  bool _autoFullscreenTriggered = false;
  ThaPlaybackState? _lastStateNotification;
  String? _lastErrorNotification;
  List<ThaAudioTrack> _audioTracks = const <ThaAudioTrack>[];
  List<ThaSubtitleTrack> _subtitleTracks = const <ThaSubtitleTrack>[];
  Future<void>? _pendingAudioFetch;
  Future<void>? _pendingSubtitleFetch;
  int _audioFetchTicket = 0;
  int _subtitleFetchTicket = 0;
  String? _manualAudioId;
  String? _manualSubtitleId;

  // Convenience accessor for thumbnail headers (first item wins)
  Map<String, String>? get _thumbHeaders {
    final list = widget.controller.playlist;
    if (list.isEmpty) return null;
    return list.first.thumbnailHeaders;
  }

  ThaNativeEvents? get _events => widget.controller.events;

  @override
  void dispose() {
    _hide?.cancel();
    _seekRepeat?.cancel();
    _seekFlashTimer?.cancel();
    _fit.dispose();
    super.dispose();
  }

  void _restartHide() {
    _hide?.cancel();
    _hide = Timer(widget.autoHideAfter, () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _maybeAutoFullscreen() {
    if (_autoFullscreenTriggered) return;
    if (!widget.autoFullscreen || widget.isFullscreen) return;
    _autoFullscreenTriggered = true;
    _enterFullscreen();
  }

  void _enterFullscreen() {
    if (!mounted || widget.isFullscreen) return;
    setState(() {
      _showControls = false;
      _preview = null;
      _seekFlash = null;
    });
    _hide?.cancel();
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder:
                (_) => ThaNativeFullscreenPage(
                  controller: widget.controller,
                  boxFitNotifier: _fit,
                  overlay: widget.overlay,
                ),
          ),
        )
        .then((_) {
          if (!mounted) return;
          _hide?.cancel();
          _restartHide();
        });
  }

  @override
  void didUpdateWidget(covariant ThaModernPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoFullscreen != widget.autoFullscreen &&
        widget.autoFullscreen) {
      _autoFullscreenTriggered = false;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maybeAutoFullscreen(),
      );
    }
  }

  bool _hasStateChanged(ThaPlaybackState current) {
    final prev = _lastStateNotification;
    if (prev == null) return true;
    return prev.isPlaying != current.isPlaying ||
        prev.isBuffering != current.isBuffering ||
        prev.duration != current.duration ||
        prev.position != current.position;
  }

  @override
  void initState() {
    super.initState();
    _locked = widget.startLocked;
    _restartHide();
    _maybeLoadThumbs();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshVideoTracks();
      _maybeAutoFullscreen();
    });
  }

  Future<void> _maybeLoadThumbs() async {
    if (_thumbsLoading) return;
    final list = widget.controller.playlist;
    if (list.isEmpty) return;
    final vtt = list.first.thumbnailVttUrl;
    if (vtt == null) return;
    setState(() => _thumbsLoading = true);
    try {
      final cues = await fetchVttThumbnails(
        vtt,
        headers: list.first.thumbnailHeaders,
      );
      if (!mounted) return;
      setState(() {
        _thumbs = cues;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _thumbs = const [];
      });
    } finally {
      if (mounted) setState(() => _thumbsLoading = false);
    }
  }

  void _showSeekFlash(String text, Alignment alignment, {Duration? hideAfter}) {
    _seekFlashTimer?.cancel();
    _seekFlashTimer = null;
    if (!mounted) {
      _seekFlash = text;
      _seekFlashAlign = alignment;
      return;
    }
    setState(() {
      _seekFlash = text;
      _seekFlashAlign = alignment;
    });
    if (hideAfter != null) {
      _seekFlashTimer = Timer(hideAfter, () {
        if (!mounted) return;
        setState(() => _seekFlash = null);
      });
    } else {
      _seekFlashTimer = null;
    }
  }

  void _hideSeekFlash() {
    _seekFlashTimer?.cancel();
    _seekFlashTimer = null;
    if (!mounted) {
      _seekFlash = null;
      return;
    }
    if (_seekFlash != null) {
      setState(() => _seekFlash = null);
    }
  }

  void _startLongPressSeek({required bool forward}) {
    final events = _events;
    if (events == null) return;
    final state = events.state.value;
    if (state.duration.inMilliseconds <= 0) return;
    _seekRepeat?.cancel();
    _seekFlashTimer?.cancel();
    _longPressDirection = forward ? 1 : -1;
    _longPressAccumulated = Duration.zero;
    _longPressTarget = state.position;
    _applyLongPressSeek();
    _seekRepeat = Timer.periodic(_longPressTick, (_) => _applyLongPressSeek());
    _restartHide();
  }

  void _updateLongPressDirection({required bool forward}) {
    final newDirection = forward ? 1 : -1;
    if (_seekRepeat == null || _longPressDirection == newDirection) {
      return;
    }
    _longPressDirection = newDirection;
    _longPressAccumulated = Duration.zero;
    final events = _events;
    _longPressTarget = events?.state.value.position;
  }

  void _applyLongPressSeek() {
    final events = _events;
    if (events == null) return;
    if (_longPressDirection == 0) return;
    final state = events.state.value;
    final duration = state.duration;
    if (duration.inMilliseconds <= 0) {
      _stopLongPressSeek(animateHide: false);
      return;
    }
    final step = widget.longPressSeek;
    if (step.inMilliseconds <= 0) return;
    final base = _longPressTarget ?? state.position;
    final delta = _longPressDirection < 0 ? -step : step;
    final target = _clampDuration(base + delta, Duration.zero, duration);
    final actual = target - base;
    if (actual.inMilliseconds == 0) {
      final label =
          '${_longPressDirection < 0 ? '-' : '+'}${_formatSeekValue(_longPressAccumulated)}s';
      _showSeekFlash(
        label,
        _longPressDirection < 0 ? Alignment.centerLeft : Alignment.centerRight,
      );
      return;
    }
    _longPressTarget = target;
    widget.controller.seekTo(target);
    _longPressAccumulated += _absDuration(actual);
    final label =
        '${_longPressDirection < 0 ? '-' : '+'}${_formatSeekValue(_longPressAccumulated)}s';
    _showSeekFlash(
      label,
      _longPressDirection < 0 ? Alignment.centerLeft : Alignment.centerRight,
    );
  }

  void _stopLongPressSeek({bool animateHide = true}) {
    final direction = _longPressDirection;
    final accumulated = _longPressAccumulated;
    _seekRepeat?.cancel();
    _seekRepeat = null;
    _longPressTarget = null;
    _longPressDirection = 0;
    _longPressAccumulated = Duration.zero;
    if (!animateHide) {
      _hideSeekFlash();
      _restartHide();
      return;
    }
    if (accumulated.inMilliseconds <= 0) {
      _hideSeekFlash();
      _restartHide();
      return;
    }
    final label =
        '${direction < 0 ? '-' : '+'}${_formatSeekValue(accumulated)}s';
    _showSeekFlash(
      label,
      direction < 0 ? Alignment.centerLeft : Alignment.centerRight,
      hideAfter: const Duration(milliseconds: 600),
    );
    _restartHide();
  }

  Duration _clampDuration(Duration value, Duration min, Duration max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  Duration _absDuration(Duration value) {
    return value.isNegative ? -value : value;
  }

  String _formatSeekValue(Duration value) {
    final ms = value.inMilliseconds.abs();
    if (ms == 0) return '0';
    if (ms % 1000 == 0) {
      return (ms ~/ 1000).toString();
    }
    final seconds = ms / 1000;
    final fixed = seconds.toStringAsFixed(1);
    return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
  }

  void _refreshVideoTracks({bool force = false}) {
    if (!force && _pendingTrackFetch != null) return;
    final ticket = ++_trackFetchTicket;
    _pendingTrackFetch = widget.controller
        .getVideoTracks()
        .then((tracks) {
          if (!mounted || _trackFetchTicket != ticket) return;
          setState(() {
            _videoTracks = tracks;
            if (_manualTrackId != null &&
                tracks.every((t) => t.id != _manualTrackId)) {
              _manualTrackId = null;
            }
          });
        })
        .catchError((_) {})
        .whenComplete(() {
          if (_trackFetchTicket == ticket) {
            _pendingTrackFetch = null;
          }
        });
  }

  void _refreshAudioTracks({bool force = false}) {
    if (!force && _pendingAudioFetch != null) return;
    final ticket = ++_audioFetchTicket;
    _pendingAudioFetch = widget.controller
        .getAudioTracks()
        .then((tracks) {
          if (!mounted || _audioFetchTicket != ticket) return;
          setState(() {
            _audioTracks = tracks;
            if (_manualAudioId != null &&
                tracks.every((t) => t.id != _manualAudioId)) {
              _manualAudioId = null;
            }
          });
        })
        .catchError((_) {})
        .whenComplete(() {
          if (_audioFetchTicket == ticket) {
            _pendingAudioFetch = null;
          }
        });
  }

  void _refreshSubtitleTracks({bool force = false}) {
    if (!force && _pendingSubtitleFetch != null) return;
    final ticket = ++_subtitleFetchTicket;
    _pendingSubtitleFetch = widget.controller
        .getSubtitleTracks()
        .then((tracks) {
          if (!mounted || _subtitleFetchTicket != ticket) return;
          setState(() {
            _subtitleTracks = tracks;
            if (_manualSubtitleId != null &&
                tracks.every((t) => t.id != _manualSubtitleId)) {
              _manualSubtitleId = null;
            }
          });
        })
        .catchError((_) {})
        .whenComplete(() {
          if (_subtitleFetchTicket == ticket) {
            _pendingSubtitleFetch = null;
          }
        });
  }

  ThaVideoTrack? get _activeTrack {
    for (final t in _videoTracks) {
      if (t.selected) return t;
    }
    return null;
  }

  void _ensureTracksLoaded(ThaPlaybackState st) {
    if (st.isBuffering && st.duration == Duration.zero) return;
    if (_videoTracks.isEmpty) _refreshVideoTracks();
    if (_audioTracks.isEmpty) _refreshAudioTracks();
    if (_subtitleTracks.isEmpty) _refreshSubtitleTracks();
  }

  IconData get _qualityIcon {
    if (_dataSaver) return Icons.data_saver_on;
    if (_manualTrackId != null) return Icons.high_quality;
    return Icons.hd;
  }

  Future<void> _onQualitySelected(String value) async {
    switch (value) {
      case 'auto':
        setState(() {
          _dataSaver = false;
          _manualTrackId = null;
        });
        await widget.controller.setDataSaver(false);
        await widget.controller.clearVideoTrackSelection();
        break;
      case 'dataSaver':
        setState(() {
          _dataSaver = true;
          _manualTrackId = null;
        });
        await widget.controller.setDataSaver(true);
        await widget.controller.clearVideoTrackSelection();
        break;
      default:
        setState(() {
          _dataSaver = false;
          _manualTrackId = value;
        });
        await widget.controller.setDataSaver(false);
        await widget.controller.selectVideoTrack(value);
        break;
    }
    _restartHide();
    if (!mounted) return;
    _refreshVideoTracks(force: true);
  }

  Widget _qualityMenuRow(
    BuildContext context, {
    required String label,
    bool selected = false,
    String? subtitle,
    bool isPlaying = false,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final titleStyle = textTheme.labelLarge?.copyWith(color: Colors.white);
    final subStyle = textTheme.bodySmall?.copyWith(color: Colors.white70);
    return SizedBox(
      width: 220,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected)
            const Icon(Icons.check, size: 16, color: Colors.white)
          else
            const SizedBox(width: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: titleStyle),
                if (subtitle != null) Text(subtitle, style: subStyle),
              ],
            ),
          ),
          if (isPlaying)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.play_arrow, size: 16, color: Colors.white70),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThaPlaybackState>(
      valueListenable:
          _events?.state ??
          ValueNotifier(
            const ThaPlaybackState(
              position: Duration.zero,
              duration: Duration.zero,
              isPlaying: false,
              isBuffering: true,
            ),
          ),
      builder: (_, st, __) {
        final showCenterButton = !_locked && !st.isBuffering && !st.isPlaying;
        if (widget.onStateChanged != null && _hasStateChanged(st)) {
          widget.onStateChanged!(st);
          _lastStateNotification = st;
        }
        final currentError = _events?.error.value;
        if (widget.onError != null && currentError != _lastErrorNotification) {
          widget.onError!(currentError);
          _lastErrorNotification = currentError;
        }
        _ensureTracksLoaded(st);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_locked) {
              _lockHint = true;
              _lockHintTimer?.cancel();
              _lockHintTimer = Timer(const Duration(seconds: 2), () {
                if (!mounted) return;
                setState(() => _lockHint = false);
              });
              setState(() {});
              return;
            }
            setState(() => _showControls = !_showControls);
            if (_showControls) _restartHide();
          },
          onDoubleTapDown: (d) {
            if (_locked) {
              return;
            }
            final w = context.size?.width ?? 0;
            final x = d.localPosition.dx;
            final left = x < w / 3;
            final right = x > 2 * w / 3;
            if (left || right) {
              final delta = left ? -widget.doubleTapSeek : widget.doubleTapSeek;
              final t = st.position + delta;
              final target =
                  t < Duration.zero
                      ? Duration.zero
                      : (t > st.duration ? st.duration : t);
              _stopLongPressSeek(animateHide: false);
              widget.controller.seekTo(target);
              final text =
                  "${delta.isNegative ? '-' : '+'}${_formatSeekValue(widget.doubleTapSeek)}s";
              _showSeekFlash(
                text,
                left ? Alignment.centerLeft : Alignment.centerRight,
                hideAfter: const Duration(milliseconds: 600),
              );
            } else {
              st.isPlaying
                  ? widget.controller.pause()
                  : widget.controller.play();
            }
            _restartHide();
          },
          onHorizontalDragStart: (d) {
            if (_locked) {
              return;
            }
            _hStart = d.localPosition;
            _preview = st.position;
          },
          onHorizontalDragUpdate: (d) {
            if (_locked) {
              return;
            }
            final start = _hStart;
            if (start == null) return;
            final diff = d.localPosition.dx - start.dx;
            final newPos =
                (_preview ?? st.position) +
                Duration(milliseconds: (diff * 50).toInt());
            final clamped =
                newPos < Duration.zero
                    ? Duration.zero
                    : (newPos > st.duration ? st.duration : newPos);
            setState(() => _preview = clamped);
          },
          onHorizontalDragEnd: (_) {
            if (_locked) {
              return;
            }
            if (_preview != null) {
              widget.controller.seekTo(_preview!);
              setState(() => _preview = null);
            }
          },
          onLongPressStart: (details) {
            if (_locked) return;
            if (st.duration.inMilliseconds <= 0) return;
            final width = context.size?.width ?? 0;
            final forward = details.localPosition.dx > width / 2;
            _startLongPressSeek(forward: forward);
          },
          onLongPressMoveUpdate: (details) {
            if (_locked || _seekRepeat == null) return;
            final width = context.size?.width ?? 0;
            final forward = details.localPosition.dx > width / 2;
            _updateLongPressDirection(forward: forward);
          },
          onLongPressEnd: (_) {
            if (_locked) return;
            _stopLongPressSeek();
          },
          onLongPressCancel: () {
            _stopLongPressSeek(animateHide: false);
          },
          onVerticalDragUpdate: (d) async {
            if (_locked) {
              return;
            }
            final w = context.size?.width ?? 0;
            final right = d.localPosition.dx > w / 2;
            final delta = -d.delta.dy / 200; // up increase
            if (right) {
              setState(() {
                _showVol = true;
                _volLevel = (_volLevel + delta).clamp(0.0, 1.0);
              });
              unawaited(
                NativeBridge.setVolume(delta)
                    .then((value) {
                      if (!mounted) return;
                      setState(() => _volLevel = value);
                    })
                    .catchError((_) {}),
              );
            } else {
              setState(() {
                _showBri = true;
                _briLevel = (_briLevel + delta).clamp(0.0, 1.0);
              });
              unawaited(
                NativeBridge.setBrightness(delta)
                    .then((value) {
                      if (!mounted) return;
                      setState(() => _briLevel = value);
                    })
                    .catchError((_) {}),
              );
            }
            _vbHide?.cancel();
            _vbHide = Timer(const Duration(milliseconds: 800), () {
              if (!mounted) return;
              setState(() {
                _showVol = false;
                _showBri = false;
              });
            });
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              ValueListenableBuilder<BoxFit>(
                valueListenable: _fit,
                builder:
                    (_, fit, __) => ThaNativePlayerView(
                      controller: widget.controller,
                      boxFit: fit,
                      overlay: null,
                    ),
              ),
              // Top transparent interaction layer to ensure taps anywhere are detected
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    if (_locked) {
                      _lockHint = true;
                      _lockHintTimer?.cancel();
                      _lockHintTimer = Timer(const Duration(seconds: 2), () {
                        if (!mounted) return;
                        setState(() => _lockHint = false);
                      });
                      setState(() {});
                      return;
                    }
                    setState(() => _showControls = !_showControls);
                    if (_showControls) _restartHide();
                  },
                  onDoubleTapDown: (d) {
                    if (_locked) {
                      return;
                    }
                    final box = context.findRenderObject() as RenderBox?;
                    final w = box?.size.width ?? 0;
                    final x = d.localPosition.dx;
                    final left = x < w / 3;
                    final right = x > 2 * w / 3;
                    final st =
                        _events?.state.value ??
                        const ThaPlaybackState(
                          position: Duration.zero,
                          duration: Duration.zero,
                          isPlaying: false,
                          isBuffering: false,
                        );
                    if (left || right) {
                      final delta =
                          left ? -widget.doubleTapSeek : widget.doubleTapSeek;
                      final t = st.position + delta;
                      final target =
                          t < Duration.zero
                              ? Duration.zero
                              : (t > st.duration ? st.duration : t);
                      _stopLongPressSeek(animateHide: false);
                      widget.controller.seekTo(target);
                      final text =
                          "${delta.isNegative ? '-' : '+'}${_formatSeekValue(widget.doubleTapSeek)}s";
                      _showSeekFlash(
                        text,
                        left ? Alignment.centerLeft : Alignment.centerRight,
                        hideAfter: const Duration(milliseconds: 600),
                      );
                    } else {
                      st.isPlaying
                          ? widget.controller.pause()
                          : widget.controller.play();
                    }
                    _restartHide();
                  },
                  onHorizontalDragStart: (d) {
                    if (_locked) {
                      return;
                    }
                    final st =
                        _events?.state.value ??
                        const ThaPlaybackState(
                          position: Duration.zero,
                          duration: Duration.zero,
                          isPlaying: false,
                          isBuffering: false,
                        );
                    _hStart = d.localPosition;
                    _preview = st.position;
                  },
                  onHorizontalDragUpdate: (d) {
                    if (_locked) {
                      return;
                    }
                    final st =
                        _events?.state.value ??
                        const ThaPlaybackState(
                          position: Duration.zero,
                          duration: Duration.zero,
                          isPlaying: false,
                          isBuffering: false,
                        );
                    final start = _hStart;
                    if (start == null) return;
                    final diff = d.localPosition.dx - start.dx;
                    final newPos =
                        (_preview ?? st.position) +
                        Duration(milliseconds: (diff * 50).toInt());
                    final clamped =
                        newPos < Duration.zero
                            ? Duration.zero
                            : (newPos > st.duration ? st.duration : newPos);
                    setState(() => _preview = clamped);
                  },
                  onHorizontalDragEnd: (_) {
                    if (_locked) {
                      return;
                    }
                    if (_preview != null) {
                      widget.controller.seekTo(_preview!);
                      setState(() => _preview = null);
                    }
                  },
                  onLongPressStart: (details) {
                    if (_locked) return;
                    final st = _events?.state.value;
                    if (st == null || st.duration.inMilliseconds <= 0) return;
                    final box = context.findRenderObject() as RenderBox?;
                    final width = box?.size.width ?? 0;
                    final forward = details.localPosition.dx > width / 2;
                    _startLongPressSeek(forward: forward);
                  },
                  onLongPressMoveUpdate: (details) {
                    if (_locked || _seekRepeat == null) return;
                    final box = context.findRenderObject() as RenderBox?;
                    final width = box?.size.width ?? 0;
                    final forward = details.localPosition.dx > width / 2;
                    _updateLongPressDirection(forward: forward);
                  },
                  onLongPressEnd: (_) {
                    if (_locked) return;
                    _stopLongPressSeek();
                  },
                  onLongPressCancel: () {
                    _stopLongPressSeek(animateHide: false);
                  },
                  onVerticalDragUpdate: (d) async {
                    if (_locked) {
                      return;
                    }
                    final box = context.findRenderObject() as RenderBox?;
                    final w = box?.size.width ?? 0;
                    final right = d.localPosition.dx > w / 2;
                    final delta = -d.delta.dy / 200; // up increase
                    if (right) {
                      setState(() {
                        _showVol = true;
                        _volLevel = (_volLevel + delta).clamp(0.0, 1.0);
                      });
                      unawaited(
                        NativeBridge.setVolume(delta)
                            .then((value) {
                              if (!mounted) return;
                              setState(() => _volLevel = value);
                            })
                            .catchError((_) {}),
                      );
                    } else {
                      setState(() {
                        _showBri = true;
                        _briLevel = (_briLevel + delta).clamp(0.0, 1.0);
                      });
                      unawaited(
                        NativeBridge.setBrightness(delta)
                            .then((value) {
                              if (!mounted) return;
                              setState(() => _briLevel = value);
                            })
                            .catchError((_) {}),
                      );
                    }
                    _vbHide?.cancel();
                    _vbHide = Timer(const Duration(milliseconds: 800), () {
                      if (!mounted) return;
                      setState(() {
                        _showVol = false;
                        _showBri = false;
                      });
                    });
                  },
                ),
              ),
              if (widget.overlay != null)
                Positioned(
                  top: 12,
                  right: 12,
                  child: IgnorePointer(ignoring: false, child: widget.overlay!),
                ),
              if (_preview != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_thumbs != null && _thumbs!.isNotEmpty)
                          _buildThumbFor(_preview!),
                        const SizedBox(height: 4),
                        Text(
                          _fmt(_preview!),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              IgnorePointer(
                ignoring: !showCenterButton,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: showCenterButton ? 1 : 0,
                  child: Center(
                    child: RawMaterialButton(
                      elevation: 0,
                      fillColor: Colors.black54,
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(20),
                      onPressed: () {
                        if (st.isPlaying) {
                          widget.controller.pause();
                        } else {
                          widget.controller.play();
                        }
                        _restartHide();
                      },
                      child: Icon(
                        st.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 44,
                      ),
                    ),
                  ),
                ),
              ),
              if (st.isBuffering)
                const Center(
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              if (_showControls)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _controls(context, st),
                ),
              if (_seekFlash != null)
                Align(
                  alignment: _seekFlashAlign,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _seekFlash!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_locked || _lockHint)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.small(
                    backgroundColor: Colors.black54,
                    onPressed: () {
                      setState(() {
                        _locked = false;
                        _lockHint = false;
                      });
                      _restartHide();
                    },
                    child: const Icon(Icons.lock_open, color: Colors.white),
                  ),
                ),
              if (_showVol)
                Positioned(
                  right: 12,
                  top: 24,
                  bottom: 24,
                  child: _VerticalSlider(
                    value: _volLevel,
                    icon: Icons.volume_up,
                  ),
                ),
              if (_showBri)
                Positioned(
                  left: 12,
                  top: 24,
                  bottom: 24,
                  child: _VerticalSlider(
                    value: _briLevel,
                    icon: Icons.brightness_6,
                  ),
                ),
              // Error overlay (retry) on top of everything
              if (_events?.error.value != null)
                Container(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.white70,
                          size: 36,
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Text(
                            _events!.error.value ?? 'Playback error',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () {
                            widget.controller.retry();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _controls(BuildContext context, ThaPlaybackState st) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 520;
        final leading = _buildLeadingControls(context, st, isCompact);
        final trailing = _buildTrailingControls(context, isCompact);
        return Container(
          color: Colors.black45,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildProgressRow(context, st),
              const SizedBox(height: 8),
              Row(
                children: [
                  ..._joinWithSpacing(leading),
                  const Spacer(),
                  ..._joinWithSpacing(trailing),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProgressRow(BuildContext context, ThaPlaybackState st) {
    return Row(
      children: [
        Text(
          _fmt(st.position),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              min: 0,
              max: st.duration.inMilliseconds.toDouble().clamp(
                1,
                double.infinity,
              ),
              value:
                  st.position.inMilliseconds
                      .clamp(0, st.duration.inMilliseconds)
                      .toDouble(),
              onChanged:
                  (v) => setState(
                    () => _preview = Duration(milliseconds: v.toInt()),
                  ),
              onChangeEnd: (v) {
                widget.controller.seekTo(Duration(milliseconds: v.toInt()));
                setState(() => _preview = null);
              },
            ),
          ),
        ),
        Text(
          _fmt(st.duration),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    );
  }

  List<Widget> _joinWithSpacing(List<Widget> children, {double spacing = 6}) {
    if (children.isEmpty) return const [];
    final output = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      output.add(children[i]);
      if (i != children.length - 1) {
        output.add(SizedBox(width: spacing));
      }
    }
    return output;
  }

  List<Widget> _buildLeadingControls(
    BuildContext context,
    ThaPlaybackState st,
    bool isCompact,
  ) {
    final widgets = <Widget>[_buildPlayPauseButton(st)];
    if (isCompact) {
      widgets.add(_buildLockButton());
    } else {
      widgets
        ..add(_buildQualityButton(context))
        ..add(_buildAudioButton(context))
        ..add(_buildSubtitleButton(context))
        ..add(_buildLockButton())
        ..add(_buildSpeedButton());
    }
    return widgets;
  }

  List<Widget> _buildTrailingControls(BuildContext context, bool isCompact) {
    final widgets = <Widget>[
      if (!isCompact) _buildResizeButton(context),
      _buildPipButton(),
      _buildFullscreenButton(context),
    ];
    if (isCompact) {
      widgets.add(_buildOverflowButton(context));
    }
    return widgets;
  }

  Widget _buildPlayPauseButton(ThaPlaybackState st) {
    return IconButton(
      icon: Icon(
        st.isPlaying ? Icons.pause : Icons.play_arrow,
        color: Colors.white,
      ),
      onPressed: () {
        st.isPlaying ? widget.controller.pause() : widget.controller.play();
        _restartHide();
      },
    );
  }

  Widget _buildQualityButton(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Quality',
      color: const Color(0xFF1F1F1F),
      surfaceTintColor: Colors.transparent,
      icon: Icon(_qualityIcon, color: Colors.white),
      onOpened: () => _refreshVideoTracks(force: true),
      onSelected: (v) => unawaited(_onQualitySelected(v)),
      itemBuilder: _qualityPopupItems,
    );
  }

  Widget _buildAudioButton(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Audio',
      color: const Color(0xFF1F1F1F),
      surfaceTintColor: Colors.transparent,
      icon: const Icon(Icons.audiotrack, color: Colors.white),
      onOpened: () => _refreshAudioTracks(force: true),
      onSelected: (value) {
        if (value == '__auto__') {
          setState(() => _manualAudioId = null);
          unawaited(widget.controller.selectAudioTrack(null));
        } else {
          setState(() => _manualAudioId = value);
          unawaited(widget.controller.selectAudioTrack(value));
        }
        _restartHide();
      },
      itemBuilder: _audioPopupItems,
    );
  }

  Widget _buildSubtitleButton(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Subtitles',
      color: const Color(0xFF1F1F1F),
      surfaceTintColor: Colors.transparent,
      icon: const Icon(Icons.subtitles, color: Colors.white),
      onOpened: () => _refreshSubtitleTracks(force: true),
      onSelected: (value) {
        if (value == '__off__') {
          setState(() => _manualSubtitleId = null);
          unawaited(widget.controller.selectSubtitleTrack(null));
        } else {
          setState(() => _manualSubtitleId = value);
          unawaited(widget.controller.selectSubtitleTrack(value));
        }
        _restartHide();
      },
      itemBuilder: _subtitlePopupItems,
    );
  }

  Widget _buildLockButton() {
    return IconButton(
      icon: const Icon(Icons.lock, color: Colors.white),
      onPressed: () {
        setState(() {
          _locked = true;
          _showControls = false;
        });
      },
    );
  }

  Widget _buildSpeedButton() {
    return PopupMenuButton<double>(
      tooltip: 'Speed',
      icon: const Icon(Icons.speed, color: Colors.white),
      onSelected: (s) => widget.controller.setSpeed(s),
      itemBuilder: _speedPopupItems,
    );
  }

  Widget _buildResizeButton(BuildContext context) {
    return IconButton(
      tooltip: 'Resize',
      icon: const Icon(Icons.aspect_ratio, color: Colors.white),
      onPressed: () async {
        final fit = await _showBoxFitDialog();
        if (fit == null) return;
        _fit.value = fit;
        await widget.controller.setBoxFit(fit);
        if (!mounted) return;
        _restartHide();
      },
    );
  }

  Widget _buildPipButton() {
    return IconButton(
      icon: const Icon(Icons.picture_in_picture_alt, color: Colors.white),
      tooltip: 'Picture-in-picture',
      onPressed: () {
        unawaited(
          widget.controller
              .enterPictureInPicture()
              .then((ok) {
                if (!mounted) return;
                if (ok) {
                  _restartHide();
                } else {
                  debugPrint('Picture-in-picture is unavailable.');
                }
              })
              .catchError((_) {}),
        );
      },
    );
  }

  Widget _buildFullscreenButton(BuildContext context) {
    return IconButton(
      icon: Icon(
        widget.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
        color: Colors.white,
      ),
      onPressed: () {
        if (widget.isFullscreen) {
          Navigator.of(context).pop();
        } else {
          _enterFullscreen();
        }
      },
    );
  }

  Widget _buildOverflowButton(BuildContext context) {
    return Builder(
      builder: (buttonContext) {
        return PopupMenuButton<_OverflowAction>(
          tooltip: 'More options',
          color: const Color(0xFF1F1F1F),
          surfaceTintColor: Colors.transparent,
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onOpened: () {
            _refreshVideoTracks(force: true);
            _refreshAudioTracks(force: true);
            _refreshSubtitleTracks(force: true);
          },
          itemBuilder:
              (c) => [
                _overflowMenuItem(
                  _OverflowAction.quality,
                  Icons.hd_outlined,
                  'Quality',
                ),
                _overflowMenuItem(
                  _OverflowAction.audio,
                  Icons.audiotrack,
                  'Audio',
                ),
                _overflowMenuItem(
                  _OverflowAction.subtitles,
                  Icons.subtitles,
                  'Subtitles',
                ),
                _overflowMenuItem(_OverflowAction.speed, Icons.speed, 'Speed'),
                _overflowMenuItem(
                  _OverflowAction.resize,
                  Icons.aspect_ratio,
                  'Resize',
                ),
              ],
          onSelected:
              (action) =>
                  unawaited(_handleOverflowAction(buttonContext, action)),
        );
      },
    );
  }

  PopupMenuItem<_OverflowAction> _overflowMenuItem(
    _OverflowAction action,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem(
      value: action,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Future<void> _handleOverflowAction(
    BuildContext anchorContext,
    _OverflowAction action,
  ) async {
    if (!mounted) return;
    final menuPosition = _menuPositionFor(anchorContext);
    switch (action) {
      case _OverflowAction.quality:
        _refreshVideoTracks(force: true);
        final pendingVideo = _pendingTrackFetch;
        if (pendingVideo != null) {
          try {
            await pendingVideo;
          } catch (_) {}
        }
        if (!mounted) return;
        final quality = await _showAnchoredMenu<String>(
          menuPosition,
          _qualityPopupItems(context),
        );
        if (quality != null) {
          await _onQualitySelected(quality);
        }
        break;
      case _OverflowAction.audio:
        _refreshAudioTracks(force: true);
        final pendingAudio = _pendingAudioFetch;
        if (pendingAudio != null) {
          try {
            await pendingAudio;
          } catch (_) {}
        }
        if (!mounted) return;
        final audio = await _showAnchoredMenu<String>(
          menuPosition,
          _audioPopupItems(context),
        );
        if (audio != null) {
          if (audio == '__auto__') {
            setState(() => _manualAudioId = null);
            await widget.controller.selectAudioTrack(null);
          } else {
            setState(() => _manualAudioId = audio);
            await widget.controller.selectAudioTrack(audio);
          }
        }
        break;
      case _OverflowAction.subtitles:
        _refreshSubtitleTracks(force: true);
        final pendingSub = _pendingSubtitleFetch;
        if (pendingSub != null) {
          try {
            await pendingSub;
          } catch (_) {}
        }
        if (!mounted) return;
        final subtitle = await _showAnchoredMenu<String>(
          menuPosition,
          _subtitlePopupItems(context),
        );
        if (subtitle != null) {
          if (subtitle == '__off__') {
            setState(() => _manualSubtitleId = null);
            await widget.controller.selectSubtitleTrack(null);
          } else {
            setState(() => _manualSubtitleId = subtitle);
            await widget.controller.selectSubtitleTrack(subtitle);
          }
        }
        break;
      case _OverflowAction.speed:
        final speed = await _showAnchoredMenu<double>(
          menuPosition,
          _speedPopupItems(context),
        );
        if (speed != null) {
          await widget.controller.setSpeed(speed);
        }
        break;
      case _OverflowAction.resize:
        final fit = await _showBoxFitDialog();
        if (fit != null) {
          _fit.value = fit;
          await widget.controller.setBoxFit(fit);
        }
        break;
    }
    if (!mounted) return;
    _restartHide();
  }

  Future<T?> _showAnchoredMenu<T>(
    RelativeRect position,
    List<PopupMenuEntry<T>> items,
  ) {
    if (items.isEmpty || !mounted) return Future.value(null);
    return showMenu<T>(
      context: context,
      position: position,
      color: const Color(0xFF1F1F1F),
      items: items,
    );
  }

  RelativeRect _menuPositionFor(BuildContext anchorContext) {
    final renderBox = anchorContext.findRenderObject() as RenderBox?;
    final overlayState = Overlay.of(anchorContext);
    final overlay = overlayState.context.findRenderObject() as RenderBox?;
    if (overlay == null) {
      return const RelativeRect.fromLTRB(0, 0, 0, 0);
    }
    if (renderBox == null) {
      return RelativeRect.fromLTRB(
        overlay.size.width * 0.5,
        overlay.size.height * 0.5,
        overlay.size.width * 0.5,
        overlay.size.height * 0.5,
      );
    }
    return RelativeRect.fromRect(
      Rect.fromPoints(
        renderBox.localToGlobal(Offset.zero, ancestor: overlay),
        renderBox.localToGlobal(
          renderBox.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );
  }

  List<PopupMenuEntry<String>> _qualityPopupItems(BuildContext context) {
    final items = <PopupMenuEntry<String>>[];
    final current = _activeTrack;
    final autoSubtitle =
        !_dataSaver && current != null && _manualTrackId == null
            ? 'Current: ${current.displayLabel}'
            : null;
    items.add(
      PopupMenuItem(
        value: 'auto',
        child: _qualityMenuRow(
          context,
          label: 'Auto',
          subtitle: autoSubtitle,
          selected: !_dataSaver && _manualTrackId == null,
        ),
      ),
    );
    items.add(
      PopupMenuItem(
        value: 'dataSaver',
        child: _qualityMenuRow(
          context,
          label: 'Data Saver',
          subtitle: 'Cap ~0.8 Mbps',
          selected: _dataSaver,
        ),
      ),
    );
    if (_videoTracks.isNotEmpty) {
      final sorted = [..._videoTracks]
        ..sort((a, b) => (b.bitrate ?? 0).compareTo(a.bitrate ?? 0));
      items.add(const PopupMenuDivider());
      for (final track in sorted) {
        items.add(
          PopupMenuItem(
            value: track.id,
            child: _qualityMenuRow(
              context,
              label: track.displayLabel,
              selected: _manualTrackId == track.id,
              isPlaying: track.selected,
            ),
          ),
        );
      }
    } else if (_pendingTrackFetch != null) {
      items.add(
        const PopupMenuItem<String>(
          enabled: false,
          value: '__loading__',
          child: Text('Loading variants...'),
        ),
      );
    } else {
      items.add(
        const PopupMenuItem<String>(
          enabled: false,
          value: '__empty__',
          child: Text('No variants reported'),
        ),
      );
    }
    return items;
  }

  List<PopupMenuEntry<String>> _audioPopupItems(BuildContext context) {
    final items = <PopupMenuEntry<String>>[
      PopupMenuItem(
        value: '__auto__',
        child: _qualityMenuRow(
          context,
          label: 'Auto',
          subtitle: 'Default audio',
          selected: _manualAudioId == null,
        ),
      ),
    ];
    if (_audioTracks.isNotEmpty) {
      items.add(const PopupMenuDivider());
      for (final track in _audioTracks) {
        items.add(
          PopupMenuItem(
            value: track.id,
            child: _qualityMenuRow(
              context,
              label: track.label ?? (track.language ?? track.id),
              subtitle: track.language,
              selected:
                  _manualAudioId == track.id ||
                  (_manualAudioId == null && track.selected),
              isPlaying: track.selected,
            ),
          ),
        );
      }
    } else if (_pendingAudioFetch != null) {
      items.add(
        const PopupMenuItem<String>(
          enabled: false,
          value: '__loading_audio__',
          child: Text('Loading audio tracks...'),
        ),
      );
    }
    return items;
  }

  List<PopupMenuEntry<String>> _subtitlePopupItems(BuildContext context) {
    final items = <PopupMenuEntry<String>>[
      PopupMenuItem(
        value: '__off__',
        child: _qualityMenuRow(
          context,
          label: 'Subtitles off',
          selected: _manualSubtitleId == null,
        ),
      ),
    ];
    if (_subtitleTracks.isNotEmpty) {
      items.add(const PopupMenuDivider());
      for (final track in _subtitleTracks) {
        items.add(
          PopupMenuItem(
            value: track.id,
            child: _qualityMenuRow(
              context,
              label: track.label ?? (track.language ?? track.id),
              subtitle: track.language,
              selected:
                  _manualSubtitleId == track.id ||
                  (_manualSubtitleId == null && track.selected),
              isPlaying: track.selected,
            ),
          ),
        );
      }
    } else if (_pendingSubtitleFetch != null) {
      items.add(
        const PopupMenuItem<String>(
          enabled: false,
          value: '__loading_sub__',
          child: Text('Loading subtitles...'),
        ),
      );
    }
    return items;
  }

  List<PopupMenuEntry<double>> _speedPopupItems(BuildContext context) {
    return [0.5, 1.0, 1.25, 1.5, 2.0]
        .map((s) => PopupMenuItem<double>(value: s, child: Text('${s}x')))
        .toList();
  }

  Future<BoxFit?> _showBoxFitDialog() {
    if (!mounted) return Future.value(null);
    final current = _fit.value;
    return showDialog<BoxFit>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1F1F1F),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_dialogCornerRadius),
          ),
          title: const Text('Resize', style: TextStyle(color: Colors.white)),
          contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          content: SingleChildScrollView(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children:
                  _boxFitChoices.map((fit) {
                    final isSelected = fit == current;
                    final label = _boxFitLabel(fit);
                    final icon = _boxFitIcon(fit);
                    final borderColor =
                        isSelected ? Colors.white : Colors.white24;
                    final background =
                        isSelected
                            ? const Color.fromRGBO(255, 255, 255, 0.18)
                            : const Color.fromRGBO(255, 255, 255, 0.04);
                    return SizedBox(
                      width: 88,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(
                            _dialogCornerRadius,
                          ),
                          onTap: () => Navigator.of(dialogContext).pop(fit),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: background,
                              borderRadius: BorderRadius.circular(
                                _dialogCornerRadius,
                              ),
                              border: Border.all(
                                color: borderColor,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon, color: Colors.white, size: 26),
                                const SizedBox(height: 6),
                                Text(
                                  label,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight:
                                        isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  String _boxFitLabel(BoxFit fit) {
    switch (fit) {
      case BoxFit.contain:
        return 'Contain';
      case BoxFit.cover:
        return 'Cover';
      case BoxFit.fill:
        return 'Fill';
      case BoxFit.fitWidth:
        return 'Fit Width';
      case BoxFit.fitHeight:
        return 'Fit Height';
      case BoxFit.none:
        return 'None';
      case BoxFit.scaleDown:
        return 'Scale Down';
    }
  }

  IconData _boxFitIcon(BoxFit fit) {
    switch (fit) {
      case BoxFit.contain:
        return Icons.fit_screen;
      case BoxFit.cover:
        return Icons.crop_original;
      case BoxFit.fill:
        return Icons.aspect_ratio;
      case BoxFit.fitWidth:
        return Icons.swap_horiz;
      case BoxFit.fitHeight:
        return Icons.swap_vert;
      case BoxFit.none:
        return Icons.crop_free;
      case BoxFit.scaleDown:
        return Icons.compress;
    }
  }

  String _fmt(Duration d) {
    if (d.inHours > 0) {
      final h = d.inHours.toString().padLeft(2, '0');
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$h:$m:$s';
    }
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _buildThumbFor(Duration d) {
    final cues = _thumbs;
    if (cues == null || cues.isEmpty) return const SizedBox.shrink();
    ThumbCue? cue;
    for (final c in cues) {
      if (d >= c.start && d < c.end) {
        cue = c;
        break;
      }
    }
    cue ??= cues.last;
    final uri = cue.image.toString();
    final crop =
        cue.hasCrop
            ? Rect.fromLTWH(
              (cue.x!).toDouble(),
              (cue.y!).toDouble(),
              (cue.w!).toDouble(),
              (cue.h!).toDouble(),
            )
            : null;
    const targetW = 160.0;
    if (crop == null) {
      return Image.network(
        uri,
        width: targetW,
        fit: BoxFit.cover,
        headers: _thumbHeaders,
      );
    }
    final scale = targetW / crop.width;
    return ClipRect(
      child: SizedBox(
        width: targetW,
        height: crop.height * scale,
        child: FittedBox(
          fit: BoxFit.none,
          alignment: Alignment.topLeft,
          child: Transform.translate(
            offset: Offset(-crop.left, -crop.top),
            child: Image.network(uri, headers: _thumbHeaders),
          ),
        ),
      ),
    );
  }
}

class _VerticalSlider extends StatelessWidget {
  final double value;
  final IconData icon;
  const _VerticalSlider({required this.value, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(height: 8),
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(trackHeight: 2),
                child: Slider(value: value, onChanged: (_) {}),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _OverflowAction { quality, audio, subtitles, speed, resize }
