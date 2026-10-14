## 0.1.2

- **New**: `UpdateGate.resumeRecheckAfter` re-checks when the app returns to
  the foreground and the last check is older than the given age.
- **New**: `AppUpdateController.checkIfStale(maxAge)` and `lastCheckedAt`;
  optional `clock` parameter for tests.
- **Fix**: a re-check no longer flashes the app behind a forced screen, and
  blocking mode no longer shows the loader again on re-checks — the gate keeps
  the last resolved screen until the new result arrives.
- **Fix**: overlapping triggers (on open, periodic, resume, manual) share one
  in-flight check instead of running several evaluations.

## 0.1.1

- Fix: disposing `AppUpdateController` while a check is in flight no longer
  throws (`ValueNotifier used after being disposed`); the late result is
  dropped silently.

## 0.1.0

Initial release — the source-agnostic core extracted from
`firebase_remote_update`.

- `UpdatePolicySource` abstraction with `HttpUpdatePolicySource`
  (user-defined endpoint, auth headers, body, and JSON mapper) and
  `CallbackUpdatePolicySource`.
- Explicit `VersionScheme` (`semantic` version names or `buildNumber`
  codes) with strict, fail-open validation.
- `AppUpdateController`: on-open / periodic / manual check triggers,
  observable `status`, and `ForcePresentation` (`immediate` or
  `onNextNavigation` via `UpdateGateNavigatorObserver`).
- `UpdateGate` widget with blocking and non-blocking modes.
- Store-availability gate: Play In-App Update on Android, iTunes lookup on
  iOS; always fails open.
