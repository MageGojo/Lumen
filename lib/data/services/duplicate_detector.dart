import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/utils/link_classifier.dart';

/// How an existing on-disk file relates to the incoming download.
enum DuplicateMatchKind {
  /// Same filename AND same byte size — almost certainly the identical file.
  identical,

  /// Same filename but a different size — likely a different / updated version
  /// that merely reuses the old name (the case users get bitten by).
  sameNameDiffSize,

  /// Different filename but the exact same byte size — a possible renamed copy.
  sameSizeDiffName,
}

/// What to do about a detected duplicate. Lives in the domain layer so both the
/// dialog (one way to produce it) and the controller can share it.
enum DuplicateDecision { cancel, rename, replace }

/// One on-disk file that looks like a duplicate of the incoming download.
class ExistingFile {
  final String path;
  final String name;
  final int size;
  final DateTime modified;
  final DuplicateMatchKind kind;

  const ExistingFile({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
    required this.kind,
  });
}

/// The outcome of inspecting a target directory before a download starts.
class DuplicateReport {
  final String url;
  final String dir;
  final String remoteName;

  /// Remote size in bytes, or -1 when the server didn't disclose it (HEAD
  /// without `Content-Length`, or HEAD unsupported). Without a size we can only
  /// match by name, so the "version update" distinction is unavailable.
  final int remoteSize;

  final List<ExistingFile> matches;

  const DuplicateReport({
    required this.url,
    required this.dir,
    required this.remoteName,
    required this.remoteSize,
    required this.matches,
  });

  bool get hasMatches => matches.isNotEmpty;

  bool get sizeKnown => remoteSize >= 0;

  /// Same name + same size present.
  bool get hasIdentical =>
      matches.any((m) => m.kind == DuplicateMatchKind.identical);

  /// A same-name file exists but the size differs — the user-flagged case of a
  /// new version sharing the old filename.
  bool get hasVersionConflict =>
      matches.any((m) => m.kind == DuplicateMatchKind.sameNameDiffSize);

  /// Any file already occupies the target filename.
  bool get hasNameConflict => matches.any((m) =>
      m.kind == DuplicateMatchKind.identical ||
      m.kind == DuplicateMatchKind.sameNameDiffSize);

  List<String> get matchPaths =>
      matches.map((m) => m.path).toList(growable: false);
}

/// Looks for files in the destination directory that duplicate an incoming
/// download, *before* the download starts. Pure logic + filesystem/HTTP I/O;
/// no Flutter dependencies.
class DuplicateDetector {
  final http.Client _client;

  DuplicateDetector({http.Client? client}) : _client = client ?? http.Client();

  static const String _ua =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

