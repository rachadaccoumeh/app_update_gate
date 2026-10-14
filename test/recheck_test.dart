import 'dart:async';

import 'package:app_update_gate/src/app_update_config.dart';
import 'package:app_update_gate/src/app_update_controller.dart';
import 'package:app_update_gate/src/app_update_service.dart';
import 'package:app_update_gate/src/update_decision.dart';
import 'package:app_update_gate/src/update_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Each evaluation waits on its own completer, so a test decides when (and
/// with what) every check resolves.
class _ManualService implements AppUpdateService {
  final calls = <Completer<UpdateDecision>>[];

  @override
  AppUpdateConfig get config =>
      const AppUpdateConfig(androidPackageId: '', iosAppStoreId: '');

  @override
  Future<UpdateDecision> evaluate() {
    final call = Completer<UpdateDecision>();
    calls.add(call);
    return call.future;
  }

  @override
  Future<void> startUpdate() async {}
}

const _forced = UpdateDecision(requirement: UpdateRequirement.forced);
const _none = UpdateDecision.none();

void main() {
  group('AppUpdateController', () {
    test('overlapping checks share one evaluation', () async {
      final service = _ManualService();
      final controller = AppUpdateController(service: service);

      final first = controller.checkForUpdate();
      final second = controller.checkForUpdate();
      expect(service.calls, hasLength(1));

      service.calls.single.complete(_forced);
      expect(await first, _forced);
      expect(await second, _forced);
      controller.dispose();
    });

    test(
      'checkIfStale skips a fresh result and re-checks an old one',
      () async {
        var now = DateTime(2026, 1, 1, 12);
        final service = _ManualService();
        final controller = AppUpdateController(
          service: service,
          clock: () => now,
        );

        final first = controller.checkIfStale(const Duration(minutes: 5));
        service.calls.single.complete(_none);
        expect(await first, _none);
        expect(controller.lastCheckedAt, now);

        now = now.add(const Duration(minutes: 4));
        expect(
          await controller.checkIfStale(const Duration(minutes: 5)),
          isNull,
        );
        expect(service.calls, hasLength(1));

        now = now.add(const Duration(minutes: 2));
        final stale = controller.checkIfStale(const Duration(minutes: 5));
        expect(service.calls, hasLength(2));
        service.calls.last.complete(_forced);
        expect(await stale, _forced);
        controller.dispose();
      },
    );
  });

  group('UpdateGate re-checks', () {
    Widget gate(
      AppUpdateController controller, {
      UpdateGateMode mode = UpdateGateMode.nonBlocking,
    }) => MaterialApp(
      home: UpdateGate(
        controller: controller,
        mode: mode,
        resumeRecheckAfter: Duration.zero,
        forcedBuilder: (_, _) => const Text('forced'),
        loadingBuilder: (_) => const Text('loading'),
        child: const Text('app'),
      ),
    );

    testWidgets('the forced screen stays up while a re-check runs', (
      tester,
    ) async {
      final service = _ManualService();
      final controller = AppUpdateController(service: service);
      addTearDown(controller.dispose);
      await tester.pumpWidget(gate(controller));
      service.calls.single.complete(_forced);
      await tester.pump();
      expect(find.text('forced'), findsOneWidget);

      unawaited(controller.checkForUpdate());
      await tester.pump();
      expect(
        find.text('forced'),
        findsOneWidget,
        reason: 'no flash of the app during the re-check',
      );

      service.calls.last.complete(_none);
      await tester.pump();
      await tester.pump();
      expect(
        find.text('app'),
        findsOneWidget,
        reason: 'a lifted force shows the app again',
      );
    });

    testWidgets('blocking mode shows the loader only before the first result', (
      tester,
    ) async {
      final service = _ManualService();
      final controller = AppUpdateController(service: service);
      addTearDown(controller.dispose);
      await tester.pumpWidget(gate(controller, mode: UpdateGateMode.blocking));
      expect(find.text('loading'), findsOneWidget);
      service.calls.single.complete(_none);
      await tester.pump();

      unawaited(controller.checkForUpdate());
      await tester.pump();
      expect(find.text('app'), findsOneWidget);
      service.calls.last.complete(_none);
      await tester.pump();
      await tester.pump();
    });

    testWidgets('returning to the foreground re-checks', (tester) async {
      final service = _ManualService();
      final controller = AppUpdateController(service: service);
      addTearDown(controller.dispose);
      await tester.pumpWidget(gate(controller));
      service.calls.single.complete(_none);
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(service.calls, hasLength(2));
      service.calls.last.complete(_forced);
      await tester.pump();
      await tester.pump();
      expect(find.text('forced'), findsOneWidget);
    });
  });
}
