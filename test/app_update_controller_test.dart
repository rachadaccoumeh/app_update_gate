import 'package:app_update_gate/src/app_update_config.dart';
import 'package:app_update_gate/src/app_update_controller.dart';
import 'package:app_update_gate/src/app_update_service.dart';
import 'package:app_update_gate/src/update_decision.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// A controllable [AppUpdateService] stand-in that counts evaluations.
class _FakeUpdateService implements AppUpdateService {
  _FakeUpdateService(this.decision);

  UpdateDecision decision;
  int evaluateCalls = 0;
  int startUpdateCalls = 0;

  @override
  AppUpdateConfig get config =>
      const AppUpdateConfig(androidPackageId: '', iosAppStoreId: '');

  @override
  Future<UpdateDecision> evaluate() async {
    evaluateCalls++;
    return decision;
  }

  @override
  Future<void> startUpdate() async {
    startUpdateCalls++;
  }
}

const _forced = UpdateDecision(
  requirement: UpdateRequirement.forced,
  message: 'Update now',
);
const _optional = UpdateDecision(requirement: UpdateRequirement.optional);

void main() {
  group('AppUpdateController.start', () {
    test('runs the on-open check and publishes the forced state', () async {
      final service = _FakeUpdateService(_forced);
      final controller = AppUpdateController(service: service);

      controller.start();
      await pumpEventQueue();

      expect(service.evaluateCalls, 1);
      expect(controller.status.value.state, UpdateCheckState.updateForced);
      expect(controller.status.value.decision, _forced);
      controller.dispose();
    });

    test('is idempotent — a second start does not re-check', () async {
      final service = _FakeUpdateService(_forced);
      final controller = AppUpdateController(service: service);

      controller.start();
      controller.start();
      await pumpEventQueue();

      expect(service.evaluateCalls, 1);
      controller.dispose();
    });

    test('does not check when checkOnStart is false', () async {
      final service = _FakeUpdateService(_forced);
      final controller = AppUpdateController(
        service: service,
        checkOnStart: false,
      );

      controller.start();
      await pumpEventQueue();

      expect(service.evaluateCalls, 0);
      expect(controller.status.value.state, UpdateCheckState.idle);
      controller.dispose();
    });

    test('re-checks on the recheck interval', () {
      fakeAsync((fake) {
        final service = _FakeUpdateService(const UpdateDecision.none());
        final controller = AppUpdateController(
          service: service,
          recheckInterval: const Duration(hours: 6),
        );

        controller.start();
        fake.flushMicrotasks();
        expect(service.evaluateCalls, 1);

        fake.elapse(const Duration(hours: 6));
        fake.flushMicrotasks();
        expect(service.evaluateCalls, 2);

        controller.dispose();
        fake.elapse(const Duration(hours: 6));
        fake.flushMicrotasks();
        expect(service.evaluateCalls, 2, reason: 'dispose cancels the timer');
      });
    });
  });

  group('AppUpdateController.checkForUpdate (manual, one-time)', () {
    test('returns the decision and publishes the matching state', () async {
      final service = _FakeUpdateService(_optional);
      final controller = AppUpdateController(
        service: service,
        checkOnStart: false,
      );

      final decision = await controller.checkForUpdate();

      expect(decision, _optional);
      expect(controller.status.value.state, UpdateCheckState.updateOptional);
      controller.dispose();
    });

    test('publishes upToDate when no update applies', () async {
      final service = _FakeUpdateService(const UpdateDecision.none());
      final controller = AppUpdateController(
        service: service,
        checkOnStart: false,
      );

      await controller.checkForUpdate();

      expect(controller.status.value.state, UpdateCheckState.upToDate);
      controller.dispose();
    });
  });

  group('ForcePresentation.onNextNavigation', () {
    test('holds the forced state until a navigation happens', () async {
      final service = _FakeUpdateService(_forced);
      final controller = AppUpdateController(
        service: service,
        forcePresentation: ForcePresentation.onNextNavigation,
      );

      controller.start();
      await pumpEventQueue();

      // Forced result is held — the app keeps running.
      expect(
        controller.status.value.state,
        isNot(UpdateCheckState.updateForced),
      );

      controller.notifyNavigation();

      expect(controller.status.value.state, UpdateCheckState.updateForced);
      expect(controller.status.value.decision, _forced);
      controller.dispose();
    });

    test('navigation without a pending forced result is a no-op', () async {
      final service = _FakeUpdateService(const UpdateDecision.none());
      final controller = AppUpdateController(
        service: service,
        forcePresentation: ForcePresentation.onNextNavigation,
      );

      controller.start();
      await pumpEventQueue();
      controller.notifyNavigation();

      expect(controller.status.value.state, UpdateCheckState.upToDate);
      controller.dispose();
    });
  });

  group('AppUpdateController.startUpdate', () {
    test('delegates to the service', () async {
      final service = _FakeUpdateService(const UpdateDecision.none());
      final controller = AppUpdateController(
        service: service,
        checkOnStart: false,
      );

      await controller.startUpdate();

      expect(service.startUpdateCalls, 1);
      controller.dispose();
    });
  });
}
