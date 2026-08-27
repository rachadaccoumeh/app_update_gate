import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_update_config.dart';
import 'app_version.dart';
import 'store_availability_checker.dart';
import 'update_decision.dart';
import 'update_policy.dart';
import 'version_scheme.dart';

/// Decides whether the running app must update, backed by any
/// [UpdatePolicySource] and guarded by a real store-availability check.
///
/// Depends only on injected abstractions ([AppUpdateConfig],
/// [UpdatePolicySource], [StoreAvailabilityChecker]), so it is easy to unit
/// test and to reuse across apps by supplying a different config/source.
class AppUpdateService {
  AppUpdateService({
    required AppUpdateConfig config,
    required UpdatePolicySource source,
    StoreAvailabilityChecker? storeChecker,
  }) : _config = config,
       _source = source,
       _storeChecker =
           storeChecker ?? StoreAvailabilityChecker.forPlatform(config);

  final AppUpdateConfig _config;
  final UpdatePolicySource _source;
  final StoreAvailabilityChecker _storeChecker;

  AppUpdateConfig get config => _config;

  /// Evaluates the update policy for the running version.
  ///
  /// Always fails open (returns [UpdateRequirement.none]) on any error, so a
  /// misconfiguration or flaky network can never lock users out.
  Future<UpdateDecision> evaluate() async {
    try {
      final policy = await _source.fetchPolicy();
      final info = await PackageInfo.fromPlatform();
      final scheme = _config.versionScheme;

      final current = PolicyVersion.current(
        versionName: info.version,
        buildNumber: info.buildNumber,
        scheme: scheme,
      );
      if (current == null) return const UpdateDecision.none();

      final minRequired = PolicyVersion.tryParse(
        policy.minRequiredVersion,
        scheme,
      );
      final recommended = PolicyVersion.tryParse(
        policy.recommendedVersion,
        scheme,
      );

      final belowMinimum = minRequired != null && current < minRequired;

      if (policy.forceUpdateEnabled && belowMinimum) {
        final forced = await _resolveForced(policy, minRequired, info);
        // When the store gate fails open, `forced` is null and we fall through
        // to a soft prompt instead of blocking the user.
        if (forced != null) return forced;
      }

      if (recommended != null && current < recommended) {
        return UpdateDecision(
          requirement: UpdateRequirement.optional,
          message: policy.message,
        );
      }
      return const UpdateDecision.none();
    } catch (e) {
      debugPrint('⚠️ Update evaluation failed, allowing app to continue: $e');
      return const UpdateDecision.none();
    }
  }

  /// Starts the update: an immediate in-app update on Android (falling back to
  /// the store page), or the App Store page on iOS.
  Future<void> startUpdate() async {
    if (Platform.isAndroid) {
      try {
        final info = await InAppUpdate.checkForUpdate();
        if (info.updateAvailability == UpdateAvailability.updateAvailable) {
          await InAppUpdate.performImmediateUpdate();
          return;
        }
      } catch (e) {
        debugPrint('⚠️ In-app update failed, opening store page: $e');
      }
    }
    await _openStorePage();
  }

  // --- internals -----------------------------------------------------------

  Future<UpdateDecision?> _resolveForced(
    UpdatePolicy policy,
    PolicyVersion minRequired,
    PackageInfo info,
  ) async {
    // Emergency override: skip the store gate and force regardless.
    if (policy.ignoreStoreCheck) {
      return UpdateDecision(
        requirement: UpdateRequirement.forced,
        message: policy.message,
      );
    }

    // Under the buildNumber scheme there is no comparable version name for
    // the store, so the checker falls back to comparing against the running
    // app's version name.
    final status = await _storeChecker.check(
      minRequired: minRequired.semanticVersion,
      currentVersion: AppVersion.tryParse(info.version),
    );
    if (status.isUpdateAvailable) {
      return UpdateDecision(
        requirement: UpdateRequirement.forced,
        message: policy.message,
        latestStoreVersion: status.latestStoreVersion,
      );
    }
    return null;
  }

  Future<void> _openStorePage() async {
    final url = Platform.isIOS ? _config.iosStoreUrl : _config.androidStoreUrl;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('❌ Could not launch store URL: $url');
    }
  }
}
