/// Screen-facing orchestration for the legal rule layer
/// (`COMPLIANCE-RULES-01`, V-4).
///
/// The screen shows the rules in force on a date, and the date is a control the
/// reader operates — not a default nobody chose. That is the feature: asking
/// "what did the law say in 2024" is how a retrospective correction gets made
/// correctly, and a screen that could only show today would make that
/// impossible.
///
/// **Nothing here counts anything.** The unverified and decision-support totals
/// come from the server, taken over the whole matched set. Counting the list
/// would tie the figure to whatever the current filter happens to hold.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/compliance_rule_dto.dart';
import 'compliance_rules_providers.dart';
import 'compliance_rules_repository.dart';

const Object _unchanged = Object();

enum ComplianceRulesPhase { idle, loading, ready, forbidden, error }

enum ComplianceRulesActionPhase { idle, running, failed, succeeded }

class ComplianceRulesState {
  const ComplianceRulesState({
    this.phase = ComplianceRulesPhase.idle,
    this.actionPhase = ComplianceRulesActionPhase.idle,
    this.ruleSet,
    this.asOfDate,
    this.message,
    this.actionMessage,
    this.versionConflict,
  });

  final ComplianceRulesPhase phase;
  final ComplianceRulesActionPhase actionPhase;

  /// Null until the first answer lands, and null again after a failure — never
  /// an empty list standing in for one. "This workspace has recorded no legal
  /// rules" and "the rules could not be read" are different statements, and
  /// only the first is safe to act on.
  final ComplianceRuleSetDto? ruleSet;

  /// The date the reader asked about. Null means "today", which the server
  /// resolves and reports back.
  final DateTime? asOfDate;

  final String? message;
  final String? actionMessage;
  final ComplianceRuleVersionConflict? versionConflict;

  List<ComplianceRuleDto> get rules =>
      ruleSet?.rules ?? const <ComplianceRuleDto>[];

  int get unverifiedCount => ruleSet?.unverifiedCount ?? 0;
  int get decisionSupportCount => ruleSet?.decisionSupportCount ?? 0;

  /// The date the answer was actually computed for. Distinct from [asOfDate],
  /// which is what the reader asked: when they asked for nothing, the server
  /// chose, and the screen has to show the choice rather than imply it.
  DateTime? get effectiveDate => ruleSet?.asOfDate;

  ComplianceRulesState copyWith({
    ComplianceRulesPhase? phase,
    ComplianceRulesActionPhase? actionPhase,
    Object? ruleSet = _unchanged,
    Object? asOfDate = _unchanged,
    Object? message = _unchanged,
    Object? actionMessage = _unchanged,
    Object? versionConflict = _unchanged,
  }) {
    return ComplianceRulesState(
      phase: phase ?? this.phase,
      actionPhase: actionPhase ?? this.actionPhase,
      ruleSet: identical(ruleSet, _unchanged)
          ? this.ruleSet
          : ruleSet as ComplianceRuleSetDto?,
      asOfDate: identical(asOfDate, _unchanged)
          ? this.asOfDate
          : asOfDate as DateTime?,
      message: identical(message, _unchanged) ? this.message : message as String?,
      actionMessage: identical(actionMessage, _unchanged)
          ? this.actionMessage
          : actionMessage as String?,
      versionConflict: identical(versionConflict, _unchanged)
          ? this.versionConflict
          : versionConflict as ComplianceRuleVersionConflict?,
    );
  }
}

class ComplianceRulesController extends StateNotifier<ComplianceRulesState> {
  ComplianceRulesController({
    required ComplianceRulesPort port,
    required WorkspaceSessionScope scope,
    String Function()? idFactory,
  }) : _port = port,
       _scope = scope,
       _idFactory = idFactory ?? (() => const Uuid().v4()),
       super(const ComplianceRulesState());

  final ComplianceRulesPort _port;
  final WorkspaceSessionScope _scope;
  final String Function() _idFactory;

  int _generation = 0;

