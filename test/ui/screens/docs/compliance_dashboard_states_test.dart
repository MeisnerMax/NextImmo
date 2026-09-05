import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/documents_compliance/application/compliance_dashboard_controller.dart';
import 'package:neximmo_app/features/documents_compliance/application/document_providers.dart';
import 'package:neximmo_app/features/documents_compliance/application/document_repository.dart';
import 'package:neximmo_app/features/documents_compliance/domain/document_dto.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_overview_dto.dart';
import 'package:neximmo_app/ui/screens/docs/compliance_dashboard_screen.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// Mandatory-state coverage for the rebuilt compliance dashboard (SCR-052,
/// Phase 2, Wave 2, Arbeitspaket 2). Mirrors the wave's test pattern from
/// `parties_screen_states_test.dart`, including its `buttonWithText<T>` helper.
///
/// The states that matter most here are the ones the old screen had no answer
/// for: `forbidden` as its own state, a *positive* empty state, and the two
/// coverage notices — because a compliance view that silently omits rows is
/// worse than one that admits what it did not check.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String workspace = 'ws-1';

  /// `find.byType` matches the exact runtime type, so the private `*.icon`
  /// button subclasses would slip through. Match by `is` instead.
  Finder buttonWithText<T extends Widget>(String text) {
    return find.ancestor(
      of: find.text(text),
      matching: find.byWidgetPredicate((widget) => widget is T),
    );
  }

  WorkspaceSessionScope scope() {
    return WorkspaceSessionScope(
      workspaceId: workspace,
      actorId: 'actor-1',
      permissions: const <String>{'document.read'},
      mutationsSupported: true,
    );
  }

  DocumentRequirementProjection requirement({
    required String entityId,
    required DocumentRequirementState state,
    String name = 'Energieausweis',
    bool isMandatory = true,
  }) {
    return DocumentRequirementProjection(
      requirementId: 'req-$entityId-$name',
      documentTypeId: 'type-1',
      documentTypeKey: 'energy_certificate',
      documentTypeName: name,
      entityType: DocumentLinkEntityType.property,
      entityId: entityId,
      isMandatory: isMandatory,
      isInstanceRule: false,
      state: state,
    );
  }

  Future<ProviderContainer> pumpDashboard(
    WidgetTester tester, {
    required _FakeRequirementBackend backend,
    _FakePropertyDirectory? directory,
    ComplianceOpenCallback? onOpen,
    Size size = const Size(1440, 900),
    AppDensityModeSetting density = AppDensityModeSetting.comfort,
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          workspaceSessionScopeProvider.overrideWithValue(scope()),
          requirementPolicyProvider.overrideWithValue(backend),
          complianceObjectDirectoryProvider.overrideWithValue(directory),
        ],
        child: MaterialApp(
          theme: AppTheme.light(densityMode: density),
          home: Scaffold(
            body: ComplianceDashboardScreen(onOpenRequirement: onOpen),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    }
    return ProviderScope.containerOf(
      tester.element(find.byType(ComplianceDashboardScreen)),
    );
  }

  testWidgets('loading shows a skeleton, not a full-page spinner', (
    tester,
  ) async {
    final backend = _FakeRequirementBackend()..hold();
    await pumpDashboard(tester, backend: backend, settle: false);
    await tester.pump();

    expect(
      find.byKey(const Key('documents-compliance-loading')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // The filter stays usable while the projection loads.
    expect(
      find.byKey(const Key('documents-compliance-only-unmet')),
      findsOneWidget,
    );

    backend.release();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'nothing outstanding reads as a positive result, not as no data',
    (tester) async {
      final container = await pumpDashboard(
        tester,
        backend: _FakeRequirementBackend(),
      );
      await container
          .read(complianceDashboardControllerProvider.notifier)
          .setOnlyUnmet(true);
      await tester.pumpAndSettle();

      expect(find.text('Alles erfüllt'), findsOneWidget);
      expect(find.textContaining('Zuletzt geprüft'), findsOneWidget);
    },
  );

  testWidgets('an empty rule set is not dressed up as compliance', (
    tester,
  ) async {
    await pumpDashboard(tester, backend: _FakeRequirementBackend());

    // Without the "only outstanding" filter, an empty projection means no rules
    // are defined — which is not the same as everything being satisfied.
    expect(find.text('Keine Anforderungen hinterlegt'), findsOneWidget);
    expect(find.text('Alles erfüllt'), findsNothing);
  });

  testWidgets(
    'infrastructure failure offers retry without raw exception text',
    (tester) async {
      await pumpDashboard(
        tester,
        backend: _FakeRequirementBackend(
          failure:
              const DocumentRepositoryFailure<WorkspaceDocumentRequirements>(
                kind: DocumentRepositoryFailureKind.infrastructureFailure,
                message: 'Exception: socket closed',
              ),
        ),
      );

      expect(
        find.text('Compliance konnte nicht ausgewertet werden'),
        findsOneWidget,
      );
      expect(find.text('Erneut versuchen'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
    },
  );

  testWidgets('forbidden is its own state, distinct from empty and error', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      backend: _FakeRequirementBackend(
        failure: const DocumentRepositoryFailure<WorkspaceDocumentRequirements>(
          kind: DocumentRepositoryFailureKind.forbidden,
          message: 'document.read missing',
        ),
      ),
    );

    expect(find.text('Kein Zugriff auf Compliance'), findsOneWidget);
    expect(find.text('Keine Anforderungen hinterlegt'), findsNothing);
    expect(
      find.text('Compliance konnte nicht ausgewertet werden'),
      findsNothing,
    );
  });

  testWidgets('findings are grouped by object name, not by raw id', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      backend: _FakeRequirementBackend(
        requirements: <DocumentRequirementProjection>[
          requirement(entityId: 'p-1', state: DocumentRequirementState.missing),
        ],
      ),
      directory: _FakePropertyDirectory(
        properties: <String, String>{'p-1': 'Hauptstrasse 1'},
      ),
    );

    expect(find.text('Hauptstrasse 1'), findsOneWidget);
    expect(find.text('p-1'), findsNothing);
    expect(find.text('Fehlt'), findsOneWidget);
  });

  testWidgets('the object directory is contributed in one call, not per row', (
    tester,
  ) async {
    final backend = _FakeRequirementBackend(
      requirements: <DocumentRequirementProjection>[
        requirement(entityId: 'p-1', state: DocumentRequirementState.missing),
        requirement(entityId: 'p-2', state: DocumentRequirementState.expiring),
      ],
    );
    await pumpDashboard(
      tester,
      backend: backend,
      directory: _FakePropertyDirectory(
        properties: <String, String>{'p-1': 'Objekt A', 'p-2': 'Objekt B'},
      ),
    );

    // The whole reason the workspace RPC exists: one round trip for every
    // object, replacing the old per-property compliance loop.
    expect(backend.calls, hasLength(1));
    expect(backend.calls.single.entityIds, <String>['p-1', 'p-2']);
    expect(backend.calls.single.entityType, DocumentLinkEntityType.property);
  });

  testWidgets(
    'KPI tiles count the server states and separate the mandatory ones',
    (tester) async {
      await pumpDashboard(
        tester,
        backend: _FakeRequirementBackend(
          requirements: <DocumentRequirementProjection>[
            requirement(
              entityId: 'p-1',
              state: DocumentRequirementState.missing,
            ),
            requirement(
              entityId: 'p-2',
              state: DocumentRequirementState.missing,
              isMandatory: false,
              name: 'Optionaler Nachweis',
            ),
            requirement(
              entityId: 'p-3',
              state: DocumentRequirementState.expiring,
              name: 'Versicherung',
            ),
            requirement(
              entityId: 'p-4',
              state: DocumentRequirementState.satisfied,
              name: 'Kaufvertrag',
            ),
          ],
        ),
        directory: _FakePropertyDirectory(properties: const <String, String>{}),
      );

      // The tile labels deliberately reuse the status vocabulary, so the tiles
      // are identified by their unique sublabels instead.
      // NxKpiTile renders its label uppercased.
      expect(find.text('OFFEN'), findsOneWidget);
      // Two outstanding rows, but only one of them actually blocks.
      expect(find.text('davon 1 pflichtig'), findsOneWidget);
      expect(find.text('in 45 Tagen'), findsOneWidget);
      expect(find.text('verifiziert und gültig'), findsOneWidget);
      expect(find.text('Upload oder Verifikation offen'), findsOneWidget);
    },
  );

  testWidgets('scoped rules the server could not evaluate are reported', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      backend: _FakeRequirementBackend(
        requirements: <DocumentRequirementProjection>[
          requirement(entityId: 'p-1', state: DocumentRequirementState.missing),
        ],
        scopedRuleCount: 3,
      ),
      directory: _FakePropertyDirectory(
        properties: <String, String>{'p-1': 'Objekt A'},
      ),
    );

    expect(find.text('Nicht vollständig ausgewertet'), findsOneWidget);
    expect(find.textContaining('3 Regel(n)'), findsOneWidget);
  });

  testWidgets('a missing object directory is admitted, not hidden', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      backend: _FakeRequirementBackend(
        requirements: <DocumentRequirementProjection>[
          requirement(entityId: 'p-1', state: DocumentRequirementState.missing),
        ],
      ),
    );

    // No directory port bound: objects without a rule or a document cannot be
    // evaluated, and the screen says so instead of implying full coverage.
    expect(find.text('Eingeschränkte Abdeckung'), findsOneWidget);
  });

  testWidgets('a truncated object directory is reported as partial', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      backend: _FakeRequirementBackend(
        requirements: <DocumentRequirementProjection>[
          requirement(entityId: 'p-1', state: DocumentRequirementState.missing),
        ],
      ),
      directory: _FakePropertyDirectory(
        properties: <String, String>{'p-1': 'Objekt A'},
        alwaysHasMore: true,
      ),
    );

    expect(find.text('Teilweise ausgewertet'), findsOneWidget);
  });

  testWidgets(
    'a finding jumps to its object rather than pretending to fix it',
    (tester) async {
      final opened = <String>[];
      await pumpDashboard(
        tester,
        backend: _FakeRequirementBackend(
          requirements: <DocumentRequirementProjection>[
            requirement(
              entityId: 'p-1',
              state: DocumentRequirementState.missing,
            ),
          ],
        ),
        directory: _FakePropertyDirectory(
          properties: <String, String>{'p-1': 'Objekt A'},
        ),
        onOpen: (requirement) => opened.add(requirement.entityId),
      );

      await tester.tap(find.text('Energieausweis'));
      await tester.pumpAndSettle();

      expect(opened, <String>['p-1']);
    },
  );

  testWidgets('the outstanding filter is re-queried server-side', (
    tester,
  ) async {
    final backend = _FakeRequirementBackend(
      requirements: <DocumentRequirementProjection>[
        requirement(entityId: 'p-1', state: DocumentRequirementState.missing),
      ],
    );
    await pumpDashboard(
      tester,
      backend: backend,
      directory: _FakePropertyDirectory(
        properties: <String, String>{'p-1': 'Objekt A'},
      ),
    );

    await tester.tap(buttonWithText<OutlinedButton>('Nur offene anzeigen'));
    await tester.pumpAndSettle();

    // Filtering is part of the projection, not a view over a loaded list.
    expect(backend.calls, hasLength(2));
    expect(backend.calls.last.onlyUnmet, isTrue);
  });

  group('responsive', () {
    const sizes = <String, Size>{
      'phone 390x844': Size(390, 844),
      'tablet 1024x768': Size(1024, 768),
      'desktop 1440x900': Size(1440, 900),
    };

    for (final density in AppDensityModeSetting.values) {
      for (final entry in sizes.entries) {
        testWidgets('${entry.key} renders in ${density.name} density', (
          tester,
        ) async {
          await pumpDashboard(
            tester,
            backend: _FakeRequirementBackend(
              requirements: <DocumentRequirementProjection>[
                requirement(
                  entityId: 'p-1',
                  state: DocumentRequirementState.missing,
                ),
                requirement(
                  entityId: 'p-2',
                  state: DocumentRequirementState.expiring,
                  name: 'Versicherung',
                ),
              ],
            ),
            directory: _FakePropertyDirectory(
              properties: <String, String>{
                'p-1': 'Objekt A',
                'p-2': 'Objekt B',
              },
            ),
            size: entry.value,
            density: density,
          );

          expect(tester.takeException(), isNull);
          expect(find.text('Energieausweis'), findsOneWidget);
          expect(find.text('Versicherung'), findsOneWidget);
        });
      }
    }
  });
}

