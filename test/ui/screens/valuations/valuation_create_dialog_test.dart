import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/property.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/valuation/application/valuation_case_controller.dart';
import 'package:neximmo_app/features/valuation/application/valuation_providers.dart';
import 'package:neximmo_app/features/valuation/application/valuation_repository.dart';
import 'package:neximmo_app/features/valuation/domain/cash_flow_projection.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case_dto.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_factor_ids.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_method.dart';
import 'package:neximmo_app/ui/screens/valuations/valuation_create_dialog.dart';
import 'package:neximmo_app/ui/state/property_state.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

PropertyRecord _property() => const PropertyRecord(
  id: 'prop-1',
  name: 'Objekt Alpha',
  addressLine1: 'Hauptstrasse 1',
  zip: '10115',
  city: 'Berlin',
  country: 'de',
  propertyType: 'residential',
  units: 12,
  createdAt: 1750000000000,
  updatedAt: 1760000000000,
);

class _CapturingRepository implements ValuationCaseRepository {
  _CapturingRepository({this.failure});

  final ValuationRepositoryFailure<Object?>? failure;
  final commands = <CreateValuationCaseCommand>[];

  @override
  Future<ValuationRepositoryResult<ValuationCaseDetail>> createValuationCase(
    CreateValuationCaseCommand command,
  ) async {
    commands.add(command);
    final f = failure;
    if (f != null) {
      return ValuationRepositoryFailure<ValuationCaseDetail>(
        kind: f.kind,
        message: f.message,
      );
    }
    return ValuationRepositorySuccess(
      ValuationCaseDetail(
        valuationCase: ValuationCaseDto(
          id: 'case-neu',
          workspaceId: 'ws-1',
          propertyId: command.propertyId,
          title: command.title,
          kind: command.kind,
          status: ValuationCaseStatus.draft,
          dcfTerminal: DcfTerminalMethod.exitCap,
          enabledMethods: command.enabledMethods ?? ValuationCase.allMethodKinds,
          createdAt: DateTime.utc(2026, 7, 30),
          updatedAt: DateTime.utc(2026, 7, 30),
          createdBy: 'user-1',
          updatedBy: 'user-1',
          version: 1,
        ),
        factors: const <ValuationFactorDto>[],
      ),
    );
  }

  @override
  Future<ValuationRepositoryResult<ValuationPageResult<ValuationCaseDto>>>
  searchValuationCases(ValuationCaseListQuery query) async =>
      throw UnimplementedError();

  @override
  Future<ValuationRepositoryResult<ValuationCaseDetail>> getValuationCaseById({
    required String workspaceId,
    required String valuationCaseId,
  }) async => throw UnimplementedError();

  @override
  Future<ValuationRepositoryResult<ValuationCaseDetail>> updateValuationCase(
    UpdateValuationCaseCommand command,
  ) async => throw UnimplementedError();

  @override
  Future<ValuationRepositoryResult<ValuationCaseDto>>
  transitionValuationCaseStatus(
    TransitionValuationCaseStatusCommand command,
  ) async => throw UnimplementedError();
}

class _StubProperties extends PropertiesController {
  @override
  Future<List<PropertyRecord>> build() async => <PropertyRecord>[_property()];
}

