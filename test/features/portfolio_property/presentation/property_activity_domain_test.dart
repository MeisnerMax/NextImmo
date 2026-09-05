import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_workspace_host_state.dart';
import 'package:neximmo_app/features/portfolio_property/presentation/property_workspace_screen.dart';

import 'property_workspace_fixtures.dart';

/// `Aktivität` as a workspace domain (AUDIT-01, PROPERTY-ACTIVITY-01,
/// `PROPERTY_ACTIVITY_REPORTS_V2.md`).
///
/// The domain answers "what happened to this property" through two children
/// with deliberately different gates. `Aktivität` is the readable chronicle
/// and needs only `property.read`, because every row it shows was already
/// filtered against the domain permission it belongs to. `Protokoll` is the
/// forensic trail and needs `audit.read` on top, because it reports which
/// fields changed. The rule under test is the one every domain follows: it
/// appears when something inside it can be opened, never as an empty frame.
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
    test('opens for either of its two children', () {
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
        contains(PropertyWorkspaceDomain.activity),
        reason: 'the chronicle alone is enough to make the domain worth '
            'opening',
      );
      expect(
        visiblePropertyWorkspaceDomains(
          const <String>{},
        ).map((registration) => registration.domain),
        isNot(contains(PropertyWorkspaceDomain.activity)),
        reason: 'fail closed on an empty permission set',
      );
    });

    test('each child carries its own gate', () {
      expect(visiblePropertyActivitySubAreas(_withAudit), <
        PropertyActivitySubArea
      >[PropertyActivitySubArea.activity, PropertyActivitySubArea.audit]);
      expect(
        visiblePropertyActivitySubAreas(const <String>{'property.read'}),
        <PropertyActivitySubArea>[PropertyActivitySubArea.activity],
        reason: 'the chronicle needs no audit rights',
      );
      expect(
        visiblePropertyActivitySubAreas(const <String>{'audit.read'}),
        <PropertyActivitySubArea>[PropertyActivitySubArea.audit],
        reason: 'and the trail needs no property.read of its own here — the '
            'server still requires it',
      );
    });
  });

  group('Aktivität domain', () {
    testWidgets('mounts both children, each under its own chip', (
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
        find.byKey(const Key('property-activity-sub-activity')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('property-activity-sub-audit')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('fake-audit-surface')), findsOneWidget);
      expect(
        built,
        <PropertyActivitySubArea>[PropertyActivitySubArea.activity],
        reason: 'the chronicle is the landing child, not the trail',
      );
      expect(propertyIds, contains('property-a'));
      expect(find.byKey(const Key('property-workspace-edit')), findsNothing);
    });

    testWidgets('without audit.read the chronicle is still offered', (
      tester,
    ) async {
      final built = <PropertyActivitySubArea>[];
      await _pump(
        tester,
        permissions: fullPermissions,
        activityBuilder: (context, propertyId, subArea) {
          built.add(subArea);
          return const SizedBox(key: Key('fake-audit-surface'));
        },
      );

      expect(
        find.byKey(const Key('property-workspace-nav-activity')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('property-workspace-nav-activity')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('property-activity-sub-audit')),
        findsNothing,
        reason: 'the trail hides itself; the domain does not disappear with it',
      );
      expect(built, <PropertyActivitySubArea>[PropertyActivitySubArea.activity]);
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
