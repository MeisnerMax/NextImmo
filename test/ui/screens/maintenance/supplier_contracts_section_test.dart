/// SUPPLIER-CONTRACTS-01 (P-3) on screen.
///
/// The section renders a judgement it never makes. Whether a notice deadline
/// has passed was decided by the server against the date the read asked for,
/// and this widget's job is to show that decision without re-deriving it —
/// because with no scheduler anywhere in this product, a second implementation
/// of the arithmetic would eventually disagree about which day it was.
///
/// So the fixtures here set the derived flags **against** what the dates would
/// suggest. A widget that computed its own deadline would fail every one of
/// them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/contacts_parties/application/contractors_controller.dart';
import 'package:neximmo_app/features/contacts_parties/domain/supplier_contract_dto.dart';
import 'package:neximmo_app/ui/screens/maintenance/widgets/supplier_contracts_section.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

SupplierContractDto _contract({
  String id = 'contract-1',
  String title = 'Aufzugswartung',
  SupplierContractStatus status = SupplierContractStatus.active,
  DateTime? endDate,
  int? noticePeriodDays = 90,
  DateTime? noticeDeadline,
  int? daysToNotice,
  bool noticeDeadlinePassed = false,
  DateTime? renewsOn,
  int? renewalTermMonths,
  double? annualValue,
  String? currencyCode,
  String? propertyId,
  String? endedReason,
}) {
  return SupplierContractDto(
    id: id,
    workspaceId: 'ws-1',
    partyId: 'party-1',
    title: title,
    contractType: 'Wartung',
    status: status,
    startDate: DateTime(2024, 1, 1),
    endDate: endDate ?? DateTime(2026, 12, 31),
    noticePeriodDays: noticePeriodDays,
    autoRenew: renewsOn != null,
    renewalTermMonths: renewalTermMonths,
    annualValue: annualValue,
    currencyCode: currencyCode,
    propertyId: propertyId,
    endedReason: endedReason,
    version: 1,
    isEffective: status == SupplierContractStatus.active,
    noticeDeadline: noticeDeadline,
    daysToNotice: daysToNotice,
    noticeDeadlinePassed: noticeDeadlinePassed,
    renewsOn: renewsOn,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  SupplierContractsPhase phase = SupplierContractsPhase.ready,
  List<SupplierContractDto> contracts = const <SupplierContractDto>[],
  bool canMutate = true,
  Size viewport = const Size(900, 1200),
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SupplierContractsSection(
            phase: phase,
            contracts: contracts,
            canMutate: canMutate,
            onAdd: () {},
            onEdit: (_) {},
            onEnd: (_) {},
            onRetry: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows the contract with its term and type', (tester) async {
    await _pump(
      tester,
      contracts: <SupplierContractDto>[
        _contract(noticeDeadline: DateTime(2026, 10, 2), daysToNotice: 123),
      ],
    );

    expect(find.text('Aufzugswartung'), findsOneWidget);
    expect(find.textContaining('Wartung · 01.01.2024 – 31.12.2026'), findsOneWidget);
    expect(find.text('Aktiv'), findsOneWidget);
  });

  testWidgets('an open notice window shows the deadline and the days left', (
    tester,
  ) async {
    await _pump(
      tester,
      contracts: <SupplierContractDto>[
        _contract(noticeDeadline: DateTime(2026, 10, 2), daysToNotice: 123),
      ],
    );

    expect(
      find.textContaining('Kündigung bis 02.10.2026 (noch 123 Tage)'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('supplier-contract-notice-missed')),
      findsNothing,
    );
  });

  testWidgets('a missed deadline is the loudest thing on the card', (
    tester,
  ) async {
    await _pump(
      tester,
      contracts: <SupplierContractDto>[
        _contract(
          noticeDeadline: DateTime(2026, 10, 2),
          daysToNotice: -44,
          noticeDeadlinePassed: true,
        ),
      ],
    );

    expect(
      find.byKey(const Key('supplier-contract-notice-missed')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Kündigungsfrist am 02.10.2026 abgelaufen'),
      findsOneWidget,
      reason: 'the one state nobody can fix afterwards: the contract will run '
          'on and the moment to stop it has gone',
    );
    expect(
      find.byKey(const Key('supplier-contract-notice-open')),
      findsNothing,
    );
  });

  testWidgets('the widget renders the server\'s verdict, not its own', (
    tester,
  ) async {
    // The dates say the deadline is far in the future; the server says it has
    // passed. A widget computing its own would show the open window.
    await _pump(
      tester,
      contracts: <SupplierContractDto>[
        _contract(
          endDate: DateTime(2099, 12, 31),
          noticeDeadline: DateTime(2099, 10, 2),
          noticeDeadlinePassed: true,
        ),
      ],
    );

    expect(
      find.byKey(const Key('supplier-contract-notice-missed')),
      findsOneWidget,
      reason: 'the derivation lives on the server. Two implementations of it '
          'would eventually disagree about which day the deadline was',
    );
  });

  testWidgets('no agreed notice period is stated as such, not as a dash', (
    tester,
  ) async {
    await _pump(
      tester,
      contracts: <SupplierContractDto>[
        _contract(noticePeriodDays: null, noticeDeadline: null),
      ],
    );

    expect(
      find.byKey(const Key('supplier-contract-no-notice')),
      findsOneWidget,
    );
    expect(
      find.text('Keine Kündigungsfrist vereinbart'),
      findsOneWidget,
      reason: '"none was agreed" and "it is due today" are different '
          'statements, and a dash in a deadline column reads as the second',
    );
  });

  testWidgets('an auto-renewing contract names the next renewal only', (
    tester,
  ) async {
    await _pump(
      tester,
      contracts: <SupplierContractDto>[
        _contract(
          noticeDeadline: DateTime(2026, 10, 2),
          renewsOn: DateTime(2026, 12, 31),
          renewalTermMonths: 12,
        ),
      ],
    );

    expect(
      find.textContaining('Verlängert sich am 31.12.2026 um 12 Monate'),
      findsOneWidget,
    );
    expect(
      find.textContaining('2027-12-31'),
      findsNothing,
      reason: 'an auto-renewing contract has infinitely many renewal dates, '
          'and projecting them is a calendar that would want a scheduler',
    );
  });

  testWidgets('a portfolio-wide contract says so', (tester) async {
    await _pump(
      tester,
      contracts: <SupplierContractDto>[_contract(propertyId: null)],
    );

    expect(find.text('Gilt für das gesamte Portfolio'), findsOneWidget);
  });

  testWidgets('an ended contract shows its reason and offers no actions', (
    tester,
  ) async {
    await _pump(
      tester,
      contracts: <SupplierContractDto>[
        _contract(
          status: SupplierContractStatus.ended,
          endedReason: 'Anbieter gewechselt',
        ),
      ],
    );

    expect(find.text('Beendet'), findsOneWidget);
    expect(find.text('Beendet: Anbieter gewechselt'), findsOneWidget);
    expect(find.text('Bearbeiten'), findsNothing);
    expect(find.text('Beenden'), findsNothing);
  });

  testWidgets('no contracts is a positive statement, not an omission', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.byKey(const Key('supplier-contracts-empty')), findsOneWidget);
    expect(
      find.textContaining('Ein fehlender Vertrag ist kein Mangel'),
      findsOneWidget,
    );
  });

  testWidgets('a failed read says so and does not look empty', (tester) async {
    await _pump(tester, phase: SupplierContractsPhase.error);

    expect(find.byKey(const Key('supplier-contracts-error')), findsOneWidget);
    expect(find.byKey(const Key('supplier-contracts-empty')), findsNothing);
  });

  testWidgets('a member who may not write gets no actions', (tester) async {
    await _pump(
      tester,
      contracts: <SupplierContractDto>[_contract()],
      canMutate: false,
    );

    expect(find.text('Aufzugswartung'), findsOneWidget);
    expect(find.byKey(const Key('supplier-contract-add')), findsNothing);
    expect(find.text('Bearbeiten'), findsNothing);
  });

  testWidgets('renders without overflow at a phone width', (tester) async {
    await _pump(
      tester,
      contracts: <SupplierContractDto>[
        _contract(
          title: 'Wartungsvertrag für die Aufzugsanlagen aller Objekte',
          noticeDeadline: DateTime(2026, 10, 2),
          daysToNotice: -44,
          noticeDeadlinePassed: true,
          annualValue: 12500,
          currencyCode: 'EUR',
        ),
      ],
      viewport: const Size(360, 900),
    );

    expect(tester.takeException(), isNull);
  });
}
