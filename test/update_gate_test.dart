import 'dart:async';

import 'package:app_update_gate/src/app_update_config.dart';
import 'package:app_update_gate/src/app_update_controller.dart';
import 'package:app_update_gate/src/app_update_service.dart';
import 'package:app_update_gate/src/update_decision.dart';
import 'package:app_update_gate/src/update_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A controllable [AppUpdateService] stand-in.
///
/// [evaluate] waits for [completer] to complete before returning [decision],
/// so tests can simulate slow or fast evaluations.
class _FakeUpdateService implements AppUpdateService {
  _FakeUpdateService(this.decision, this.completer);

  final UpdateDecision decision;
  final Completer<void> completer;

  @override
  AppUpdateConfig get config =>
      const AppUpdateConfig(androidPackageId: '', iosAppStoreId: '');

  @override
  Future<UpdateDecision> evaluate() async {
    await completer.future;
    return decision;
  }

  @override
  Future<void> startUpdate() async {}
}

const _childKey = Key('child');
const _forcedKey = Key('forced');
const _loadingKey = Key('loading');

const _forcedDecision = UpdateDecision(
  requirement: UpdateRequirement.forced,
  message: 'Update now',
);

Widget _child() => const Scaffold(body: Text('app', key: _childKey));

Widget _forcedBuilder(BuildContext _, UpdateDecision d) =>
    const Scaffold(body: Text('forced', key: _forcedKey));

Widget _loadingBuilder(BuildContext _) =>
    const Scaffold(body: Text('loading', key: _loadingKey));

/// Wraps [widget] in a [MaterialApp] so that [Scaffold] has the required
/// [Directionality] ancestor.
Widget _wrap(Widget widget) => MaterialApp(home: widget);

AppUpdateController _controller(
  UpdateDecision decision,
  Completer<void> completer, {
  ForcePresentation forcePresentation = ForcePresentation.immediate,
}) {
  return AppUpdateController(
    service: _FakeUpdateService(decision, completer),
    forcePresentation: forcePresentation,
  );
}

