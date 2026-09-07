/// SERVICE-CHARGE-PREVIEW-01: the client half.
///
/// Four things this side must never do:
///
///   * **Let "apportionable" imply "distributed".** A cost classified as
///     passable-on that refused still has an amount, and that amount belongs
///     in a total of its own. Collapsing the two would produce a statement
///     that looks complete while a position is missing — the one failure mode
///     DEC-029 exists to prevent.
///   * **Collapse "unclassified" into "not apportionable".** Only one of them
///     is a decision somebody made.
///   * **Present a preview as a statement.** `isPreview` defaults to true when
///     the field is missing, so a build that failed to read it errs towards
///     the cautious claim.
///   * **Send a period the booking model cannot express.** A range that is not
///     whole months is refused before the round trip, because the server would
///     refuse it too and the reason belongs on the form.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/finance_ledger/application/finance_ledger_port.dart';
import 'package:neximmo_app/features/finance_ledger/application/service_charge_controller.dart';
import 'package:neximmo_app/features/finance_ledger/data/supabase_service_charge_preview_adapter.dart';
import 'package:neximmo_app/features/finance_ledger/domain/service_charge_preview_dto.dart';
import 'package:neximmo_app/features/finance_ledger/data/supabase_finance_ledger_adapter.dart'
    show FinanceSupabaseGateway;
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';

