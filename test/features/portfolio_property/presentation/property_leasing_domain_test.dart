import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_workspace_host_state.dart';
import 'package:neximmo_app/features/portfolio_property/presentation/property_workspace_screen.dart';

import 'property_workspace_fixtures.dart';

/// `Vermietung` in the workspace host (`PROPERTY_LEASING_V2`).
///
/// The four Welle-3 panels are rehosted unchanged; what is new — and therefore
/// what is proven here — is the domain gate, the sub-navigation and the
/// host state that remembers the last sub-area per domain.
void main() {
  group('Leasing domain registration', () {
    test('is registered and gated by lease.read', () {
      final leasing = registeredPropertyWorkspaceDomains.firstWhere(
        (entry) => entry.domain == PropertyWorkspaceDomain.leasing,
      );
      expect(leasing.label, 'Vermietung');
      expect(leasing.readPermission, 'lease.read');
    });

    test('carries exactly the four spec sub-areas in reading order', () {
      expect(PropertyLeasingSubArea.values, <PropertyLeasingSubArea>[
        PropertyLeasingSubArea.units,
        PropertyLeasingSubArea.leases,
        PropertyLeasingSubArea.pipeline,
        PropertyLeasingSubArea.rentRoll,
      ]);
      expect(PropertyLeasingSubArea.values.map((s) => s.label), <String>[
        'Flächen',
        'Verträge',
        'Pipeline',
        'Rent Roll',
      ]);
      expect(
        PropertyLeasingSubArea.values.length,
        lessThanOrEqualTo(4),
        reason: 'a domain carries at most four sub-areas',
      );
    });

    test('stays hidden without lease.read', () {
      expect(
        visiblePropertyWorkspaceDomains(<String>{
          'property.read',
        }).map((entry) => entry.domain),
        isNot(contains(PropertyWorkspaceDomain.leasing)),
      );
      expect(
        visiblePropertyWorkspaceDomains(<String>{
          'property.read',
          'lease.read',
        }).map((entry) => entry.domain),
        contains(PropertyWorkspaceDomain.leasing),
      );
    });
  });

  group('Host state sub-areas', () {
    test('remembers one sub-area per domain and serializes it', () {
      const initial = PropertyWorkspaceHostState();
      expect(initial.subAreaOf(PropertyWorkspaceDomain.leasing), isNull);

      final withLeasing = initial.withSubArea(
        PropertyWorkspaceDomain.leasing,
        'pipeline',
      );
      final withBoth = withLeasing.withSubArea(
        PropertyWorkspaceDomain.operations,
        'tasks',
      );

      expect(withBoth.subAreaOf(PropertyWorkspaceDomain.leasing), 'pipeline');
      expect(withBoth.subAreaOf(PropertyWorkspaceDomain.operations), 'tasks');
      expect(
        withLeasing.subAreaOf(PropertyWorkspaceDomain.operations),
        isNull,
        reason: 'the earlier state is not mutated',
      );
      expect((withBoth.toJson()['subAreas'] as Map)['leasing'], 'pipeline');
    });

    test('equality and hash are order independent', () {
      final a = const PropertyWorkspaceHostState()
          .withSubArea(PropertyWorkspaceDomain.leasing, 'leases')
          .withSubArea(PropertyWorkspaceDomain.operations, 'tasks');
      final b = const PropertyWorkspaceHostState()
          .withSubArea(PropertyWorkspaceDomain.operations, 'tasks')
          .withSubArea(PropertyWorkspaceDomain.leasing, 'leases');

      expect(a, b);
      expect(a.hashCode, b.hashCode);

      final c = a.withSubArea(PropertyWorkspaceDomain.leasing, 'pipeline');
      expect(a, isNot(c));
    });
  });

  group('Leasing domain in the workspace', () {
    testWidgets('appears in the domain navigation and opens on Flächen', (
      tester,
    ) async {
      final built = <PropertyLeasingSubArea>[];
      await _pump(tester, _leasingPermissions(), built);

      expect(
        find.byKey(const Key('property-workspace-nav-leasing')),
        findsOneWidget,
      );
      await _openLeasing(tester);

      expect(find.byKey(const Key('property-leasing')), findsOneWidget);
      expect(find.byKey(const Key('property-leasing-sub-nav')), findsOneWidget);
      for (final label in const <String>[
        'Flächen',
        'Verträge',
        'Pipeline',
        'Rent Roll',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(
        built.last,
        PropertyLeasingSubArea.units,
        reason: 'the first sub-area is the default',
      );
    });

    testWidgets('switching a sub-area rebuilds only that panel', (
      tester,
    ) async {
      final built = <PropertyLeasingSubArea>[];
      await _pump(tester, _leasingPermissions(), built);
      await _openLeasing(tester);

      await tester.tap(find.byKey(const Key('property-leasing-sub-rentRoll')));
      await tester.pumpAndSettle();

      expect(built.last, PropertyLeasingSubArea.rentRoll);
      expect(
        find.byKey(const Key('property-leasing-content-rentRoll')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('property-leasing-content-units')),
        findsNothing,
      );
    });

    testWidgets('leaving and re-entering the domain lands on the same '
        'sub-area', (tester) async {
      final built = <PropertyLeasingSubArea>[];
      await _pump(tester, _leasingPermissions(), built);
      await _openLeasing(tester);
      await tester.tap(find.byKey(const Key('property-leasing-sub-pipeline')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('property-workspace-nav-asset')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('property-asset')), findsOneWidget);

      await _openLeasing(tester);
      expect(
        built.last,
        PropertyLeasingSubArea.pipeline,
        reason: 'the domain remembers where the user left it',
      );
    });

    testWidgets('is absent from the navigation without lease.read', (
      tester,
    ) async {
      await _pump(tester, const <String>{
        'property.read',
        'property.update',
      }, <PropertyLeasingSubArea>[]);

      expect(
        find.byKey(const Key('property-workspace-nav-leasing')),
        findsNothing,
      );
      expect(find.text('Vermietung'), findsNothing);
    });

    for (final viewport in const <Size>[
      Size(320, 700),
      Size(390, 844),
      Size(768, 1024),
      Size(1440, 900),
    ]) {
      testWidgets('sub-navigation has no overflow at $viewport', (
        tester,
      ) async {
        await _pump(
          tester,
          _leasingPermissions(),
          <PropertyLeasingSubArea>[],
          viewport: viewport,
        );
        await _openLeasing(tester);

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const Key('property-leasing-sub-nav')),
          findsOneWidget,
        );
      });
    }
  });
}

Set<String> _leasingPermissions() => const <String>{
  'property.read',
  'property.update',
  'lease.read',
};

Future<void> _openLeasing(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('property-workspace-nav-leasing')));
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  Set<String> permissions,
  List<PropertyLeasingSubArea> built, {
  Size viewport = const Size(1440, 900),
}) async {
  setViewport(tester, viewport);
  await tester.pumpWidget(
    wrapApp(
      PropertyWorkspaceView(
        state: detailState(permissions: permissions),
        onOpenProperty: (_) async => true,
        onCloseProperty: () {},
        onLoadMore: () async {},
        onReload: () async {},
        onSetIncludeArchived: (_) async {},
        onRefreshWorkspaces: () async {},
        onUpdateProperty: (_, {expectedVersion}) async => true,
        onRetryUpdate: () async {},
        // A stand-in for the real Welle-3 panels: this test proves the host
        // wiring, not the panels' own behaviour, which their own tests cover.
        leasingBuilder: (context, propertyId, subArea) {
          built.add(subArea);
          return Center(
            key: Key('property-leasing-content-${subArea.name}'),
            child: Text('$propertyId/${subArea.name}'),
          );
        },
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}
