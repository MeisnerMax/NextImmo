/// Screen-facing orchestration for a property's leasing summary
/// (LEASING-SUMMARY-01).
///
/// A single read with no filters and no local derivation. The controller's
/// only real decision is the one it makes before the round trip: the server
/// gates on `property.read` *and* `lease.read`, so a session holding only the
/// first is told which capability is missing instead of being shown a generic
/// failure.
///
/// Nothing here computes. There is no occupancy rate, no cross-currency total
/// and no "risk" — the state exposes exactly the fields the server sent, and
/// the widgets read them.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/leasing_summary_dto.dart';
import 'leasing_providers.dart';
import 'leasing_repository.dart';

const Object _unchanged = Object();

/// [idle] is the settled "no workspace resolved, nothing asked" state, not a
/// pre-loading one: the controller starts the read in its constructor, so a
/// surface that is still idle after that has no session to read for.
enum PropertyLeasingSummaryPhase { idle, loading, ready, forbidden, error }

class PropertyLeasingSummaryState {
  const PropertyLeasingSummaryState({
    this.phase = PropertyLeasingSummaryPhase.idle,
    this.summary,
    this.message,
  });

  final PropertyLeasingSummaryPhase phase;

  /// Null unless [phase] is ready. There is no empty placeholder: a property
  /// with no units still has a real summary, all of it zero, and that is a
  /// fact rather than a missing source.
  final PropertyLeasingSummaryDto? summary;

  final String? message;

  bool get isBusy => phase == PropertyLeasingSummaryPhase.loading;

  PropertyLeasingSummaryState copyWith({
    PropertyLeasingSummaryPhase? phase,
    Object? summary = _unchanged,
    Object? message = _unchanged,
  }) {
    return PropertyLeasingSummaryState(
      phase: phase ?? this.phase,
      summary: identical(summary, _unchanged)
          ? this.summary
          : summary as PropertyLeasingSummaryDto?,
      message: identical(message, _unchanged) ? this.message : message as String?,
    );
  }
}

class PropertyLeasingSummaryController
    extends StateNotifier<PropertyLeasingSummaryState> {
  PropertyLeasingSummaryController({
    required this.propertyId,
    required PropertyLeasingSummaryPort port,
    required WorkspaceSessionScope scope,
  }) : _port = port,
       _scope = scope,
       super(const PropertyLeasingSummaryState());

  static const String leaseReadPermission = 'lease.read';
  static const String propertyReadPermission = 'property.read';

  final String propertyId;
  final PropertyLeasingSummaryPort _port;
  final WorkspaceSessionScope _scope;

  int _generation = 0;

  bool get canRead =>
      _scope.permissions.contains(leaseReadPermission) &&
      _scope.permissions.contains(propertyReadPermission);

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      // No workspace is resolved yet, so there is nothing to ask the server
      // for. This has to leave a *settled* state: an unresolved session that
      // stayed `loading` would spin forever, which reads as "still working"
      // when in fact no work was ever started.
      state = state.copyWith(
        phase: PropertyLeasingSummaryPhase.idle,
        summary: null,
        message: null,
      );
      return;
    }
    if (!canRead) {
      // Both gates matter, and which one is missing changes who the user has
      // to ask. The server refuses either way; naming it here saves a round
      // trip without inventing an outcome.
      state = state.copyWith(
        phase: PropertyLeasingSummaryPhase.forbidden,
        summary: null,
        message: _scope.permissions.contains(leaseReadPermission)
            ? 'Für diese Ansicht fehlt die Berechtigung "property.read".'
            : 'Für diese Ansicht fehlt die Berechtigung "lease.read".',
      );
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(
      phase: PropertyLeasingSummaryPhase.loading,
      message: null,
    );
    final result = await _port.read(
      workspaceId: workspaceId,
      propertyId: propertyId,
    );
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case LeasingRepositorySuccess<PropertyLeasingSummaryDto>(:final value):
        state = state.copyWith(
          phase: PropertyLeasingSummaryPhase.ready,
          summary: value,
          message: null,
        );
      case LeasingRepositoryFailure<PropertyLeasingSummaryDto>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          phase: kind == LeasingRepositoryFailureKind.forbidden
              ? PropertyLeasingSummaryPhase.forbidden
              : PropertyLeasingSummaryPhase.error,
          summary: null,
          message: message,
        );
    }
  }
}

final propertyLeasingSummaryControllerProvider =
    StateNotifierProvider.autoDispose
        .family<
          PropertyLeasingSummaryController,
          PropertyLeasingSummaryState,
          String
        >((ref, propertyId) {
          final controller = PropertyLeasingSummaryController(
            propertyId: propertyId,
            port: ref.watch(propertyLeasingSummaryProvider),
            scope: ref.watch(workspaceSessionScopeProvider),
          );
          controller.load();
          return controller;
        });
