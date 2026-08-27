/// What the update policy wants the app to do for the running version.
enum UpdateRequirement {
  /// No action needed.
  none,

  /// A newer version is recommended, but the app may continue (soft prompt).
  optional,

  /// The app must update before it can be used (blocking).
  forced,
}

/// Immutable result of evaluating the update policy.
class UpdateDecision {
  const UpdateDecision({
    required this.requirement,
    this.message = '',
    this.latestStoreVersion,
  });

  const UpdateDecision.none() : this(requirement: UpdateRequirement.none);

  final UpdateRequirement requirement;

  /// Optional human-readable message sourced from the update policy.
  final String message;

  /// Latest version reported by the store, when known (iOS lookup only today).
  final String? latestStoreVersion;

  bool get isForced => requirement == UpdateRequirement.forced;
  bool get isOptional => requirement == UpdateRequirement.optional;
  bool get isNone => requirement == UpdateRequirement.none;
}
