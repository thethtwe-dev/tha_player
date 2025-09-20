# 📺 tha_player

Native, network‑only video player for Flutter with modern MX/VLC‑style UX. Android uses ExoPlayer; iOS uses AVPlayer. Includes gestures, thumbnails on seek, DRM (Android), fullscreen, BoxFit, and more.

---

## ✨ Features

- ✅ Native engines: ExoPlayer (Android) and AVPlayer (iOS)
- ✅ Gestures: tap to show/hide, double‑tap seek, horizontal scrub, vertical volume/brightness
- ✅ Controls: play/pause, speed, fullscreen (manual or auto), lock, BoxFit (contain/cover/fill/fitWidth/fitHeight)
- ✅ Quality, audio, and subtitle track selection with data saver toggle
- ✅ Configurable retry/backoff, error callbacks, PiP playback controls
- ✅ Thumbnails: WebVTT sprites or image sequences during seek preview (cached in-memory)
- ✅ DRM (Android): Widevine and ClearKey
- ✅ M3U playlist parsing utility
- ✅ Overlay support (watermark, logos)

---

## 📦 Install

Add to `pubspec.yaml`:

```yaml
dependencies:
  tha_player: ^0.3.1
```

Then:

```
flutter pub get
```

## 🚀 Quick Start

```
import 'package:tha_player/tha_player.dart';

final ctrl = ThaNativePlayerController.single(
  ThaMediaSource(
    'https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    // Optional VTT thumbnails
    // thumbnailVttUrl: 'https://example.com/thumbs.vtt',
  ),
  autoPlay: true,
  playbackOptions: ThaPlaybackOptions(
    maxRetryCount: 5,
    initialRetryDelay: Duration(milliseconds: 800),
  ),
);

// In build:
AspectRatio(
  aspectRatio: 16 / 9,
  child: ThaModernPlayer(
    controller: ctrl,
    doubleTapSeek: Duration(seconds: 10),
    autoHideAfter: Duration(seconds: 3),
    initialBoxFit: BoxFit.contain,
  ),
)
```

### Fullscreen
Tap the fullscreen icon in the control bar. Playback position and state are preserved when entering/exiting fullscreen.

### BoxFit
Choose between `contain`, `cover`, `fill`, `fitWidth`, and `fitHeight` from the menu.

### Track Selection
Use the control bar to switch quality, audio, or subtitle tracks at runtime. You can also fetch tracks directly:

```
final qualities = await ctrl.getVideoTracks();
final audios = await ctrl.getAudioTracks();
final subtitles = await ctrl.getSubtitleTracks();
await ctrl.selectAudioTrack(audios.first.id);
await ctrl.selectSubtitleTrack(null); // disable captions
```

### Lock Controls
Use the lock icon to prevent controls/gestures; unlock with the floating button.

### DRM (Android)

```
final ctrl = ThaNativePlayerController.single(
  ThaMediaSource(
    'https://my.cdn.com/drm/manifest.mpd',
    drm: ThaDrmConfig(
      type: ThaDrmType.widevine, // or ThaDrmType.clearKey
      licenseUrl: 'https://license.server/wv',
      headers: {'Authorization': 'Bearer <token>'},
      // clearKey: '{"keys":[{"kty":"oct","k":"...","kid":"..."}]}'
    ),
  ),
);
```

### Thumbnails (WebVTT)
Provide a `.vtt` with sprites or images and optional `#xywh` regions:

```
ThaMediaSource(
  'https://example.com/video.m3u8',
  thumbnailVttUrl: 'https://example.com/thumbs.vtt',
)
```

---

## 🛠 Platform Notes

- Android: ExoPlayer backend with Media3; Widevine/ClearKey supported; per‑item HTTP headers.
- iOS: AVPlayer backend; `fitWidth`/`fitHeight` approximate via `resizeAspect`.
- Keep‑screen‑on is enabled during playback (Android/iOS).
- Playability depends on device codecs, stream, and network.

Thumbnails are cached in-memory. Call `clearThumbnailCache()` if you need to purge the cache.

### Resilient playback

`ThaPlaybackOptions` lets you tweak retry/backoff behaviour and rebuffer handling. Failures are surfaced via `ThaNativeEvents.error` and the `onError` callback on `ThaModernPlayer`.

### Custom HTTP (Android)

Provide a bespoke `OkHttpClient` to inject interceptors or caching:

Register the factory inside your Android `Application`:

```kotlin
class App : FlutterApplication() {
  override fun onCreate() {
    super.onCreate()
    ThaPlayerPlugin.setHttpClientFactory {
      OkHttpClient.Builder()
        .addInterceptor(MyHeaderInterceptor())
        .cache(Cache(cacheDir.resolve("video"), 100L * 1024L * 1024L))
        .build()
    }
  }
}
```

Set the factory before creating any Flutter controllers so every instance shares the same client.

### 16 KB Page Size Support
This plugin does not ship custom native decoder binaries. If you add native libraries, link them with a max page size compatible with 16 KB systems (e.g., `-Wl,-z,max-page-size=16384` on Android NDK).

---

## 🧪 Example

See `example/` for a runnable app that demonstrates the modern controls, gestures, fullscreen, and thumbnails.

---

## 💖 Support

If this package helps you, consider a tip:

- Tron (TRC20): `TLbwVrZyaZujcTCXAb94t6k7BrvChVfxzi`

---

## 📣 Contributing

Issues and PRs are welcome! Please file bugs or ideas at the issue tracker.

---

## 📄 License

MIT — see `LICENSE`.
