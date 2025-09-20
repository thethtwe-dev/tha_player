/// Metadata describing a selectable video track exposed by the native player.
class ThaVideoTrack {
  final String id;
  final String? label;
  final int? bitrate;
  final int? width;
  final int? height;
  final bool selected;

  const ThaVideoTrack({
    required this.id,
    required this.label,
    required this.bitrate,
    required this.width,
    required this.height,
    required this.selected,
  });

  factory ThaVideoTrack.fromMap(Map<dynamic, dynamic> map) {
    // ignore: no_leading_underscores_for_local_identifiers
    int? _int(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is double) return v.round();
      return int.tryParse(v.toString());
    }

    return ThaVideoTrack(
      id: map['id']?.toString() ?? '',
      label: map['label']?.toString(),
      bitrate: _int(map['bitrate']),
      width: _int(map['width']),
      height: _int(map['height']),
      selected: map['selected'] == true,
    );
  }

  String get displayLabel {
    final pieces = <String>[];
    if (label != null && label!.trim().isNotEmpty) {
      pieces.add(label!.trim());
    }
    final res = _resolutionLabel;
    if (res != null && !pieces.contains(res)) {
      pieces.add(res);
    }
    final br = _bitrateLabel;
    if (br != null && !pieces.contains(br)) {
      pieces.add(br);
    }
    if (pieces.isEmpty) {
      pieces.add(id);
    }
    return pieces.join(' • ');
  }

  String? get _resolutionLabel {
    if (height == null || height == 0) return null;
    return '${height}p';
  }

  String? get _bitrateLabel {
    final br = bitrate;
    if (br == null || br <= 0) return null;
    final mbps = br / 1000000.0;
    if (mbps >= 1) {
      return '${mbps.toStringAsFixed(mbps >= 10 ? 0 : 1)} Mbps';
    }
    final kbps = br / 1000.0;
    return '${kbps.toStringAsFixed(0)} Kbps';
  }
}

/// Metadata for an audio track the user can switch to.
class ThaAudioTrack {
  final String id;
  final String? label;
  final String? language;
  final bool selected;

  const ThaAudioTrack({
    required this.id,
    this.label,
    this.language,
    required this.selected,
  });

  factory ThaAudioTrack.fromMap(Map<dynamic, dynamic> map) => ThaAudioTrack(
    id: map['id']?.toString() ?? '',
    label: map['label']?.toString(),
    language: map['language']?.toString(),
    selected: map['selected'] == true,
  );
}

/// Metadata for closed captions / subtitle tracks.
class ThaSubtitleTrack {
  final String id;
  final String? label;
  final String? language;
  final bool selected;
  final bool isForced;

  const ThaSubtitleTrack({
    required this.id,
    this.label,
    this.language,
    required this.selected,
    this.isForced = false,
  });

  factory ThaSubtitleTrack.fromMap(Map<dynamic, dynamic> map) =>
      ThaSubtitleTrack(
        id: map['id']?.toString() ?? '',
        label: map['label']?.toString(),
        language: map['language']?.toString(),
        selected: map['selected'] == true,
        isForced: map['forced'] == true,
      );
}