class _FakeRequirementBackend implements RequirementPolicyRepository {
  _FakeRequirementBackend({
    this.requirements = const <DocumentRequirementProjection>[],
    this.scopedRuleCount = 0,
    this.failure,
  });

  final List<DocumentRequirementProjection> requirements;
  final int scopedRuleCount;
  final DocumentRepositoryFailure<WorkspaceDocumentRequirements>? failure;

  final List<WorkspaceDocumentRequirementQuery> calls =
      <WorkspaceDocumentRequirementQuery>[];
  Completer<void>? _gate;

  void hold() => _gate = Completer<void>();

  void release() => _gate?.complete();

  @override
  Future<DocumentRepositoryResult<WorkspaceDocumentRequirements>>
  evaluateWorkspace(WorkspaceDocumentRequirementQuery query) async {
    calls.add(query);
    await _gate?.future;
    final error = failure;
    if (error != null) {
      return error;
    }
    return DocumentRepositorySuccess<WorkspaceDocumentRequirements>(
      WorkspaceDocumentRequirements(
        requirements:
            query.onlyUnmet
                ? requirements
                    .where(
                      (row) =>
                          row.state != DocumentRequirementState.satisfied &&
                          row.state != DocumentRequirementState.waived,
                    )
                    .toList(growable: false)
                : requirements,
        scopedRuleCount: scopedRuleCount,
      ),
    );
  }

