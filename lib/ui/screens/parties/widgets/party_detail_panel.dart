import 'package:flutter/material.dart';

import '../../../../features/contacts_parties/application/parties_controller.dart';
import '../../../../features/contacts_parties/domain/party_dto.dart';
import '../../../components/nx_card.dart';
import '../../../components/nx_empty_state.dart';
import '../../../components/nx_section_header.dart';
import '../../../theme/app_theme.dart';
import 'party_badges.dart';

/// The identity half of the directory: who this party is, which functional
/// roles it holds over time, and the contractor satellite when it has one.
///
/// Roles live here rather than in the list because the contract's list
/// projection ([PartySummaryDto]) carries no roles — filling a roles column
/// would mean a read per row, which is exactly the N+1 pattern this wave
/// removes elsewhere. The role *filter* covers the list-level need server-side.
class PartyDetailPanel extends StatelessWidget {
  const PartyDetailPanel({
    super.key,
    required this.state,
    required this.canMutate,
    required this.readOnlyBackend,
    required this.onEdit,
    required this.onAssignRole,
    required this.onEndRole,
    required this.onMerge,
    required this.onClose,
    required this.onRetry,
    this.showCloseAction = false,
  });

  final PartiesState state;
  final bool canMutate;
  final bool readOnlyBackend;
  final VoidCallback onEdit;
  final VoidCallback onAssignRole;
  final void Function(PartyRoleDto role) onEndRole;
  final VoidCallback onMerge;
  final VoidCallback onClose;
  final VoidCallback onRetry;

  /// Narrow layouts render the panel instead of the list, so they need a way
  /// back.
  final bool showCloseAction;

  @override
  Widget build(BuildContext context) {
    switch (state.detailPhase) {
      case PartiesDetailPhase.idle:
        return const NxEmptyState(
          title: 'Keine Partei ausgewählt',
          description:
              'Wähle links eine Partei, um Identität und Rollen zu sehen.',
          icon: Icons.person_search_outlined,
        );
      case PartiesDetailPhase.loading:
        return const NxCard(
          child: Center(child: CircularProgressIndicator()),
        );
      case PartiesDetailPhase.forbidden:
        return const NxEmptyState(
          title: 'Kein Zugriff auf diese Partei',
          description:
              'Dein Konto darf diese Partei nicht sehen. Wende dich an eine '
              'Administratorin oder einen Administrator des Arbeitsbereichs.',
          icon: Icons.lock_outline,
        );
      case PartiesDetailPhase.error:
        return NxEmptyState(
          title: 'Partei konnte nicht geladen werden',
          description:
              'Beim Laden der Partei ist ein Fehler aufgetreten. Bitte '
              'versuche es erneut.',
          icon: Icons.error_outline,
          primaryAction: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Erneut versuchen'),
          ),
        );
      case PartiesDetailPhase.ready:
        final party = state.selectedParty;
        if (party == null) {
          return const SizedBox.shrink();
        }
        return _buildReady(context, party);
    }
  }

  Widget _buildReady(BuildContext context, PartyDto party) {
    final merged = party.mergedIntoPartyId != null || party.deletedAt != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        NxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              NxSectionHeader(
                title: party.displayName,
                description: party.legalName,
                compact: true,
                trailing: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    PartyTypeBadge(type: party.type),
                    PartyLifecycleBadge(merged: merged),
                  ],
                ),
                actions: <Widget>[
                  if (showCloseAction)
                    TextButton.icon(
                      onPressed: onClose,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Zur Liste'),
                    ),
                  _MutationButton(
                    canMutate: canMutate && !merged,
                    readOnlyBackend: readOnlyBackend,
                    onPressed: onEdit,
                    icon: Icons.edit_outlined,
                    label: 'Bearbeiten',
                  ),
                  _MutationButton(
                    canMutate: canMutate && !merged,
                    readOnlyBackend: readOnlyBackend,
                    onPressed: onMerge,
                    icon: Icons.merge_outlined,
                    label: 'Zusammenführen',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.component),
              _Field(label: 'E-Mail', value: party.email),
              _Field(label: 'Telefon', value: party.phone),
              _Field(label: 'Notizen', value: party.notes),
              _Field(label: 'Version', value: '${party.version}'),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        NxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              NxSectionHeader(
                title: 'Rollen',
                description:
                    'Fachliche Rollen dieser Partei, zeitlich begrenzbar.',
                compact: true,
                actions: <Widget>[
                  _MutationButton(
                    canMutate: canMutate && !merged,
                    readOnlyBackend: readOnlyBackend,
                    onPressed: onAssignRole,
                    icon: Icons.add,
                    label: 'Rolle zuweisen',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (state.roles.isEmpty)
                Text(
                  'Noch keine Rolle zugewiesen.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.semanticColors.textSecondary,
                  ),
                )
              else
                for (final role in state.roles)
                  _RoleRow(
                    role: role,
                    canMutate: canMutate && !merged,
                    readOnlyBackend: readOnlyBackend,
                    onEnd: () => onEndRole(role),
                  ),
            ],
          ),
        ),
        if (state.contractorDetails != null) ...<Widget>[
          const SizedBox(height: AppSpacing.component),
          _ContractorCard(details: state.contractorDetails!),
        ],
      ],
    );
  }
}

