import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_workspace_host_state.dart';
import 'package:neximmo_app/features/portfolio_property/presentation/property_workspace_screen.dart';

import 'property_workspace_fixtures.dart';

/// `Investment` as a workspace domain (`VALUATION-REHOST-01`,
/// `PROPERTY_INVESTMENT_V2.md`).
///
/// The host groups independent screens and supplies the property context —
/// nothing more. So what these tests pin is the grouping's honesty: it appears
/// only when something inside it can actually be opened, it names the
/// capability when it cannot, and it never claims a child it does not have.
Future<void> _pump(
  WidgetTester tester, {
  required Set<String> permissions,
  Widget Function(BuildContext, String, PropertyInvestmentSubArea)?
  investmentBuilder,
  Size viewport = const Size(1440, 900),
}) async {
  setViewport(tester, viewport);
  await tester.pumpWidget(
    wrapApp(
      PropertyWorkspaceView(
        state: detailState(permissions: permissions),
        initialPropertyId: 'property-a',
        onOpenProperty: (_) async => true,
        onCloseProperty: () {},
        onLoadMore: () async {},
        onReload: () async {},
        onSetIncludeArchived: (_) async {},
        onRefreshWorkspaces: () async {},
        onUpdateProperty: (changes, {expectedVersion}) async => true,
        onRetryUpdate: () async {},
        investmentBuilder: investmentBuilder,
      ),
    ),
  );
  await tester.pump();
}

const Set<String> _withValuation = <String>{
  'property.read',
  'property.update',
  'valuation.read',
};

void main() {
  group('Investment registration', () {
    test('is gated by the read capability of its one implemented child', () {
      expect(
        visiblePropertyWorkspaceDomains(_withValuation)
            .map((registration) => registration.domain),
        contains(PropertyWorkspaceDomain.investment),
      );
      expect(
        visiblePropertyWorkspaceDomains(const <String>{
          'property.read',
        }).map((registration) => registration.domain),
        isNot(contains(PropertyWorkspaceDomain.investment)),
      );
    });

    test('Bewertung is the only sub-area today', () {
      expect(visiblePropertyInvestmentSubAreas(_withValuation), <
        PropertyInvestmentSubArea
      >[PropertyInvestmentSubArea.valuation]);
      expect(
        visiblePropertyInvestmentSubAreas(const <String>{'property.read'}),
        isEmpty,
        reason: 'Szenarien and Performance wait for their own contracts',
      );
    });
  });

  group('Investment domain', () {
    testWidgets('mounts the injected valuation surface under its own chip', (
      tester,
    ) async {
      final built = <PropertyInvestmentSubArea>[];
      final propertyIds = <String>[];
      await _pump(
        tester,
        permissions: _withValuation,
        investmentBuilder: (context, propertyId, subArea) {
          built.add(subArea);
          propertyIds.add(propertyId);
          return const SizedBox(key: Key('fake-valuation-surface'));
        },
      );

      await tester.tap(
        find.byKey(const Key('property-workspace-nav-investment')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('property-investment')), findsOneWidget);
      expect(
        find.byKey(const Key('property-investment-sub-valuation')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('fake-valuation-surface')), findsOneWidget);
      expect(built, <PropertyInvestmentSubArea>[
        PropertyInvestmentSubArea.valuation,
      ]);
      expect(propertyIds, contains('property-a'));
      // The asset edit action belongs to the Objekt domain only.
      expect(find.byKey(const Key('property-workspace-edit')), findsNothing);
    });

    testWidgets('without valuation.read there is no Investment entry', (
      tester,
    ) async {
      await _pump(
        tester,
        permissions: fullPermissions,
        investmentBuilder:
            (context, propertyId, subArea) =>
                const SizedBox(key: Key('fake-valuation-surface')),
      );

      expect(
        find.byKey(const Key('property-workspace-nav-investment')),
        findsNothing,
      );
      expect(find.text('Investment'), findsNothing);
    });

    testWidgets('a host that cannot build it does not offer it', (
      tester,
    ) async {
      await _pump(tester, permissions: _withValuation);

      expect(
        find.byKey(const Key('property-workspace-nav-investment')),
        findsNothing,
        reason: 'a permitted domain with no builder would be an empty frame',
      );
    });

    testWidgets('has no overflow on a phone', (tester) async {
      await _pump(
        tester,
        permissions: _withValuation,
        investmentBuilder:
            (context, propertyId, subArea) =>
                const SizedBox(key: Key('fake-valuation-surface')),
        viewport: const Size(390, 844),
      );

      await tester.tap(
        find.byKey(const Key('property-workspace-nav-investment')),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('property-investment')), findsOneWidget);
    });
  });
}
