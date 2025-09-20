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
              widget.controller.seekTo(target);
              _seekFlash =
                  "${delta.isNegative ? '-' : '+'}${widget.doubleTapSeek.inSeconds}s";
              _seekFlashAlign =
                  left ? Alignment.centerLeft : Alignment.centerRight;
              setState(() {});
              Timer(const Duration(milliseconds: 600), () {
                if (!mounted) return;
                setState(() {
                  _seekFlash = null;
                });
              });
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
                      widget.controller.seekTo(target);
                      _seekFlash =
                          "${delta.isNegative ? '-' : '+'}${widget.doubleTapSeek.inSeconds}s";
                      _seekFlashAlign =
                          left ? Alignment.centerLeft : Alignment.centerRight;
                      setState(() {});
                      Timer(const Duration(milliseconds: 600), () {
                        if (!mounted) return;
                        setState(() {
                          _seekFlash = null;
                        });
                      });
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
    return Container(
      color: Colors.black45,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress with slider
          Row(
            children: [
              Text(
                _fmt(st.position),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
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
                      widget.controller.seekTo(
                        Duration(milliseconds: v.toInt()),
                      );
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
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(
                  st.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                onPressed: () {
                  st.isPlaying
                      ? widget.controller.pause()
                      : widget.controller.play();
                  _restartHide();
                },
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                tooltip: 'Quality',
                color: const Color(0xFF1F1F1F),
                surfaceTintColor: Colors.transparent,
                icon: Icon(_qualityIcon, color: Colors.white),
                onOpened: () => _refreshVideoTracks(force: true),
                onSelected: (v) => unawaited(_onQualitySelected(v)),
                itemBuilder: (c) {
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
                        c,
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
                        c,
                        label: 'Data Saver',
                        subtitle: 'Cap ~0.8 Mbps',
                        selected: _dataSaver,
                      ),
                    ),
                  );
                  if (_videoTracks.isNotEmpty) {
                    final sorted = [..._videoTracks]..sort(
                      (a, b) => (b.bitrate ?? 0).compareTo(a.bitrate ?? 0),
                    );
                    items.add(const PopupMenuDivider());
                    for (final track in sorted) {
                      items.add(
                        PopupMenuItem(
                          value: track.id,
                          child: _qualityMenuRow(
                            c,
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
                },
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
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
                itemBuilder: (c) {
                  final items = <PopupMenuEntry<String>>[
                    PopupMenuItem(
                      value: '__auto__',
                      child: _qualityMenuRow(
                        c,
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
                            c,
                            label: track.label ?? (track.language ?? track.id),
                            selected:
                                _manualAudioId == track.id ||
                                (_manualAudioId == null && track.selected),
                            isPlaying: track.selected,
                            subtitle: track.language,
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
                },
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
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
                itemBuilder: (c) {
                  final items = <PopupMenuEntry<String>>[
                    PopupMenuItem(
                      value: '__off__',
                      child: _qualityMenuRow(
                        c,
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
                            c,
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
                },
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.lock, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _locked = true;
                    _showControls = false;
                  });
                },
              ),
              const SizedBox(width: 6),
              PopupMenuButton<double>(
                tooltip: 'Speed',
                icon: const Icon(Icons.speed, color: Colors.white),
                onSelected: (s) => widget.controller.setSpeed(s),
                itemBuilder:
                    (c) =>
                        [0.5, 1.0, 1.25, 1.5, 2.0]
                            .map(
                              (s) =>
                                  PopupMenuItem(value: s, child: Text('${s}x')),
                            )
                            .toList(),
              ),
              const Spacer(),
              PopupMenuButton<BoxFit>(
                tooltip: 'Resize',
                icon: const Icon(Icons.aspect_ratio, color: Colors.white),
                onSelected: (fit) {
                  _fit.value = fit;
                  widget.controller.setBoxFit(fit);
                  _restartHide();
                },
                itemBuilder:
                    (context) => const [
                      PopupMenuItem(
                        value: BoxFit.contain,
                        child: Text('Contain'),
                      ),
                      PopupMenuItem(value: BoxFit.cover, child: Text('Cover')),
                      PopupMenuItem(value: BoxFit.fill, child: Text('Fill')),
                      PopupMenuItem(
                        value: BoxFit.fitWidth,
                        child: Text('Fit Width'),
                      ),
                      PopupMenuItem(
                        value: BoxFit.fitHeight,
                        child: Text('Fit Height'),
                      ),
                    ],
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(
                  Icons.picture_in_picture_alt,
                  color: Colors.white,
                ),
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
              ),
              IconButton(
                icon: Icon(
                  widget.isFullscreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                  color: Colors.white,
                ),
                onPressed: () {
                  if (widget.isFullscreen) {
                    Navigator.of(context).pop();
                  } else {
                    _enterFullscreen();
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
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
