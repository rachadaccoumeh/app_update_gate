import 'package:app_update_gate/src/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppVersion.tryParse', () {
    test('parses full and partial versions', () {
      expect(AppVersion.tryParse('1.2.8'), const AppVersion(1, 2, 8));
      expect(AppVersion.tryParse('2'), const AppVersion(2, 0, 0));
      expect(AppVersion.tryParse('2.1'), const AppVersion(2, 1, 0));
    });

    test('ignores build metadata after +', () {
      expect(AppVersion.tryParse('1.2.8+128'), const AppVersion(1, 2, 8));
    });

    test('ignores hand-written build suffix from App Store version strings', () {
      // The iTunes lookup API returns the marketing version verbatim, and
      // developers sometimes type the build number into it (e.g. "1.4.9 (149)").
      expect(AppVersion.tryParse('1.4.9 (149)'), const AppVersion(1, 4, 9));
      expect(AppVersion.tryParse('1.4.9(149)'), const AppVersion(1, 4, 9));
      expect(AppVersion.tryParse('1.4.9 build 149'), const AppVersion(1, 4, 9));
      expect(AppVersion.tryParse('1.4.9-beta'), const AppVersion(1, 4, 9));
      expect(AppVersion.tryParse('  1.4.9  '), const AppVersion(1, 4, 9));
    });

    test('finds the version anywhere in the string, even with a prefix', () {
      expect(AppVersion.tryParse('149 1.4.9'), const AppVersion(1, 4, 9));
      expect(AppVersion.tryParse('(149) 1.4.9'), const AppVersion(1, 4, 9));
      expect(AppVersion.tryParse('v1.4.9'), const AppVersion(1, 4, 9));
      expect(AppVersion.tryParse('version 1.4.9'), const AppVersion(1, 4, 9));
      expect(
        AppVersion.tryParse('release 1.4.9 build 149'),
        const AppVersion(1, 4, 9),
      );
    });

    test('returns null when two dotted versions make the input ambiguous', () {
      expect(AppVersion.tryParse('1.4.9 requires iOS 15.6'), isNull);
      expect(AppVersion.tryParse('1.4.9 1.5.0'), isNull);
    });

    test('returns null for invalid input (so callers fail open)', () {
      expect(AppVersion.tryParse(null), isNull);
      expect(AppVersion.tryParse(''), isNull);
      expect(AppVersion.tryParse('abc'), isNull);
      expect(AppVersion.tryParse('(149)'), isNull);
      expect(AppVersion.tryParse('build 149'), isNull);
    });
  });

  group('comparison (min-version semantics)', () {
    test('below minimum requires update', () {
      final current = AppVersion.tryParse('1.2.7')!;
      final min = AppVersion.tryParse('1.2.8')!;
      expect(current < min, isTrue);
    });

    test('at or above minimum does not', () {
      final min = AppVersion.tryParse('1.2.8')!;
      expect(AppVersion.tryParse('1.2.8')! < min, isFalse);
      expect(AppVersion.tryParse('1.3.0')! < min, isFalse);
      expect(AppVersion.tryParse('2.0.0')! < min, isFalse);
    });

    test('compares numerically, not lexically (2.10 > 2.9)', () {
      expect(
        AppVersion.tryParse('2.10.0')! > AppVersion.tryParse('2.9.0')!,
        isTrue,
      );
    });
  });
}
