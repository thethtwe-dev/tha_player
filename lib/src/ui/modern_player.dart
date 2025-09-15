import 'dart:async';
import 'package:flutter/material.dart';
import '../platform/native_player_controller.dart';
import '../platform/native_player_view.dart';
import '../platform/native_events.dart';
import '../utils/native_bridge.dart';
import 'native_fullscreen.dart';
import '../utils/thumbnails.dart';

class ThaModernPlayer extends StatefulWidget {
  final ThaNativePlayerController controller;
  final Widget? overlay;
  final Duration doubleTapSeek;
  final Duration autoHideAfter;
  final BoxFit initialBoxFit;
  final bool startLocked;
  final bool isFullscreen;

  const ThaModernPlayer({
    super.key,
    required this.controller,
    this.overlay,
    this.doubleTapSeek = const Duration(seconds: 10),
    this.autoHideAfter = const Duration(seconds: 3),
    this.initialBoxFit = BoxFit.contain,
    this.startLocked = false,
    this.isFullscreen = false,
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

  @override
  void initState() {
    super.initState();
    _locked = widget.startLocked;
    _restartHide();
    _maybeLoadThumbs();
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
              await NativeBridge.setVolume(delta);
            } else {
              setState(() {
                _showBri = true;
                _briLevel = (_briLevel + delta).clamp(0.0, 1.0);
              });
              await NativeBridge.setBrightness(delta);
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
                      await NativeBridge.setVolume(delta);
                    } else {
                      setState(() {
                        _showBri = true;
                        _briLevel = (_briLevel + delta).clamp(0.0, 1.0);
                      });
                      await NativeBridge.setBrightness(delta);
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
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder:
                            (_) => ThaNativeFullscreenPage(
                              controller: widget.controller,
                              boxFitNotifier: _fit,
                              overlay: widget.overlay,
                            ),
                      ),
                    );
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
      return Image.network(uri, width: targetW, fit: BoxFit.cover);
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
            child: Image.network(uri),
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
