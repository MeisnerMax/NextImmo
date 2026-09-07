/// FINANCE-BOOKINGS-01: the client half.
///
/// Four things this side must never do:
///
///   * **Collapse "not classified" into "not apportionable".** Only one of
///     them is a decision somebody made, and the count of the first is the
///     work standing between these bookings and a settlement.
///   * **Blank the whole screen when only the entries failed.** The period
///     list is workspace-wide and needs `finance.read`; the entry list is per
///     property and is gated on the property scope first. A member scoped to
///     one building must still see the periods.
///   * **Send an empty reason.** The shared finance gate refuses a reason of
///     length zero outright — not merely on reopening — so "no reason" has to
///     be null on every command.
///   * **Re-read the version at submit time.** The period version travels
///     with the row the caller was looking at; a refusal reloads the list, and
///     a retry carrying the fresher version with the older intent is how a
///     concurrent close gets overwritten.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/finance_ledger/application/cost_pool_controller.dart'
    show CostPoolActionFailure;
import 'package:neximmo_app/features/finance_ledger/application/finance_booking_controller.dart';
import 'package:neximmo_app/features/finance_ledger/application/finance_ledger_port.dart';
import 'package:neximmo_app/features/finance_ledger/data/supabase_finance_booking_adapter.dart';
import 'package:neximmo_app/features/finance_ledger/data/supabase_finance_ledger_adapter.dart';
import 'package:neximmo_app/features/finance_ledger/domain/finance_booking_dto.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';

