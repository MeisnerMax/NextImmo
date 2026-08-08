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
import 'package:neximmo_app/ui/screens/property_detail/widgets/valuation/valuation_section.dart';
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
  enabledMethods: ValuationCase.allMethodKinds,
  createdAt: DateTime.utc(2026, 7, 1),
  updatedAt: DateTime.utc(2026, 7, 28),
  createdBy: 'user-1',
  updatedBy: 'user-1',
  version: version,
);

/// One available and one unavailable method — the mix the section must render
/// side by side.
ValuationReport _report({
  MissingFactorReason missingReason = MissingFactorReason.notEntered,
}) => ValuationReport(
  methodResults: <ValuationMethodKind, MethodResult>{
    ValuationMethodKind.incomeApproachDe: const MethodValue(
      amount: 1091313,
      confidence: ConfidenceBand.high,
      breakdown: <MethodBreakdownLine>[
        MethodBreakdownLine(
          label: 'Gebäudeertragswert',
          amount: 891313,
          unit: '€',
          formula: 'Gebäudereinertrag × Vervielfältiger',
        ),
      ],
      assumptions: <ValuationAssumption>[
        ValuationAssumption(
          factorId: ValuationFactorIds.liegenschaftszinssatz,
          label: 'Liegenschaftszinssatz',
          provenance: FactorProvenance.accepted,
          value: 0.035,
          source: 'Referenztabelle',
        ),
      ],
    ),
    ValuationMethodKind.costApproachDe: MethodUnavailable(
      missingFactors: <MissingFactor>[
        MissingFactor(
          factorId: ValuationFactorIds.sachwertfaktor,
          label: 'Sachwertfaktor',
          reason: missingReason,
          message: missingReason == MissingFactorReason.suggestionNotConfirmed
              ? 'Systemvorschlag für „Sachwertfaktor" muss bestätigt werden.'
              : 'Pflichtwert „Sachwertfaktor" fehlt.',
        ),
      ],
    ),
  },
  opinion: const MarketValue(
    amount: 1091313,
    confidence: ConfidenceBand.high,
    weights: <ValuationMethodKind, double>{
      ValuationMethodKind.incomeApproachDe: 1.0,
    },
    rationale: 'Nur das Ertragswertverfahren war verfügbar.',
  ),
  assumptionLedger: const <ValuationAssumption>[
    ValuationAssumption(
      factorId: ValuationFactorIds.liegenschaftszinssatz,
      label: 'Liegenschaftszinssatz',
      provenance: FactorProvenance.accepted,
      value: 0.035,
      source: 'Referenztabelle',
    ),
  ],
);

ValuationCaseState _readyState({
  ValuationReport? report,
  ValuationCaseDto? valuationCase,
  ValuationReportSnapshot? storedReport,
  ValuationActionPhase actionPhase = ValuationActionPhase.idle,
  ValuationVersionConflict? conflict,
  String? actionMessage,
}) => ValuationCaseState(
  loadPhase: ValuationLoadPhase.ready,
  actionPhase: actionPhase,
  detail: ValuationCaseDetail(
    valuationCase: valuationCase ?? _caseDto(),
    factors: const <ValuationFactorDto>[],
    report: storedReport,
  ),
  liveReport: report ?? _report(),
  versionConflict: conflict,
  actionMessage: actionMessage,
);

