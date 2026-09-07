/// Screen-facing orchestration for periods and bookings
/// (`FINANCE-BOOKINGS-01`).
///
/// **Two reads that fail independently.** The period list is workspace-wide
/// and needs only `finance.read`; the entry list is per property and is gated
/// on the property scope first. A member scoped to one building can see every
/// period and only its own bookings, so the two are held separately and one
/// failing does not blank the other — unlike the pool/key pair, where an empty
/// key list beside live pools would have read as "no key is in force".
///
/// **Nothing here nets a counter-booking away.** A mis-booking cannot be
/// edited or deleted; the remedy is a second, negative entry. Both rows stay
/// visible, because hiding the pair would hide the mistake along with its
/// correction.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/finance_booking_dto.dart';
import 'cost_pool_controller.dart' show CostPoolActionFailure;
import 'finance_ledger_port.dart';
import 'finance_providers.dart';

const Object _unchanged = Object();

enum FinanceBookingPhase { idle, loading, ready, forbidden, error }

enum FinanceBookingActionPhase { idle, running, failed, succeeded }

class FinanceBookingState {
  const FinanceBookingState({
    this.phase = FinanceBookingPhase.idle,
    this.actionPhase = FinanceBookingActionPhase.idle,
    this.periods,
    this.ledger,
    this.propertyId,
    this.propertyName,
    this.periodId,
    this.message,
    this.entriesMessage,
    this.actionMessage,
    this.actionField,
  });

  final FinanceBookingPhase phase;
  final FinanceBookingActionPhase actionPhase;

  /// Null until the first answer, and null again after a failure. An empty
  /// list and an unreadable one are different statements.
  final FinancePeriodOverviewDto? periods;

  /// Null when no property is chosen yet, and null again when the entry read
  /// failed. The period list survives either, because they are different
  /// permissions over different scopes.
  final FinanceLedgerOverviewDto? ledger;

  final String? propertyId;
  final String? propertyName;

  /// Null means every period. The entry read takes the filter; the period
  /// list never does.
  final String? periodId;

  final String? message;

  /// The entry read's own failure, kept apart from [message] so a property a
  /// member may not see does not read as a broken screen.
  final String? entriesMessage;

  final String? actionMessage;
  final String? actionField;

  List<FinancePeriodDto> get periodList =>
      periods?.periods ?? const <FinancePeriodDto>[];

  List<FinanceLedgerEntryDto> get entries =>
      ledger?.entries ?? const <FinanceLedgerEntryDto>[];

  FinancePeriodDto? get selectedPeriod {
    final String? id = periodId;
    if (id == null) {
      return null;
    }
    for (final FinancePeriodDto period in periodList) {
      if (period.id == id) {
        return period;
      }
    }
    return null;
  }

  /// Whether a booking is possible at all right now: a property, a period, and
  /// a period that still accepts entries.
  bool get canBookNow =>
      propertyId != null && (selectedPeriod?.isOpen ?? false);

  /// Costs on the page that nobody has classified. Not an error — it is the
  /// work that stands between these bookings and a settlement, and the surface
  /// says so rather than waiting for the settlement to fail.
  int get unclassifiedOnPage => entries
      .where((FinanceLedgerEntryDto entry) => entry.allocatable == null)
      .length;

  FinanceBookingState copyWith({
    FinanceBookingPhase? phase,
    FinanceBookingActionPhase? actionPhase,
    Object? periods = _unchanged,
    Object? ledger = _unchanged,
    Object? propertyId = _unchanged,
    Object? propertyName = _unchanged,
    Object? periodId = _unchanged,
    Object? message = _unchanged,
    Object? entriesMessage = _unchanged,
    Object? actionMessage = _unchanged,
    Object? actionField = _unchanged,
  }) {
    return FinanceBookingState(
      phase: phase ?? this.phase,
      actionPhase: actionPhase ?? this.actionPhase,
      periods: identical(periods, _unchanged)
          ? this.periods
          : periods as FinancePeriodOverviewDto?,
      ledger: identical(ledger, _unchanged)
          ? this.ledger
          : ledger as FinanceLedgerOverviewDto?,
      propertyId: identical(propertyId, _unchanged)
          ? this.propertyId
          : propertyId as String?,
      propertyName: identical(propertyName, _unchanged)
          ? this.propertyName
          : propertyName as String?,
      periodId: identical(periodId, _unchanged)
          ? this.periodId
          : periodId as String?,
      message: identical(message, _unchanged)
          ? this.message
          : message as String?,
      entriesMessage: identical(entriesMessage, _unchanged)
          ? this.entriesMessage
          : entriesMessage as String?,
      actionMessage: identical(actionMessage, _unchanged)
          ? this.actionMessage
          : actionMessage as String?,
      actionField: identical(actionField, _unchanged)
          ? this.actionField
          : actionField as String?,
    );
  }
}