  /// Whether this member may change the rules. `security.manage`, not
  /// `workspace.manage` — the latter does not exist in the catalogue, and the
  /// workspace's legal position is administration rather than day-to-day data.
  /// The server checks it too; this only decides whether an action is offered,
  /// so nobody spends a round trip on a certain refusal.
  bool get canMutate =>
      _scope.mutationsSupported && _scope.permissions.contains('security.manage');

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      state = state.copyWith(
        phase: ComplianceRulesPhase.forbidden,
        ruleSet: null,
        message: 'Kein Workspace ausgewählt.',
      );
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(
      phase: ComplianceRulesPhase.loading,
      message: null,
    );
    final result = await _port.readAsOf(
      ComplianceRulesQuery(
        workspaceId: workspaceId,
        asOfDate: state.asOfDate,
      ),
    );
    if (generation != _generation || !mounted) {
      return;
    }
    switch (result) {
      case ComplianceRulesSuccess<ComplianceRuleSetDto>(:final value):
        state = state.copyWith(
          phase: ComplianceRulesPhase.ready,
          ruleSet: value,
          message: null,
        );
      case ComplianceRulesFailure<ComplianceRuleSetDto>(:final kind, :final message):
        state = state.copyWith(
          phase: kind == ComplianceRulesFailureKind.forbidden
              ? ComplianceRulesPhase.forbidden
              : ComplianceRulesPhase.error,
          ruleSet: null,
          message: message,
        );
    }
  }

  /// Changes the date the rules are asked about, and re-reads.
  ///
  /// Server-side, because that is where the validity periods are. A client-side
  /// filter over one day's answer could not produce another day's.
  Future<void> setAsOfDate(DateTime? asOfDate) async {
    state = state.copyWith(asOfDate: asOfDate);
    await load();
  }

  Future<void> upsert({
    required String ruleKey,
    required DateTime validFrom,
    required Object value,
    required String sourceReference,
    DateTime? validTo,
    String? unit,
    String? note,
    bool decisionSupport = false,
    ComplianceRuleDto? existing,
  }) async {
    await _run(
      () => _port.upsert(
        UpsertComplianceRuleCommand(
          context: _context(),
          ruleId: existing?.id,
          expectedVersion: existing?.version,
          ruleKey: ruleKey,
          validFrom: validFrom,
          validTo: validTo,
          value: value,
          sourceReference: sourceReference,
          unit: unit,
          note: note,
          decisionSupport: decisionSupport,
        ),
      ),
      successMessage: existing == null
          ? 'Regel angelegt. Sie gilt als ungeprüft, bis jemand sie bestätigt.'
          // Said out loud, because it is a consequence the reader did not ask
          // for: they corrected a figure and the confirmation fell away with
          // it. Silently dropping a verification would be worse.
          : 'Regel geändert. Die Bestätigung ist damit erloschen.',
    );
  }

  Future<void> verify({
    required ComplianceRuleDto rule,
    required bool verified,
    String? verificationNote,
  }) async {
    await _run(
      () => _port.verify(
        VerifyComplianceRuleCommand(
          context: _context(),
          ruleId: rule.id,
          expectedVersion: rule.version,
          verified: verified,
          verificationNote: verificationNote,
        ),
      ),
      successMessage: verified
          ? 'Regel bestätigt.'
          : 'Bestätigung zurückgezogen.',
    );
  }

  Future<void> _run(
    Future<ComplianceRulesResult<ComplianceRuleDto>> Function() command, {
    required String successMessage,
  }) async {
    if (!canMutate) {
      state = state.copyWith(
        actionPhase: ComplianceRulesActionPhase.failed,
        actionMessage:
            'Für Rechtsregeln fehlt die Berechtigung zur '
            'Workspace-Administration.',
      );
      return;
    }
    state = state.copyWith(
      actionPhase: ComplianceRulesActionPhase.running,
      actionMessage: null,
      versionConflict: null,
    );
    final result = await command();
    if (!mounted) {
      return;
    }
    switch (result) {
      case ComplianceRulesSuccess<ComplianceRuleDto>():
        state = state.copyWith(
          actionPhase: ComplianceRulesActionPhase.succeeded,
          actionMessage: successMessage,
        );
        // Re-read rather than patching the list. The rule that changed may
        // have moved out of the date being shown, and reproducing the server's
        // validity arithmetic here is how two answers to "what applies today"
        // start to differ.
        await load();
      case ComplianceRulesFailure<ComplianceRuleDto>(
        :final kind,
        :final message,
        :final versionConflict,
      ):
        state = state.copyWith(
          actionPhase: ComplianceRulesActionPhase.failed,
          actionMessage: switch (kind) {
            ComplianceRulesFailureKind.overlap =>
              'Für diesen Schlüssel gibt es in dem Zeitraum bereits eine '
                  'Regel. Zwei Regeln für einen Tag hätten zwei Antworten.',
            _ => message,
          },
          versionConflict: versionConflict,
        );
    }
  }

  ComplianceCommandContext _context() {
    return ComplianceCommandContext(
      workspaceId: _scope.workspaceId!,
      actorId: _scope.actorId!,
      mutationId: _idFactory(),
      correlationId: _idFactory(),
    );
  }
}

final complianceRulesControllerProvider = StateNotifierProvider.autoDispose<
  ComplianceRulesController,
  ComplianceRulesState
>((Ref ref) {
  final controller = ComplianceRulesController(
    port: ref.watch(complianceRulesPortProvider),
    scope: ref.watch(workspaceSessionScopeProvider),
  );
  unawaited(controller.load());
  return controller;
});