Future<void> _pump(
  WidgetTester tester,
  Widget section, {
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
          child: Padding(padding: const EdgeInsets.all(16), child: section),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the Verkehrswert with its weighting and rationale',
      (tester) async {
    await _pump(tester, ValuationSection(state: _readyState()));

    expect(find.text('Verkehrswert'), findsOneWidget);
    expect(find.text('1.091.313 €'), findsWidgets);
    expect(find.textContaining('Ertragswertverfahren 100 %'), findsOneWidget);
    expect(
      find.text('Nur das Ertragswertverfahren war verfügbar.'),
      findsOneWidget,
    );
  });

  testWidgets('an unavailable method states "nicht ermittelbar" with its reason',
      (tester) async {
    await _pump(tester, ValuationSection(state: _readyState()));

    expect(find.text('Sachwertverfahren'), findsOneWidget);
    expect(find.text('nicht ermittelbar'), findsWidgets);
    expect(
      find.text('Pflichtwert „Sachwertfaktor" fehlt.'),
      findsOneWidget,
    );
  });

  testWidgets('offers the jump to the missing factor', (tester) async {
    final jumps = <String>[];
    await _pump(
      tester,
      ValuationSection(state: _readyState(), onJumpToFactor: jumps.add),
    );

    await tester.tap(find.text('Zur Eingabe'));
    await tester.pump();

    expect(jumps, <String>[ValuationFactorIds.sachwertfaktor]);
  });

  testWidgets('offers confirming a suggestion straight from the reason',
      (tester) async {
    final accepted = <String>[];
    await _pump(
      tester,
      ValuationSection(
        state: _readyState(
          report: _report(
            missingReason: MissingFactorReason.suggestionNotConfirmed,
          ),
        ),
        onAcceptSuggestion: accepted.add,
      ),
    );

    expect(
      find.textContaining('muss bestätigt werden'),
      findsOneWidget,
    );
    await tester.tap(find.text('Vorschlag übernehmen'));
    await tester.pump();

    expect(accepted, <String>[ValuationFactorIds.sachwertfaktor]);
  });

  testWidgets('does not offer confirming when mutations are not allowed',
      (tester) async {
    await _pump(
      tester,
      ValuationSection(
        state: _readyState(
          report: _report(
            missingReason: MissingFactorReason.suggestionNotConfirmed,
          ),
        ),
      ),
    );

    expect(find.text('Vorschlag übernehmen'), findsNothing);
  });

  testWidgets('shows the calculation trail of the leading method', (tester) async {
    await _pump(tester, ValuationSection(state: _readyState()));

    expect(find.text('Gebäudeertragswert'), findsOneWidget);
    expect(
      find.text('Gebäudereinertrag × Vervielfältiger'),
      findsOneWidget,
    );
  });

  testWidgets('flags a published report that predates the factors',
      (tester) async {
    await _pump(
      tester,
      ValuationSection(
        state: _readyState(
          valuationCase: _caseDto(version: 5),
          storedReport: const ValuationReportSnapshot(
            valuationCaseId: 'case-1',
            computedFromVersion: 3,
            methodResults: <ValuationMethodResultDto>[],
          ),
        ),
      ),
    );

    expect(find.text('Bericht veraltet'), findsOneWidget);
    expect(
      find.textContaining('älteren Faktorstand'),
      findsOneWidget,
    );
  });

  testWidgets('renders the assumption ledger with provenance', (tester) async {
    await _pump(tester, ValuationSection(state: _readyState()));

    expect(find.text('Annahmen'), findsOneWidget);
    expect(find.text('Liegenschaftszinssatz'), findsWidgets);
    expect(find.text('Vorschlag bestätigt'), findsWidgets);
  });

  group('mandatory states', () {
    testWidgets('loading shows a skeleton, not a blank frame', (tester) async {
      await _pump(
        tester,
        const ValuationSection(state: ValuationCaseState.loading()),
      );

      expect(find.byKey(const Key('valuation-section-skeleton')), findsOneWidget);
      // A skeleton matching the eventual layout — not a blocking spinner.
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('empty offers creating a case', (tester) async {
      var created = 0;
      await _pump(
        tester,
        ValuationSection(
          state: const ValuationCaseState(loadPhase: ValuationLoadPhase.empty),
          onCreateCase: () => created++,
        ),
      );

      expect(find.text('Noch keine Bewertung'), findsOneWidget);
      await tester.tap(find.text('Bewertung anlegen'));
      expect(created, 1);
    });

    testWidgets('forbidden is distinct from empty', (tester) async {
      await _pump(
        tester,
        const ValuationSection(
          state: ValuationCaseState(
            loadPhase: ValuationLoadPhase.forbidden,
            message: 'Keine Berechtigung für Bewertungen.',
          ),
        ),
      );

      expect(find.text('Kein Zugriff auf Bewertungen'), findsOneWidget);
      expect(find.text('Noch keine Bewertung'), findsNothing);
    });

    testWidgets('error offers a retry and shows no raw exception',
        (tester) async {
      var retried = 0;
      await _pump(
        tester,
        ValuationSection(
          state: const ValuationCaseState(
            loadPhase: ValuationLoadPhase.error,
            message: 'Bewertung konnte nicht geladen werden.',
          ),
          onRetry: () => retried++,
        ),
      );

      await tester.tap(find.text('Erneut versuchen'));
      expect(retried, 1);
    });

    testWidgets('read-only backend is announced, not silently ignored',
        (tester) async {
      await _pump(
        tester,
        ValuationSection(
          state: _readyState(
            actionPhase: ValuationActionPhase.readOnly,
            actionMessage:
                'Im lokalen Bestand schreibgeschützt, bis die Bewertung '
                'migriert ist.',
          ),
        ),
      );

      expect(find.text('Schreibgeschützt bis migriert'), findsOneWidget);
    });

    testWidgets('version conflict shows both versions', (tester) async {
      await _pump(
        tester,
        ValuationSection(
          state: _readyState(
            actionPhase: ValuationActionPhase.conflict,
            actionMessage: 'Der Bericht wurde aus einem alten Stand berechnet.',
            conflict: const ValuationVersionConflict(
              expectedVersion: 3,
              actualVersion: 4,
            ),
          ),
        ),
      );

      expect(find.text('Versionskonflikt'), findsOneWidget);
      expect(
        find.textContaining('Erwartete Version 3, aktuelle Version 4'),
        findsOneWidget,
      );
    });

    testWidgets('an approved case is shown as a closed record', (tester) async {
      await _pump(
        tester,
        ValuationSection(
          state: _readyState(
            valuationCase: _caseDto(status: ValuationCaseStatus.approved),
            actionPhase: ValuationActionPhase.approvedImmutable,
            actionMessage: 'Freigegebene Bewertung ist ein Datensatz.',
          ),
        ),
      );

      expect(find.text('Freigegeben'), findsOneWidget);
      expect(find.text('Freigegeben – unveränderlich'), findsOneWidget);
    });
  });

  group('responsive', () {
    for (final size in const <Size>[
      Size(390, 844),
      Size(1024, 768),
      Size(1440, 900),
    ]) {
      testWidgets('lays out without overflow at ${size.width.toInt()}px',
          (tester) async {
        await _pump(tester, ValuationSection(state: _readyState()), size: size);

        expect(tester.takeException(), isNull);
        expect(find.text('Wertermittlung'), findsOneWidget);
      });
    }
  });
}
