/// A supplier's framework and utility contracts
/// (`SUPPLIER-CONTRACTS-01`, P-3).
///
/// It sits on the supplier because that is what a contract is about — the lift
/// maintenance agreement belongs to the company that signed it, not to one of
/// the nine buildings it covers.
///
/// **Every date and every judgement here comes from the server.** The notice
/// deadline, whether it has passed, whether the window is still open: all of
/// it was computed against the date the read asked for, and none of it is
/// recomputed on this side. With no scheduler anywhere in this product, that
/// derivation is the only thing standing between a contract quietly renewing
/// itself and somebody noticing in time — and two implementations of it would
/// eventually disagree about which day that was.
///
/// **A missed notice deadline is the loudest thing on the card**, because it
/// is the one state nobody can fix afterwards.
library;

import 'package:flutter/material.dart';

import '../../../../features/contacts_parties/application/contractors_controller.dart';
import '../../../../features/contacts_parties/domain/supplier_contract_dto.dart';
import '../../../components/nx_card.dart';
import '../../../components/nx_empty_state.dart';
import '../../../components/nx_section_header.dart';
import '../../../components/nx_status_badge.dart';
import '../../../theme/app_theme.dart';

String supplierContractStatusLabel(SupplierContractDto contract) =>
    switch (contract.status) {
      SupplierContractStatus.draft => 'Entwurf',
      SupplierContractStatus.active => 'Aktiv',
      SupplierContractStatus.ended => 'Beendet',
      // Shown raw: a status this build does not know is visibly unfamiliar
      // rather than quietly renamed.
      SupplierContractStatus.unknown => contract.rawStatusKey ?? 'Unbekannt',
    };

NxBadgeKind supplierContractStatusKind(SupplierContractStatus status) =>
    switch (status) {
      SupplierContractStatus.active => NxBadgeKind.success,
      SupplierContractStatus.draft => NxBadgeKind.neutral,
      SupplierContractStatus.ended => NxBadgeKind.neutral,
      SupplierContractStatus.unknown => NxBadgeKind.warning,
    };

String formatSupplierContractDate(DateTime? value) {
  if (value == null) {
    return '—';
  }
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}.'
      '${local.month.toString().padLeft(2, '0')}.${local.year}';
}

class SupplierContractsSection extends StatelessWidget {
  const SupplierContractsSection({
    super.key,
    required this.phase,
    required this.contracts,
    required this.canMutate,
    this.onAdd,
    this.onEdit,
    this.onEnd,
    this.onRetry,
  });

  final SupplierContractsPhase phase;
  final List<SupplierContractDto> contracts;
  final bool canMutate;
  final VoidCallback? onAdd;
  final void Function(SupplierContractDto contract)? onEdit;
  final void Function(SupplierContractDto contract)? onEnd;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return NxCard(
      key: const Key('supplier-contracts-section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          NxSectionHeader(
            title: 'Verträge',
            description:
                'Fristen werden zum Lesezeitpunkt berechnet, nicht '
                'gespeichert — es gibt keinen Scheduler, der eine gespeicherte '
                'Frist nachziehen würde.',
            actions: <Widget>[
              if (canMutate && onAdd != null)
                TextButton.icon(
                  key: const Key('supplier-contract-add'),
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Vertrag anlegen'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ..._body(context),
        ],
      ),
    );
  }

