# app_update_gate

A source-agnostic **force / optional update gate** for Flutter.

Bring your own update policy source — a REST API, Firebase Remote Config (via
the [`firebase_remote_update`](https://pub.dev/packages/firebase_remote_update)
adapter), or any custom backend. Forced updates are guarded by a **real
store-availability check** (Play In-App Update on Android, iTunes lookup on
iOS), so users are never locked out of a build that is not actually live.

## Features

- **Any policy source**: built-in HTTP source with your own endpoint, auth,
  and JSON mapping — or implement one method for anything else.
- **Fail open everywhere**: network errors, bad config, or an unreachable
  backend never block your users.
- **Store-availability gate**: never force an update the user cannot install.
- **Version name or build code**: compare against `1.4.0`-style version names
  or `140`-style build numbers — your choice, explicit and validated.
- **Flexible triggers**: check on app open, on a background interval, or
  manually — and present a forced update immediately or on the next
  navigation.
- **Observable status**: react to results anywhere in your UI.

## Quick start

```dart
final service = AppUpdateService(
  config: const AppUpdateConfig(
    androidPackageId: 'com.example.myapp',
    iosAppStoreId: '1234567890',
    versionScheme: VersionScheme.semantic, // see "Pick ONE version scheme"
  ),
  source: HttpUpdatePolicySource(
    uri: Uri.parse('https://api.example.com/app-version'),
    headersBuilder: () async => {
      'Authorization': 'Bearer ${await authRepo.token()}',
    },
    mapper: (json) {
      // One endpoint usually serves both platforms — pick your branch here.
      final p = Platform.isAndroid ? json['android'] : json['ios'];
      return UpdatePolicy(
        minRequiredVersion: p['min_version'] as String?,
        recommendedVersion: p['recommended_version'] as String?,
        message: (json['message'] as String?) ?? '',
      );
    },
  ),
);

final controller = AppUpdateController(
  service: service,
  checkOnStart: true,                        // one check on app open (default)
  recheckInterval: const Duration(hours: 6), // optional background re-checks
  forcePresentation: ForcePresentation.immediate,
);

runApp(
  UpdateGate(
    controller: controller,
    forcedBuilder: (context, decision) => ForcedUpdateScreen(
      message: decision.message,
      onUpdate: controller.startUpdate,
    ),
    child: MaterialApp(home: HomeScreen()),
  ),
);
```

That is all: the gate starts the controller on mount, and blocks the app with
`forcedBuilder` when a forced update is required.

## ⚠️ Pick ONE version scheme

The **version name** (`1.4.0`) and the **version/build code** (`140`,
`14000`) are two unrelated number lines. Mixing them silently would compare
apples to oranges, so the scheme is explicit and applies to **all** policy
values:

| `versionScheme` | Policy values look like | Compared against |
|---|---|---|
| `VersionScheme.semantic` (default) | `1.4.0`, `1.2` (= `1.2.0`) | the app version name |
| `VersionScheme.buildNumber` | `140`, `14000` | the app build number |

Use the same scheme on your backend and in your release process. A value that
does not fit the scheme (a bare `140` under `semantic`, a dotted `1.4.0`
under `buildNumber`) is **rejected with a warning and fails open** — a config
mistake can never force-block your users.

## Triggers and presentation

**When checks run** (`AppUpdateController`):

- `checkOnStart: true` — one check when the gate mounts (default).
- `recheckInterval: Duration(...)` — periodic background re-checks
  (`null` = never).
- `controller.checkForUpdate()` — manual one-time check, returns the
  `UpdateDecision`.
- `UpdateGate(resumeRecheckAfter: Duration(...))` — re-check when the app
  returns to the foreground and the last check is older than this
  (`controller.checkIfStale(maxAge)` does the same by hand).

Overlapping triggers share one check, and a re-check never changes the screen
until it resolves: a forced screen stays up, and the blocking loader shows
only before the first result.

**How a forced result is shown** (`forcePresentation`):

- `ForcePresentation.immediate` — the forced screen appears the moment the
  check resolves.
- `ForcePresentation.onNextNavigation` — the result is held until the next
  route change, so users are not interrupted mid-task. Attach the observer:

```dart
MaterialApp(
  navigatorObservers: [UpdateGateNavigatorObserver(controller)],
  ...
)
```

## Optional (recommended) updates

Optional updates never block. Consume them either way:

```dart
// 1. Observe — react wherever you render a banner/badge:
ValueListenableBuilder(
  valueListenable: controller.status,
  builder: (context, status, _) {
    if (status.state == UpdateCheckState.updateOptional) {
      return UpdateBanner(message: status.decision!.message);
    }
    return const SizedBox.shrink();
  },
);

// 2. Or one manual call:
final decision = await controller.checkForUpdate();
if (decision.isOptional) showUpdateDialog(decision);
```

When and where to show the prompt is your app's responsibility.

## Custom policy sources

Any backend fits in one method:

```dart
final source = CallbackUpdatePolicySource(() async {
  final doc = await myGraphQlClient.query(...);
  return UpdatePolicy(minRequiredVersion: doc.minVersion);
});
```

Or implement `UpdatePolicySource` directly. Throw on failure — the service
catches everything and fails open.

## The store-availability gate

Before forcing, the package verifies the update is actually installable:

- **Android**: Play In-App Update API (accounts for staged rollouts and
  per-user eligibility). `startUpdate()` runs an immediate in-app update,
  falling back to the Play Store page.
- **iOS**: iTunes lookup API. `startUpdate()` opens the App Store page.
- **Other platforms**: never forced.

For genuine emergencies only, `UpdatePolicy(ignoreStoreCheck: true)` skips
the gate — it can leave users with no installable build, so use with care.

## Using Firebase Remote Config?

Use [`firebase_remote_update`](https://pub.dev/packages/firebase_remote_update),
which supplies a Remote Config policy source on top of this core.

## License

MIT
