/// What a property actually spent (`FINANCE-BOOKINGS-01`).
///
/// **This is the surface the last five packages were missing.** P-2a decided
/// which costs may be passed on, P-2b built the pools and keys, P-2c the
/// per-unit figures, F-1 made the cost types creatable — and none of it could
/// produce a number, because nothing could record what a building actually
/// paid. This screen is where that starts.
///
/// **A booking cannot be edited or deleted, and the screen never hides that.**
/// A mistake is answered by a negative counter-booking, and both rows stay in
/// the list: netting them away would hide the mistake along with its
/// correction.
///
/// **An unclassified cost is counted, not filtered.** A cost type nobody has
/// classified is booked like any other and then sits outside every settlement
/// until somebody decides. That is work standing between these bookings and an
/// abrechnung, so the count is on the screen rather than discovered later.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/finance_ledger/application/cost_allocation_controller.dart';
import '../../../features/finance_ledger/application/finance_booking_controller.dart';
import '../../../features/finance_ledger/domain/cost_allocation_dto.dart';
import '../../../features/finance_ledger/domain/finance_booking_dto.dart';
import '../../../features/identity_access/application/workspace_session_scope.dart';
import '../../../features/portfolio_property/application/property_repository.dart';
import '../../../features/portfolio_property/domain/property_dto.dart';
import '../../../features/portfolio_property/presentation/property_switcher_dialog.dart';
import '../../../features/reference_slice/application/reference_slice_controller.dart';
import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_kpi_tile.dart';
import '../../components/nx_notice.dart';
import '../../components/nx_page_header.dart';
import '../../components/nx_responsive_grid.dart';
import '../../components/nx_section_header.dart';
import '../../components/nx_status_badge.dart';
import '../../theme/app_theme.dart';
import 'finance_booking_dialog.dart';

class FinanceBookingsScreen extends ConsumerStatefulWidget {
  const FinanceBookingsScreen({super.key});

  @override
  ConsumerState<FinanceBookingsScreen> createState() =>
      _FinanceBookingsScreenState();
}

