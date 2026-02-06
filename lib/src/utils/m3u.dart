import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/media_source.dart';

/// Parses a simple M3U playlist (not HLS). Lines beginning with `#` are ignored
/// except `#EXTINF` metadata which is currently skipped.
Future<List<ThaMediaSource>> parseM3U(
  String url, {
  Map<String, String>? headers,
}) async {
  final client = HttpClient();
  try {
    if (headers != null && headers.isNotEmpty) {
      client.userAgent = headers['User-Agent'];
    }
    final req = await client.getUrl(Uri.parse(url));
    headers?.forEach((k, v) => req.headers.set(k, v));
    final resp = await req.close();
    if (resp.statusCode != 200) {
      throw StateError('Failed to load M3U: HTTP ${resp.statusCode}');
    }
    final body = await utf8.decodeStream(resp);
    final lines = body.split('\n');
    final result = <ThaMediaSource>[];
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) continue;
      // Basic absolute/relative handling
      final uri = Uri.parse(line);
      String resolved = line;
      if (!uri.hasScheme) {
        final base = Uri.parse(url);
        resolved = base.resolveUri(Uri.parse(line)).toString();
      }
      result.add(ThaMediaSource(resolved));
    }
    return result;
  } finally {
    client.close(force: true);
  }
}
