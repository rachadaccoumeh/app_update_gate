/// The update policy for the running platform, as served by the backend.
///
/// Values are raw strings; they are resolved under the configured
/// `VersionScheme` at evaluation time. Keep the policy single-platform: when
/// one endpoint serves both platforms, the source's mapper picks the branch
/// for the current platform.
class UpdatePolicy {
  const UpdatePolicy({
    this.forceUpdateEnabled = true,
    this.minRequiredVersion,
    this.recommendedVersion,
    this.ignoreStoreCheck = false,
    this.message = '',
  });

  /// Kill switch. When `false`, no forced update is ever shown.
  final bool forceUpdateEnabled;

  /// Version below which the app is forced to update.
  final String? minRequiredVersion;

  /// Version below which a non-blocking "update available" prompt applies.
  final String? recommendedVersion;

  /// Emergency override: force even if the target build is not yet visible on
  /// the store. Use only for genuine emergencies (security/data-integrity),
  /// since it can leave users with no installable build.
  final bool ignoreStoreCheck;

  /// Optional message to display on the update screen.
  final String message;
}

/// Where the update policy comes from (REST API, Remote Config, anything).
///
/// Implementations may throw on failure; the service catches everything and
/// fails open, so an unreachable backend can never lock users out.
abstract class UpdatePolicySource {
  Future<UpdatePolicy> fetchPolicy();
}

/// Adapts a plain callback into an [UpdatePolicySource], for backends that do
/// not fit the HTTP source (GraphQL, gRPC, local overrides, ...).
class CallbackUpdatePolicySource implements UpdatePolicySource {
  CallbackUpdatePolicySource(this._fetch);

  final Future<UpdatePolicy> Function() _fetch;

  @override
  Future<UpdatePolicy> fetchPolicy() => _fetch();
}