class FinanceBookingController extends StateNotifier<FinanceBookingState> {
  FinanceBookingController({
    required FinancePeriodsPort periodsPort,
    required PropertyLedgerPort ledgerPort,
    required WorkspaceSessionScope scope,
    String Function()? idFactory,
  }) : _periodsPort = periodsPort,
       _ledgerPort = ledgerPort,
       _scope = scope,
       _idFactory = idFactory ?? (() => const Uuid().v4()),
       super(const FinanceBookingState());

  final FinancePeriodsPort _periodsPort;
  final PropertyLedgerPort _ledgerPort;
  final WorkspaceSessionScope _scope;
  final String Function() _idFactory;

  int _generation = 0;

  /// The server checks it too; this only decides whether an action is offered.
  bool get canBook =>
      _scope.mutationsSupported && _scope.permissions.contains('finance.manage');

  /// Closing and reopening is a separate permission on purpose: whoever books
  /// should not automatically be whoever seals the month.
  bool get canClose =>
      _scope.mutationsSupported && _scope.permissions.contains('finance.close');

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      state = state.copyWith(
        phase: FinanceBookingPhase.forbidden,
        periods: null,
        ledger: null,
        message: 'Kein Workspace ausgewählt.',
      );
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(phase: FinanceBookingPhase.loading, message: null);

