import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_update_service.dart';
import 'update_decision.dart';

/// Lifecycle state of the update check, observable via
/// [AppUpdateController.status].
enum UpdateCheckState {
  /// No check has run yet.
  idle,

  /// A check is in flight.
  checking,

  /// The last check found nothing to do.
  upToDate,

  /// A newer version is recommended (soft prompt — never blocks).
  updateOptional,

  /// The app must update. `UpdateGate` reacts to this state.
  updateForced,
}

/// Immutable snapshot published by [AppUpdateController.status].
class UpdateStatus {
  const UpdateStatus(this.state, [this.decision]);

  static const idle = UpdateStatus(UpdateCheckState.idle);

  final UpdateCheckState state;

  /// The decision behind [state], when a check has completed.
  final UpdateDecision? decision;
}

/// How a forced result is surfaced to the UI.
enum ForcePresentation {
  /// Publish the forced state the moment the check resolves.
  immediate,

  /// Hold the forced state until the next route change (attach an
  /// `UpdateGateNavigatorObserver`), so users are not interrupted mid-task.
  onNextNavigation,
}

/// Owns when update checks run and exposes their result as an observable
/// [status].
///
/// Triggers:
/// - on open: one check when [start] is called (default; disable with
///   `checkOnStart: false`),
/// - periodic: every [recheckInterval] when set (`null` = never re-check),
/// - manual: [checkForUpdate] at any time.
///
/// The controller is passive until [start] is called (`UpdateGate` calls it
/// on mount). Dispose it to cancel the periodic timer.
class AppUpdateController {
  AppUpdateController({
    required AppUpdateService service,
    this.checkOnStart = true,
    this.recheckInterval,
    this.forcePresentation = ForcePresentation.immediate,
  }) : _service = service;

  final AppUpdateService _service;

  /// Whether [start] runs an immediate check.
  final bool checkOnStart;

  /// Background re-check period. `null` disables periodic checks.
  final Duration? recheckInterval;

  /// How a forced result reaches the UI.
  final ForcePresentation forcePresentation;

  final _status = ValueNotifier<UpdateStatus>(UpdateStatus.idle);
  Timer? _timer;
  bool _started = false;
  bool _disposed = false;
  UpdateDecision? _pendingForced;

  /// Observable check status. Listen (or hand the controller to `UpdateGate`)
  /// to react to update results wherever they were triggered from.
  ValueListenable<UpdateStatus> get status => _status;

  /// Starts the configured triggers. Idempotent — `UpdateGate` calls this on
  /// mount, and calling it again is a no-op.
  void start() {
    if (_started) return;
    _started = true;
    if (checkOnStart) unawaited(_check());
    final interval = recheckInterval;
    if (interval != null) {
      _timer = Timer.periodic(interval, (_) => unawaited(_check()));
    }
  }

  /// Runs one check now and returns the raw decision (also published to
  /// [status], honoring [forcePresentation]).
  Future<UpdateDecision> checkForUpdate() => _check();

  /// Releases a held forced result (see [ForcePresentation.onNextNavigation]).
  /// Called by `UpdateGateNavigatorObserver` on route changes.
  void notifyNavigation() {
    if (_disposed) return;
    final pending = _pendingForced;
    if (pending == null) return;
    _pendingForced = null;
    _status.value = UpdateStatus(UpdateCheckState.updateForced, pending);
  }

  /// Starts the platform update flow (delegates to the service).
  Future<void> startUpdate() => _service.startUpdate();

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _status.dispose();
  }

  Future<UpdateDecision> _check() async {
    if (!_disposed) {
      _status.value = UpdateStatus(
        UpdateCheckState.checking,
        _status.value.decision,
      );
    }
    final decision = await _service.evaluate();
    _publish(decision);
    return decision;
  }

  void _publish(UpdateDecision decision) {
    // A check may resolve after the owning widget is gone — drop it silently.
    if (_disposed) return;
    switch (decision.requirement) {
      case UpdateRequirement.forced:
        if (forcePresentation == ForcePresentation.onNextNavigation) {
          // Hold it: the app keeps running until the next route change.
          _pendingForced = decision;
          _status.value = UpdateStatus(UpdateCheckState.upToDate, decision);
        } else {
          _status.value = UpdateStatus(
            UpdateCheckState.updateForced,
            decision,
          );
        }
      case UpdateRequirement.optional:
        _status.value = UpdateStatus(UpdateCheckState.updateOptional, decision);
      case UpdateRequirement.none:
        _status.value = UpdateStatus(UpdateCheckState.upToDate, decision);
    }
  }
}