void main() {
  group('adapter', () {
    late _FakeGateway gateway;
    late SupabaseFinanceBookingAdapter adapter;

    setUp(() {
      gateway = _FakeGateway();
      adapter = SupabaseFinanceBookingAdapter.withGateway(gateway);
    });

    test('an unclassified cost keeps a null allocatable', () async {
      gateway.result = _ledger();

      final FinanceLedgerOverviewDto value = _ledgerOf(
        await adapter.readEntries(
          workspaceId: 'ws-1',
          propertyId: 'property-1',
        ),
      );

      expect(value.entries, hasLength(3));
      expect(value.entries[0].allocatable, isTrue);
      expect(value.entries[1].allocatable, isFalse);
      expect(
        value.entries[2].allocatable,
        isNull,
        reason: 'nobody has decided whether this cost may be passed on, which '
            'is not the same as deciding that it may not',
      );
      expect(value.entries[2].isApportionable, isFalse);
      expect(
        value.entries[1].isApportionable,
        isFalse,
        reason: 'paired with the case above so neither passes by the getter '
            'always answering false',
      );
      expect(value.entries[0].isApportionable, isTrue);
    });

    test('a negative amount is a counter-booking, not an error', () async {
      gateway.result = _ledger();

      final FinanceLedgerOverviewDto value = _ledgerOf(
        await adapter.readEntries(
          workspaceId: 'ws-1',
          propertyId: 'property-1',
        ),
      );

      expect(value.entries[1].isCounterBooking, isTrue);
      expect(value.entries[0].isCounterBooking, isFalse);
      expect(
        value.pageTotalsByCurrency['EUR'],
        1400,
        reason: 'the page total nets the pair, but the rows stay separate: '
            'hiding one would hide the mistake with its correction',
      );
    });

    test('a truncated page says so rather than reading as the whole answer',
        () async {
      gateway.result = _ledger(returned: 3, total: 41);

      final FinanceLedgerOverviewDto value = _ledgerOf(
        await adapter.readEntries(
          workspaceId: 'ws-1',
          propertyId: 'property-1',
        ),
      );

      expect(value.isTruncated, isTrue);
      expect(value.totalCount, 41);
    });

    test('a booking of zero is refused before the round trip', () async {
      final FinanceRepositoryResult<FinanceLedgerEntryDto> result =
          await adapter.recordEntry(_booking(amount: 0));

      expect(gateway.calls, 0);
      expect(
        (result as FinanceRepositoryFailure<FinanceLedgerEntryDto>).field,
        'amount',
      );
    });

    test('a non-finite amount is an input error, not a transport failure',
        () async {
      final FinanceRepositoryResult<FinanceLedgerEntryDto> result =
          await adapter.recordEntry(_booking(amount: double.nan));

      expect(gateway.calls, 0);
      final failure =
          result as FinanceRepositoryFailure<FinanceLedgerEntryDto>;
      expect(failure.kind, FinanceRepositoryFailureKind.validationFailed);
      expect(failure.field, 'amount');
    });

    test('a currency that is not three letters is refused here', () async {
      final FinanceRepositoryResult<FinanceLedgerEntryDto> result =
          await adapter.recordEntry(_booking(currency: 'eur'));

      expect(
        gateway.calls,
        0,
        reason: 'the server wants upper case, and there is no workspace '
            'default anywhere, so a typo is worth catching before the trip',
      );
      expect(
        (result as FinanceRepositoryFailure<FinanceLedgerEntryDto>).field,
        'currency_code',
      );
    });

    test('a negative booking is sent, because it is the only correction there is',
        () async {
      gateway.result = <String, Object?>{'ok': true, 'entity': _entryRow(amount: -500)};

      await adapter.recordEntry(_booking(amount: -500));

      expect(gateway.lastParameters!['p_amount'], -500);
      expect(gateway.lastParameters!['p_booked_on'], '2026-01-15');
    });

    test('reopening without a reason is refused before the round trip', () async {
      final FinanceRepositoryResult<FinancePeriodDto> result =
          await adapter.transitionPeriod(
        const TransitionFinancePeriodCommand(
          context: FinanceCommandContext(
            workspaceId: 'ws-1',
            actorId: 'actor-a',
            mutationId: 'm-1',
            correlationId: 'c-1',
          ),
          periodId: 'period-1',
          targetState: FinancePeriodState.open,
          expectedVersion: 3,
        ),
      );

      expect(gateway.calls, 0);
      expect(
        (result as FinanceRepositoryFailure<FinancePeriodDto>).field,
        'reason',
      );
    });

    test('a known refusal arrives in German, an unknown one verbatim', () async {
      gateway.result = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'dependency_conflict',
          'message': 'That period already exists',
        },
      };
      final FinanceRepositoryResult<FinancePeriodDto> known =
          await adapter.openPeriod(_openCommand());
      expect(
        (known as FinanceRepositoryFailure<FinancePeriodDto>).message,
        contains('gibt es bereits'),
      );

      gateway.result = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'validation_failed',
          'message': 'Some future rule was violated',
        },
      };
      final FinanceRepositoryResult<FinancePeriodDto> unknown =
          await adapter.openPeriod(_openCommand());
      expect(
        (unknown as FinanceRepositoryFailure<FinancePeriodDto>).message,
        'Some future rule was violated',
        reason: 'an untranslated sentence is better than a wrong one',
      );
    });

    test('a period the command just opened reads as empty, not as unknown',
        () async {
      // The command's snapshot carries no entry count -- it answers what was
      // written. A period that was just created is empty by construction.
      gateway.result = <String, Object?>{'ok': true, 'entity': _periodRow()};

      final FinancePeriodDto value =
          (await adapter.openPeriod(_openCommand())
                  as FinanceRepositorySuccess<FinancePeriodDto>)
              .value;

      expect(value.entryCount, 0);
      expect(value.isOpen, isTrue);
      expect(value.label, '01/2026');
    });

    test('a period status this build does not know is never usable', () async {
      gateway.result = <String, Object?>{
        'ok': true,
        'entity': _periodRow(status: 'archived'),
      };

      final FinancePeriodDto value =
          (await adapter.openPeriod(_openCommand())
                  as FinanceRepositorySuccess<FinancePeriodDto>)
              .value;

      expect(value.state, FinancePeriodState.unknown);
      expect(value.rawStateKey, 'archived');
      expect(
        value.isActionable,
        isFalse,
        reason: 'a newer server could introduce a state with rules this build '
            'does not know, and acting on it would be acting blind',
      );
    });
  });

  group('controller', () {
    late _FakePeriodsPort periods;
    late _FakeLedgerPort ledger;

    FinanceBookingController controller({
      Set<String> permissions = const <String>{
        'finance.read',
        'finance.manage',
        'finance.close',
      },
    }) {
      final FinanceBookingController subject = FinanceBookingController(
        periodsPort: periods,
        ledgerPort: ledger,
        scope: WorkspaceSessionScope(
          workspaceId: 'ws-1',
          actorId: 'actor-a',
          permissions: permissions,
          mutationsSupported: true,
        ),
        idFactory: () => 'id-1',
      );
      addTearDown(subject.dispose);
      return subject;
    }

    setUp(() {
      periods = _FakePeriodsPort();
      ledger = _FakeLedgerPort();
    });

    test('the entry read failing leaves the periods standing', () async {
      final FinanceBookingController subject = controller();
      await subject.load();
      await subject.selectProperty(propertyId: 'property-1');
      expect(subject.state.entries, isNotEmpty);

      ledger.readFailure = FinanceRepositoryFailureKind.forbidden;
      await subject.selectProperty(propertyId: 'property-2');

      expect(
        subject.state.periodList,
        isNotEmpty,
        reason: 'a property this member may not see is a fact about that '
            'property, not a broken screen',
      );
      expect(subject.state.ledger, isNull);
      expect(subject.state.entriesMessage, isNotNull);
      expect(subject.state.phase, FinanceBookingPhase.ready);
    });

    test('the period read failing blanks both, because nothing is trustworthy',
        () async {
      final FinanceBookingController subject = controller();
      periods.readFailure = FinanceRepositoryFailureKind.forbidden;
      await subject.load();

      expect(subject.state.phase, FinanceBookingPhase.forbidden);
      expect(subject.state.periods, isNull);
      expect(subject.state.ledger, isNull);
    });

    test('a reason is never sent as an empty string', () async {
      final FinanceBookingController subject = controller();
      await subject.load();

      await subject.openPeriod(fiscalYear: 2026, periodMonth: 3);
      expect(
        periods.opens.single.context.reason,
        isNull,
        reason: 'the shared finance gate refuses a reason of length zero '
            'outright, so "no reason" has to be null',
      );

      await subject.setPeriodState(
        period: _periodDto(),
        target: FinancePeriodState.open,
        reason: '   ',
      );
      expect(periods.transitions.single.context.reason, isNull);
    });

    test('the period version travels with the row the caller saw', () async {
      final FinanceBookingController subject = controller();
      await subject.load();

      await subject.setPeriodState(
        period: _periodDto(version: 5),
        target: FinancePeriodState.closed,
      );

      expect(
        periods.transitions.single.expectedVersion,
        5,
        reason: 'not re-read at submit time: a refusal reloads the list, and '
            'a retry with the fresher version and the older intent would '
            'overwrite whoever changed it',
      );
    });

    test('closing needs finance.close, which booking does not grant', () async {
      final FinanceBookingController subject = controller(
        permissions: const <String>{'finance.read', 'finance.manage'},
      );
      await subject.load();

      expect(subject.canBook, isTrue);
      expect(subject.canClose, isFalse);

      final CostPoolActionFailure? failure = await subject.setPeriodState(
        period: _periodDto(),
        target: FinancePeriodState.closed,
      );

      expect(periods.transitions, isEmpty);
      expect(failure, isNotNull);
    });

    test('booking without a property is refused with the reason', () async {
      final FinanceBookingController subject = controller();
      await subject.load();

      final CostPoolActionFailure? failure = await subject.book(
        accountId: 'account-1',
        periodId: 'period-1',
        bookedOn: DateTime(2026, 1, 15),
        amount: 100,
        currencyCode: 'EUR',
      );

      expect(ledger.records, isEmpty);
      expect(failure!.message, contains('Objekt'));
    });

    test('a write re-reads either way, because a period may have been closed '
        'under it', () async {
      final FinanceBookingController subject = controller();
      await subject.load();
      await subject.selectProperty(propertyId: 'property-1');
      expect(periods.reads, 1);

      await subject.openPeriod(fiscalYear: 2026, periodMonth: 4);
      expect(periods.reads, 2);

      periods.writeFails = true;
      await subject.openPeriod(fiscalYear: 2026, periodMonth: 5);
      expect(periods.reads, 3);
    });

    test('canBookNow is false while the chosen period is closed', () async {
      final FinanceBookingController subject = controller();
      periods.closed = true;
      await subject.load();
      await subject.selectProperty(propertyId: 'property-1');
      await subject.selectPeriod('period-1');

      expect(subject.state.selectedPeriod, isNotNull);
      expect(
        subject.state.canBookNow,
        isFalse,
        reason: 'the server refuses an entry into a closed period, so the '
            'action is not offered',
      );
    });

    test('the unclassified count is what stands between these bookings and a '
        'settlement', () async {
      final FinanceBookingController subject = controller();
      await subject.load();
      await subject.selectProperty(propertyId: 'property-1');

      expect(subject.state.unclassifiedOnPage, 1);
    });
  });
}