  List<Widget> _body(BuildContext context) {
    switch (phase) {
      case SupplierContractsPhase.idle:
        return const <Widget>[SizedBox.shrink()];
      case SupplierContractsPhase.loading:
        return const <Widget>[
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(
              key: Key('supplier-contracts-loading'),
            ),
          ),
        ];
      case SupplierContractsPhase.error:
        return <Widget>[
          Text(
            'Die Verträge konnten nicht geladen werden.',
            key: const Key('supplier-contracts-error'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Erneut laden')),
        ];
      case SupplierContractsPhase.ready:
        if (contracts.isEmpty) {
          return <Widget>[
            const NxEmptyState(
              key: Key('supplier-contracts-empty'),
              title: 'Kein Vertrag hinterlegt',
              description:
                  'Die meisten Lieferanten arbeiten ohne Rahmenvertrag. Ein '
                  'fehlender Vertrag ist kein Mangel.',
              icon: Icons.description_outlined,
            ),
          ];
        }
        return <Widget>[
          for (final SupplierContractDto contract in contracts)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: _ContractRow(
                contract: contract,
                canMutate: canMutate,
                onEdit: onEdit,
                onEnd: onEnd,
              ),
            ),
        ];
    }
  }
}

class _ContractRow extends StatelessWidget {
  const _ContractRow({
    required this.contract,
    required this.canMutate,
    this.onEdit,
    this.onEnd,
  });

  final SupplierContractDto contract;
  final bool canMutate;
  final void Function(SupplierContractDto contract)? onEdit;
  final void Function(SupplierContractDto contract)? onEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(contract.title, style: theme.textTheme.titleSmall),
              ),
              const SizedBox(width: AppSpacing.xs),
              NxStatusBadge(
                label: supplierContractStatusLabel(contract),
                kind: supplierContractStatusKind(contract.status),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${contract.contractType} · '
            '${formatSupplierContractDate(contract.startDate)} – '
            '${contract.endDate == null ? 'offen' : formatSupplierContractDate(contract.endDate)}',
            style: muted,
          ),
          if (contract.isPortfolioWide) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text('Gilt für das gesamte Portfolio', style: muted),
          ],
          // The loudest thing on the card, because it is the one state nobody
          // can fix afterwards: the contract will run on and the moment to
          // stop it has gone.
          if (contract.noticeDeadlinePassed) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Row(
              key: const Key('supplier-contract-notice-missed'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.error_outline, size: 16, color: semantic.error),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(
                    'Kündigungsfrist am '
                    '${formatSupplierContractDate(contract.noticeDeadline)} '
                    'abgelaufen — der Vertrag läuft weiter.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: semantic.error,
                    ),
                  ),
                ),
              ],
            ),
          ] else if (contract.noticeDeadline != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Kündigung bis '
              '${formatSupplierContractDate(contract.noticeDeadline)}'
              '${contract.daysToNotice == null ? '' : ' (noch ${contract.daysToNotice} Tage)'}',
              key: const Key('supplier-contract-notice-open'),
              style: muted,
            ),
          ] else if (contract.endDate != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              // "None was agreed" and "it is due today" are different
              // statements, and a dash in a deadline column would read as the
              // second.
              'Keine Kündigungsfrist vereinbart',
              key: const Key('supplier-contract-no-notice'),
              style: muted,
            ),
          ],
          if (contract.renewsOn != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Verlängert sich am '
              '${formatSupplierContractDate(contract.renewsOn)}'
              '${contract.renewalTermMonths == null ? '' : ' um ${contract.renewalTermMonths} Monate'}',
              style: muted,
            ),
          ],
          if (contract.annualValue != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Jahreswert: ${contract.annualValue!.toStringAsFixed(2)} '
              '${contract.currencyCode ?? ''}',
              style: muted,
            ),
          ],
          if (contract.endedReason != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text('Beendet: ${contract.endedReason}', style: muted),
          ],
          if (canMutate && !contract.isEnded) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                if (onEdit != null)
                  OutlinedButton.icon(
                    key: Key('supplier-contract-edit-${contract.id}'),
                    onPressed: () => onEdit!(contract),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Bearbeiten'),
                  ),
                if (onEnd != null)
                  OutlinedButton.icon(
                    key: Key('supplier-contract-end-${contract.id}'),
                    onPressed: () => onEnd!(contract),
                    icon: const Icon(Icons.event_busy_outlined, size: 18),
                    label: const Text('Beenden'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
