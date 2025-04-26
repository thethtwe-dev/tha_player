# 📺 tha_player

A clean, customizable network-only video player package built purely with Flutter and Dart — inspired by MX Player.

`tha_player` gives you full control over network video playback with a simple and modern UI, gesture controls, fullscreen support, BoxFit scaling, custom overlays, and more.

---

## ✨ Features

- ✅ Play **network videos** (stream MP4, HLS, etc.)
- ✅ Built-in **BoxFit** control (`cover`, `contain`, `fill`, etc.)
- ✅ **Fullscreen support** with auto screen rotation
- ✅ **Custom overlay widget** support (e.g., logo, watermark)
- ✅ Minimal **ControlBar** with Play/Pause, Lock, Fullscreen, Speed
- ✅ **Double-tap seek** (forward/backward 10 seconds)
- ✅ **Vertical swipe gestures** to adjust volume and brightness
- ✅ **Mini progress bar** at the top
- ✅ Save last playback position (Coming soon 🚀)
- ✅ Lightweight, clean code, easy to extend

---

## 📦 Installation

Add `tha_player` to your `pubspec.yaml`:

```yaml
dependencies:
  tha_player: ^latest
```
Then run:
```
flutter pub get
```

## Quick Start Example
```
import 'package:flutter/material.dart';
import 'package:tha_player/tha_player.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tha Player Demo',
      home: HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late ThaPlayerController thaPlayerController;
  late ValueNotifier<BoxFit> boxFitNotifier;

  @override
  void initState() {
    super.initState();
    boxFitNotifier = ValueNotifier(BoxFit.contain);
    thaPlayerController = ThaPlayerController.network(
      'https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    );
    thaPlayerController.initialize();
  }

  @override
  void dispose() {
    thaPlayerController.dispose();
    boxFitNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tha Player Example')),
      body: Center(
        child: ThaPlayerView(
          thaController: thaPlayerController,
          boxFitNotifier: boxFitNotifier,
          overlay: Row(
            children: const [
              Icon(Icons.play_circle_fill, color: Colors.white, size: 18),
              SizedBox(width: 6),
              Text(
                "THA Player",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

| Property | Description |
|:---------|:------------|
| `ThaPlayerController` | Control playback (play, pause, seek) |
| `ThaPlayerView` | Widget for video playback and UI |
| `boxFitNotifier` | Dynamic BoxFit switching (cover, contain, etc.) |
| `overlay` | Add custom widget over video (logo, watermark) |
| `isFullscreen` | Handle fullscreen state manually (optional) |

### Credits

#### Based on Flutter's ```video_player``` plugin

Made with ❤️ by [ThetHtwe](https://github.com/thethtwe-dev)
# tha_player
