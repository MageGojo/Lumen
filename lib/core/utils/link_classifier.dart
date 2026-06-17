/// Where a pasted/sniffed link should be sent.
enum LinkRoute {
  /// magnet: / .torrent  ->  aria2 (BitTorrent engine).
  torrent,

  /// A direct downloadable file (incl. .mp4 / .m3u8)  ->  Surge (HTTP engine).
  directFile,

  /// A supported short-video / social *page*  ->  Apizero (parse first).
  share,

  /// Anything else  ->  Surge (HTTP engine).
  generic,
}

/// Decides which engine handles a link. Priority is important:
///   torrent  >  directFile  >  share  >  generic
/// so that e.g. a `.mp4` / `.m3u8` URL (even on a video-site domain) downloads
/// directly via Surge instead of being sent to the Apizero video parser.
class LinkClassifier {
  LinkClassifier._();

  /// Hosts whose *pages* need parsing into a real media URL (Apizero).
  static const List<String> _shareHosts = [
    'bilibili.com',
    'b23.tv',
    'douyin.com',
    'iesdouyin.com',
    'kuaishou.com',
    'gifshow.com',
    'xiaohongshu.com',
    'xhslink.com',
    'weibo.com',
    'weibo.cn',
    't.cn',
    'ixigua.com',
    'toutiao.com',
    'pipix.com',
    'huoshan.com',
    'acfun.cn',
    'weishi.qq.com',
    'youtube.com',
    'youtu.be',
    'tiktok.com',
    'instagram.com',
    'twitter.com',
    'x.com',
    'facebook.com',
  ];

  /// Extensions we treat as a direct, downloadable resource (Surge).
  static const List<String> _fileExtensions = [
    '.mp4', '.mkv', '.mov', '.avi', '.flv', '.webm', '.m4v', '.ts', '.m4s',
    '.m3u8',
    '.mp3', '.flac', '.wav', '.aac', '.m4a', '.ogg',
    '.zip', '.rar', '.7z', '.tar', '.gz', '.xz', '.dmg', '.pkg', '.exe',
    '.msi', '.iso', '.bin', '.img', '.apk', '.deb', '.rpm',
    '.pdf', '.epub', '.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg',
  ];

  /// The single source of truth for routing a link.
  static LinkRoute classify(String url) {
    if (isTorrentLink(url)) return LinkRoute.torrent;
    if (isDirectFile(url)) return LinkRoute.directFile;
    if (_isShareHost(url)) return LinkRoute.share;
    return LinkRoute.generic;
  }

  /// True for BitTorrent inputs (a `magnet:` URI or a `.torrent` link) that
  /// must be handled by the aria2 engine rather than the HTTP downloader.
  static bool isTorrentLink(String url) {
    final trimmed = url.trim().toLowerCase();
    if (trimmed.startsWith('magnet:')) return true;
    final uri = _tryParse(url);
    final path = (uri?.path ?? url).toLowerCase();
    return path.endsWith('.torrent');
  }

  /// True for HLS / DASH streaming manifests, which can't be saved as a single
  /// file without an external muxer (ffmpeg).
  static bool isStreamingManifest(String url) {
    final uri = _tryParse(url);
    final path = (uri?.path ?? url).toLowerCase();
    return path.endsWith('.m3u8') || path.endsWith('.mpd');
  }

  /// True when the URL clearly ends in a downloadable file extension.
  static bool isDirectFile(String url) {
    final uri = _tryParse(url);
    final path = (uri?.path ?? url).toLowerCase();
    for (final ext in _fileExtensions) {
      if (path.endsWith(ext)) return true;
    }
    return false;
  }

  /// True only when the link should be parsed by Apizero first: a supported
  /// share host *and* not already a direct media file / torrent.
  static bool isShareLink(String url) => classify(url) == LinkRoute.share;

  static bool _isShareHost(String url) {
    final uri = _tryParse(url);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;
    for (final h in _shareHosts) {
      if (host == h || host.endsWith('.$h')) return true;
    }
    return false;
  }

  static Uri? _tryParse(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    final normalized =
        trimmed.startsWith('http') ? trimmed : 'https://$trimmed';
    return Uri.tryParse(normalized);
  }
}
