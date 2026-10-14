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
/// - manual: [checkForUpdate] at any time, or [checkIfStale] (e.g. when the
///   app returns to the foreground).
///
/// Overlapping triggers share one check: a check requested while another is
/// in flight returns the in-flight result instead of starting a second one.
///
/// The controller is passive until [start] is called (`UpdateGate` calls it
/// on mount). Dispose it to cancel the periodic timer.
class AppUpdateController {
  AppUpdateController({
    required AppUpdateService service,
    this.checkOnStart = true,
    this.recheckInterval,
    this.forcePresentation = ForcePresentation.immediate,
    DateTime Function()? clock,
  }) : _service = service,
       _clock = clock ?? DateTime.now;

  final AppUpdateService _service;

  /// Whether [start] runs an immediate check.
  final bool checkOnStart;

  /// Background re-check period. `null` disables periodic checks.
  final Duration? recheckInterval;

  /// How a forced result reaches the UI.
  final ForcePresentation forcePresentation;

  final DateTime Function() _clock;
  final _status = ValueNotifier<UpdateStatus>(UpdateStatus.idle);
  Timer? _timer;
  Future<UpdateDecision>? _inFlight;
  DateTime? _lastCheckedAt;
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

  /// When the last check completed, or null before the first one.
  DateTime? get lastCheckedAt => _lastCheckedAt;

  /// Runs a check only when none completed in the last [maxAge] (and none is
  /// in flight). Returns the new decision, or null when the last one is fresh.
  Future<UpdateDecision?> checkIfStale(Duration maxAge) async {
    final last = _lastCheckedAt;
    if (_inFlight == null &&
        last != null &&
        _clock().difference(last) < maxAge) {
      return null;
    }
    return _check();
  }

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

  Future<UpdateDecision> _check() =>
      _inFlight ??= _runCheck().whenComplete(() => _inFlight = null);

  Future<UpdateDecision> _runCheck() async {
    if (!_disposed) {
      _status.value = UpdateStatus(
        UpdateCheckState.checking,
        _status.value.decision,
      );
    }
    final decision = await _service.evaluate();
    _lastCheckedAt = _clock();
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
          _status.value = UpdateStatus(UpdateCheckState.updateForced, decision);
        }
      case UpdateRequirement.optional:
        _status.value = UpdateStatus(UpdateCheckState.updateOptional, decision);
      case UpdateRequirement.none:
        _status.value = UpdateStatus(UpdateCheckState.upToDate, decision);
    }
  }
}
