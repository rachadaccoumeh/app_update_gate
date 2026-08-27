import 'package:flutter/foundation.dart';

import 'app_version.dart';

/// Which app identifier the policy values are compared against.
///
/// One scheme applies to ALL values of a policy source (min, recommended).
/// Never mix schemes: the version name (`1.4.0`) and the build code (`140`,
/// `14000`) are two unrelated number lines.
enum VersionScheme {
  /// Values are dotted version names (`1.4.0`, `1.2` == `1.2.0`), compared
  /// against the app's version name.
  semantic,

  /// Values are pure integers (`140`, `14000`), compared against the app's
  /// build number.
  buildNumber,
}

/// A policy version value resolved under a [VersionScheme].
///
/// Parsing is strict per scheme and fails open (returns `null`) on any value
/// that does not fit the scheme, so a config mistake can never force-block
/// users. Instances are only comparable within the same scheme.
class PolicyVersion implements Comparable<PolicyVersion> {
  const PolicyVersion._(this.scheme, this._semantic, this._build);

  final VersionScheme scheme;
  final AppVersion? _semantic;
  final int? _build;

  /// Requires a dotted core somewhere in the string (`1.2`, `v1.4.9 (149)`).
  static final RegExp _hasDottedCore = RegExp(r'\d+\.\d+');

  /// Pure integer, nothing else.
  static final RegExp _pureInteger = RegExp(r'^\d+$');

  /// Parses [raw] under [scheme]. Returns `null` (fail open) when the value
  /// does not fit the scheme, logging a warning for config mistakes.
  static PolicyVersion? tryParse(String? raw, VersionScheme scheme) {
    if (raw == null) return null;
    final input = raw.trim();
    if (input.isEmpty) return null;

    switch (scheme) {
      case VersionScheme.semantic:
        if (!_hasDottedCore.hasMatch(input)) {
          _warnMismatch(input, scheme);
          return null;
        }
        final version = AppVersion.tryParse(input);
        if (version == null) return null;
        return PolicyVersion._(scheme, version, null);

      case VersionScheme.buildNumber:
        if (!_pureInteger.hasMatch(input)) {
          _warnMismatch(input, scheme);
          return null;
        }
        return PolicyVersion._(scheme, null, int.parse(input));
    }
  }

  /// Resolves the running app's version under [scheme]: the version name for
  /// [VersionScheme.semantic], the build number for
  /// [VersionScheme.buildNumber].
  static PolicyVersion? current({
    required String versionName,
    required String buildNumber,
    required VersionScheme scheme,
  }) {
    final raw = switch (scheme) {
      VersionScheme.semantic => versionName,
      VersionScheme.buildNumber => buildNumber,
    };
    return tryParse(raw, scheme);
  }

  static void _warnMismatch(String input, VersionScheme scheme) {
    debugPrint(
      '⚠️ app_update_gate: "$input" does not fit VersionScheme.${scheme.name} '
      '(semantic needs a dotted version, buildNumber a pure integer). '
      'Ignoring it (fail open).',
    );
  }

  @override
  int compareTo(PolicyVersion other) {
    assert(scheme == other.scheme, 'Cannot compare across version schemes');
    return switch (scheme) {
      VersionScheme.semantic => _semantic!.compareTo(other._semantic!),
      VersionScheme.buildNumber => _build!.compareTo(other._build!),
    };
  }

  bool operator <(PolicyVersion other) => compareTo(other) < 0;
  bool operator >(PolicyVersion other) => compareTo(other) > 0;
  bool operator <=(PolicyVersion other) => compareTo(other) <= 0;
  bool operator >=(PolicyVersion other) => compareTo(other) >= 0;

  /// The semantic value when [scheme] is [VersionScheme.semantic].
  AppVersion? get semanticVersion => _semantic;

  @override
  String toString() => switch (scheme) {
    VersionScheme.semantic => _semantic.toString(),
    VersionScheme.buildNumber => _build.toString(),
  };
}