  /// Only single-file HTTP(S) downloads can be checked ahead of time. Torrents
  /// resolve their name from metadata (unknown up front) and streaming
  /// manifests aren't saved as one file, so both are skipped.
  bool isCheckable(String url) {
    final t = url.trim();
    if (t.isEmpty) return false;
    if (LinkClassifier.isTorrentLink(t)) return false;
    if (LinkClassifier.isStreamingManifest(t)) return false;
    final uri = Uri.tryParse(t.startsWith('http') ? t : 'https://$t');
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  /// Probes [url] and scans [dir]; returns a report only when at least one
  /// match is found. Returns null (proceed silently) on any inability to check.
  Future<DuplicateReport?> inspect({
    required String url,
    required String dir,
    String? referer,
  }) async {
    final target = dir.trim();
    if (target.isEmpty) return null;
    final directory = Directory(target);
    if (!await directory.exists()) return null;

    final (remoteName, remoteSize) = await _probe(url, referer);
    if (remoteName.isEmpty) return null;

    final matches = <ExistingFile>[];
    try {
      for (final entry in directory.listSync(followLinks: false)) {
        if (entry is! File) continue;
        final name = _leaf(entry.path);
        if (name.isEmpty || name.startsWith('.')) continue;

        final FileStat stat;
        try {
          stat = entry.statSync();
        } catch (_) {
          continue;
        }

        final sameName = name == remoteName;
        final sameSize = remoteSize >= 0 && stat.size == remoteSize;
        final DuplicateMatchKind kind;
        if (sameName && sameSize) {
          kind = DuplicateMatchKind.identical;
        } else if (sameName) {
          kind = DuplicateMatchKind.sameNameDiffSize;
        } else if (sameSize) {
          kind = DuplicateMatchKind.sameSizeDiffName;
        } else {
          continue;
        }

        matches.add(ExistingFile(
          path: entry.path,
          name: name,
          size: stat.size,
          modified: stat.modified,
          kind: kind,
        ));
      }
    } catch (_) {
      return null;
    }

    if (matches.isEmpty) return null;
    matches.sort((a, b) => a.kind.index.compareTo(b.kind.index));
    return DuplicateReport(
      url: url,
      dir: target,
      remoteName: remoteName,
      remoteSize: remoteSize,
      matches: matches,
    );
  }

  /// A non-colliding filename in [dir] for [name], using Surge's own
  /// `name(1).ext` collision style so both engines stay visually consistent.
  String freeNameIn(String dir, String name) {
    final dot = name.lastIndexOf('.');
    final hasExt = dot > 0 && dot < name.length - 1;
    final stem = hasExt ? name.substring(0, dot) : name;
    final ext = hasExt ? name.substring(dot) : '';
    final sep = Platform.pathSeparator;
    var candidate = name;
    var n = 1;
    while (File('$dir$sep$candidate').existsSync()) {
      candidate = '$stem($n)$ext';
      n++;
    }
    return candidate;
  }

  /// Best-effort deletion of the matched originals (used by "replace").
  Future<void> deleteFiles(Iterable<String> paths) async {
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // best-effort; a still-present file just collides again next time.
      }
    }
  }

  /// HEAD the URL to learn the filename + size without downloading the body.
  /// Falls back to the (redirect-resolved) URL path for the name and -1 size.
  Future<(String, int)> _probe(String url, String? referer) async {
    final normalized =
        url.trim().startsWith('http') ? url.trim() : 'https://${url.trim()}';
    final uri = Uri.tryParse(normalized);
    if (uri == null) return ('', -1);

    var name = _nameFromUrl(uri);
    var size = -1;
    try {
      final headers = <String, String>{'user-agent': _ua};
      if (referer != null && referer.trim().isNotEmpty) {
        headers['referer'] = referer.trim();
      }
      final res = await _client
          .head(uri, headers: headers)
          .timeout(const Duration(seconds: 6));

      final cl = res.headers['content-length'];
      if (cl != null) size = int.tryParse(cl.trim()) ?? -1;

      final fromCd = _nameFromContentDisposition(res.headers['content-disposition']);
      if (fromCd != null && fromCd.isNotEmpty) {
        name = fromCd;
      } else {
        final finalUrl = res.request?.url;
        if (finalUrl != null) {
          final n = _nameFromUrl(finalUrl);
          if (n.isNotEmpty) name = n;
        }
      }
    } catch (_) {
      // HEAD unsupported / unreachable: keep URL-derived name, size unknown.
    }
    return (name, size);
  }

  String _leaf(String path) {
    final parts = path.split(Platform.pathSeparator);
    return parts.isEmpty ? '' : parts.last;
  }

  String _nameFromUrl(Uri uri) {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) return '';
    final last = segs.last;
    try {
      return Uri.decodeComponent(last);
    } catch (_) {
      return last;
    }
  }

  String? _nameFromContentDisposition(String? value) {
    if (value == null || value.isEmpty) return null;
    // RFC 5987 extended form takes precedence: filename*=UTF-8''encoded%20name
    final star =
        RegExp(r"filename\*\s*=\s*([^;]+)", caseSensitive: false).firstMatch(value);
    if (star != null) {
      var v = star.group(1)!.trim();
      final tick = v.indexOf("''");
      if (tick >= 0) v = v.substring(tick + 2);
      v = v.replaceAll('"', '').trim();
      try {
        return Uri.decodeComponent(v);
      } catch (_) {
        return v;
      }
    }
    final plain = RegExp(r'filename\s*=\s*"?([^";]+)"?', caseSensitive: false)
        .firstMatch(value);
    return plain?.group(1)?.trim();
  }

  void dispose() => _client.close();
}
