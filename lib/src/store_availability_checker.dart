import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_update/in_app_update.dart';

import 'app_update_config.dart';
import 'app_version.dart';

/// Outcome of asking the store whether the required build is actually live.
class StoreStatus {
  const StoreStatus({
    required this.isUpdateAvailable,
    this.latestStoreVersion,
  });

  /// Safe, fail-open default: nothing confirmed, so never force.
  const StoreStatus.unknown() : this(isUpdateAvailable: false);

  /// Whether a build satisfying the requirement is actually available to this
  /// user on the store.
  final bool isUpdateAvailable;

  /// Latest version reported by the store, when known.
  final String? latestStoreVersion;
}

/// Verifies that the version we intend to force actually exists and is
/// approved on the store, so we never lock users out of a build they cannot
/// download.
///
/// [minRequired] is the minimum version name (semantic scheme only). Under
/// the buildNumber scheme it is `null`, and implementations fall back to
/// comparing the store's version name against [currentVersion].
///
/// Implementations must fail open (return [StoreStatus.unknown]) on any error.
abstract class StoreAvailabilityChecker {
  Future<StoreStatus> check({
    AppVersion? minRequired,
    AppVersion? currentVersion,
  });

  /// Picks the right implementation for the current platform.
  factory StoreAvailabilityChecker.forPlatform(AppUpdateConfig config) {
    if (Platform.isAndroid) return AndroidStoreAvailabilityChecker();
    if (Platform.isIOS) return IosStoreAvailabilityChecker(config);
    return const UnsupportedStoreAvailabilityChecker();
  }
}

/// Android: rely on Play's In-App Update API, which already accounts for
/// staged rollouts and per-user eligibility.
class AndroidStoreAvailabilityChecker implements StoreAvailabilityChecker {
  @override
  Future<StoreStatus> check({
    AppVersion? minRequired,
    AppVersion? currentVersion,
  }) async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      final available =
          info.updateAvailability == UpdateAvailability.updateAvailable;
      return StoreStatus(isUpdateAvailable: available);
    } catch (e) {
      debugPrint('⚠️ Play update check failed, failing open: $e');
      return const StoreStatus.unknown();
    }
  }
}

/// iOS: query the public iTunes lookup API and compare the live store version
/// against the requirement.
class IosStoreAvailabilityChecker implements StoreAvailabilityChecker {
  IosStoreAvailabilityChecker(this._config, {http.Client? client})
      : _client = client ?? http.Client();

  final AppUpdateConfig _config;
  final http.Client _client;

  @override
  Future<StoreStatus> check({
    AppVersion? minRequired,
    AppVersion? currentVersion,
  }) async {
    try {
      final uri = Uri.parse(
        'https://itunes.apple.com/lookup'
        '?id=${_config.iosAppStoreId}&country=${_config.storeCountry}',
      );
      final response = await _client.get(uri).timeout(_config.fetchTimeout);
      if (response.statusCode != 200) return const StoreStatus.unknown();

      final body = json.decode(response.body) as Map<String, dynamic>;
      final results = (body['results'] as List?) ?? const [];
      if (results.isEmpty) return const StoreStatus.unknown();

      final latestRaw = (results.first as Map)['version']?.toString();
      final latest = AppVersion.tryParse(latestRaw);
      if (latest == null) return const StoreStatus.unknown();

      // Semantic scheme: the live version must satisfy the minimum.
      // BuildNumber scheme (no comparable version name): fall back to
      // "the store serves something newer than the running app".
      final bool available;
      if (minRequired != null) {
        available = latest >= minRequired;
      } else if (currentVersion != null) {
        available = latest > currentVersion;
      } else {
        return const StoreStatus.unknown();
      }

      return StoreStatus(
        isUpdateAvailable: available,
        latestStoreVersion: latestRaw,
      );
    } catch (e) {
      debugPrint('⚠️ iTunes lookup failed, failing open: $e');
      return const StoreStatus.unknown();
    }
  }
}

/// Desktop / web / anything else: never force via the store gate.
class UnsupportedStoreAvailabilityChecker implements StoreAvailabilityChecker {
  const UnsupportedStoreAvailabilityChecker();

  @override
  Future<StoreStatus> check({
    AppVersion? minRequired,
    AppVersion? currentVersion,
  }) async => const StoreStatus.unknown();
}
