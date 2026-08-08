import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/valuation/application/valuation_variant_group.dart';
import 'package:neximmo_app/features/valuation/domain/cash_flow_projection.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case_dto.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_method.dart';
import 'package:neximmo_app/ui/screens/property_detail/widgets/valuation/valuation_variant_bar.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

ValuationCaseDto _caseDto({
  required String id,
  required String variantLabel,
  ValuationCaseStatus status = ValuationCaseStatus.draft,
}) => ValuationCaseDto(
  id: id,
  workspaceId: 'ws-1',
  propertyId: 'prop-1',
  title: 'Musterfall MFH',
  kind: ValuationCaseKind.holding,
  status: status,
  dcfTerminal: DcfTerminalMethod.exitCap,
  enabledMethods: const {ValuationMethodKind.incomeApproachDe},
  createdAt: DateTime.utc(2026, 7, 1),
  updatedAt: DateTime.utc(2026, 7, 30),
  createdBy: 'user-1',
  updatedBy: 'user-1',
  version: 2,
  variantGroupId: 'group-1',
  variantLabel: variantLabel,
);

Future<void> _pump(
  WidgetTester tester,
  Widget bar, {
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
          child: Padding(padding: const EdgeInsets.all(16), child: bar),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows each variant with its own value', (tester) async {
    await _pump(
      tester,
      ValuationVariantBar(
        activeCaseId: 'case-1',
        entries: <ValuationVariantEntry>[
          ValuationVariantEntry(
            valuationCase: _caseDto(id: 'case-1', variantLabel: 'Basis'),
            marketValue: 1091313,
          ),
          ValuationVariantEntry(
            valuationCase: _caseDto(
              id: 'case-2',
              variantLabel: 'Konservativ',
            ),
            marketValue: 940000,
          ),
        ],
      ),
    );

    expect(find.text('Basis'), findsOneWidget);
    expect(find.text('Konservativ'), findsOneWidget);
    expect(find.text('1.091.313 €'), findsOneWidget);
    expect(find.text('940.000 €'), findsOneWidget);
    // No combined number: averaging a conservative and an optimistic case
    // would produce a value nobody assumed.
    expect(find.textContaining('Gesamt'), findsNothing);
  });

  testWidgets('a variant without a report says so instead of borrowing one',
      (tester) async {
    await _pump(
      tester,
      ValuationVariantBar(
        activeCaseId: 'case-1',
        entries: <ValuationVariantEntry>[
          ValuationVariantEntry(
            valuationCase: _caseDto(id: 'case-1', variantLabel: 'Basis'),
            marketValue: 1091313,
          ),
          ValuationVariantEntry(
            valuationCase: _caseDto(id: 'case-2', variantLabel: 'Neu'),
          ),
        ],
      ),
    );

    expect(find.text('nicht ermittelbar'), findsOneWidget);
  });

  testWidgets('marks a stale sibling', (tester) async {
    await _pump(
      tester,
      ValuationVariantBar(
        activeCaseId: 'case-1',
        entries: <ValuationVariantEntry>[
          ValuationVariantEntry(
            valuationCase: _caseDto(id: 'case-1', variantLabel: 'Basis'),
            marketValue: 1091313,
            isStale: true,
          ),
        ],
      ),
    );

    expect(find.text('Bericht veraltet'), findsOneWidget);
  });

  testWidgets('switching selects the sibling case', (tester) async {
    final selected = <String>[];
    await _pump(
      tester,
      ValuationVariantBar(
        activeCaseId: 'case-1',
        entries: <ValuationVariantEntry>[
          ValuationVariantEntry(
            valuationCase: _caseDto(id: 'case-1', variantLabel: 'Basis'),
          ),
          ValuationVariantEntry(
            valuationCase: _caseDto(id: 'case-2', variantLabel: 'Konservativ'),
          ),
        ],
        onSelect: (entry) => selected.add(entry.id),
      ),
    );

    await tester.tap(find.text('Konservativ'));
    await tester.pump();

    expect(selected, <String>['case-2']);
  });

  testWidgets('a standalone case explains what a variant is for',
      (tester) async {
    await _pump(
      tester,
      const ValuationVariantBar(
        activeCaseId: 'case-1',
        entries: <ValuationVariantEntry>[],
      ),
    );

    expect(find.textContaining('kopiert Faktoren'), findsOneWidget);
  });

  testWidgets('read-only offers no variant creation', (tester) async {
    await _pump(
      tester,
      const ValuationVariantBar(
        activeCaseId: 'case-1',
        entries: <ValuationVariantEntry>[],
      ),
    );

    expect(find.text('Variante anlegen'), findsNothing);
  });
}
