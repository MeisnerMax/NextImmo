import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/valuation/application/valuation_case_controller.dart';
import 'package:neximmo_app/features/valuation/application/valuation_providers.dart';
import 'package:neximmo_app/features/valuation/application/valuation_repository.dart';
import 'package:neximmo_app/features/valuation/domain/cash_flow_projection.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_case_dto.dart';
import 'package:neximmo_app/features/valuation/domain/valuation_method.dart';
import 'package:neximmo_app/ui/screens/valuations/valuations_screen.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

ValuationCaseDto _caseDto({
  String id = 'case-1',
  String title = 'Musterfall MFH',
  ValuationCaseKind kind = ValuationCaseKind.holding,
  ValuationCaseStatus status = ValuationCaseStatus.draft,
  DateTime? updatedAt,
}) => ValuationCaseDto(
  id: id,
  workspaceId: 'ws-1',
  propertyId: 'prop-1',
  title: title,
  kind: kind,
  status: status,
  dcfTerminal: DcfTerminalMethod.exitCap,
  enabledMethods: const {ValuationMethodKind.incomeApproachDe},
  createdAt: DateTime.utc(2026, 7, 1),
  updatedAt: updatedAt ?? DateTime.utc(2026, 7, 28),
  createdBy: 'user-1',
  updatedBy: 'user-1',
  version: 2,
);

class _FakeRepository implements ValuationCaseRepository {
  _FakeRepository({this.pages = const [], this.failure});

  /// One entry per call, so paging and filter reloads can return different sets.
  List<ValuationPageResult<ValuationCaseDto>> pages;
  ValuationRepositoryFailure<Object?>? failure;

  final queries = <ValuationCaseListQuery>[];
  int _call = 0;

  @override
  Future<ValuationRepositoryResult<ValuationPageResult<ValuationCaseDto>>>
  searchValuationCases(ValuationCaseListQuery query) async {
    queries.add(query);
    final f = failure;
    if (f != null) {
      return ValuationRepositoryFailure<ValuationPageResult<ValuationCaseDto>>(
        kind: f.kind,
        message: f.message,
      );
    }
    final page = _call < pages.length ? pages[_call] : pages.last;
    _call++;
    return ValuationRepositorySuccess(page);
  }

  @override
  Future<ValuationRepositoryResult<ValuationCaseDetail>> getValuationCaseById({
    required String workspaceId,
    required String valuationCaseId,
  }) async => throw UnimplementedError();

  @override
  Future<ValuationRepositoryResult<ValuationCaseDetail>> createValuationCase(
    CreateValuationCaseCommand command,
  ) async => throw UnimplementedError();

  @override
  Future<ValuationRepositoryResult<ValuationCaseDetail>> updateValuationCase(
    UpdateValuationCaseCommand command,
  ) async => throw UnimplementedError();

  @override
  Future<ValuationRepositoryResult<ValuationCaseDetail>> createValuationVariant(
    CreateValuationVariantCommand command,
  ) async => throw UnimplementedError();

  @override
  Future<ValuationRepositoryResult<ValuationCaseDto>>
  transitionValuationCaseStatus(
    TransitionValuationCaseStatusCommand command,
  ) async => throw UnimplementedError();
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeRepository repository,
  Set<String> permissions = const {
    ValuationPermissions.read,
    ValuationPermissions.manage,
  },
  bool mutationsSupported = true,
  void Function(ValuationCaseDto)? onOpenCase,
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        valuationCaseRepositoryProvider.overrideWithValue(repository),
        workspaceSessionScopeProvider.overrideWithValue(
          WorkspaceSessionScope(
            workspaceId: 'ws-1',
            actorId: 'user-1',
            permissions: permissions,
            mutationsSupported: mutationsSupported,
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: ValuationsScreen(onOpenCase: onOpenCase)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists the workspace cases with status and kind', (tester) async {
    final repository = _FakeRepository(
      pages: <ValuationPageResult<ValuationCaseDto>>[
        ValuationPageResult<ValuationCaseDto>(
          items: <ValuationCaseDto>[
            _caseDto(),
            _caseDto(
              id: 'case-2',
              title: 'Verkauf Nordstadt',
              kind: ValuationCaseKind.disposition,
              status: ValuationCaseStatus.inReview,
            ),
          ],
        ),
      ],
    );

    await _pump(tester, repository: repository);

    expect(find.text('Musterfall MFH'), findsOneWidget);
    expect(find.text('Verkauf Nordstadt'), findsOneWidget);
    expect(find.text('Verkauf'), findsOneWidget);
    expect(find.text('In Prüfung'), findsOneWidget);
    // The queue's reason for existing: what is waiting for a decision.
    expect(find.textContaining('1 zur Prüfung'), findsOneWidget);
  });

  testWidgets('a row selection opens the case', (tester) async {
    final opened = <String>[];
    final repository = _FakeRepository(
      pages: <ValuationPageResult<ValuationCaseDto>>[
        ValuationPageResult<ValuationCaseDto>(
          items: <ValuationCaseDto>[_caseDto()],
        ),
      ],
    );

    await _pump(
      tester,
      repository: repository,
      onOpenCase: (entry) => opened.add(entry.id),
    );
    await tester.tap(find.text('Musterfall MFH'));
    await tester.pumpAndSettle();

    expect(opened, <String>['case-1']);
  });

