import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ThumbCue {
  final Duration start;
  final Duration end;
  final Uri image;
  final int? x;
  final int? y;
  final int? w;
  final int? h;

  const ThumbCue({
    required this.start,
    required this.end,
    required this.image,
    this.x,
    this.y,
    this.w,
    this.h,
  });

  bool get hasCrop => x != null && y != null && w != null && h != null;
}

Future<List<ThumbCue>> fetchVttThumbnails(
  String url, {
  Map<String, String>? headers,
}) async {
  final client = HttpClient();
  final req = await client.getUrl(Uri.parse(url));
  headers?.forEach((k, v) => req.headers.set(k, v));
  final resp = await req.close();
  if (resp.statusCode != 200) {
    throw StateError('Failed to fetch thumbnails VTT: HTTP ${resp.statusCode}');
  }
  final text = await utf8.decodeStream(resp);
  return parseWebVtt(text, base: Uri.parse(url));
}

List<ThumbCue> parseWebVtt(String input, {Uri? base}) {
  final lines = const LineSplitter().convert(input);
  final result = <ThumbCue>[];
  Duration? start;
  Duration? end;
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('WEBVTT')) continue;
    if (line.contains('-->')) {
      final parts = line.split('-->');
      start = _parseVttTime(parts[0].trim());
      end = _parseVttTime(parts[1].trim());
      continue;
    }
    if (start != null && end != null) {
      // Expect image url possibly with #xywh=x,y,w,h
      final uri = base == null ? Uri.parse(line) : base.resolve(line);
      int? x, y, w, h;
      if (uri.fragment.startsWith('xywh=')) {
        final vals = uri.fragment.substring(5).split(',');
        if (vals.length == 4) {
          x = int.tryParse(vals[0]);
          y = int.tryParse(vals[1]);
          w = int.tryParse(vals[2]);
          h = int.tryParse(vals[3]);
        }
      }
      final clean = uri.replace(fragment: '');
      result.add(
        ThumbCue(start: start, end: end, image: clean, x: x, y: y, w: w, h: h),
      );
      start = null;
      end = null;
    }
  }
  return result;
}

Duration _parseVttTime(String s) {
  // 00:00:05.000 or 00:05.000
  final parts = s.split(':');
  int h = 0, m = 0;
  double sec = 0;
  if (parts.length == 3) {
    h = int.parse(parts[0]);
    m = int.parse(parts[1]);
    sec = double.parse(parts[2].replaceAll(',', '.'));
  } else if (parts.length == 2) {
    m = int.parse(parts[0]);
    sec = double.parse(parts[1].replaceAll(',', '.'));
  }
  final ms = (sec * 1000).round();
  return Duration(hours: h, minutes: m, milliseconds: ms);
}
