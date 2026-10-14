import 'package:flutter/material.dart';

import 'app_update_controller.dart';
import 'update_decision.dart';

/// Controls how [UpdateGate] behaves while the first update check runs.
enum UpdateGateMode {
  /// The app renders immediately and checks run in the background. When the
  /// controller publishes a forced state, the gate swaps to
  /// [UpdateGate.forcedBuilder].
  ///
  /// Use this when you want the user to see the app as fast as possible.
  nonBlocking,

  /// The app is hidden behind [UpdateGate.loadingBuilder] until the on-open
  /// check completes, then either [UpdateGate.child] or
  /// [UpdateGate.forcedBuilder] is shown.
  ///
  /// Use this when you need the decision before any UI is visible (e.g. to
  /// avoid a flash of the main screen before a forced update).
  blocking,
}

/// Wraps the app root and blocks it with [forcedBuilder] when the controller
/// publishes a forced update — whichever trigger produced it (on open,
/// periodic re-check, or a manual `checkForUpdate`).
///
/// The gate calls [AppUpdateController.start] on mount, so attaching the gate
/// is all that is needed to run the configured triggers. Optional updates
/// never block: observe [AppUpdateController.status] or use [onDecision] for
/// a soft prompt.
///
/// A re-check never changes the screen until it resolves: a forced screen
/// stays up and the blocking loader shows only before the first result.
class UpdateGate extends StatefulWidget {
  const UpdateGate({
    super.key,
    required this.controller,
    required this.child,
    required this.forcedBuilder,
    this.mode = UpdateGateMode.nonBlocking,
    this.loadingBuilder,
    this.onDecision,
    this.resumeRecheckAfter,
  });

  final AppUpdateController controller;

  /// The app to show when no forced update is required.
  final Widget child;

  /// Blocking screen shown when a forced update is required.
  final Widget Function(BuildContext context, UpdateDecision decision)
  forcedBuilder;

  /// How the gate behaves while the on-open check runs.
  ///
  /// Defaults to [UpdateGateMode.nonBlocking].
  final UpdateGateMode mode;

  /// Shown while the on-open check runs in [UpdateGateMode.blocking] mode.
  /// Ignored in [UpdateGateMode.nonBlocking] mode.
  ///
  /// Defaults to a centered spinner.
  final WidgetBuilder? loadingBuilder;

  /// Called with every resolved decision (useful for optional prompts,
  /// analytics, etc.).
  final void Function(UpdateDecision decision)? onDecision;

  /// Re-check when the app returns to the foreground and the last check is
  /// older than this (see [AppUpdateController.checkIfStale]). `null` = no
  /// foreground re-check.
  final Duration? resumeRecheckAfter;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> with WidgetsBindingObserver {
  UpdateDecision? _lastReported;

  /// The last non-`checking` status: what the gate shows while a re-check runs.
  UpdateStatus? _settled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.status.addListener(_onStatus);
    widget.controller.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final maxAge = widget.resumeRecheckAfter;
    if (state == AppLifecycleState.resumed && maxAge != null) {
      widget.controller.checkIfStale(maxAge);
    }
  }

  @override
  void didUpdateWidget(UpdateGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.status.removeListener(_onStatus);
      _settled = null;
      widget.controller.status.addListener(_onStatus);
      widget.controller.start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.status.removeListener(_onStatus);
    super.dispose();
  }

  void _onStatus() {
    final status = widget.controller.status.value;
    if (status.state != UpdateCheckState.checking) _settled = status;
    final decision = status.decision;
    if (decision != null && !identical(decision, _lastReported)) {
      _lastReported = decision;
      widget.onDecision?.call(decision);
    }
    if (mounted) setState(() {});
  }

  bool get _waitingForFirstCheck {
    if (_settled != null) return false;
    final state = widget.controller.status.value.state;
    return state == UpdateCheckState.checking ||
        (state == UpdateCheckState.idle && widget.controller.checkOnStart);
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.controller.status.value;
    final status = current.state == UpdateCheckState.checking
        ? (_settled ?? current)
        : current;

    if (status.state == UpdateCheckState.updateForced) {
      return widget.forcedBuilder(context, status.decision!);
    }

    if (widget.mode == UpdateGateMode.blocking && _waitingForFirstCheck) {
      return widget.loadingBuilder?.call(context) ?? const _Loading();
    }

    return widget.child;
  }
}

/// Releases a held forced update on route changes.
///
/// Attach to `MaterialApp.navigatorObservers` when the controller uses
/// [ForcePresentation.onNextNavigation]:
///
/// ```dart
/// MaterialApp(
///   navigatorObservers: [UpdateGateNavigatorObserver(controller)],
///   ...
/// )
/// ```
class UpdateGateNavigatorObserver extends NavigatorObserver {
  UpdateGateNavigatorObserver(this.controller);

  final AppUpdateController controller;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      controller.notifyNavigation();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      controller.notifyNavigation();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      controller.notifyNavigation();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      controller.notifyNavigation();
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
