import 'drm.dart';

class ThaMediaSource {
  final String url;
  final Map<String, String>? headers;
  final bool isLive;
  final ThaDrmConfig drm;
  final String? thumbnailVttUrl;
  final Map<String, String>? thumbnailHeaders;

  const ThaMediaSource(
    this.url, {
    this.headers,
    this.isLive = false,
    this.drm = const ThaDrmConfig(type: ThaDrmType.none),
    this.thumbnailVttUrl,
    this.thumbnailHeaders,
  });

  bool get isM3U8 => url.toLowerCase().endsWith('.m3u8');
  bool get isM3U => url.toLowerCase().endsWith('.m3u');
}