  testWidgets('the status filter goes to the server, not the client',
      (tester) async {
    final repository = _FakeRepository(
      pages: <ValuationPageResult<ValuationCaseDto>>[
        ValuationPageResult<ValuationCaseDto>(
          items: <ValuationCaseDto>[_caseDto()],
        ),
      ],
    );

    await _pump(tester, repository: repository);
    await tester.tap(find.text('Status: alle').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('In Prüfung').last);
    await tester.pumpAndSettle();

    expect(repository.queries.last.status, ValuationCaseStatus.inReview);
  });

  testWidgets('an empty filter result reads differently from no data at all',
      (tester) async {
    final repository = _FakeRepository(
      pages: <ValuationPageResult<ValuationCaseDto>>[
        const ValuationPageResult<ValuationCaseDto>(
          items: <ValuationCaseDto>[],
        ),
      ],
    );

    await _pump(tester, repository: repository);
    expect(find.text('Noch keine Bewertungen'), findsOneWidget);

    await tester.tap(find.text('Archivierte einschließen'));
    await tester.pumpAndSettle();

    expect(find.text('Keine Bewertung für diesen Filter'), findsOneWidget);
  });

  testWidgets('loads the next page on demand', (tester) async {
    final repository = _FakeRepository(
      pages: <ValuationPageResult<ValuationCaseDto>>[
        ValuationPageResult<ValuationCaseDto>(
          items: <ValuationCaseDto>[_caseDto()],
          nextCursor: '2026-07-28T00:00:00.000Z|case-1',
        ),
        ValuationPageResult<ValuationCaseDto>(
          items: <ValuationCaseDto>[_caseDto(id: 'case-2', title: 'Zweiter')],
        ),
      ],
    );

    await _pump(tester, repository: repository);
    await tester.tap(find.text('Weitere Bewertungen laden'));
    await tester.pumpAndSettle();

    expect(find.text('Musterfall MFH'), findsOneWidget);
    expect(find.text('Zweiter'), findsOneWidget);
    expect(repository.queries.last.page.cursor, isNotNull);
  });

  testWidgets('forbidden is its own state, not an empty list', (tester) async {
    final repository = _FakeRepository(
      failure: const ValuationRepositoryFailure<Object?>(
        kind: ValuationRepositoryFailureKind.forbidden,
        message: 'Kein Zugriff.',
      ),
    );

    await _pump(tester, repository: repository);

    expect(find.text('Kein Zugriff auf Bewertungen'), findsOneWidget);
    expect(find.text('Noch keine Bewertungen'), findsNothing);
  });

  testWidgets('an error offers a retry', (tester) async {
    final repository = _FakeRepository(
      failure: const ValuationRepositoryFailure<Object?>(
        kind: ValuationRepositoryFailureKind.infrastructureFailure,
        message: 'Verbindung fehlgeschlagen.',
      ),
    );

    await _pump(tester, repository: repository);

    expect(find.text('Erneut versuchen'), findsOneWidget);
  });

  testWidgets('without the read permission nothing is queried', (tester) async {
    final repository = _FakeRepository();

    await _pump(tester, repository: repository, permissions: const {});

    expect(repository.queries, isEmpty);
    expect(find.text('Kein Zugriff auf Bewertungen'), findsOneWidget);
  });

  testWidgets('the read-only backend says why nothing can be created',
      (tester) async {
    // Regression: the screen used to hide the action and leave an empty
    // surface, which reads as a missing feature rather than a bound backend
    // that cannot write.
    final repository = _FakeRepository(
      pages: <ValuationPageResult<ValuationCaseDto>>[
        const ValuationPageResult<ValuationCaseDto>(
          items: <ValuationCaseDto>[],
        ),
      ],
    );

    await _pump(tester, repository: repository, mutationsSupported: false);

    expect(find.textContaining('schreibgeschützt'), findsOneWidget);
    expect(find.textContaining('Supabase-Modus'), findsWidgets);
    expect(find.text('Bewertung anlegen'), findsNothing);
  });

  testWidgets('the read-only backend offers no create action', (tester) async {
    final repository = _FakeRepository(
      pages: <ValuationPageResult<ValuationCaseDto>>[
        ValuationPageResult<ValuationCaseDto>(
          items: <ValuationCaseDto>[_caseDto()],
        ),
      ],
    );

    await _pump(tester, repository: repository, mutationsSupported: false);

    expect(find.text('Neue Bewertung'), findsNothing);
  });

  group('responsive', () {
    for (final size in const <Size>[
      Size(390, 844),
      Size(1024, 768),
      Size(1440, 900),
    ]) {
      testWidgets('renders without overflow at ${size.width.toInt()}px',
          (tester) async {
        final repository = _FakeRepository(
          pages: <ValuationPageResult<ValuationCaseDto>>[
            ValuationPageResult<ValuationCaseDto>(
              items: <ValuationCaseDto>[_caseDto()],
            ),
          ],
        );

        await _pump(tester, repository: repository, size: size);

        expect(tester.takeException(), isNull);
        expect(find.text('Bewertungen'), findsWidgets);
      });
    }
  });
}
