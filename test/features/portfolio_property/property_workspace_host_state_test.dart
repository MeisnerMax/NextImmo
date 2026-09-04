import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_workspace_host_state.dart';

void main() {
  group('PropertyWorkspaceDomain registry', () {
    test('carries the seven binding domains', () {
      expect(PropertyWorkspaceDomain.values, hasLength(7));
      expect(PropertyWorkspaceDomain.values, <PropertyWorkspaceDomain>[
        PropertyWorkspaceDomain.overview,
        PropertyWorkspaceDomain.asset,
        PropertyWorkspaceDomain.leasing,
        PropertyWorkspaceDomain.operations,
        PropertyWorkspaceDomain.documents,
        PropertyWorkspaceDomain.investment,
        PropertyWorkspaceDomain.activity,
      ]);
    });

    test('registers exactly the implemented domains: Objekt (A1), '
        'Betrieb (TASK-CENTER-01) and Dokumente (DOCUMENTS-COMPLETE-01)', () {
      expect(registeredPropertyWorkspaceDomains, hasLength(3));
      final asset = registeredPropertyWorkspaceDomains.first;
      expect(asset.domain, PropertyWorkspaceDomain.asset);
      expect(asset.label, 'Objekt');
      expect(asset.readPermission, 'property.read');
      final operations = registeredPropertyWorkspaceDomains[1];
      expect(operations.domain, PropertyWorkspaceDomain.operations);
      expect(operations.label, 'Betrieb');
      // Gated on the read permission of its one implemented child, the
      // property-scoped task surface; MAINTENANCE-PARITY-01 widens this.
      expect(operations.readPermission, 'task.read');
      // Documents: the property-scoped document panel, gated by the screen's
      // own read capability (PROPERTY_DOCUMENTS_V2.md §8).
      final documents = registeredPropertyWorkspaceDomains.last;
      expect(documents.domain, PropertyWorkspaceDomain.documents);
      expect(documents.label, 'Dokumente');
      expect(documents.readPermission, 'document.read');
      // Blocked or not yet implemented domains are absent, not disabled.
      expect(
        registeredPropertyWorkspaceDomains.map((d) => d.domain),
        isNot(contains(PropertyWorkspaceDomain.overview)),
      );
      expect(
        registeredPropertyWorkspaceDomains.map((d) => d.domain),
        isNot(contains(PropertyWorkspaceDomain.activity)),
      );
    });

    test('derives visible domains from read capabilities, fail closed', () {
      expect(
        visiblePropertyWorkspaceDomains(<String>{
          'property.read',
        }).map((d) => d.domain),
        <PropertyWorkspaceDomain>[PropertyWorkspaceDomain.asset],
      );
      expect(
        visiblePropertyWorkspaceDomains(<String>{
          'property.read',
          'task.read',
        }).map((d) => d.domain),
        <PropertyWorkspaceDomain>[
          PropertyWorkspaceDomain.asset,
          PropertyWorkspaceDomain.operations,
        ],
      );
      expect(visiblePropertyWorkspaceDomains(<String>{'lease.read'}), isEmpty);
      expect(visiblePropertyWorkspaceDomains(const <String>{}), isEmpty);
    });
  });

  group('PropertyWorkspaceHostState', () {
    test('defaults to the list with Objekt as the default domain', () {
      const state = PropertyWorkspaceHostState();
      expect(state.isPropertyOpen, isFalse);
      expect(state.openPropertyId, isNull);
      expect(state.domain, PropertyWorkspaceDomain.asset);
      expect(state.list, const PropertyListRestoreState());
    });

    test('keeps workspace-scoped list state across open and back', () {
      const list = PropertyListRestoreState(
        includeArchived: true,
        scrollOffset: 420.5,
        focusedPropertyId: 'property-b',
      );
      final opened = const PropertyWorkspaceHostState().copyWith(
        openPropertyId: 'property-b',
        list: list,
      );
      expect(opened.isPropertyOpen, isTrue);
      expect(opened.list.includeArchived, isTrue);

      final back = opened.copyWith(openPropertyId: null);
      expect(back.isPropertyOpen, isFalse);
      expect(back.list, list, reason: 'back restores the same list state');
      expect(back.domain, PropertyWorkspaceDomain.asset);
    });

    test('is serializable and deterministic', () {
      final state = const PropertyWorkspaceHostState().copyWith(
        openPropertyId: 'property-a',
        list: const PropertyListRestoreState(
          includeArchived: false,
          scrollOffset: 12,
          focusedPropertyId: 'property-a',
        ),
      );
      expect(state.toJson(), <String, Object?>{
        'openPropertyId': 'property-a',
        'domain': 'asset',
        'list': <String, Object?>{
          'includeArchived': false,
          'scrollOffset': 12.0,
          'focusedPropertyId': 'property-a',
        },
      });
      expect(
        state,
        const PropertyWorkspaceHostState().copyWith(
          openPropertyId: 'property-a',
          list: const PropertyListRestoreState(
            scrollOffset: 12,
            focusedPropertyId: 'property-a',
          ),
        ),
      );
      expect(state.hashCode, state.copyWith().hashCode);
    });

    test('copyWith clears the focused property explicitly', () {
      const list = PropertyListRestoreState(focusedPropertyId: 'property-a');
      expect(list.copyWith().focusedPropertyId, 'property-a');
      expect(list.copyWith(focusedPropertyId: null).focusedPropertyId, isNull);
    });
  });

  group('PropertyWorkspaceDirtyRegistry', () {
    test('reports the active child and ignores stale unregisters', () {
      final registry = PropertyWorkspaceDirtyRegistry();
      expect(registry.hasUnsavedChanges, isFalse);
      expect(registry.child, isNull);

      final first = _Child(dirty: true);
      final second = _Child(dirty: false);
      registry.register(first);
      expect(registry.hasUnsavedChanges, isTrue);

      registry.register(second);
      registry.unregister(first);
      expect(
        registry.child,
        same(second),
        reason: 'a replaced child must not clear its successor',
      );
      expect(registry.hasUnsavedChanges, isFalse);

      registry.unregister(second);
      expect(registry.child, isNull);
    });
  });
}

class _Child implements PropertyWorkspaceDirtyChild {
  _Child({required this.dirty});

  final bool dirty;

  @override
  bool get hasUnsavedChanges => dirty;

  @override
  Future<bool> saveChanges() async => true;

  @override
  void discardChanges() {}
}