class _FinanceBookingsScreenState
    extends ConsumerState<FinanceBookingsScreen> {
  @override
  Widget build(BuildContext context) {
    final FinanceBookingState state = ref.watch(
      financeBookingControllerProvider,
    );
    final FinanceBookingController controller = ref.read(
      financeBookingControllerProvider.notifier,
    );
    // Watched, not read: the provider is autoDispose and loads from its own
    // body, so a bare read returns its empty initial state and disposes the
    // controller before the load lands — which is how a picker ends up
    // permanently empty.
    final List<CostAccountAllocationDto> accounts = ref
        .watch(costAllocationControllerProvider)
        .accounts;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const NxPageHeader(
            title: 'Buchungen',
            subtitle:
                'Was ein Objekt tatsächlich ausgegeben hat, je Periode. Die '
                'Grundlage jeder Betriebskostenabrechnung.',
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(child: _body(context, state, controller, accounts)),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    FinanceBookingState state,
    FinanceBookingController controller,
    List<CostAccountAllocationDto> accounts,
  ) {
    switch (state.phase) {
      case FinanceBookingPhase.idle:
      case FinanceBookingPhase.loading:
        return const Center(
          child: CircularProgressIndicator(key: Key('finance-booking-loading')),
        );
      case FinanceBookingPhase.forbidden:
        return NxCard(
          child: NxEmptyState(
            key: const Key('finance-booking-forbidden'),
            title: 'Kein Zugriff',
            description:
                state.message ??
                'Für Buchungen fehlt die Leseberechtigung für Finanzdaten.',
            icon: Icons.lock_outline,
          ),
        );
      case FinanceBookingPhase.error:
        return NxCard(
          child: NxEmptyState(
            key: const Key('finance-booking-error'),
            title: 'Die Perioden konnten nicht geladen werden',
            description: state.message ?? 'Bitte erneut versuchen.',
            icon: Icons.error_outline,
          ),
        );
      case FinanceBookingPhase.ready:
        return _ready(context, state, controller, accounts);
    }
  }

  Widget _ready(
    BuildContext context,
    FinanceBookingState state,
    FinanceBookingController controller,
    List<CostAccountAllocationDto> accounts,
  ) {
    final semantic = context.semanticColors;
    final theme = Theme.of(context);

    return ListView(
      key: const Key('finance-booking-list'),
      children: <Widget>[
        NxResponsiveGrid(
          maxColumns: 3,
          children: <Widget>[
            NxKpiTile(
              label: 'Offene Perioden',
              value: '${state.periods?.openCount ?? 0}',
              caption: 'von ${state.periods?.totalCount ?? 0} insgesamt',
            ),
            NxKpiTile(
              label: 'Buchungen',
              value: '${state.ledger?.totalCount ?? 0}',
              caption: state.propertyId == null
                  ? 'kein Objekt gewählt'
                  : 'für dieses Objekt und diese Auswahl',
            ),
            NxKpiTile(
              label: 'Nicht eingeordnet',
              value: '${state.unclassifiedOnPage}',
              status: state.unclassifiedOnPage > 0 ? semantic.warning : null,
              // The work between these bookings and a settlement.
              caption: 'Kostenarten ohne Umlage-Entscheidung',
            ),
          ],
        ),
        if (state.actionMessage != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          NxNotice(
            key: const Key('finance-booking-action-message'),
            message: state.actionMessage!,
            kind: state.actionPhase == FinanceBookingActionPhase.failed
                ? NxNoticeKind.error
                : NxNoticeKind.info,
          ),
        ],
        const SizedBox(height: AppSpacing.md),

        // --- The selection -------------------------------------------------
        NxSectionHeader(
          title: 'Auswahl',
          description:
              'Eine Buchung gehört zu einem Objekt und einer Periode. Die '
              'Periode gilt für den ganzen Workspace, das Objekt nicht.',
          actions: <Widget>[
            if (controller.canBook)
              OutlinedButton.icon(
                key: const Key('finance-period-open'),
                onPressed: () => _openPeriod(controller),
                icon: const Icon(Icons.event_available_outlined, size: 18),
                label: const Text('Periode öffnen'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        NxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      state.propertyName ?? 'Kein Objekt gewählt',
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    key: const Key('finance-booking-pick-property'),
                    onPressed: () => _pickProperty(controller),
                    child: Text(
                      state.propertyId == null ? 'Objekt wählen' : 'Wechseln',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String?>(
                key: const Key('finance-booking-period'),
                value: state.periodList.any(
                  (FinancePeriodDto p) => p.id == state.periodId,
                )
                    ? state.periodId
                    : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Periode',
                  helperText: state.periodList.isEmpty
                      ? 'Noch keine Periode geöffnet.'
                      : null,
                ),
                items: <DropdownMenuItem<String?>>[
                  const DropdownMenuItem<String?>(child: Text('Alle Perioden')),
                  for (final FinancePeriodDto period in state.periodList)
                    DropdownMenuItem<String?>(
                      value: period.id,
                      child: Text(
                        period.isOpen
                            ? '${period.label} · offen (${period.entryCount})'
                            : '${period.label} · abgeschlossen '
                                  '(${period.entryCount})',
                      ),
                    ),
                ],
                onChanged: (String? value) => controller.selectPeriod(value),
              ),
              if (state.selectedPeriod != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                _PeriodActions(
                  period: state.selectedPeriod!,
                  canClose: controller.canClose,
                  onClose: () => _setPeriodState(
                    controller,
                    state.selectedPeriod!,
                    FinancePeriodState.closed,
                  ),
                  onReopen: () => _setPeriodState(
                    controller,
                    state.selectedPeriod!,
                    FinancePeriodState.open,
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // --- The bookings --------------------------------------------------
        NxSectionHeader(
          title: 'Buchungen',
          description:
              'Eine Buchung lässt sich nicht ändern oder löschen — eine '
              'Gegenbuchung mit negativem Betrag gleicht sie aus, und beide '
              'Zeilen bleiben stehen.',
          actions: <Widget>[
            if (controller.canBook && state.canBookNow)
              FilledButton.icon(
                key: const Key('finance-booking-create'),
                onPressed: () => _book(controller, state, accounts),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Buchung erfassen'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),

        if (state.entriesMessage != null)
          NxCard(
            child: NxEmptyState(
              key: const Key('finance-booking-entries-error'),
              title: 'Die Buchungen konnten nicht geladen werden',
              description: state.entriesMessage!,
              icon: Icons.lock_outline,
            ),
          )
        else if (state.propertyId == null)
          const NxCard(
            child: NxEmptyState(
              key: Key('finance-booking-no-property'),
              title: 'Kein Objekt gewählt',
              description:
                  'Eine Buchung gehört zu einem Objekt. Oben eines wählen, '
                  'dann erscheinen hier seine Buchungen.',
              icon: Icons.apartment_outlined,
            ),
          )
        else if (state.entries.isEmpty)
          NxCard(
            child: NxEmptyState(
              key: const Key('finance-booking-empty'),
              title: 'Noch nichts gebucht',
              description: state.periodList.isEmpty
                  ? 'Es ist noch keine Periode geöffnet. Ohne Periode kann '
                        'nichts gebucht werden.'
                  : 'Für diese Auswahl liegen keine Buchungen vor.',
              icon: Icons.receipt_long_outlined,
            ),
          )
        else ...<Widget>[
          if (state.ledger!.isTruncated)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: NxNotice(
                key: const Key('finance-booking-truncated'),
                message:
                    'Es werden ${state.ledger!.returnedCount} von '
                    '${state.ledger!.totalCount} Buchungen gezeigt. Die '
                    'Auswahl über die Periode eingrenzen.',
                kind: NxNoticeKind.warning,
              ),
            ),
          for (final FinanceLedgerEntryDto entry in state.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: _EntryRow(entry: entry),
            ),
        ],
      ],
    );
  }

  Future<void> _pickProperty(FinanceBookingController controller) async {
    final PropertyRepository repository = ref.read(
      referencePropertyRepositoryProvider,
    );
    final String? workspaceId = ref
        .read(workspaceSessionScopeProvider)
        .workspaceId;
    final String? chosen = await PropertySwitcherDialog.show(
      context,
      currentPropertyId:
          ref.read(financeBookingControllerProvider).propertyId ?? '',
      loadPage: ({String? cursor, String? searchTerm}) async {
        if (workspaceId == null) {
          return const PropertyRepositoryFailure<PropertyPageResult>(
            kind: PropertyRepositoryFailureKind.forbidden,
            message: 'Kein Workspace ausgewählt.',
          );
        }
        return repository.list(
          PropertyListQuery(
            workspaceId: workspaceId,
            page: PropertyPageRequest(cursor: cursor),
            searchTerm: searchTerm,
          ),
        );
      },
    );
    if (chosen == null || workspaceId == null || !mounted) {
      return;
    }
    // The name is fetched once so the header reads as a building rather than
    // as a uuid.
    final PropertyRepositoryResult<PropertyDto> named = await repository
        .getById(workspaceId: workspaceId, propertyId: chosen);
    final String? name =
        named is PropertyRepositorySuccess<PropertyDto> ? named.value.name : null;
    await controller.selectProperty(propertyId: chosen, propertyName: name);
  }

  Future<void> _openPeriod(FinanceBookingController controller) async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year, now.month, 1),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 2, 12, 31),
      helpText: 'Monat der Periode wählen',
    );
    if (picked == null) {
      return;
    }
    await controller.openPeriod(
      fiscalYear: picked.year,
      periodMonth: picked.month,
    );
  }

  Future<void> _setPeriodState(
    FinanceBookingController controller,
    FinancePeriodDto period,
    FinancePeriodState target,
  ) async {
    String? reason;
    if (target == FinancePeriodState.open) {
      // The server refuses a blank reason on reopening, and it is the right
      // refusal: reopening a sealed month is the kind of act that should be
      // explainable afterwards.
      reason = await _askReason(period);
      if (reason == null) {
        return;
      }
    }
    await controller.setPeriodState(
      period: period,
      target: target,
      reason: reason,
    );
  }

  Future<String?> _askReason(FinancePeriodDto period) async {
    final TextEditingController input = TextEditingController();
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        key: const Key('finance-period-reopen-dialog'),
        title: Text('Periode ${period.label} wieder öffnen'),
        content: TextField(
          key: const Key('finance-period-reopen-reason'),
          controller: input,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Begründung',
            helperText:
                'Pflicht. Sie steht anschließend im Protokoll, weil das '
                'Wiederöffnen eines abgeschlossenen Monats erklärbar bleiben '
                'muss.',
            helperMaxLines: 3,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: const Key('finance-period-reopen-submit'),
            onPressed: () {
              final String text = input.text.trim();
              if (text.isEmpty) {
                return;
              }
              Navigator.of(dialogContext).pop(text);
            },
            child: const Text('Wieder öffnen'),
          ),
        ],
      ),
    );
    input.dispose();
    return reason;
  }

  Future<void> _book(
    FinanceBookingController controller,
    FinanceBookingState state,
    List<CostAccountAllocationDto> accounts,
  ) async {
    final FinancePeriodDto? period = state.selectedPeriod;
    if (period == null) {
      return;
    }
    await showFinanceBookingDialog(
      context,
      period: period,
      propertyName: state.propertyName ?? 'Objekt',
      accounts: accounts,
      onSubmit: (FinanceBookingFormResult result) => controller.book(
        accountId: result.accountId,
        periodId: period.id,
        bookedOn: result.bookedOn,
        amount: result.amount,
        currencyCode: result.currencyCode,
        description: result.description,
      ),
    );
  }
}

class _PeriodActions extends StatelessWidget {
  const _PeriodActions({
    required this.period,
    required this.canClose,
    required this.onClose,
    required this.onReopen,
  });

  final FinancePeriodDto period;
  final bool canClose;
  final VoidCallback onClose;
  final VoidCallback onReopen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        if (period.isOpen)
          const NxStatusBadge(label: 'Offen', kind: NxBadgeKind.success)
        else
          const NxStatusBadge(
            label: 'Abgeschlossen',
            kind: NxBadgeKind.neutral,
          ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            period.isOpen
                ? '${period.entryCount} Buchungen im ganzen Workspace'
                : 'Nimmt keine Buchungen mehr auf',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (canClose && period.isActionable)
          TextButton(
            key: Key('finance-period-toggle-${period.id}'),
            onPressed: period.isOpen ? onClose : onReopen,
            child: Text(period.isOpen ? 'Abschließen' : 'Wieder öffnen'),
          ),
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final FinanceLedgerEntryDto entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  '${entry.accountCode ?? '—'} · ${entry.accountName ?? ''}',
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '${_formatAmount(entry.amount)} ${entry.currencyCode}',
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            <String>[
              _formatDate(entry.bookedOn),
              if (entry.periodMonth != null && entry.periodFiscalYear != null)
                'Periode ${entry.periodMonth.toString().padLeft(2, '0')}/'
                    '${entry.periodFiscalYear}',
              if (entry.unitCode != null) entry.unitCode!,
            ].join(' · '),
            style: muted,
          ),
          if (entry.description != null)
            Text(entry.description!, style: muted),
          const SizedBox(height: AppSpacing.xxs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: <Widget>[
              // Three states drawn three ways. "Not classified" and "not
              // apportionable" mean different things and must not look alike:
              // only one of them is a decision somebody made.
              if (entry.allocatable == null)
                const NxStatusBadge(
                  key: Key('finance-booking-entry-unclassified'),
                  label: 'Nicht eingeordnet',
                  kind: NxBadgeKind.warning,
                )
              else if (entry.allocatable!)
                const NxStatusBadge(
                  label: 'Umlagefähig',
                  kind: NxBadgeKind.success,
                )
              else
                const NxStatusBadge(
                  label: 'Nicht umlagefähig',
                  kind: NxBadgeKind.neutral,
                ),
              if (entry.isCounterBooking)
                const NxStatusBadge(
                  key: Key('finance-booking-entry-counter'),
                  label: 'Gegenbuchung',
                  kind: NxBadgeKind.neutral,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime value) {
  final String day = value.day.toString().padLeft(2, '0');
  final String month = value.month.toString().padLeft(2, '0');
  return '$day.$month.${value.year}';
}

/// German formatting: full stop groups thousands, comma separates decimals.
/// Always two decimals, because a money figure that sometimes shows one reads
/// as a different quantity.
String _formatAmount(num value) {
  final bool negative = value < 0;
  final String fixed = value.abs().toStringAsFixed(2);
  final List<String> parts = fixed.split('.');
  final String whole = parts[0];
  final StringBuffer grouped = StringBuffer();
  for (int i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) {
      grouped.write('.');
    }
    grouped.write(whole[i]);
  }
  return '${negative ? '−' : ''}$grouped,${parts[1]}';
}
