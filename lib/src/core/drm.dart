enum ThaDrmType { none, widevine, clearKey }

class ThaDrmConfig {
  final ThaDrmType type;
  final String? licenseUrl;
  final Map<String, String>? headers;
  final String? clearKey; // JSON as required by ExoPlayer when using ClearKey
  final String? contentId;

  const ThaDrmConfig({
    required this.type,
    this.licenseUrl,
    this.headers,
    this.clearKey,
    this.contentId,
  });

  bool get isDrm => type != ThaDrmType.none;

  @override
  String toString() =>
      'ThaDrmConfig(type: $type, licenseUrl: $licenseUrl, hasHeaders: ${headers?.isNotEmpty == true}, contentId: $contentId, clearKey: ${clearKey != null ? "***" : null})';
}
