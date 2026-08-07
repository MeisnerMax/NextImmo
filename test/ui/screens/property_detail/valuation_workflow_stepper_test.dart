import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/valuation/application/valuation_case_controller.dart';
import 'package:neximmo_app/features/valuation/application/valuation_repository.dart';
import 'package:neximmo_app/features/valuation/domain/cash_flow_projection.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case_dto.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor_ids.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_method.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_report.dart';
import 'package:neximmo_app/ui/screens/property_detail/widgets/valuation/valuation_workflow_stepper.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

ValuationCaseDto _caseDto({
  ValuationCaseStatus status = ValuationCaseStatus.draft,
  int version = 3,
}) => ValuationCaseDto(
  id: 'case-1',
  workspaceId: 'ws-1',
  propertyId: 'prop-1',
  title: 'Musterfall MFH',
  kind: ValuationCaseKind.holding,
  status: status,
  dcfTerminal: DcfTerminalMethod.exitCap,
  enabledMethods: const {ValuationMethodKind.incomeApproachDe},
  createdAt: DateTime.utc(2026, 7, 1),
  updatedAt: DateTime.utc(2026, 7, 28),
  createdBy: 'user-1',
  updatedBy: 'user-1',
  version: version,
);

ValuationReport _reportWithMissing({bool complete = false}) => ValuationReport(
  methodResults: <ValuationMethodKind, MethodResult>{
    ValuationMethodKind.incomeApproachDe: complete
        ? const MethodValue(amount: 1091313, confidence: ConfidenceBand.high)
        : const MethodUnavailable(
            missingFactors: <MissingFactor>[
              MissingFactor(
                factorId: ValuationFactorIds.liegenschaftszinssatz,
                label: 'Liegenschaftszinssatz',
                reason: MissingFactorReason.notEntered,
                message: 'Pflichtwert fehlt.',
              ),
            ],
          ),
  },
  opinion: complete
      ? const MarketValue(
          amount: 1091313,
          confidence: ConfidenceBand.high,
          weights: <ValuationMethodKind, double>{
            ValuationMethodKind.incomeApproachDe: 1.0,
          },
          rationale: 'Ein Verfahren verfügbar.',
        )
      : const MarketValueUnavailable(reason: 'Kein Verfahren verfügbar.'),
);

ValuationCaseState _state({
  ValuationCaseStatus status = ValuationCaseStatus.draft,
  bool factorsComplete = false,
  ValuationReportSnapshot? storedReport,
  int version = 3,
}) => ValuationCaseState(
  loadPhase: ValuationLoadPhase.ready,
  detail: ValuationCaseDetail(
    valuationCase: _caseDto(status: status, version: version),
    factors: const <ValuationFactorDto>[],
    report: storedReport,
  ),
  liveReport: _reportWithMissing(complete: factorsComplete),
);

Future<void> _pump(
  WidgetTester tester,
  Widget stepper, {
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: stepper),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('step conditions', () {
    test('a step is done only when its condition holds, not when visited', () {
      final steps = ValuationWorkflowStepper(state: _state()).buildSteps();

      expect(steps[0].state, ValuationStepState.done); // case exists
      expect(steps[1].state, ValuationStepState.current); // factors missing
      expect(steps[2].state, ValuationStepState.open); // no report
      expect(steps[3].state, ValuationStepState.blocked); // no report yet
      expect(steps[4].state, ValuationStepState.blocked);
    });

    test('a published report that predates the factors does not count', () {
      final steps = ValuationWorkflowStepper(
        state: _state(
          factorsComplete: true,
          version: 5,
          storedReport: const ValuationReportSnapshot(
            valuationCaseId: 'case-1',
            computedFromVersion: 3,
            methodResults: <ValuationMethodResultDto>[],
          ),
        ),
      ).buildSteps();

      expect(steps[2].state, isNot(ValuationStepState.done));
      expect(steps[2].detail, contains('älteren Faktorstand'));
    });

    test('review unlocks once a current report exists', () {
      final steps = ValuationWorkflowStepper(
        state: _state(
          factorsComplete: true,
          version: 3,
          storedReport: const ValuationReportSnapshot(
            valuationCaseId: 'case-1',
            computedFromVersion: 3,
            methodResults: <ValuationMethodResultDto>[],
          ),
        ),
      ).buildSteps();

      expect(steps[1].state, ValuationStepState.done);
      expect(steps[2].state, ValuationStepState.done);
      expect(steps[3].state, ValuationStepState.open);
      expect(steps[3].actionLabel, 'Zur Prüfung geben');
    });

    test('an approved case is done and offers nothing to change', () {
      final steps = ValuationWorkflowStepper(
        state: _state(
          status: ValuationCaseStatus.approved,
          factorsComplete: true,
          storedReport: const ValuationReportSnapshot(
            valuationCaseId: 'case-1',
            computedFromVersion: 3,
            methodResults: <ValuationMethodResultDto>[],
          ),
        ),
      ).buildSteps();

      expect(steps[4].state, ValuationStepState.done);
      expect(steps.every((step) => step.actionLabel == null), isTrue);
      expect(steps[4].detail, contains('unveränderlich'));
    });

    test('a case in review can be sent back to draft', () {
      final steps = ValuationWorkflowStepper(
        state: _state(
          status: ValuationCaseStatus.inReview,
          factorsComplete: true,
          storedReport: const ValuationReportSnapshot(
            valuationCaseId: 'case-1',
            computedFromVersion: 3,
            methodResults: <ValuationMethodResultDto>[],
          ),
        ),
      ).buildSteps();

      expect(steps[3].actionLabel, 'Zurück in Bearbeitung');
      expect(steps[4].state, ValuationStepState.open);
    });
  });

  group('rendering', () {
    testWidgets('names what is still open instead of a bare status',
        (tester) async {
      await _pump(tester, ValuationWorkflowStepper(state: _state()));

      expect(find.text('Faktoren'), findsOneWidget);
      expect(find.textContaining('Faktor(en) offen'), findsOneWidget);
      expect(find.text('Noch kein Bericht veröffentlicht.'), findsOneWidget);
    });

    testWidgets('the factor step jumps into the entry form', (tester) async {
      var jumped = 0;
      await _pump(
        tester,
        ValuationWorkflowStepper(state: _state(), onGoToFactors: () => jumped++),
      );

      await tester.tap(find.text('Zu den Faktoren'));
      await tester.pump();

      expect(jumped, 1);
    });

    testWidgets('publishing stays possible while methods are unavailable',
        (tester) async {
      var published = 0;
      await _pump(
        tester,
        ValuationWorkflowStepper(
          state: _state(),
          onPublish: () => published++,
        ),
      );

      // Step 3 is reachable even though step 2 is incomplete: the reconciled
      // value is derived from what is available, and the rest is named.
      await tester.tap(find.text('Bericht veröffentlichen'));
      await tester.pump();

      expect(published, 1);
    });

    for (final size in const <Size>[
      Size(390, 844),
      Size(1024, 768),
      Size(1440, 900),
    ]) {
      testWidgets('lays out without overflow at ${size.width.toInt()}px',
          (tester) async {
        await _pump(tester, ValuationWorkflowStepper(state: _state()), size: size);

        expect(tester.takeException(), isNull);
        expect(find.text('Freigabe'), findsOneWidget);
      });
    }
  });
}
