import 'version_scheme.dart';

/// Everything project-specific for the update module.
///
/// Supplying a different instance is all that is required to reuse the module
/// in another app — no code changes.
class AppUpdateConfig {
  const AppUpdateConfig({
    required this.androidPackageId,
    required this.iosAppStoreId,
    this.storeCountry = 'us',
    this.fetchTimeout = const Duration(seconds: 8),
    this.versionScheme = VersionScheme.semantic,
  });

  /// Android application id, e.g. `com.example.myapp`.
  final String androidPackageId;

  /// Numeric App Store id (without the leading `id`), e.g. `1234567890`.
  final String iosAppStoreId;

  /// Storefront/country code used for the App Store URL and iTunes lookup.
  final String storeCountry;

  /// Max time to wait for the iTunes lookup.
  final Duration fetchTimeout;

  /// The scheme ALL policy values are resolved under. Pick one and use it on
  /// both your backend and your store metadata — the version name (`1.4.0`)
  /// and the build code (`140`) are two unrelated number lines.
  final VersionScheme versionScheme;

  String get androidStoreUrl =>
      'https://play.google.com/store/apps/details?id=$androidPackageId';

  String get iosStoreUrl =>
      'https://apps.apple.com/$storeCountry/app/id$iosAppStoreId';
}
