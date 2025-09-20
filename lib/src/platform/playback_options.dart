/// Configuration options that influence playback resilience and buffering.
class ThaPlaybackOptions {
  /// Maximum automatic retry attempts before surfacing a failure. `-1`
  /// indicates unlimited retries.
  final int maxRetryCount;

  /// Delay before the first retry attempt.
  final Duration initialRetryDelay;

  /// Maximum backoff delay between retries.
  final Duration maxRetryDelay;

  /// Whether the native player should automatically retry after recoverable
  /// errors (HTTP 5xx, network timeouts, etc.).
  final bool autoRetry;

  /// Optional timeout to rebuffer before considering playback stalled.
  final Duration? rebufferTimeout;

  const ThaPlaybackOptions({
    this.maxRetryCount = 3,
    this.initialRetryDelay = const Duration(seconds: 1),
    this.maxRetryDelay = const Duration(seconds: 10),
    this.autoRetry = true,
    this.rebufferTimeout,
  });

  /// Serializes this instance for the native platform layers.
  Map<String, dynamic> toMap() => {
    'maxRetryCount': maxRetryCount,
    'initialRetryDelayMs': initialRetryDelay.inMilliseconds,
    'maxRetryDelayMs': maxRetryDelay.inMilliseconds,
    'autoRetry': autoRetry,
    'rebufferTimeoutMs': rebufferTimeout?.inMilliseconds,
  };
}
