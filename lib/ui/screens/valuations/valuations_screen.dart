import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/valuation/application/valuation_workspace_controller.dart';
import '../../../features/valuation/domain/valuation_case.dart';
import '../../../features/valuation/domain/valuation_case_dto.dart';
import '../../components/nx_content_frame.dart';
import '../../components/nx_data_table_shell.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_page_header.dart';
import '../../components/nx_status_badge.dart';
import '../property_detail/widgets/valuation/valuation_badges.dart';
import 'valuation_create_dialog.dart';

/// The workspace-wide valuation work queue (Welle 5, AP3).
///
/// Replaces the old entry point into valuations, which was three levels deep
/// (object → scenario → Underwriting → tab) and offered no view of what was in
/// flight. The same widget serves one property when [propertyId] is set — the
/// object view is a filter, not a second screen.
class ValuationsScreen extends ConsumerWidget {
  const ValuationsScreen({
    super.key,
    this.propertyId,
    this.onOpenCase,
    this.embedded = false,
  });

  final String? propertyId;

  /// Mounted inside a host that already supplies the page frame and the
  /// property context — the property workspace's `Investment` domain. The
  /// screen then drops its own frame and title instead of stacking a second
  /// header under the workspace's.
  final bool embedded;

  /// Opens a case. Null while the case workflow (AP4) is not wired yet — the
  /// row then still selects, so the queue is usable, but nothing pretends to
  /// navigate somewhere that does not exist.
  final void Function(ValuationCaseDto valuationCase)? onOpenCase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = valuationWorkspaceControllerProvider(propertyId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (embedded)
          Align(
            alignment: Alignment.centerRight,
            child:
                controller.canCreate
                    ? FilledButton.icon(
                      onPressed: () => _createCase(context, ref, controller),
                      icon: const Icon(Icons.add),
                      label: const Text('Neue Bewertung'),
                    )
                    : const SizedBox.shrink(),
          )
        else
          NxPageHeader(
            title: 'Bewertungen',
            subtitle: _subtitle(state),
            primaryAction:
                controller.canCreate
                    ? FilledButton.icon(
                      onPressed: () => _createCase(context, ref, controller),
                      icon: const Icon(Icons.add),
                      label: const Text('Neue Bewertung'),
                    )
                    : null,
          ),
        if (!controller.canCreate)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: NxStatusBadge(
              label:
                  'Lokaler Bestand: Bewertungen sind schreibgeschützt — '
                  'Anlegen im Supabase-Modus',
              kind: NxBadgeKind.warning,
            ),
          ),
        const SizedBox(height: 12),
        _Filters(state: state, controller: controller),
        const SizedBox(height: 12),
        Expanded(
          child: _Body(
            state: state,
            controller: controller,
            onOpenCase: onOpenCase,
            onCreateCase: () => _createCase(context, ref, controller),
          ),
        ),
      ],
    );
    return embedded ? body : NxContentFrame(child: body);
  }

  String _subtitle(ValuationWorkspaceState state) {
    if (state.phase != ValuationWorkspacePhase.ready) {
      return 'Verkehrswerte nach ImmoWertV und Investmentrechnung';
    }
    final open = state.inReview.length;
    final total = state.cases.length;
    return open == 0
        ? '$total Bewertungen'
        : '$total Bewertungen · $open zur Prüfung';
  }

  Future<void> _createCase(
    BuildContext context,
    WidgetRef ref,
    ValuationWorkspaceController controller,
  ) async {
    final createdId = await showDialog<String>(
      context: context,
      builder: (context) => ValuationCreateDialog(propertyId: propertyId),
    );
    if (createdId == null) return;
    // The queue reloads and lands on the new case, so creating and continuing
    // are one movement rather than two screens.
    await controller.load();
    controller.select(createdId);
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.state, required this.controller});

  final ValuationWorkspaceState state;
  final ValuationWorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        DropdownButton<ValuationCaseStatus?>(
          value: state.statusFilter,
          hint: const Text('Status: alle'),
          onChanged: controller.filterByStatus,
          items: <DropdownMenuItem<ValuationCaseStatus?>>[
            const DropdownMenuItem<ValuationCaseStatus?>(
              child: Text('Status: alle'),
            ),
            for (final status in ValuationCaseStatus.values)
              DropdownMenuItem<ValuationCaseStatus?>(
                value: status,
                child: Text(ValuationStatusBadge.labelFor(status)),
              ),
          ],
        ),
        DropdownButton<ValuationCaseKind?>(
          value: state.kindFilter,
          hint: const Text('Art: alle'),
          onChanged: controller.filterByKind,
          items: <DropdownMenuItem<ValuationCaseKind?>>[
            const DropdownMenuItem<ValuationCaseKind?>(
              child: Text('Art: alle'),
            ),
            for (final kind in ValuationCaseKind.values)
              DropdownMenuItem<ValuationCaseKind?>(
                value: kind,
                child: Text(kind.labelDe),
              ),
          ],
        ),
        FilterChip(
          label: const Text('Archivierte einschließen'),
          selected: state.includeArchived,
          onSelected: controller.setIncludeArchived,
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.controller,
    required this.onCreateCase,
    this.onOpenCase,
  });

  final VoidCallback onCreateCase;

  final ValuationWorkspaceState state;
  final ValuationWorkspaceController controller;
  final void Function(ValuationCaseDto valuationCase)? onOpenCase;

  @override
  Widget build(BuildContext context) {
    switch (state.phase) {
      case ValuationWorkspacePhase.forbidden:
        return NxEmptyState(
          icon: Icons.lock_outline,
          title: 'Kein Zugriff auf Bewertungen',
          description:
              state.message ??
              'Für diesen Arbeitsbereich fehlt die Berechtigung „Bewertung '
                  'lesen".',
        );
      case ValuationWorkspacePhase.error:
        return NxEmptyState(
          icon: Icons.error_outline,
          title: 'Bewertungen konnten nicht geladen werden',
          description: state.message ?? 'Bitte erneut versuchen.',
          primaryAction: OutlinedButton(
            onPressed: controller.load,
            child: const Text('Erneut versuchen'),
          ),
        );
      case ValuationWorkspacePhase.empty:
        return NxEmptyState(
          icon: Icons.calculate_outlined,
          title:
              state.isFiltered
                  ? 'Keine Bewertung für diesen Filter'
                  : 'Noch keine Bewertungen',
          // A screen that invites creating something the bound backend cannot
          // create is a dead end; it says which backend can instead.
          description:
              state.isFiltered
                  ? 'Setz den Filter zurück, um alle Bewertungen zu sehen.'
                  : controller.canCreate
                  ? 'Lege die erste Bewertung an — Ertrags-, Sach- und '
                      'Vergleichswert sowie DCF werden daraus gerechnet.'
                  : 'Der lokale Bestand kann Bewertungen nur lesen: ihm fehlen '
                      'Versionierung, Idempotenz und Audit-Envelope. Zum Anlegen '
                      'die App im Supabase-Modus starten '
                      '(NEXIMMO_DATA_BACKEND=supabase).',
          primaryAction:
              controller.canCreate
                  ? FilledButton(
                    onPressed: onCreateCase,
                    child: const Text('Bewertung anlegen'),
                  )
                  : null,
        );
      case ValuationWorkspacePhase.idle:
      case ValuationWorkspacePhase.loading:
      case ValuationWorkspacePhase.ready:
        return _Table(
          state: state,
          controller: controller,
          onOpenCase: onOpenCase,
        );
    }
  }
}

