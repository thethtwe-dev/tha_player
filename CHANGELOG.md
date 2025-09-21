## 0.4.1

- Modern player quick actions now sit in a tidy wrap along the top-left, keeping the progress and transport controls anchored to the bottom without overlap
- Rebuilt the transport row around a larger play toggle with consistent skip chips and picture-in-picture/fullscreen buttons
- Added a press-and-hold speed boost (2×) with visual speed badges in menus and chips, plus refreshed control styling for a cleaner transparent overlay

## 0.4.0

- Added MX Player–style long-press seeking with configurable `longPressSeek` interval
- Improved seek overlays for double-tap/hold gestures (consistent flash, formatting)
- Replaced BoxFit popup with a compact dialog grid that clearly marks the active fit
- Removed fullscreen SafeArea gutters so video truly fills edge-to-edge

## 0.3.1

- Normal Player overflow bug fix
- Player controls duplicate issues fix

## 0.3.0

- Added optional `autoFullscreen` flag to `ThaModernPlayer` with sample toggle
- Fixed autoplay regression when jumping straight into fullscreen
- Exposed reusable fullscreen helper to keep inline + fullscreen UIs in sync
- Returned normalised brightness/volume levels for gesture overlays
- Added video/audio/subtitle track selection APIs and richer control-bar menus
- Provided shared OkHttp client hook, configurable retry/backoff, and PiP media session controls (Android / iOS)
- Expanded Dartdoc coverage across core public API
- Updated documentation and example app controls

## 0.0.2

- Initial release
- Basic player functionality
- BoxFit control
- Overlay support
- Fullscreen support
## 0.2.0

- Native engines: ExoPlayer (Android) and AVPlayer (iOS) via platform views
- Modern controls: auto-hide on tap, double-tap seek with feedback, lock mode
- Volume/Brightness vertical gestures with auto-hidden side sliders
- Fullscreen uses same controls; seamless resume across enter/exit
- BoxFit controls: contain, cover, fill, fitWidth, fitHeight
- Buffering indicator; keep-screen-on during playback (Android/iOS)
- WebVTT thumbnails preview during seek (sprites supported via xywh)
- DRM (Android): Widevine and ClearKey
- Per-item HTTP headers; M3U parsing utility
- Documentation overhaul and pub.dev metadata updates