    final result = await _periodsPort.readPeriods(workspaceId: workspaceId);
    if (generation != _generation || !mounted) {
      return;
    }
    switch (result) {
      case FinanceRepositorySuccess<FinancePeriodOverviewDto>(:final value):
        state = state.copyWith(
          phase: FinanceBookingPhase.ready,
          periods: value,
          message: null,
        );
      case FinanceRepositoryFailure<FinancePeriodOverviewDto>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          phase: kind == FinanceRepositoryFailureKind.forbidden
              ? FinanceBookingPhase.forbidden
              : FinanceBookingPhase.error,
          periods: null,
          ledger: null,
          message: message,
        );
        return;
    }
    await _loadEntries(generation);
  }

  Future<void> selectProperty({
    required String propertyId,
    String? propertyName,
  }) async {
    state = state.copyWith(
      propertyId: propertyId,
      propertyName: propertyName,
      ledger: null,
      entriesMessage: null,
    );
    await _loadEntries(++_generation);
  }

  Future<void> selectPeriod(String? periodId) async {
    state = state.copyWith(periodId: periodId, entriesMessage: null);
    await _loadEntries(++_generation);
  }

  Future<void> _loadEntries(int generation) async {
    final String? workspaceId = _scope.workspaceId;
    final String? propertyId = state.propertyId;
    if (workspaceId == null || propertyId == null) {
      return;
    }
    final result = await _ledgerPort.readEntries(
      workspaceId: workspaceId,
      propertyId: propertyId,
      periodId: state.periodId,
    );
    if (generation != _generation || !mounted) {
      return;
    }
    switch (result) {
      case FinanceRepositorySuccess<FinanceLedgerOverviewDto>(:final value):
        state = state.copyWith(ledger: value, entriesMessage: null);
      case FinanceRepositoryFailure<FinanceLedgerOverviewDto>(:final message):
        // Only the entry half is dropped. A property this member may not see
        // is a fact about that property, not a broken screen — the periods
        // stay, and so does everything else on it.
        state = state.copyWith(ledger: null, entriesMessage: message);
    }
  }

  Future<CostPoolActionFailure?> openPeriod({
    required int fiscalYear,
    required int periodMonth,
  }) async {
    final CostPoolActionFailure? refusal = _guard(canBook, 'Buchungen');
    if (refusal != null) {
      return refusal;
    }
    _running();
    final result = await _periodsPort.openPeriod(
      OpenFinancePeriodCommand(
        context: _context(),
        fiscalYear: fiscalYear,
        periodMonth: periodMonth,
      ),
    );
    return _settle<FinancePeriodDto>(result, 'Periode geöffnet.');
  }

  Future<CostPoolActionFailure?> setPeriodState({
    required FinancePeriodDto period,
    required FinancePeriodState target,
    String? reason,
  }) async {
    final CostPoolActionFailure? refusal = _guard(
      canClose,
      'das Abschließen von Perioden',
    );
    if (refusal != null) {
      return refusal;
    }
    _running();
    final result = await _periodsPort.transitionPeriod(
      TransitionFinancePeriodCommand(
        context: _context(reason: reason),
        periodId: period.id,
        targetState: target,
        // The version of the row the caller is looking at, never re-read at
        // submit time: a refusal reloads the list, and a retry carrying a
        // fresher version with the older intent is how a concurrent change
        // gets overwritten.
        expectedVersion: period.version,
      ),
    );
    return _settle<FinancePeriodDto>(
      result,
      target == FinancePeriodState.closed
          ? 'Periode abgeschlossen.'
          : 'Periode wieder geöffnet.',
    );
  }

  Future<CostPoolActionFailure?> book({
    required String accountId,
    required String periodId,
    required DateTime bookedOn,
    required num amount,
    required String currencyCode,
    String? description,
    String? unitId,
  }) async {
    final CostPoolActionFailure? refusal = _guard(canBook, 'Buchungen');
    if (refusal != null) {
      return refusal;
    }
    final String? propertyId = state.propertyId;
    if (propertyId == null) {
      return const CostPoolActionFailure(
        message: 'Zuerst ein Objekt wählen — eine Buchung gehört zu einem Objekt.',
      );
    }
    _running();
    final result = await _ledgerPort.recordEntry(
      RecordFinanceLedgerEntryCommand(
        context: _context(),
        propertyId: propertyId,
        accountId: accountId,
        periodId: periodId,
        bookedOn: bookedOn,
        amount: amount,
        currencyCode: currencyCode,
        description: description,
        unitId: unitId,
      ),
    );
    return _settle<FinanceLedgerEntryDto>(result, 'Buchung erfasst.');
  }

  void _running() {
    state = state.copyWith(
      actionPhase: FinanceBookingActionPhase.running,
      actionMessage: null,
      actionField: null,
    );
  }

  CostPoolActionFailure? _guard(bool permitted, String subject) {
    // Checked before touching state: this controller is autoDispose and its
    // provider watches the session scope, so a token refresh between opening a
    // dialog and pressing save disposes it while the dialog still holds it.
    if (!mounted) {
      return const CostPoolActionFailure(
        message: 'Die Sitzung wurde neu geladen. Bitte erneut versuchen.',
      );
    }
    if (permitted) {
      return null;
    }
    final CostPoolActionFailure refusal = CostPoolActionFailure(
      message: 'Für $subject fehlt die erforderliche Berechtigung.',
    );
    state = state.copyWith(
      actionPhase: FinanceBookingActionPhase.failed,
      actionMessage: refusal.message,
      actionField: null,
    );
    return refusal;
  }

  FinanceCommandContext _context({String? reason}) => FinanceCommandContext(
    workspaceId: _scope.workspaceId!,
    actorId: _scope.actorId!,
    mutationId: _idFactory(),
    correlationId: _idFactory(),
    // Never an empty string: the shared finance gate refuses a reason of
    // length zero outright, so "no reason" has to be null.
    reason: (reason != null && reason.trim().isNotEmpty) ? reason.trim() : null,
  );

  Future<CostPoolActionFailure?> _settle<T>(
    FinanceRepositoryResult<T> result,
    String successMessage,
  ) async {
    if (!mounted) {
      return const CostPoolActionFailure(
        message: 'Die Sitzung wurde neu geladen. Bitte erneut versuchen.',
      );
    }
    switch (result) {
      case FinanceRepositorySuccess<T>():
        state = state.copyWith(
          actionPhase: FinanceBookingActionPhase.succeeded,
          actionMessage: successMessage,
          actionField: null,
        );
        await load();
        return null;
      case FinanceRepositoryFailure<T>(:final message, :final field):
        state = state.copyWith(
          actionPhase: FinanceBookingActionPhase.failed,
          actionMessage: message,
          actionField: field,
        );
        // Re-read after a refusal too: a refusal means this side's picture and
        // the server's disagreed — a period somebody else closed, a version
        // that moved — and the next attempt is built from what is on screen.
        await load();
        return CostPoolActionFailure(message: message, field: field);
    }
  }
}

final financeBookingControllerProvider = StateNotifierProvider.autoDispose<
  FinanceBookingController,
  FinanceBookingState
>((Ref ref) {
  final controller = FinanceBookingController(
    periodsPort: ref.watch(financePeriodsProvider),
    ledgerPort: ref.watch(propertyLedgerProvider),
    scope: ref.watch(workspaceSessionScopeProvider),
  );
  unawaited(controller.load());
  return controller;
});