class _Table extends StatelessWidget {
  const _Table({
    required this.state,
    required this.controller,
    this.onOpenCase,
  });

  final ValuationWorkspaceState state;
  final ValuationWorkspaceController controller;
  final void Function(ValuationCaseDto valuationCase)? onOpenCase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: NxDataTableShell(
            loading: state.phase == ValuationWorkspacePhase.loading,
            minTableWidth: 860,
            child: DataTable(
              showCheckboxColumn: false,
              columns: const <DataColumn>[
                DataColumn(label: Text('Bewertung')),
                DataColumn(label: Text('Art')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Aktualisiert')),
              ],
              rows: <DataRow>[
                for (final entry in state.cases)
                  DataRow(
                    selected: entry.id == state.selectedCaseId,
                    onSelectChanged: (_) {
                      controller.select(entry.id);
                      onOpenCase?.call(entry);
                    },
                    cells: <DataCell>[
                      DataCell(Text(entry.title)),
                      DataCell(Text(entry.kind.labelDe)),
                      DataCell(ValuationStatusBadge(status: entry.status)),
                      DataCell(Text(_formatDate(entry.updatedAt))),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (state.hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton(
              onPressed: state.loadingMore ? null : controller.loadMore,
              child: Text(
                state.loadingMore ? 'Lädt …' : 'Weitere Bewertungen laden',
              ),
            ),
          ),
        // Named rather than quietly missing: the reconciled value needs a join
        // between case and opinion, and loading it per row would be an N+1.
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Verkehrswert und Konfidenz stehen im geöffneten Fall — die Liste '
            'zeigt sie erst, wenn die Server-Projektion dafür steht.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year}';
  }
}
