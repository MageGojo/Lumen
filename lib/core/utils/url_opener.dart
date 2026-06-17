import 'dart:io';

class UrlOpener {
  const UrlOpener._();

  static Future<void> open(String url) async {
    await Process.run('open', [url]);
  }
}
