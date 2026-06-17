// Unit tests for Lumen's settings helpers.
//
// The full app boots native daemons (Surge / aria2) and a loopback bridge, so a
// widget smoke test isn't meaningful here. Instead we cover the pure header
// parsing logic that powers the custom UA / request-header feature.

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/state/settings_controller.dart';

void main() {
  group('SettingsController.parseHeadersText', () {
    test('parses "Key: Value" lines, trimming whitespace', () {
      final headers = SettingsController.parseHeadersText(
        'Cookie: a=1; b=2\n  Referer:  https://example.com  ',
      );
      expect(headers['Cookie'], 'a=1; b=2');
      expect(headers['Referer'], 'https://example.com');
      expect(headers.length, 2);
    });

    test('keeps colons that appear in the value', () {
      final headers = SettingsController.parseHeadersText(
        'Authorization: Bearer abc:def',
      );
      expect(headers['Authorization'], 'Bearer abc:def');
    });

    test('ignores blank lines and lines without a separator', () {
      final headers = SettingsController.parseHeadersText(
        '\nGarbageLine\nX-Token: t\n   \n',
      );
      expect(headers, {'X-Token': 't'});
    });

    test('round-trips through headersToText', () {
      const text = 'Cookie: a=1\nX-Token: t';
      final parsed = SettingsController.parseHeadersText(text);
      expect(SettingsController.headersToText(parsed), text);
    });
  });
}
