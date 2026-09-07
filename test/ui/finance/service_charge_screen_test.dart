/// The Betriebskostenabrechnung screen (`SERVICE-CHARGE-PREVIEW-01`).
///
/// What a controller test cannot cover: that the derivation actually reaches
/// the reader. A per-unit amount without its numerator, denominator and the
/// key's explanation is a figure nobody can check, and DEC-014 makes the key
/// with its explanation one of the four particulars an operating-cost
/// statement cannot be valid without — so it is asserted on the rendered
/// screen, not only in the DTO.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/finance_ledger/application/finance_ledger_port.dart';
import 'package:neximmo_app/features/finance_ledger/application/finance_providers.dart';
import 'package:neximmo_app/features/finance_ledger/application/service_charge_controller.dart';
import 'package:neximmo_app/features/finance_ledger/domain/service_charge_preview_dto.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/ui/screens/finance/service_charge_screen.dart';

void main() {
  testWidgets('without a property the screen asks for one', (tester) async {
    await _pump(tester);

    expect(
      find.byKey(const Key('service-charge-no-property')),
      findsOneWidget,
      reason: 'the controller reads nothing until a property is chosen, and '
          'the screen must say so rather than sit on a spinner',
    );
  });

  testWidgets('a refusal is shown and no figures are left behind', (
    tester,
  ) async {
    await _pump(
      tester,
      port: _StubPort(
        const FinanceRepositoryFailure<ServiceChargePreviewDto>(
          kind: FinanceRepositoryFailureKind.validationFailed,
          message: 'Der Abrechnungszeitraum endet vor seinem Beginn.',
          field: 'to',
        ),
      ),
      property: 'property-1',
    );

    expect(find.byKey(const Key('service-charge-message')), findsOneWidget);
    expect(find.byKey(const Key('service-charge-kpi-distributed')), findsNothing);
  });

  testWidgets('a member without finance.read gets the capability, not a crash',
      (tester) async {
    await _pump(tester, permissions: const <String>{'property.read'});

    expect(find.byKey(const Key('service-charge-forbidden')), findsOneWidget);
    expect(find.textContaining('finance.read'), findsOneWidget);
  });

  group('with a statement', () {
    testWidgets('the per-unit amount is shown with its derivation', (
      tester,
    ) async {
      await _pump(tester, property: 'property-1', surface: _tall);

      expect(find.text('A-01'), findsOneWidget);
      expect(
        find.text('600,00 EUR'),
        findsWidgets,
        reason: 'the figure itself, in German formatting',
      );
      expect(
        find.textContaining('60 von 100'),
        findsOneWidget,
        reason: 'a share without its numerator and denominator cannot be '
            'checked by the person it is charged to',
      );
      expect(
        find.textContaining('Nach Wohnfläche.'),
        findsWidgets,
        reason: 'DEC-014: the key with its explanation is one of the four '
            'particulars a statement cannot be valid without',
      );
    });

    testWidgets('it says on its face that it is not a statement', (
      tester,
    ) async {
      await _pump(tester, property: 'property-1', surface: _tall);

      expect(
        find.byKey(const Key('service-charge-preview-notice')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('service-charge-open-questions')),
        findsOneWidget,
        reason: 'the two undecided modelling questions are named on the '
            'screen, so nobody reads their absence as a decision',
      );
    });

    testWidgets('a refused position keeps its amount visible', (tester) async {
      await _pump(tester, property: 'property-1', surface: _tall);

      expect(find.byKey(const Key('service-charge-refused')), findsWidgets);
      expect(
        find.text('800,00 EUR'),
        findsOneWidget,
        reason: 'DEC-029: an apportionable cost that could not be distributed '
            'stays on screen with its amount rather than disappearing from a '
            'total that then looks complete',
      );
      expect(
        find.textContaining('Meters and readings arrive with P-4'),
        findsOneWidget,
        reason: 'the server explains the refusal and the screen passes it on '
            'rather than replacing it with a shrug',
      );
    });

    testWidgets('an unclassified cost is called out as work, not as a fault', (
      tester,
    ) async {
      await _pump(tester, property: 'property-1', surface: _tall);

      expect(
        find.byKey(const Key('service-charge-unclassified')),
        findsOneWidget,
      );
      expect(
        find.textContaining('etwas anderes als die Entscheidung'),
        findsOneWidget,
        reason: 'the notice states the distinction the whole feature rests on',
      );
    });

    testWidgets('a unit that was only partly let says so', (tester) async {
      await _pump(tester, property: 'property-1', surface: _tall);

      expect(
        find.textContaining('31 von 59 Tagen vermietet'),
        findsOneWidget,
        reason: 'question 2 as a figure: the share is not split between tenant '
            'and owner, so the screen shows what would decide it',
      );
    });

    for (final Size size in const <Size>[
      Size(320, 700),
      Size(390, 844),
      Size(768, 1024),
      Size(1440, 900),
    ]) {
      testWidgets('has no overflow at $size', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pump(tester, property: 'property-1');
        // Scrolled to the end, because the screen is a lazily-built
        // `ListView`: without this the unit cards below the fold are never
        // laid out at this width, and the narrowest breakpoint would pass by
        // never rendering the widest content.
        await tester.scrollUntilVisible(
          find.byKey(const Key('service-charge-open-questions')),
          300,
          scrollable: find.descendant(
            of: find.byKey(const Key('service-charge-list')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  });
}

/// A surface tall enough that the whole statement is built.
///
/// The screen is a lazily-built `ListView`, so a unit card below the fold does
/// not exist to be found at all. The content assertions want the whole page;
/// the overflow tests below set their own real sizes and pass nothing here.
const Size _tall = Size(1200, 4000);

Future<void> _pump(
  WidgetTester tester, {
  _StubPort? port,
  String? property,
  Size? surface,
  Set<String> permissions = const <String>{'property.read', 'finance.read'},
}) async {
  if (surface != null) {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        serviceChargePreviewProvider.overrideWithValue(
          port ??
              _StubPort(
                FinanceRepositorySuccess<ServiceChargePreviewDto>(_dto()),
              ),
        ),
        workspaceSessionScopeProvider.overrideWithValue(
          WorkspaceSessionScope(
            workspaceId: 'ws-1',
            actorId: 'actor-a',
            permissions: permissions,
            mutationsSupported: true,
          ),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: _Harness(propertyId: property),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Drives the controller into the state under test, because the property
/// picker opens a dialog backed by a repository this test has no business
/// standing up.
class _Harness extends ConsumerStatefulWidget {
  const _Harness({this.propertyId});

  final String? propertyId;

  @override
  ConsumerState<_Harness> createState() => _HarnessState();
}

class _HarnessState extends ConsumerState<_Harness> {
  @override
  void initState() {
    super.initState();
    final String? id = widget.propertyId;
    if (id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(serviceChargeControllerProvider.notifier)
            .selectProperty(propertyId: id, propertyName: 'Haus A');
      });
    }
  }

  @override
  Widget build(BuildContext context) => const ServiceChargeScreen();
}

class _StubPort implements ServiceChargePreviewPort {
  const _StubPort(this._result);

  final FinanceRepositoryResult<ServiceChargePreviewDto> _result;

  @override
  Future<FinanceRepositoryResult<ServiceChargePreviewDto>> readPreview({
    required String workspaceId,
    required String propertyId,
    required DateTime from,
    required DateTime to,
  }) async => _result;
}

ServiceChargePreviewDto _dto() => ServiceChargePreviewDto.fromJson(
  <String, dynamic>{
    'property_id': 'property-1',
    'property_name': 'Haus A',
    'from_date': '2026-01-01',
    'to_date': '2026-02-28',
    'days_in_window': 59,
    'currency_code': 'EUR',
    'is_preview': true,
    'is_provisional': false,
    'open_period_count': 0,
    'periods': <Object?>[
      <String, dynamic>{
        'id': 'period-1',
        'fiscal_year': 2026,
        'period_month': 1,
        'status': 'closed',
      },
    ],
    'totals': <String, dynamic>{
      'distributed': 600,
      'apportionable_not_distributed': 800,
      'not_apportionable': 0,
      'unclassified': 300,
      'unclassified_account_count': 1,
    },
    'accounts': <Object?>[
      <String, dynamic>{
        'account_id': 'account-1',
        'account_code': '4300',
        'account_name': 'Müllabfuhr',
        'amount': 600,
        'entry_count': 1,
        'allocatable': true,
        'distributed': true,
        'refusal': null,
        'rounding_difference': 0,
        'key': <String, dynamic>{
          'id': 'key-1',
          'basis': 'area_sqm',
          'explanation': 'Nach Wohnfläche.',
          'valid_from': '2020-01-01',
          'valid_to': null,
        },
      },
      <String, dynamic>{
        'account_id': 'account-2',
        'account_code': '4400',
        'account_name': 'Heizung',
        'amount': 800,
        'entry_count': 1,
        'allocatable': true,
        'distributed': false,
        'refusal': <String, dynamic>{
          'reason': 'no_meters',
          'detail': 'Meters and readings arrive with P-4.',
        },
      },
      <String, dynamic>{
        'account_id': 'account-3',
        'account_code': '4950',
        'account_name': 'Verwaltung',
        'amount': 300,
        'entry_count': 1,
        'allocatable': null,
        'distributed': false,
        'refusal': <String, dynamic>{
          'reason': 'unclassified',
          'detail': 'Nobody has decided.',
        },
      },
    ],
    'units': <Object?>[
      <String, dynamic>{
        'unit_id': 'unit-1',
        'unit_code': 'A-01',
        'area_sqm': 60,
        'total': 600,
        'days_let': 31,
        'days_in_window': 59,
        'lines': <Object?>[
          <String, dynamic>{
            'unit_id': 'unit-1',
            'account_id': 'account-1',
            'account_code': '4300',
            'account_name': 'Müllabfuhr',
            'amount': 600,
            'numerator': 60,
            'denominator': 100,
            'basis': 'area_sqm',
            'explanation': 'Nach Wohnfläche.',
          },
        ],
      },
    ],
  },
);
