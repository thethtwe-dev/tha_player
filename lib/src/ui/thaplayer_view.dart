import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tha_player/src/utils/native_bridge.dart';
import 'package:tha_player/src/widgets/control_bar.dart';
import 'package:tha_player/tha_player.dart';
import 'package:video_player/video_player.dart';

class ThaPlayerView extends StatefulWidget {
  final ThaPlayerController thaController;
  final double aspectRatio;
  final Widget? overlay;
  final bool isFullscreen;
  final ValueNotifier<BoxFit> boxFitNotifier;

  const ThaPlayerView({
    super.key,
    required this.thaController,
    required this.boxFitNotifier,
    this.aspectRatio = 16 / 9,
    this.overlay,
    this.isFullscreen = false,
  });

  @override
  State<ThaPlayerView> createState() => _ThaPlayerViewState();
}

class _ThaPlayerViewState extends State<ThaPlayerView> {
  bool _showControls = true;
  bool _controlsLocked = false;
  double initialVerticalDrag = 0;
  bool isVolumeGesture = false;
  Duration? _gestureSeekPreview;
  Timer? _hideTimer;

  Offset? _initialHorizontalSwipe;

  // double? _lastVolumeOverlay;
  // double? _lastBrightnessOverlay;
  // String? _overlayType; // 'volume' or 'brightness'

  // Offset? _rippleOffset;
  // bool _rippleVisible = false;

  late BoxFit _boxFit;

  @override
  void initState() {
    super.initState();
    _boxFit = widget.boxFitNotifier.value;
    widget.boxFitNotifier.addListener(_onBoxFitChanged);
    widget.thaController.initialize().then((_) {
      if (mounted) setState(() {});
    });
    _startHideTimer();
  }

  void _onBoxFitChanged() {
    if (mounted) {
      setState(() {
        _boxFit = widget.boxFitNotifier.value;
      });
    }
  }

  @override
  void dispose() {
    widget.boxFitNotifier.removeListener(_onBoxFitChanged);
    _hideTimer?.cancel();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_controlsLocked) {
        setState(() => _showControls = false);
      }
    });
  }

  void _adjustVolume(double delta) async {
    await NativeBridge.setVolume(delta.clamp(-1.0, 1.0));
  }

  void _adjustBrightness(double delta) async {
    await NativeBridge.setBrightness(delta.clamp(-1.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.thaController.controller;

    if (!widget.thaController.isInitialized) {
      return Container(
        color: Colors.grey[800],
        alignment: Alignment.center,
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height / 4,
        child: CircularProgressIndicator(color: Colors.amber),
      );
    }

    final videoWidth =
        controller.value.size.width > 0 ? controller.value.size.width : 640;
    final videoHeight =
        controller.value.size.height > 0 ? controller.value.size.height : 480;

    return GestureDetector(
      onTap: () {
        // if (_controlsLocked) return;
        setState(() => _showControls = !_showControls);
        if (_showControls) _startHideTimer();
      },
      onDoubleTapDown: (details) {
        if (_controlsLocked) return;
        final width = MediaQuery.of(context).size.width;
        if (details.globalPosition.dx < width / 2) {
          controller.seekTo(
            controller.value.position - const Duration(seconds: 10),
          );
        } else {
          controller.seekTo(
            controller.value.position + const Duration(seconds: 10),
          );
        }
        setState(() {
          _gestureSeekPreview = controller.value.position;
          Future.delayed(Duration(milliseconds: 500), () {
            setState(() {
              _gestureSeekPreview = null;
            });
          });
        });
      },
      onVerticalDragUpdate: (details) {
        if (_controlsLocked) return;
        final delta = (-details.primaryDelta! / 100).clamp(-1.0, 1.0);
        if (isVolumeGesture) {
          _adjustVolume(delta);
        } else {
          _adjustBrightness(delta);
        }
      },
      onVerticalDragStart: (details) {
        if (_controlsLocked) return;
        isVolumeGesture =
            details.localPosition.dx > MediaQuery.of(context).size.width / 2;
      },
      onHorizontalDragStart: (details) {
        if (_controlsLocked) return;
        _initialHorizontalSwipe = details.localPosition;
        _gestureSeekPreview = controller.value.position;
      },
      onHorizontalDragUpdate: (details) {
        if (_controlsLocked) return;
        final diff = details.localPosition.dx - _initialHorizontalSwipe!.dx;
        final newPosition =
            (_gestureSeekPreview ?? Duration.zero) +
            Duration(seconds: (diff / 10).round());
        final max = controller.value.duration;

        setState(() {
          _gestureSeekPreview =
              newPosition < Duration.zero
                  ? Duration.zero
                  : (newPosition > max ? max : newPosition);
        });
      },
      onHorizontalDragEnd: (_) {
        if (_controlsLocked || _gestureSeekPreview == null) return;
        controller.seekTo(_gestureSeekPreview!);
        _gestureSeekPreview = null;
      },
      child: Stack(
        alignment:
            widget.isFullscreen
                ? AlignmentDirectional.topStart
                : Alignment.topCenter,
        fit: widget.isFullscreen ? StackFit.expand : StackFit.loose,
        children: [
          FittedBox(
            fit: _boxFit,
            child: SizedBox(
              width: videoWidth.toDouble(),
              height: videoHeight.toDouble(),
              child: VideoPlayer(controller),
            ),
          ),

          // Overlay
          if (widget.overlay != null)
            Positioned(top: 12, right: 12, child: widget.overlay!),

          // Gesture seek preview
          if (_gestureSeekPreview != null)
            Positioned.fill(
              child: Container(
                padding: const EdgeInsets.all(8),
                alignment: Alignment.center,
                // decoration: BoxDecoration(
                //   color: Colors.black87,
                //   borderRadius: BorderRadius.circular(8),
                // ),
                child: Text(
                  _format(_gestureSeekPreview!),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),

          if (_showControls && _controlsLocked)
            Positioned(
              bottom: 10,
              right: 10,
              child: SizedBox(
                width: 45,
                height: 45,
                child: IconButton(
                  onPressed: () {
                    setState(() {
                      if (widget.isFullscreen) {
                        _controlsLocked = false;
                      } else {
                        _controlsLocked = !_controlsLocked;
                      }
                    });
                  },
                  icon: Icon(Icons.lock_open, color: Colors.white),
                ),
              ),
            ),

          // Control Bar
          if (_showControls && !_controlsLocked)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Stack(
                children: [
                  // Progress Bar
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(
                      value:
                          controller.value.duration.inMilliseconds > 0
                              ? controller.value.position.inMilliseconds /
                                  controller.value.duration.inMilliseconds
                              : 0.0,
                      backgroundColor: Colors.black26,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.redAccent,
                      ),
                      minHeight: 3,
                    ),
                  ),
                  ControlBar(
                    controller: controller,
                    isLocked: _controlsLocked,
                    boxFit: _boxFit,
                    onBoxFitChange: (fit) {
                      setState(() {
                        widget.boxFitNotifier.value = fit;
                      });
                    },
                    onToggleLock: () {
                      setState(() {
                        if (widget.isFullscreen) {
                          _controlsLocked = true;
                        } else {
                          _controlsLocked = !_controlsLocked;
                        }
                      });

                      setState(() => _showControls = false);
                    },
                    thaController: widget.thaController,
                    boxFitNotifier: widget.boxFitNotifier,
                    isFullscreen: widget.isFullscreen,
                    overlay: widget.overlay,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
