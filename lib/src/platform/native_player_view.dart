import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' as services;
import 'package:flutter/rendering.dart' as rendering;
import 'package:flutter/gestures.dart';

import 'native_player_controller.dart';

/// Wraps the Android/iOS platform view that renders the native video surface.
class ThaNativePlayerView extends StatefulWidget {
  final ThaNativePlayerController controller;
  final Widget? overlay;
  final BoxFit boxFit;

  const ThaNativePlayerView({
    super.key,
    required this.controller,
    this.overlay,
    this.boxFit = BoxFit.contain,
  });

  @override
  State<ThaNativePlayerView> createState() => _ThaNativePlayerViewState();
}

class _ThaNativePlayerViewState extends State<ThaNativePlayerView> {
  @override
  Widget build(BuildContext context) {
    const viewType = 'thaplayer/native_view';
    final creationParams = widget.controller.creationParams;

    Widget platformView;
    if (defaultTargetPlatform == TargetPlatform.android) {
      platformView = PlatformViewLink(
        viewType: viewType,
        surfaceFactory: (context, controller) {
          return AndroidViewSurface(
            controller: controller as services.AndroidViewController,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
            hitTestBehavior: rendering.PlatformViewHitTestBehavior.opaque,
          );
        },
        onCreatePlatformView: (params) {
          final controller =
              services.PlatformViewsService.initSurfaceAndroidView(
                id: params.id,
                viewType: viewType,
                layoutDirection: TextDirection.ltr,
                creationParams: creationParams,
                creationParamsCodec: const services.StandardMessageCodec(),
              );
          controller.addOnPlatformViewCreatedListener(
            params.onPlatformViewCreated,
          );
          controller.addOnPlatformViewCreatedListener((id) {
            widget.controller.attachViewId(id);
            widget.controller.setBoxFit(widget.boxFit, updatePreference: false);
          });
          controller.create();
          return controller;
        },
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      platformView = UiKitView(
        viewType: viewType,
        creationParams: creationParams,
        creationParamsCodec: const services.StandardMessageCodec(),
        onPlatformViewCreated: (id) {
          widget.controller.attachViewId(id);
          widget.controller.setBoxFit(widget.boxFit, updatePreference: false);
        },
      );
    } else {
      platformView = const SizedBox.shrink();
    }

    return Stack(
      children: [
        Positioned.fill(child: platformView),
        if (widget.overlay != null)
          Positioned(top: 12, right: 12, child: widget.overlay!),
      ],
    );
  }

  @override
  void didUpdateWidget(covariant ThaNativePlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.boxFit != widget.boxFit) {
      widget.controller.setBoxFit(widget.boxFit, updatePreference: false);
    }
  }
}
