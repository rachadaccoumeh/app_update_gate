import 'dart:async';

import 'package:app_update_gate/src/app_update_config.dart';
import 'package:app_update_gate/src/app_update_controller.dart';
import 'package:app_update_gate/src/app_update_service.dart';
import 'package:app_update_gate/src/update_decision.dart';
import 'package:flutter_test/flutter_test.dart';

/// Evaluation completes only when the test releases [completer].
class _SlowUpdateService implements AppUpdateService {
  _SlowUpdateService(this.completer);

  final Completer<void> completer;

  @override
  AppUpdateConfig get config =>
      const AppUpdateConfig(androidPackageId: '', iosAppStoreId: '');

  @override
  Future<UpdateDecision> evaluate() async {
    await completer.future;
    return const UpdateDecision(requirement: UpdateRequirement.forced);
  }

  @override
  Future<void> startUpdate() async {}
}

void main() {
  test('disposing the controller during an in-flight check does not throw',
      () async {
    final completer = Completer<void>();
    final controller = AppUpdateController(
      service: _SlowUpdateService(completer),
    );

    controller.start();
    controller.dispose();

    // The late result must be dropped silently — no write to the disposed
    // notifier, no exception.
    completer.complete();
    await pumpEventQueue();
  });

  test('notifyNavigation after dispose is a no-op', () async {
    final completer = Completer<void>();
    final controller = AppUpdateController(
      service: _SlowUpdateService(completer),
      forcePresentation: ForcePresentation.onNextNavigation,
    );

    controller.start();
    controller.dispose();
    completer.complete();
    await pumpEventQueue();

    controller.notifyNavigation();
  });
}