FinanceLedgerOverviewDto _ledgerOf(
  FinanceRepositoryResult<FinanceLedgerOverviewDto> r,
) => (r as FinanceRepositorySuccess<FinanceLedgerOverviewDto>).value;

FinanceCommandContext _context() => const FinanceCommandContext(
  workspaceId: 'ws-1',
  actorId: 'actor-a',
  mutationId: 'm-1',
  correlationId: 'c-1',
);

OpenFinancePeriodCommand _openCommand() => OpenFinancePeriodCommand(
  context: _context(),
  fiscalYear: 2026,
  periodMonth: 1,
);

RecordFinanceLedgerEntryCommand _booking({
  num amount = 1000,
  String currency = 'EUR',
}) {
  return RecordFinanceLedgerEntryCommand(
    context: _context(),
    propertyId: 'property-1',
    accountId: 'account-1',
    periodId: 'period-1',
    bookedOn: DateTime(2026, 1, 15),
    amount: amount,
    currencyCode: currency,
  );
}

FinancePeriodDto _periodDto({int version = 1, bool open = true}) =>
    FinancePeriodDto(
      id: 'period-1',
      workspaceId: 'ws-1',
      fiscalYear: 2026,
      periodMonth: 1,
      state: open ? FinancePeriodState.open : FinancePeriodState.closed,
      version: version,
      entryCount: 0,
    );

