/// PROPERTY-CARD-METRICS-01: the page-at-a-time controller.
///
/// Three behaviours carry the weight here, and each one is a way the grid
/// could quietly mislead:
///
///   * asking once per page rather than once per card — the N+1 the package
///     exists to remove, and something a passing UI test would never notice;
///   * splitting a list longer than the server's cap, so a restored session
///     with several pages loaded keeps its numbers instead of losing all of
///     them to one refusal;
///   * remembering that a read failed, because a card with no figures and a
///     portfolio with nothing open look identical.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_card_metrics_controller.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_card_metrics_dto.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_dto.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_overview_dto.dart';

void main() {
  late _FakeRepository repository;

  PropertyCardMetricsController controller({String? workspaceId = 'ws-1'}) {
    return PropertyCardMetricsController(
      repository: repository,
      scope: workspaceId == null
          ? const WorkspaceSessionScope.unresolved()
          : WorkspaceSessionScope(
              workspaceId: workspaceId,
              actorId: 'actor-a',
              permissions: const <String>{'property.read'},
              mutationsSupported: true,
            ),
    );
  }

  setUp(() {
    repository = _FakeRepository();
  });

  test('one call for a whole page', () async {
    final subject = controller();

    await subject.ensure(<String>['p-1', 'p-2', 'p-3']);

    expect(repository.calls, 1);
    expect(repository.requestedIds.single, <String>['p-1', 'p-2', 'p-3']);
    expect(subject.state['p-2']!.leasing['units_total'], 4);
  });

  test('a rebuild does not re-ask for what it already has', () async {
    final subject = controller();

    await subject.ensure(<String>['p-1', 'p-2']);
    await subject.ensure(<String>['p-1', 'p-2']);

    expect(repository.calls, 1);
  });

  test('a new page asks only for the new properties', () async {
    final subject = controller();

    await subject.ensure(<String>['p-1', 'p-2']);
    await subject.ensure(<String>['p-1', 'p-2', 'p-3']);

    expect(repository.calls, 2);
    expect(repository.requestedIds.last, <String>['p-3']);
    expect(
      subject.state['p-1'],
      isNotNull,
      reason: 'and the first page keeps its numbers',
    );
  });

  test('a list longer than the server cap is split', () async {
    final subject = controller();
    final ids = <String>[for (int i = 0; i < 250; i++) 'p-$i'];

    await subject.ensure(ids);

    expect(repository.calls, 2);
    expect(repository.requestedIds.first, hasLength(200));
    expect(
      repository.requestedIds.last,
      hasLength(50),
      reason: 'the server refuses more than 200 in one call, so splitting here '
          'is what keeps a restored session from losing every number to one '
          'refusal',
    );
    expect(subject.state.metrics, hasLength(250));
  });

  test('a failed read is remembered, not swallowed', () async {
    repository.failNext = true;
    final subject = controller();

    await subject.ensure(<String>['p-1']);

    expect(subject.state.metrics, isEmpty);
    expect(
      subject.state.failed,
      isTrue,
      reason: 'without this the grid shows forty cards with no figures, which '
          'reads as a portfolio with nothing open',
    );
  });

  test('a failed batch does not cost the batches that succeeded', () async {
    repository.failFirstOnly = true;
    final subject = controller();
    final ids = <String>[for (int i = 0; i < 250; i++) 'p-$i'];

    await subject.ensure(ids);

    expect(subject.state.failed, isTrue);
    expect(
      subject.state.metrics,
      hasLength(50),
      reason: 'the second batch answered and its cards show their numbers; '
          'the notice says the rest could not be loaded',
    );
  });

  test('a failure is not retried on every rebuild', () async {
    repository.failNext = true;
    final subject = controller();

    await subject.ensure(<String>['p-1']);
    await subject.ensure(<String>['p-1']);

    expect(
      repository.calls,
      1,
      reason: 'retrying here would turn a failing backend into a request loop; '
          'the user refreshing builds a new controller',
    );
  });

  test('withheld ids are not a failure', () async {
    repository.withheld = <String>['p-2'];
    final subject = controller();

    await subject.ensure(<String>['p-1', 'p-2']);

    expect(subject.state['p-2'], isNull);
    expect(
      subject.state.failed,
      isFalse,
      reason: 'the server answered. It said this caller may not see that '
          'property, which is a correct outcome and not a degraded one',
    );
    expect(subject.state['p-1'], isNotNull);
  });

  test('without a workspace nothing is asked', () async {
    final subject = controller(workspaceId: null);

    await subject.ensure(<String>['p-1']);

    expect(repository.calls, 0);
    expect(subject.state.failed, isFalse);
  });
}

class _FakeRepository implements PropertyRepository {
  int calls = 0;
  final List<List<String>> requestedIds = <List<String>>[];
  bool failNext = false;
  bool failFirstOnly = false;
  List<String> withheld = const <String>[];

  @override
  Future<PropertyRepositoryResult<PropertyCardMetricsBatch>> cardMetrics({
    required String workspaceId,
    required List<String> propertyIds,
  }) async {
    calls++;
    requestedIds.add(List<String>.of(propertyIds));
    if (failNext || (failFirstOnly && calls == 1)) {
      return const PropertyRepositoryFailure<PropertyCardMetricsBatch>(
        kind: PropertyRepositoryFailureKind.infrastructureFailure,
        message: 'no',
      );
    }
    return PropertyRepositorySuccess<PropertyCardMetricsBatch>(
      PropertyCardMetricsBatch(
        asOf: DateTime.utc(2026, 9, 7),
        byPropertyId: <String, PropertyCardMetricsDto>{
          for (final String id in propertyIds)
            if (!withheld.contains(id))
              id: PropertyCardMetricsDto(
                propertyId: id,
                leasing: const PropertyOverviewSection.available(
                  <String, int>{'units_total': 4, 'units_occupied': 3},
                ),
                maintenance: const PropertyOverviewSection.available(
                  <String, int>{'tickets_open': 0},
                ),
              ),
        },
        withheld: withheld,
      ),
    );
  }

  @override
  Future<PropertyRepositoryResult<PropertyPageResult>> list(
    PropertyListQuery query,
  ) async => throw UnimplementedError('list');

  @override
  Future<PropertyRepositoryResult<PropertyDto>> create(
    PropertyCreateCommand command,
  ) async => throw UnimplementedError('create');

  @override
  Future<PropertyRepositoryResult<PropertyDto>> getById({
    required String workspaceId,
    required String propertyId,
  }) async => throw UnimplementedError('getById');

  @override
  Future<PropertyRepositoryResult<PropertyOverviewDto>> overview({
    required String workspaceId,
    required String propertyId,
  }) async => throw UnimplementedError('overview');

  @override
  Future<PropertyRepositoryResult<PropertyDto>> update(
    PropertyUpdateCommand command,
  ) async => throw UnimplementedError('update');
}