Future<String?> _openDialog(
  WidgetTester tester, {
  required _CapturingRepository repository,
  String? propertyId,
  bool mutationsSupported = true,
}) async {
  tester.view.physicalSize = const Size(1280, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  String? result;
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        valuationCaseRepositoryProvider.overrideWithValue(repository),
        propertiesControllerProvider.overrideWith(_StubProperties.new),
        workspaceSessionScopeProvider.overrideWithValue(
          WorkspaceSessionScope(
            workspaceId: 'ws-1',
            actorId: 'user-1',
            permissions: const <String>{
              ValuationPermissions.read,
              ValuationPermissions.manage,
            },
            mutationsSupported: mutationsSupported,
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) => ValuationCreateDialog(propertyId: propertyId),
                );
              },
              child: const Text('öffnen'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('öffnen'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('offers one case kind per template with its description',
      (tester) async {
    await _openDialog(
      tester,
      repository: _CapturingRepository(),
      propertyId: 'prop-1',
    );

    expect(find.text('Ankauf'), findsOneWidget);
    expect(find.text('Bestand'), findsOneWidget);
    expect(find.text('Sanierung'), findsOneWidget);
    expect(find.text('Verkauf'), findsOneWidget);
  });

  testWidgets('creates with the template methods and weights', (tester) async {
    final repository = _CapturingRepository();

    await _openDialog(tester, repository: repository, propertyId: 'prop-1');
    await tester.tap(find.text('Bestand'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bewertung anlegen'));
    await tester.pumpAndSettle();

    final command = repository.commands.single;
    expect(command.kind, ValuationCaseKind.holding);
    expect(command.propertyId, 'prop-1');
    expect(
      command.enabledMethods,
      isNot(contains(ValuationMethodKind.discountedCashFlow)),
    );
    expect(
      command.weightOverrides[ValuationMethodKind.incomeApproachDe],
      closeTo(0.55, 1e-9),
    );
    expect(command.context.reason, contains('Vorlage'));
  });

  testWidgets('a menu choice seeds unconfirmed suggestions', (tester) async {
    final repository = _CapturingRepository();

    await _openDialog(tester, repository: repository, propertyId: 'prop-1');
    await tester.tap(find.text('Assetklasse (optional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wohnen – Mehrfamilien').last);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('unbestätigter Vorschlag'),
      findsOneWidget,
      reason: 'der Dialog sagt, dass Vorschläge erst bestätigt werden müssen',
    );

    await tester.tap(find.text('Bewertung anlegen'));
    await tester.pumpAndSettle();

    final seeded = repository.commands.single.factors;
    expect(seeded, hasLength(1));
    expect(seeded.single.factorId, ValuationFactorIds.liegenschaftszinssatz);
    expect(seeded.single.provenance, FactorProvenance.suggestedDefault);
  });

  testWidgets('returns the new case id to the caller', (tester) async {
    final repository = _CapturingRepository();
    String? created;

    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          valuationCaseRepositoryProvider.overrideWithValue(repository),
          propertiesControllerProvider.overrideWith(_StubProperties.new),
          workspaceSessionScopeProvider.overrideWithValue(
            WorkspaceSessionScope(
              workspaceId: 'ws-1',
              actorId: 'user-1',
              permissions: const <String>{
                ValuationPermissions.read,
                ValuationPermissions.manage,
              },
              mutationsSupported: true,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  created = await showDialog<String>(
                    context: context,
                    builder: (_) =>
                        const ValuationCreateDialog(propertyId: 'prop-1'),
                  );
                },
                child: const Text('öffnen'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('öffnen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bewertung anlegen'));
    await tester.pumpAndSettle();

    expect(created, 'case-neu');
  });

  testWidgets('a read-only backend reports why nothing was created',
      (tester) async {
    final repository = _CapturingRepository();

    await _openDialog(
      tester,
      repository: repository,
      propertyId: 'prop-1',
      mutationsSupported: false,
    );
    await tester.tap(find.text('Bewertung anlegen'));
    await tester.pumpAndSettle();

    expect(repository.commands, isEmpty);
    expect(find.textContaining('schreibgeschützt'), findsOneWidget);
  });

  testWidgets('a server failure stays in the dialog with its message',
      (tester) async {
    final repository = _CapturingRepository(
      failure: const ValuationRepositoryFailure<Object?>(
        kind: ValuationRepositoryFailureKind.validationFailed,
        message: 'Objekt nicht in diesem Workspace.',
      ),
    );

    await _openDialog(tester, repository: repository, propertyId: 'prop-1');
    await tester.tap(find.text('Bewertung anlegen'));
    await tester.pumpAndSettle();

    expect(find.text('Objekt nicht in diesem Workspace.'), findsOneWidget);
    expect(find.text('Neue Bewertung'), findsOneWidget);
  });
}