Map<String, Object?> _periodRow({String status = 'open'}) =>
    <String, Object?>{
      'id': 'period-1',
      'workspace_id': 'ws-1',
      'fiscal_year': 2026,
      'period_month': 1,
      'status': status,
      'closed_at': null,
      'closed_by': null,
      'version': 1,
    };

Map<String, Object?> _entryRow({
  String id = 'entry-1',
  num amount = 1000,
  Object? allocatable = true,
}) {
  return <String, Object?>{
    'id': id,
    'workspace_id': 'ws-1',
    'property_id': 'property-1',
    'account_id': 'account-1',
    'period_id': 'period-1',
    'booked_on': '2026-01-15',
    'amount': amount,
    'currency_code': 'EUR',
    'description': 'Rechnung 42',
    'source': 'manual',
    'unit_id': null,
    'version': 1,
    'account_code': '4300',
    'account_name': 'Hausmeister',
    'account_type': 'expense',
    'period_fiscal_year': 2026,
    'period_month': 1,
    'period_status': 'open',
    'allocatable': allocatable,
    'settlement_principle': 'performance',
  };
}

Map<String, Object?> _ledger({int returned = 3, int total = 3}) {
  return <String, Object?>{
    'ok': true,
    'entity': <String, Object?>{
      'entries': <Map<String, Object?>>[
        _entryRow(),
        _entryRow(id: 'entry-2', amount: -100, allocatable: false),
        _entryRow(id: 'entry-3', amount: 500, allocatable: null),
      ],
      'returned_count': returned,
      'total_count': total,
      'limit': 100,
    },
  };
}

class _FakeGateway implements FinanceSupabaseGateway {
  Object? result;
  int calls = 0;
  Map<String, Object?>? lastParameters;

  @override
  Future<Object?> callRpc(
    String function,
    Map<String, Object?> parameters,
  ) async {
    calls++;
    lastParameters = parameters;
    return result;
  }
}

