import 'drm.dart';

/// Definition of a single media item for the native player.
class ThaMediaSource {
  /// Stream URL or manifest (HLS/DASH/MP4/etc).
  final String url;

  /// Optional HTTP headers applied to the media request.
  final Map<String, String>? headers;

  /// When `true`, enables live-stream tuning such as low latency buffering.
  final bool isLive;

  /// DRM configuration for the item.
  final ThaDrmConfig drm;

  /// Optional VTT sprite sheet used to render seek thumbnails.
  final String? thumbnailVttUrl;

  /// Additional headers for thumbnail requests.
  final Map<String, String>? thumbnailHeaders;

  /// Creates a media source definition.
  const ThaMediaSource(
    this.url, {
    this.headers,
    this.isLive = false,
    this.drm = const ThaDrmConfig(type: ThaDrmType.none),
    this.thumbnailVttUrl,
    this.thumbnailHeaders,
  });

  /// `true` if the URL looks like an HLS manifest.
  bool get isM3U8 => url.toLowerCase().endsWith('.m3u8');

  /// `true` if the URL ends with `.m3u`.
  bool get isM3U => url.toLowerCase().endsWith('.m3u');
}
