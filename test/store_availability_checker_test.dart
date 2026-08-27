import 'dart:convert';

import 'package:app_update_gate/src/app_update_config.dart';
import 'package:app_update_gate/src/app_version.dart';
import 'package:app_update_gate/src/store_availability_checker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const config = AppUpdateConfig(
    androidPackageId: 'com.example.myapp',
    iosAppStoreId: '1234567890',
  );

  IosStoreAvailabilityChecker checker(String? storeVersion) {
    return IosStoreAvailabilityChecker(
      config,
      client: MockClient((_) async {
        if (storeVersion == null) {
          return http.Response(jsonEncode({'results': []}), 200);
        }
        return http.Response(
          jsonEncode({
            'results': [
              {'version': storeVersion},
            ],
          }),
          200,
        );
      }),
    );
  }

  group('IosStoreAvailabilityChecker — semantic scheme (minRequired given)', () {
    test('available when the live store version satisfies the minimum', () async {
      final status = await checker('1.4.0').check(
        minRequired: AppVersion.tryParse('1.3.0'),
        currentVersion: AppVersion.tryParse('1.2.8'),
      );
      expect(status.isUpdateAvailable, isTrue);
      expect(status.latestStoreVersion, '1.4.0');
    });

    test('NOT available when the store still serves an older version', () async {
      final status = await checker('1.2.9').check(
        minRequired: AppVersion.tryParse('1.3.0'),
        currentVersion: AppVersion.tryParse('1.2.8'),
      );
      expect(status.isUpdateAvailable, isFalse);
    });
  });

  group('IosStoreAvailabilityChecker — buildNumber scheme (no minRequired)', () {
    test('falls back to "store is newer than the running app"', () async {
      final status = await checker('1.3.0').check(
        minRequired: null,
        currentVersion: AppVersion.tryParse('1.2.8'),
      );
      expect(status.isUpdateAvailable, isTrue);
    });

    test('NOT available when the store equals the running app', () async {
      final status = await checker('1.2.8').check(
        minRequired: null,
        currentVersion: AppVersion.tryParse('1.2.8'),
      );
      expect(status.isUpdateAvailable, isFalse);
    });

    test('fails open when nothing to compare against', () async {
      final status = await checker('1.3.0').check(
        minRequired: null,
        currentVersion: null,
      );
      expect(status.isUpdateAvailable, isFalse);
    });
  });

  group('IosStoreAvailabilityChecker — fail open', () {
    test('on HTTP failure', () async {
      final failing = IosStoreAvailabilityChecker(
        config,
        client: MockClient((_) async => http.Response('nope', 500)),
      );
      final status = await failing.check(
        minRequired: AppVersion.tryParse('1.3.0'),
        currentVersion: AppVersion.tryParse('1.2.8'),
      );
      expect(status.isUpdateAvailable, isFalse);
    });

    test('on empty lookup results', () async {
      final status = await checker(null).check(
        minRequired: AppVersion.tryParse('1.3.0'),
        currentVersion: AppVersion.tryParse('1.2.8'),
      );
      expect(status.isUpdateAvailable, isFalse);
    });
  });
}