class _FakePeriodsPort implements FinancePeriodsPort {
  int reads = 0;
  bool closed = false;
  bool writeFails = false;
  FinanceRepositoryFailureKind? readFailure;
  final List<OpenFinancePeriodCommand> opens = <OpenFinancePeriodCommand>[];
  final List<TransitionFinancePeriodCommand> transitions =
      <TransitionFinancePeriodCommand>[];

  @override
  Future<FinanceRepositoryResult<FinancePeriodOverviewDto>> readPeriods({
    required String workspaceId,
    bool includeClosed = true,
  }) async {
    reads++;
    final FinanceRepositoryFailureKind? kind = readFailure;
    if (kind != null) {
      return FinanceRepositoryFailure<FinancePeriodOverviewDto>(
        kind: kind,
        message: 'refused',
      );
    }
    return FinanceRepositorySuccess<FinancePeriodOverviewDto>(
      FinancePeriodOverviewDto(
        periods: <FinancePeriodDto>[_periodDto(open: !closed)],
        openCount: closed ? 0 : 1,
        totalCount: 1,
      ),
    );
  }

  @override
  Future<FinanceRepositoryResult<FinancePeriodDto>> openPeriod(
    OpenFinancePeriodCommand command,
  ) async {
    opens.add(command);
    return _answer();
  }

  @override
  Future<FinanceRepositoryResult<FinancePeriodDto>> transitionPeriod(
    TransitionFinancePeriodCommand command,
  ) async {
    transitions.add(command);
    return _answer();
  }

  FinanceRepositoryResult<FinancePeriodDto> _answer() {
    if (writeFails) {
      return const FinanceRepositoryFailure<FinancePeriodDto>(
        kind: FinanceRepositoryFailureKind.validationFailed,
        message: 'refused',
      );
    }
    return FinanceRepositorySuccess<FinancePeriodDto>(_periodDto());
  }
}

class _FakeLedgerPort implements PropertyLedgerPort {
  int reads = 0;
  FinanceRepositoryFailureKind? readFailure;
  final List<RecordFinanceLedgerEntryCommand> records =
      <RecordFinanceLedgerEntryCommand>[];

  @override
  Future<FinanceRepositoryResult<FinanceLedgerOverviewDto>> readEntries({
    required String workspaceId,
    required String propertyId,
    String? periodId,
    String? accountId,
    int limit = 100,
  }) async {
    reads++;
    final FinanceRepositoryFailureKind? kind = readFailure;
    if (kind != null) {
      return FinanceRepositoryFailure<FinanceLedgerOverviewDto>(
        kind: kind,
        message: 'refused',
      );
    }
    return FinanceRepositorySuccess<FinanceLedgerOverviewDto>(
      FinanceLedgerOverviewDto(
        entries: <FinanceLedgerEntryDto>[
          FinanceLedgerEntryDto(
            id: 'entry-1',
            workspaceId: 'ws-1',
            propertyId: propertyId,
            accountId: 'account-1',
            periodId: 'period-1',
            bookedOn: DateTime(2026, 1, 15),
            amount: 1000,
            currencyCode: 'EUR',
            version: 1,
            allocatable: true,
          ),
          FinanceLedgerEntryDto(
            id: 'entry-2',
            workspaceId: 'ws-1',
            propertyId: propertyId,
            accountId: 'account-2',
            periodId: 'period-1',
            bookedOn: DateTime(2026, 1, 20),
            amount: 500,
            currencyCode: 'EUR',
            version: 1,
          ),
        ],
        returnedCount: 2,
        totalCount: 2,
        limit: 100,
      ),
    );
  }

  @override
  Future<FinanceRepositoryResult<FinanceLedgerEntryDto>> recordEntry(
    RecordFinanceLedgerEntryCommand command,
  ) async {
    records.add(command);
    return FinanceRepositorySuccess<FinanceLedgerEntryDto>(
      FinanceLedgerEntryDto(
        id: 'entry-9',
        workspaceId: 'ws-1',
        propertyId: command.propertyId,
        accountId: command.accountId,
        periodId: command.periodId,
        bookedOn: command.bookedOn,
        amount: command.amount,
        currencyCode: command.currencyCode,
        version: 1,
      ),
    );
  }
}