class _RoleRow extends StatelessWidget {
  const _RoleRow({
    required this.role,
    required this.canMutate,
    required this.readOnlyBackend,
    required this.onEnd,
  });

  final PartyRoleDto role;
  final bool canMutate;
  final bool readOnlyBackend;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final validity =
        role.isOpen
            ? 'seit ${_formatDate(role.validFrom)}'
            : '${_formatDate(role.validFrom)} – ${_formatDate(role.validUntil!)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          PartyRoleBadge(role: role.roleType, closed: !role.isOpen),
          Text(validity, style: Theme.of(context).textTheme.bodySmall),
          if (role.isOpen)
            _MutationButton(
              canMutate: canMutate,
              readOnlyBackend: readOnlyBackend,
              onPressed: onEnd,
              icon: Icons.event_busy_outlined,
              label: 'Beenden',
            ),
        ],
      ),
    );
  }
}

class _ContractorCard extends StatelessWidget {
  const _ContractorCard({required this.details});

  final ContractorDetailsDto details;

  @override
  Widget build(BuildContext context) {
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const NxSectionHeader(
            title: 'Dienstleister-Details',
            description: 'Satellit der Dienstleister-Rolle.',
            compact: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          _Field(label: 'Gewerk', value: details.tradeCategory),
          _Field(
            label: 'Stundensatz',
            value:
                details.hourlyRate == null
                    ? null
                    : '${details.hourlyRate!.toStringAsFixed(2)} €',
          ),
          _Field(label: 'Einsatzgebiet', value: details.serviceArea),
          _Field(label: 'Aktiv', value: details.isActive ? 'Ja' : 'Nein'),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.semanticColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value == null || value!.trim().isEmpty ? '—' : value!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// A mutation affordance that explains *why* it is unavailable instead of
/// silently no-opping: the backend is read-only until migrated, or the actor
/// lacks the capability.
class _MutationButton extends StatelessWidget {
  const _MutationButton({
    required this.canMutate,
    required this.readOnlyBackend,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final bool canMutate;
  final bool readOnlyBackend;
  final VoidCallback onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton.icon(
      onPressed: canMutate ? onPressed : null,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
    if (canMutate) {
      return button;
    }
    return Tooltip(
      message:
          readOnlyBackend
              ? 'Schreibgeschützt bis zur Migration dieser Domäne.'
              : 'Dafür fehlt die Berechtigung.',
      child: button,
    );
  }
}

String _formatDate(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day.$month.${value.year}';
}