void main() {
  group('adapter', () {
    late _FakeGateway gateway;
    late SupabaseServiceChargePreviewAdapter adapter;

    setUp(() {
      gateway = _FakeGateway();
      adapter = SupabaseServiceChargePreviewAdapter.withGateway(gateway);
    });

    Future<FinanceRepositoryResult<ServiceChargePreviewDto>> read({
      DateTime? from,
      DateTime? to,
    }) => adapter.readPreview(
      workspaceId: 'ws-1',
      propertyId: 'property-1',
      from: from ?? DateTime(2026, 1, 1),
      to: to ?? DateTime(2026, 2, 28),
    );

    test('the arithmetic of a line survives the round trip', () async {
      gateway.result = _preview();

      final ServiceChargePreviewDto value = _valueOf(await read());
      final ServiceChargeUnitDto unit = value.units.first;

      expect(unit.unitCode, 'A-01');
      expect(unit.total, 600);
      expect(unit.lines.single.amount, 600);
      expect(unit.lines.single.numerator, 60);
      expect(unit.lines.single.denominator, 100);
      expect(
        unit.lines.single.isDerivable,
        isTrue,
        reason: 'a share whose numerator or denominator is missing cannot be '
            'checked by the person it is charged to',
      );
      expect(
        unit.lines.single.explanation,
        'Nach Wohnfläche.',
        reason: 'DEC-014 makes the key with its explanation one of the four '
            'particulars a statement cannot be valid without',
      );
    });

    test('an apportionable cost that refused keeps its amount', () async {
      gateway.result = _preview();

      final ServiceChargePreviewDto value = _valueOf(await read());
      final ServiceChargeAccountDto heating = value.accounts.firstWhere(
        (ServiceChargeAccountDto a) => a.accountCode == '4400',
      );

      expect(heating.allocatable, isTrue);
      expect(heating.distributed, isFalse);
      expect(heating.refusal!.reason, 'no_meters');
      expect(heating.refusal!.label, 'Keine Zähler erfasst');
      expect(
        value.totals.apportionableNotDistributed,
        800,
        reason: 'DEC-029: the money of a refused position stays in a total of '
            'its own rather than vanishing from one that then looks complete',
      );
      expect(
        value.totals.distributed,
        600,
        reason: 'paired with the line above so neither total can absorb the '
            'other',
      );
    });

    test('an unclassified cost is not a not-apportionable one', () async {
      gateway.result = _preview();

      final ServiceChargePreviewDto value = _valueOf(await read());
      final ServiceChargeAccountDto admin = value.accounts.firstWhere(
        (ServiceChargeAccountDto a) => a.accountCode == '4950',
      );

      expect(admin.allocatable, isNull);
      expect(admin.refusal!.reason, 'unclassified');
      expect(value.totals.unclassified, 300);
      expect(
        value.totals.notApportionable,
        500,
        reason: 'the classified-as-false amount is counted separately: only '
            'one of the two is a decision somebody made',
      );
      expect(value.totals.open, 1100, reason: '800 refused plus 300 undecided');
      expect(value.totals.isComplete, isFalse);
    });

    test('a refusal this build does not know still reads as something',
        () async {
      gateway.result = _preview(refusalReason: 'some_future_reason');

      final ServiceChargePreviewDto value = _valueOf(await read());
      final ServiceChargeAccountDto heating = value.accounts.firstWhere(
        (ServiceChargeAccountDto a) => a.accountCode == '4400',
      );

      expect(
        heating.refusal!.label,
        'some_future_reason',
        reason: 'a later migration may add a reason, and an "unknown" bucket '
            'would swallow it silently',
      );
    });

    test('a missing is_preview flag is read as a preview', () async {
      final Map<String, Object?> payload = _preview();
      (payload['entity']! as Map<String, Object?>).remove('is_preview');
      gateway.result = payload;

      expect(
        _valueOf(await read()).isPreview,
        isTrue,
        reason: 'a build that cannot read the flag must err towards "this is '
            'not a document", never the other way',
      );
    });

    test('a period that is not whole months is refused before the round trip',
        () async {
      gateway.result = _preview();

      final FinanceRepositoryResult<ServiceChargePreviewDto> result = await read(
        from: DateTime(2026, 1, 15),
      );

      expect(gateway.calls, isEmpty);
      expect(
        result,
        isA<FinanceRepositoryFailure<ServiceChargePreviewDto>>()
            .having(
              (FinanceRepositoryFailure<ServiceChargePreviewDto> f) => f.kind,
              'kind',
              FinanceRepositoryFailureKind.validationFailed,
            )
            .having(
              (FinanceRepositoryFailure<ServiceChargePreviewDto> f) => f.field,
              'field',
              'from',
            ),
      );
    });

    test('and so is one that ends mid-month', () async {
      gateway.result = _preview();

      await read(to: DateTime(2026, 2, 15));

      expect(
        gateway.calls,
        isEmpty,
        reason: 'paired with the test above: a check that only looked at the '
            'start would pass that one',
      );
    });

    test('a period that ends before it starts names the field', () async {
      final FinanceRepositoryResult<ServiceChargePreviewDto> result = await read(
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 1, 31),
      );

      expect(gateway.calls, isEmpty);
      expect(
        (result as FinanceRepositoryFailure<ServiceChargePreviewDto>).field,
        'to',
      );
    });

    test('a valid period reaches the server as two dates', () async {
      gateway.result = _preview();

      await read();

      expect(gateway.calls, hasLength(1));
      expect(gateway.calls.single.name, 'property_service_charge_preview');
      expect(gateway.calls.single.params['p_from'], '2026-01-01');
      expect(
        gateway.calls.single.params['p_to'],
        '2026-02-28',
        reason: 'paired with the refusals above so those cannot pass by the '
            'adapter never calling anything',
      );
    });

    test('a refusal is mapped by code, not by message', () async {
      gateway.result = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'forbidden',
          'message': 'Finance reads are not permitted',
        },
      };

      final FinanceRepositoryResult<ServiceChargePreviewDto> result =
          await read();

      expect(
        result,
        isA<FinanceRepositoryFailure<ServiceChargePreviewDto>>().having(
          (FinanceRepositoryFailure<ServiceChargePreviewDto> f) => f.kind,
          'kind',
          FinanceRepositoryFailureKind.forbidden,
        ),
      );
      expect(
        (result as FinanceRepositoryFailure<ServiceChargePreviewDto>).message,
        contains('finance.read'),
      );
    });

    test('a currency refusal comes through verbatim', () async {
      gateway.result = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'validation_failed',
          'field': 'currency',
          'message':
              'This period holds bookings in 2 currencies. A statement over '
              'two currencies has no total, and converting them would invent '
              'an exchange rate.',
        },
      };

      final FinanceRepositoryResult<ServiceChargePreviewDto> result =
          await read();

      expect(
        (result as FinanceRepositoryFailure<ServiceChargePreviewDto>).message,
        contains('exchange rate'),
        reason: 'the server composes this one, so a translation table cannot '
            'match it — passing it through beats replacing it with a guess',
      );
    });
  });

  group('months without a period', () {
    ServiceChargePreviewDto of({required int months, required int periods}) =>
        ServiceChargePreviewDto.fromJson(<String, dynamic>{
          'property_id': 'p',
          'from_date': '2026-01-01',
          'to_date': '2026-04-30',
          'month_count': months,
          'period_count': periods,
          'totals': <String, dynamic>{},
          'accounts': <Object?>[],
          'units': <Object?>[],
        });

    test('a month with no booking period is counted', () {
      expect(of(months: 4, periods: 3).monthsWithoutPeriod, 1);
    });

    test('and a complete period counts none', () {
      expect(
        of(months: 4, periods: 4).monthsWithoutPeriod,
        0,
        reason: 'paired with the test above so the getter is not simply the '
            'month count',
      );
    });

    test('more periods than months is not a negative gap', () {
      expect(
        of(months: 2, periods: 3).monthsWithoutPeriod,
        0,
        reason: 'a negative count on screen is worse than none, and a server '
            'reporting this would be describing something else entirely',
      );
    });
  });

  group('unit occupancy', () {
    test('a unit let throughout, partly and never are three states', () {
      ServiceChargeUnitDto unit(int daysLet) => ServiceChargeUnitDto(
        unitId: 'u',
        total: 0,
        lines: const <ServiceChargeLineDto>[],
        daysLet: daysLet,
        daysInWindow: 59,
      );

      expect(unit(59).wasLetThroughout, isTrue);
      expect(unit(59).wasPartlyLet, isFalse);
      expect(unit(31).wasPartlyLet, isTrue);
      expect(unit(0).wasNeverLet, isTrue);
      expect(
        unit(0).wasPartlyLet,
        isFalse,
        reason: 'an empty unit is not a partly let one, and the screen says '
            'something different about each',
      );
    });
  });

  group('controller', () {
    late _FakePreviewPort port;

    ServiceChargeController controller({
      Set<String> permissions = const <String>{'finance.read'},
      DateTime? today,
    }) {
      final ServiceChargeController subject = ServiceChargeController(
        port: port,
        scope: WorkspaceSessionScope(
          workspaceId: 'ws-1',
          actorId: 'actor-a',
          permissions: permissions,
          mutationsSupported: true,
        ),
        today: today ?? DateTime(2026, 3, 15),
      );
      addTearDown(subject.dispose);
      return subject;
    }

    setUp(() => port = _FakePreviewPort());

    test('the default period is the last whole month', () {
      final ServiceChargeController subject = controller();

      expect(subject.state.from, DateTime(2026, 2, 1));
      expect(
        subject.state.to,
        DateTime(2026, 2, 28),
        reason: 'a settlement over a month that still accepts bookings gives '
            'a figure that will move, and a screen should not open on one',
      );
    });

    test('and it lands on the last day of a 31-day month too', () {
      final ServiceChargeController subject = controller(
        today: DateTime(2026, 9, 8),
      );

      expect(subject.state.from, DateTime(2026, 8, 1));
      expect(subject.state.to, DateTime(2026, 8, 31));
    });

    test('nothing is read until a property is chosen', () async {
      final ServiceChargeController subject = controller();
      await subject.load();

      expect(port.calls, isEmpty);
      expect(
        subject.state.phase,
        ServiceChargePhase.ready,
        reason: 'waiting for a choice is not a failure and not a spinner',
      );
      expect(subject.state.message, isNull);
    });

    test('choosing a property reads the preview', () async {
      final ServiceChargeController subject = controller();
      await subject.selectProperty(
        propertyId: 'property-1',
        propertyName: 'Haus A',
      );

      expect(port.calls, hasLength(1));
      expect(subject.state.propertyName, 'Haus A');
      expect(subject.state.preview, isNotNull);
      expect(subject.state.phase, ServiceChargePhase.ready);
    });

    test('a chosen period is normalised to whole months', () async {
      final ServiceChargeController subject = controller();
      await subject.selectProperty(propertyId: 'property-1');
      await subject.selectPeriod(
        fromMonth: DateTime(2026, 1, 17),
        toMonth: DateTime(2026, 2, 9),
      );

      expect(subject.state.from, DateTime(2026, 1, 1));
      expect(
        subject.state.to,
        DateTime(2026, 2, 28),
        reason: 'the day the user happened to tap is not part of the choice, '
            'and sending it would earn a refusal about a field they did not '
            'touch');
      expect(port.calls.last.from, DateTime(2026, 1, 1));
      expect(port.calls.last.to, DateTime(2026, 2, 28));
    });

    test('a refusal clears the figures rather than leaving them under a new '
        'heading', () async {
      final ServiceChargeController subject = controller();
      await subject.selectProperty(propertyId: 'property-1');
      expect(subject.state.preview, isNotNull);

      port.failure = FinanceRepositoryFailureKind.validationFailed;
      await subject.selectPeriod(
        fromMonth: DateTime(2026, 5, 1),
        toMonth: DateTime(2026, 5, 31),
      );

      expect(subject.state.preview, isNull);
      expect(subject.state.phase, ServiceChargePhase.error);
      expect(subject.state.message, 'refused');
      expect(
        subject.state.from,
        DateTime(2026, 5, 1),
        reason: 'the refused period stays on screen so it can be corrected, '
            'rather than snapping back to one that worked',
      );
    });

    test('a member without finance.read is refused without a round trip',
        () async {
      final ServiceChargeController subject = controller(
        permissions: const <String>{'property.read'},
      );
      await subject.selectProperty(propertyId: 'property-1');

      expect(port.calls, isEmpty);
      expect(subject.state.phase, ServiceChargePhase.forbidden);
      expect(subject.state.message, contains('finance.read'));
    });

    test('a forbidden answer is not an error state', () async {
      port.failure = FinanceRepositoryFailureKind.forbidden;

      final ServiceChargeController subject = controller();
      await subject.selectProperty(propertyId: 'property-1');

      expect(
        subject.state.phase,
        ServiceChargePhase.forbidden,
        reason: 'a property a member may not see is not a broken screen',
      );
    });
  });
}

