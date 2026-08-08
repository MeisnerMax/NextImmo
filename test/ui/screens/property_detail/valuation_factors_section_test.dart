import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/valuation/application/valuation_case_controller.dart';
import 'package:neximmo_app/features/valuation/application/valuation_repository.dart';
import 'package:neximmo_app/features/valuation/domain/cash_flow_projection.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case_dto.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor_catalog.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor_ids.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_method.dart';
import 'package:neximmo_app/ui/screens/property_detail/widgets/valuation/valuation_factor_row.dart';
import 'package:neximmo_app/ui/screens/property_detail/widgets/valuation/valuation_factors_section.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

ValuationCaseDto _caseDto() => ValuationCaseDto(
  id: 'case-1',
  workspaceId: 'ws-1',
  propertyId: 'prop-1',
  title: 'Musterfall MFH',
  kind: ValuationCaseKind.holding,
  status: ValuationCaseStatus.draft,
  dcfTerminal: DcfTerminalMethod.exitCap,
  enabledMethods: ValuationCase.allMethodKinds,
  createdAt: DateTime.utc(2026, 7, 1),
  updatedAt: DateTime.utc(2026, 7, 28),
  createdBy: 'user-1',
  updatedBy: 'user-1',
  version: 3,
);

ValuationFactorDto _factor({
  required String factorId,
  required String label,
  required double value,
  FactorProvenance provenance = FactorProvenance.userProvided,
  String? source,
  String? unit,
}) => ValuationFactorDto(
  caseId: 'case-1',
  factorId: factorId,
  label: label,
  provenance: provenance,
  confidence: ConfidenceBand.high,
  value: value,
  source: source,
  unit: unit,
);

ValuationCaseState _state({
  List<ValuationFactorDto> factors = const <ValuationFactorDto>[],
  ValuationActionPhase actionPhase = ValuationActionPhase.idle,
}) => ValuationCaseState(
  loadPhase: ValuationLoadPhase.ready,
  actionPhase: actionPhase,
  detail: ValuationCaseDetail(valuationCase: _caseDto(), factors: factors),
);