void main() {
  group('UpdateGate — nonBlocking mode (default)', () {
    testWidgets('shows child immediately before evaluation completes', (
      tester,
    ) async {
      final controller = _controller(
        const UpdateDecision.none(),
        Completer<void>(),
      );

      await tester.pumpWidget(
        _wrap(
          UpdateGate(
            controller: controller,
            forcedBuilder: _forcedBuilder,
            child: _child(),
          ),
        ),
      );

      expect(find.byKey(_childKey), findsOneWidget);
      expect(find.byKey(_forcedKey), findsNothing);
    });

    testWidgets('swaps to forced screen when evaluation returns forced', (
      tester,
    ) async {
      final completer = Completer<void>();
      final controller = _controller(_forcedDecision, completer);

      await tester.pumpWidget(
        _wrap(
          UpdateGate(
            controller: controller,
            forcedBuilder: _forcedBuilder,
            child: _child(),
          ),
        ),
      );

      expect(find.byKey(_childKey), findsOneWidget);

      completer.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(_forcedKey), findsOneWidget);
      expect(find.byKey(_childKey), findsNothing);
    });

    testWidgets('stays on child when evaluation returns none or optional', (
      tester,
    ) async {
      final completer = Completer<void>();
      final controller = _controller(
        const UpdateDecision(requirement: UpdateRequirement.optional),
        completer,
      );

      await tester.pumpWidget(
        _wrap(
          UpdateGate(
            controller: controller,
            forcedBuilder: _forcedBuilder,
            child: _child(),
          ),
        ),
      );

      completer.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(_childKey), findsOneWidget);
      expect(find.byKey(_forcedKey), findsNothing);
    });
  });

  group('UpdateGate — blocking mode', () {
    testWidgets('shows loadingBuilder before evaluation completes', (
      tester,
    ) async {
      final controller = _controller(
        const UpdateDecision.none(),
        Completer<void>(),
      );

      await tester.pumpWidget(
        _wrap(
          UpdateGate(
            controller: controller,
            mode: UpdateGateMode.blocking,
            loadingBuilder: _loadingBuilder,
            forcedBuilder: _forcedBuilder,
            child: _child(),
          ),
        ),
      );

      expect(find.byKey(_loadingKey), findsOneWidget);
      expect(find.byKey(_childKey), findsNothing);
    });

    testWidgets('shows default spinner when no loadingBuilder is provided', (
      tester,
    ) async {
      final controller = _controller(
        const UpdateDecision.none(),
        Completer<void>(),
      );

      await tester.pumpWidget(
        _wrap(
          UpdateGate(
            controller: controller,
            mode: UpdateGateMode.blocking,
            forcedBuilder: _forcedBuilder,
            child: _child(),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(_childKey), findsNothing);
    });

    testWidgets('shows forced screen when evaluation returns forced', (
      tester,
    ) async {
      final completer = Completer<void>();
      final controller = _controller(_forcedDecision, completer);

      await tester.pumpWidget(
        _wrap(
          UpdateGate(
            controller: controller,
            mode: UpdateGateMode.blocking,
            loadingBuilder: _loadingBuilder,
            forcedBuilder: _forcedBuilder,
            child: _child(),
          ),
        ),
      );

      completer.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(_forcedKey), findsOneWidget);
      expect(find.byKey(_childKey), findsNothing);
    });

    testWidgets('shows child when evaluation returns none', (tester) async {
      final completer = Completer<void>();
      final controller = _controller(const UpdateDecision.none(), completer);

      await tester.pumpWidget(
        _wrap(
          UpdateGate(
            controller: controller,
            mode: UpdateGateMode.blocking,
            loadingBuilder: _loadingBuilder,
            forcedBuilder: _forcedBuilder,
            child: _child(),
          ),
        ),
      );

      completer.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(_childKey), findsOneWidget);
      expect(find.byKey(_loadingKey), findsNothing);
    });

    testWidgets('does not wait when checkOnStart is false', (tester) async {
      final controller = AppUpdateController(
        service: _FakeUpdateService(
          const UpdateDecision.none(),
          Completer<void>(),
        ),
        checkOnStart: false,
      );

      await tester.pumpWidget(
        _wrap(
          UpdateGate(
            controller: controller,
            mode: UpdateGateMode.blocking,
            loadingBuilder: _loadingBuilder,
            forcedBuilder: _forcedBuilder,
            child: _child(),
          ),
        ),
      );

      expect(find.byKey(_childKey), findsOneWidget);
    });
  });

  group('UpdateGate — onDecision callback', () {
    testWidgets('calls onDecision with the resolved decision', (tester) async {
      final completer = Completer<void>();
      const expected = UpdateDecision(
        requirement: UpdateRequirement.optional,
        message: 'New version available',
      );
      final controller = _controller(expected, completer);

      UpdateDecision? captured;
      await tester.pumpWidget(
        _wrap(
          UpdateGate(
            controller: controller,
            onDecision: (d) => captured = d,
            forcedBuilder: _forcedBuilder,
            child: _child(),
          ),
        ),
      );

      completer.complete();
      await tester.pumpAndSettle();

      expect(captured, expected);
    });
  });

  group('UpdateGate + UpdateGateNavigatorObserver — onNextNavigation', () {
    testWidgets('holds the forced screen until the user navigates', (
      tester,
    ) async {
      final completer = Completer<void>();
      final controller = _controller(
        _forcedDecision,
        completer,
        forcePresentation: ForcePresentation.onNextNavigation,
      );

      await tester.pumpWidget(
        UpdateGate(
          controller: controller,
          forcedBuilder: (context, decision) => const Directionality(
            textDirection: TextDirection.ltr,
            child: Text('forced', key: _forcedKey),
          ),
          child: MaterialApp(
            navigatorObservers: [UpdateGateNavigatorObserver(controller)],
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  key: _childKey,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(body: Text('page 2')),
                    ),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      );

      // Check resolves forced, but the result is held.
      completer.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(_childKey), findsOneWidget);
      expect(find.byKey(_forcedKey), findsNothing);

      // The next navigation releases it.
      await tester.tap(find.byKey(_childKey));
      await tester.pumpAndSettle();

      expect(find.byKey(_forcedKey), findsOneWidget);
    });
  });
}