// ---------------------------------------------------------------------------

ServiceChargePreviewDto _valueOf(
  FinanceRepositoryResult<ServiceChargePreviewDto> result,
) => (result as FinanceRepositorySuccess<ServiceChargePreviewDto>).value;

Map<String, Object?> _preview({String refusalReason = 'no_meters'}) {
  return <String, Object?>{
    'ok': true,
    'entity': <String, Object?>{
      'property_id': 'property-1',
      'property_name': 'Haus A',
      'from_date': '2026-01-01',
      'to_date': '2026-02-28',
      'days_in_window': 59,
      'currency_code': 'EUR',
      'is_preview': true,
      'is_provisional': false,
      'open_period_count': 0,
      'periods': <Object?>[
        <String, Object?>{
          'id': 'period-1',
          'fiscal_year': 2026,
          'period_month': 1,
          'status': 'closed',
        },
      ],
      'totals': <String, Object?>{
        'distributed': 600,
        'apportionable_not_distributed': 800,
        'not_apportionable': 500,
        'unclassified': 300,
        'unclassified_account_count': 1,
      },
      'accounts': <Object?>[
        <String, Object?>{
          'account_id': 'account-1',
          'account_code': '4300',
          'account_name': 'Müllabfuhr',
          'amount': 600,
          'entry_count': 1,
          'allocatable': true,
          'distributed': true,
          'refusal': null,
          'rounding_difference': 0,
          'key': <String, Object?>{
            'id': 'key-1',
            'basis': 'area_sqm',
            'explanation': 'Nach Wohnfläche.',
            'valid_from': '2020-01-01',
            'valid_to': null,
          },
        },
        <String, Object?>{
          'account_id': 'account-2',
          'account_code': '4400',
          'account_name': 'Heizung',
          'amount': 800,
          'entry_count': 1,
          'allocatable': true,
          'distributed': false,
          'refusal': <String, Object?>{
            'reason': refusalReason,
            'detail': 'Meters and readings arrive with P-4.',
          },
        },
        <String, Object?>{
          'account_id': 'account-3',
          'account_code': '4900',
          'account_name': 'Instandhaltung',
          'amount': 500,
          'entry_count': 1,
          'allocatable': false,
          'distributed': false,
          'refusal': null,
        },
        <String, Object?>{
          'account_id': 'account-4',
          'account_code': '4950',
          'account_name': 'Verwaltung',
          'amount': 300,
          'entry_count': 1,
          'allocatable': null,
          'distributed': false,
          'refusal': <String, Object?>{
            'reason': 'unclassified',
            'detail': 'Nobody has decided.',
          },
        },
      ],
      'units': <Object?>[
        <String, Object?>{
          'unit_id': 'unit-1',
          'unit_code': 'A-01',
          'area_sqm': 60,
          'total': 600,
          'days_let': 31,
          'days_in_window': 59,
          'lines': <Object?>[
            <String, Object?>{
              'unit_id': 'unit-1',
              'account_id': 'account-1',
              'account_code': '4300',
              'account_name': 'Müllabfuhr',
              'amount': 600,
              'numerator': 60,
              'denominator': 100,
              'basis': 'area_sqm',
              'explanation': 'Nach Wohnfläche.',
            },
          ],
        },
      ],
    },
  };
}