Future<void> _pump(
  WidgetTester tester,
  Widget section, {
  Size size = const Size(1440, 1400),
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

Finder _fieldFor(String factorId) =>
    find.byKey(ValueKey<String>('factor-field-$factorId'));

void main() {
  group('provenance', () {
    testWidgets('an empty required factor is marked as missing', (tester) async {
      await _pump(tester, ValuationFactorsSection(state: _state()));

      expect(find.text('fehlt'), findsWidgets);
      expect(find.text('Eigene Eingabe'), findsNothing);
    });

    testWidgets('a stored value shows where it came from', (tester) async {
      await _pump(
        tester,
        ValuationFactorsSection(
          state: _state(
            factors: <ValuationFactorDto>[
              _factor(
                factorId: ValuationFactorIds.grossRentAnnual,
                label: 'Rohertrag p.a.',
                value: 60000,
              ),
            ],
          ),
        ),
      );

      expect(find.text('Eigene Eingabe'), findsWidgets);
    });

    testWidgets('an unconfirmed suggestion names its source and can be taken',
        (tester) async {
      final accepted = <String>[];
      await _pump(
        tester,
        ValuationFactorsSection(
          state: _state(
            factors: <ValuationFactorDto>[
              _factor(
                factorId: ValuationFactorIds.liegenschaftszinssatz,
                label: 'Liegenschaftszinssatz',
                value: 0.035,
                provenance: FactorProvenance.suggestedDefault,
                source: 'Referenztabelle',
              ),
            ],
          ),
          onSave: (_) {},
          onAcceptSuggestion: accepted.add,
        ),
      );

      expect(find.text('Vorschlag – unbestätigt'), findsOneWidget);
      expect(
        find.textContaining('Vorschlag aus Referenztabelle'),
        findsOneWidget,
      );

      await tester.tap(find.text('Übernehmen'));
      await tester.pump();

      expect(accepted, <String>[ValuationFactorIds.liegenschaftszinssatz]);
    });
  });

  group('progress', () {
    testWidgets('counts what the method actually needs', (tester) async {
      await _pump(tester, ValuationFactorsSection(state: _state()));

      final incomeGroup = ValuationFactorCatalog.groupFor(
        ValuationMethodKind.incomeApproachDe,
      )!;
      final total = incomeGroup.progress((_) => false).total;

      expect(find.text('0 von $total'), findsWidgets);
    });

    testWidgets('an unconfirmed suggestion does not count as satisfied',
        (tester) async {
      await _pump(
        tester,
        ValuationFactorsSection(
          state: _state(
            factors: <ValuationFactorDto>[
              _factor(
                factorId: ValuationFactorIds.grossRentAnnual,
                label: 'Rohertrag p.a.',
                value: 60000,
              ),
              _factor(
                factorId: ValuationFactorIds.operatingExpensesAnnual,
                label: 'Bewirtschaftungskosten p.a.',
                value: 15000,
                provenance: FactorProvenance.suggestedDefault,
                source: 'Referenztabelle',
              ),
            ],
          ),
        ),
      );

      final incomeGroup = ValuationFactorCatalog.groupFor(
        ValuationMethodKind.incomeApproachDe,
      )!;
      final total = incomeGroup.progress((_) => false).total;

      // Only the confirmed factor counts — the suggestion is visible but not
      // usable, which is the entire point of the provenance model.
      expect(find.text('1 von $total'), findsWidgets);
    });
  });

  group('saving', () {
    testWidgets('collects the edits into one command', (tester) async {
      final saved = <List<ValuationFactorDto>>[];
      await _pump(
        tester,
        ValuationFactorsSection(state: _state(), onSave: saved.add),
      );

      await tester.enterText(
        _fieldFor(ValuationFactorIds.grossRentAnnual),
        '60000',
      );
      await tester.pump();
      await tester.enterText(
        _fieldFor(ValuationFactorIds.liegenschaftszinssatz),
        '3,5',
      );
      await tester.pump();

      expect(find.text('2 Änderung(en) speichern'), findsOneWidget);
      await tester.tap(find.text('2 Änderung(en) speichern'));
      await tester.pump();

      expect(saved, hasLength(1));
      final byId = <String, ValuationFactorDto>{
        for (final factor in saved.single) factor.factorId: factor,
      };
      expect(byId[ValuationFactorIds.grossRentAnnual]!.value, 60000);
      // A rate is entered as a percentage and stored as a fraction.
      expect(
        byId[ValuationFactorIds.liegenschaftszinssatz]!.value,
        closeTo(0.035, 1e-9),
      );
      expect(
        byId[ValuationFactorIds.grossRentAnnual]!.provenance,
        FactorProvenance.userProvided,
      );
    });

    testWidgets('unparseable input is skipped instead of stored as zero',
        (tester) async {
      final saved = <List<ValuationFactorDto>>[];
      await _pump(
        tester,
        ValuationFactorsSection(state: _state(), onSave: saved.add),
      );

      await tester.enterText(
        _fieldFor(ValuationFactorIds.grossRentAnnual),
        'keine Zahl',
      );
      await tester.pump();
      await tester.tap(find.text('1 Änderung(en) speichern'));
      await tester.pump();

      expect(saved, isEmpty);
    });

    testWidgets('removing a value is its own explicit action', (tester) async {
      final cleared = <String>[];
      await _pump(
        tester,
        ValuationFactorsSection(
          state: _state(
            factors: <ValuationFactorDto>[
              _factor(
                factorId: ValuationFactorIds.grossRentAnnual,
                label: 'Rohertrag p.a.',
                value: 60000,
              ),
            ],
          ),
          onSave: (_) {},
          onClearFactor: cleared.add,
        ),
      );

      await tester.tap(find.text('Wert entfernen').first);
      await tester.pump();

      expect(cleared, <String>[ValuationFactorIds.grossRentAnnual]);
    });
  });

  group('read-only', () {
    testWidgets('offers no save, no accept and no removal', (tester) async {
      await _pump(
        tester,
        ValuationFactorsSection(
          state: _state(
            factors: <ValuationFactorDto>[
              _factor(
                factorId: ValuationFactorIds.liegenschaftszinssatz,
                label: 'Liegenschaftszinssatz',
                value: 0.035,
                provenance: FactorProvenance.suggestedDefault,
              ),
            ],
          ),
        ),
      );

      expect(find.text('Schreibgeschützt — nur Ansicht'), findsOneWidget);
      expect(find.text('Übernehmen'), findsNothing);
      expect(find.text('Wert entfernen'), findsNothing);
      expect(find.textContaining('speichern'), findsNothing);
    });
  });

  group('input conversion', () {
    test('percent round-trips through the field representation', () {
      expect(parseFactorInput('3,5', FactorInputKind.percent), closeTo(0.035, 1e-9));
      expect(formatFactorInput(0.035, FactorInputKind.percent), '3,5');
      expect(parseFactorInput('60.000', FactorInputKind.money), 60000);
      expect(parseFactorInput('', FactorInputKind.money), isNull);
    });
  });
}