  @override
  Future<DocumentRepositoryResult<List<DocumentRequirementProjection>>>
  evaluate(DocumentRequirementQuery query) async {
    return const DocumentRepositorySuccess<List<DocumentRequirementProjection>>(
      <DocumentRequirementProjection>[],
    );
  }

  @override
  Future<DocumentRepositoryResult<List<DocumentTypeDto>>> listTypes({
    required String workspaceId,
    bool activeOnly = true,
  }) async => const DocumentRepositorySuccess<List<DocumentTypeDto>>(
    <DocumentTypeDto>[],
  );

  @override
  Future<DocumentRepositoryResult<DocumentTypeDto>> upsertType(
    UpsertDocumentTypeCommand command,
  ) async => const DocumentRepositoryFailure<DocumentTypeDto>(
    kind: DocumentRepositoryFailureKind.forbidden,
    message: 'not used by this screen',
  );

  @override
  Future<DocumentRepositoryResult<List<RequiredDocumentDto>>> listRequirements({
    required String workspaceId,
    required DocumentLinkEntityType entityType,
    String? entityId,
  }) async => const DocumentRepositorySuccess<List<RequiredDocumentDto>>(
    <RequiredDocumentDto>[],
  );

  @override
  Future<DocumentRepositoryResult<RequiredDocumentDto>> upsertRequirement(
    UpsertRequiredDocumentCommand command,
  ) async => const DocumentRepositoryFailure<RequiredDocumentDto>(
    kind: DocumentRepositoryFailureKind.forbidden,
    message: 'not used by this screen',
  );
}