/// Records every call, not only the last: several tests assert that a refused
/// period reached the server *no* times, and a fake that kept only the last
/// call would satisfy those by overwriting rather than by not calling.
class _RpcCall {
  const _RpcCall(this.name, this.params);

  final String name;
  final Map<String, Object?> params;
}

class _FakeGateway implements FinanceSupabaseGateway {
  Object? result;
  final List<_RpcCall> calls = <_RpcCall>[];

  @override
  Future<Object?> callRpc(
    String function,
    Map<String, Object?> parameters,
  ) async {
    calls.add(_RpcCall(function, parameters));
    return result;
  }
}

class _PreviewCall {
  const _PreviewCall(this.from, this.to);

  final DateTime from;
  final DateTime to;
}

class _FakePreviewPort implements ServiceChargePreviewPort {
  final List<_PreviewCall> calls = <_PreviewCall>[];
  FinanceRepositoryFailureKind? failure;

  @override
  Future<FinanceRepositoryResult<ServiceChargePreviewDto>> readPreview({
    required String workspaceId,
    required String propertyId,
    required DateTime from,
    required DateTime to,
  }) async {
    calls.add(_PreviewCall(from, to));
    final FinanceRepositoryFailureKind? kind = failure;
    if (kind != null) {
      return FinanceRepositoryFailure<ServiceChargePreviewDto>(
        kind: kind,
        message: 'refused',
      );
    }
    return FinanceRepositorySuccess<ServiceChargePreviewDto>(
      ServiceChargePreviewDto.fromJson(
        (_preview()['entity']! as Map<String, Object?>)
            .cast<String, dynamic>(),
      ),
    );
  }
}
