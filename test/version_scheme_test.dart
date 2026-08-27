import 'package:app_update_gate/src/version_scheme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PolicyVersion.tryParse — semantic scheme', () {
    PolicyVersion? parse(String? raw) =>
        PolicyVersion.tryParse(raw, VersionScheme.semantic);

    test('parses a dotted version', () {
      expect(parse('1.2.3').toString(), '1.2.3');
    });

    test('pads a two-segment version with a zero patch', () {
      expect(parse('1.2').toString(), '1.2.0');
    });

    test('extracts the version from a decorated string', () {
      expect(parse('v1.4.9 (149)').toString(), '1.4.9');
    });

    test('rejects a bare integer (build codes are not semantic)', () {
      // '140' under semantic would become 140.0.0 and force everyone.
      expect(parse('140'), isNull);
    });

    test('rejects empty and null input', () {
      expect(parse(''), isNull);
      expect(parse(null), isNull);
    });
  });

  group('PolicyVersion.tryParse — buildNumber scheme', () {
    PolicyVersion? parse(String? raw) =>
        PolicyVersion.tryParse(raw, VersionScheme.buildNumber);

    test('parses a pure integer', () {
      expect(parse('140').toString(), '140');
    });

    test('parses a padded integer', () {
      expect(parse(' 14000 ').toString(), '14000');
    });

    test('rejects a dotted version (version names are not build codes)', () {
      expect(parse('1.4.0'), isNull);
    });

    test('rejects non-numeric input', () {
      expect(parse('abc'), isNull);
      expect(parse(''), isNull);
      expect(parse(null), isNull);
    });
  });

  group('PolicyVersion comparison', () {
    test('orders semantic versions', () {
      final a = PolicyVersion.tryParse('1.2.9', VersionScheme.semantic)!;
      final b = PolicyVersion.tryParse('1.3.0', VersionScheme.semantic)!;
      expect(a < b, isTrue);
      expect(b > a, isTrue);
      expect(a < a, isFalse);
    });

    test('orders build numbers numerically, not lexically', () {
      final a = PolicyVersion.tryParse('128', VersionScheme.buildNumber)!;
      final b = PolicyVersion.tryParse('1030', VersionScheme.buildNumber)!;
      expect(a < b, isTrue);
    });
  });

  group('PolicyVersion.current — reads the right app field per scheme', () {
    test('semantic scheme uses the version name', () {
      final current = PolicyVersion.current(
        versionName: '1.2.8',
        buildNumber: '128',
        scheme: VersionScheme.semantic,
      );
      expect(current.toString(), '1.2.8');
    });

    test('buildNumber scheme uses the build number', () {
      final current = PolicyVersion.current(
        versionName: '1.2.8',
        buildNumber: '128',
        scheme: VersionScheme.buildNumber,
      );
      expect(current.toString(), '128');
    });

    test('fails open (null) when the build number is dotted (iOS style)', () {
      final current = PolicyVersion.current(
        versionName: '1.2.8',
        buildNumber: '1.2.8',
        scheme: VersionScheme.buildNumber,
      );
      expect(current, isNull);
    });
  });
}