/// Stands in for the DOM-002 port: ids and names only, never its tables.
class _FakePropertyDirectory implements PropertyRepository {
  _FakePropertyDirectory({
    required this.properties,
    this.alwaysHasMore = false,
  });

  final Map<String, String> properties;

  /// Forces the paging bound to be hit, so the partial-coverage notice can be
  /// asserted without fabricating hundreds of fixtures.
  final bool alwaysHasMore;

  @override
  Future<PropertyRepositoryResult<PropertyPageResult>> list(
    PropertyListQuery query,
  ) async {
    return PropertyRepositorySuccess<PropertyPageResult>(
      PropertyPageResult(
        items: properties.entries
            .map(
              (entry) => PropertySummaryDto(
                id: entry.key,
                workspaceId: query.workspaceId,
                name: entry.value,
                addressLine1: 'Strasse 1',
                zip: '10115',
                city: 'Berlin',
                status: PropertyStatus.active,
                version: 1,
              ),
            )
            .toList(growable: false),
        nextCursor: alwaysHasMore ? 'more' : null,
      ),
    );
  }

  @override
  Future<PropertyRepositoryResult<PropertyOverviewDto>> overview({
    required String workspaceId,
    required String propertyId,
  }) async => const PropertyRepositoryFailure<PropertyOverviewDto>(
    kind: PropertyRepositoryFailureKind.forbidden,
    message: 'not used by this screen',
  );

  @override
  Future<PropertyRepositoryResult<PropertyDto>> getById({
    required String workspaceId,
    required String propertyId,
  }) async => const PropertyRepositoryFailure<PropertyDto>(
    kind: PropertyRepositoryFailureKind.notFound,
    message: 'not used by this screen',
  );

  @override
  Future<PropertyRepositoryResult<PropertyDto>> create(
    PropertyCreateCommand command,
  ) async => const PropertyRepositoryFailure<PropertyDto>(
    kind: PropertyRepositoryFailureKind.forbidden,
    message: 'not used by this screen',
  );

  @override
  Future<PropertyRepositoryResult<PropertyDto>> update(
    PropertyUpdateCommand command,
  ) async => const PropertyRepositoryFailure<PropertyDto>(
    kind: PropertyRepositoryFailureKind.forbidden,
    message: 'not used by this screen',
  );
}
