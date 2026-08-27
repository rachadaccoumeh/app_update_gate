import 'package:app_update_gate/src/app_update_config.dart';
import 'package:app_update_gate/src/app_update_service.dart';
import 'package:app_update_gate/src/app_version.dart';
import 'package:app_update_gate/src/store_availability_checker.dart';
import 'package:app_update_gate/src/update_decision.dart';
import 'package:app_update_gate/src/update_policy.dart';
import 'package:app_update_gate/src/version_scheme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Store checker whose answer is fixed by the test.
class _FakeStoreChecker implements StoreAvailabilityChecker {
  _FakeStoreChecker(this._status);
  final StoreStatus _status;

  AppVersion? seenMinRequired;
  AppVersion? seenCurrentVersion;

  @override
  Future<StoreStatus> check({
    AppVersion? minRequired,
    AppVersion? currentVersion,
  }) async {
    seenMinRequired = minRequired;
    seenCurrentVersion = currentVersion;
    return _status;
  }
}

AppUpdateService _service({
  required UpdatePolicy policy,
  required StoreStatus store,
  VersionScheme scheme = VersionScheme.semantic,
  bool sourceThrows = false,
}) {
  return AppUpdateService(
    config: AppUpdateConfig(
      androidPackageId: 'com.example.myapp',
      iosAppStoreId: '1234567890',
      versionScheme: scheme,
    ),
    source: CallbackUpdatePolicySource(() async {
      if (sourceThrows) throw Exception('backend down');
      return policy;
    }),
    storeChecker: _FakeStoreChecker(store),
  );
}

void main() {
  // Current app version is pinned for every test.
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'MyApp',
      packageName: 'com.example.myapp',
      version: '1.2.8',
      buildNumber: '128',
      buildSignature: '',
    );
  });

  group('AppUpdateService.evaluate — semantic scheme', () {
    test('forces update when below minimum and the build is on the store',
        () async {
      final decision = await _service(
        policy: const UpdatePolicy(
          minRequiredVersion: '1.3.0',
          message: 'Please update.',
        ),
        store: const StoreStatus(
          isUpdateAvailable: true,
          latestStoreVersion: '1.3.0',
        ),
      ).evaluate();

      expect(decision.requirement, UpdateRequirement.forced);
      expect(decision.message, 'Please update.');
      expect(decision.latestStoreVersion, '1.3.0');
    });

    test('does NOT force (fails open) when the build is not yet on the store',
        () async {
      final decision = await _service(
        policy: const UpdatePolicy(minRequiredVersion: '1.3.0'),
        store: const StoreStatus.unknown(),
      ).evaluate();

      expect(decision.requirement, UpdateRequirement.none);
    });

    test('emergency ignore-store flag forces even without store confirmation',
        () async {
      final decision = await _service(
        policy: const UpdatePolicy(
          minRequiredVersion: '1.3.0',
          ignoreStoreCheck: true,
        ),
        store: const StoreStatus.unknown(),
      ).evaluate();

      expect(decision.requirement, UpdateRequirement.forced);
    });

    test('does not force when the kill switch is off', () async {
      final decision = await _service(
        policy: const UpdatePolicy(
          minRequiredVersion: '1.3.0',
          forceUpdateEnabled: false,
        ),
        store: const StoreStatus(isUpdateAvailable: true),
      ).evaluate();

      expect(decision.isForced, isFalse);
    });

    test('returns optional (soft prompt) when below recommended only',
        () async {
      final decision = await _service(
        policy: const UpdatePolicy(recommendedVersion: '1.3.0'),
        store: const StoreStatus.unknown(),
      ).evaluate();

      expect(decision.requirement, UpdateRequirement.optional);
    });

    test('returns none when current version satisfies all thresholds',
        () async {
      final decision = await _service(
        policy: const UpdatePolicy(
          minRequiredVersion: '1.2.0',
          recommendedVersion: '1.2.8',
        ),
        store: const StoreStatus(isUpdateAvailable: true),
      ).evaluate();

      expect(decision.isNone, isTrue);
    });

    test('fails open to none when a bare build code sneaks into the policy',
        () async {
      // '130' under semantic must be rejected, not read as 130.0.0.
      final decision = await _service(
        policy: const UpdatePolicy(minRequiredVersion: '130'),
        store: const StoreStatus(isUpdateAvailable: true),
      ).evaluate();

      expect(decision.isNone, isTrue);
    });
  });

  group('AppUpdateService.evaluate — buildNumber scheme', () {
    test('forces update when the build number is below minimum', () async {
      final decision = await _service(
        scheme: VersionScheme.buildNumber,
        policy: const UpdatePolicy(minRequiredVersion: '130'),
        store: const StoreStatus(isUpdateAvailable: true),
      ).evaluate();

      expect(decision.requirement, UpdateRequirement.forced);
    });

    test('returns none when the build number satisfies the minimum', () async {
      final decision = await _service(
        scheme: VersionScheme.buildNumber,
        policy: const UpdatePolicy(minRequiredVersion: '128'),
        store: const StoreStatus(isUpdateAvailable: true),
      ).evaluate();

      expect(decision.isNone, isTrue);
    });

    test('fails open to none when a dotted version sneaks into the policy',
        () async {
      final decision = await _service(
        scheme: VersionScheme.buildNumber,
        policy: const UpdatePolicy(minRequiredVersion: '1.3.0'),
        store: const StoreStatus(isUpdateAvailable: true),
      ).evaluate();

      expect(decision.isNone, isTrue);
    });

    test('passes no minRequired to the store gate (falls back to current)',
        () async {
      final checker = _FakeStoreChecker(
        const StoreStatus(isUpdateAvailable: true),
      );
      final service = AppUpdateService(
        config: const AppUpdateConfig(
          androidPackageId: 'com.example.myapp',
          iosAppStoreId: '1234567890',
          versionScheme: VersionScheme.buildNumber,
        ),
        source: CallbackUpdatePolicySource(
          () async => const UpdatePolicy(minRequiredVersion: '130'),
        ),
        storeChecker: checker,
      );

      await service.evaluate();

      expect(checker.seenMinRequired, isNull);
      expect(checker.seenCurrentVersion, AppVersion.tryParse('1.2.8'));
    });
  });

  group('AppUpdateService.evaluate — fail open', () {
    test('returns none when the policy source throws', () async {
      final decision = await _service(
        policy: const UpdatePolicy(minRequiredVersion: '1.3.0'),
        store: const StoreStatus(isUpdateAvailable: true),
        sourceThrows: true,
      ).evaluate();

      expect(decision.isNone, isTrue);
    });

    test('returns none when the policy has no thresholds', () async {
      final decision = await _service(
        policy: const UpdatePolicy(),
        store: const StoreStatus.unknown(),
      ).evaluate();

      expect(decision.isNone, isTrue);
    });
  });
}
