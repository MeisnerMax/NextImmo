import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_workspace_host_state.dart';
import 'package:neximmo_app/features/portfolio_property/presentation/property_workspace_screen.dart';

import 'property_workspace_fixtures.dart';

/// `Aktivität` as a workspace domain (AUDIT-01,
/// `PROPERTY_ACTIVITY_REPORTS_V2.md`).
///
/// The domain exists to answer "what happened to this property". Its first and
/// only child today is the audit trail, so the rule under test is the same one
/// every other domain follows: it appears when something inside it can be
/// opened, and stays absent otherwise — never as an empty frame.
Future<void> _pump(
  WidgetTester tester, {
  required Set<String> permissions,
  Widget Function(BuildContext, String, PropertyActivitySubArea)?
  activityBuilder,
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
        activityBuilder: activityBuilder,
      ),
    ),
  );
  await tester.pump();
}

const Set<String> _withAudit = <String>{
  'property.read',
  'property.update',
  'audit.read',
};

void main() {
  group('Aktivität registration', () {
    test('is gated by the read capability of its one implemented child', () {
      expect(
        visiblePropertyWorkspaceDomains(
          _withAudit,
        ).map((registration) => registration.domain),
        contains(PropertyWorkspaceDomain.activity),
      );
      expect(
        visiblePropertyWorkspaceDomains(const <String>{
          'property.read',
        }).map((registration) => registration.domain),
        isNot(contains(PropertyWorkspaceDomain.activity)),
      );
    });

    test('Protokoll is the only sub-area today', () {
      expect(visiblePropertyActivitySubAreas(_withAudit), <
        PropertyActivitySubArea
      >[PropertyActivitySubArea.audit]);
      expect(
        visiblePropertyActivitySubAreas(const <String>{'property.read'}),
        isEmpty,
        reason: 'the cross-domain timeline waits for PROPERTY-ACTIVITY-01',
      );
    });
  });

  group('Aktivität domain', () {
    testWidgets('mounts the injected audit surface under its own chip', (
      tester,
    ) async {
      final built = <PropertyActivitySubArea>[];
      final propertyIds = <String>[];
      await _pump(
        tester,
        permissions: _withAudit,
        activityBuilder: (context, propertyId, subArea) {
          built.add(subArea);
          propertyIds.add(propertyId);
          return const SizedBox(key: Key('fake-audit-surface'));
        },
      );

      await tester.tap(
        find.byKey(const Key('property-workspace-nav-activity')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('property-activity')), findsOneWidget);
      expect(
        find.byKey(const Key('property-activity-sub-audit')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('fake-audit-surface')), findsOneWidget);
      expect(built, <PropertyActivitySubArea>[PropertyActivitySubArea.audit]);
      expect(propertyIds, contains('property-a'));
      expect(find.byKey(const Key('property-workspace-edit')), findsNothing);
    });

    testWidgets('without audit.read there is no Aktivität entry', (
      tester,
    ) async {
      await _pump(
        tester,
        permissions: fullPermissions,
        activityBuilder:
            (context, propertyId, subArea) =>
                const SizedBox(key: Key('fake-audit-surface')),
      );

      expect(
        find.byKey(const Key('property-workspace-nav-activity')),
        findsNothing,
      );
      expect(find.text('Aktivität'), findsNothing);
    });

    testWidgets('a host that cannot build it does not offer it', (
      tester,
    ) async {
      await _pump(tester, permissions: _withAudit);

      expect(
        find.byKey(const Key('property-workspace-nav-activity')),
        findsNothing,
        reason: 'a permitted domain with no builder would be an empty frame',
      );
    });

    testWidgets('has no overflow on a phone', (tester) async {
      await _pump(
        tester,
        permissions: _withAudit,
        activityBuilder:
            (context, propertyId, subArea) =>
                const SizedBox(key: Key('fake-audit-surface')),
        viewport: const Size(390, 844),
      );

      await tester.tap(
        find.byKey(const Key('property-workspace-nav-activity')),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('property-activity')), findsOneWidget);
    });
  });
}
