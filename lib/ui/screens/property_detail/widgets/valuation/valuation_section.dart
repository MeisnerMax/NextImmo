import 'package:flutter/material.dart';

import '../../../../../features/valuation/application/valuation_case_controller.dart';
import '../../../../../features/valuation/domain/valuation_method.dart';
import '../../../../components/nx_card.dart';
import '../../../../components/nx_empty_state.dart';
import '../../../../components/nx_section_header.dart';
import '../../../../components/nx_status_badge.dart';
import '../../../../widgets/kpi_card.dart';
import 'assumption_ledger_table.dart';
import 'market_value_card.dart';
import 'valuation_badges.dart';
import 'valuation_formatting.dart';
import 'valuation_method_card.dart';

/// The Wertermittlung section of the analysis screen (Welle 5, AP1).
///
/// Pure presentation over [ValuationCaseState]: every mandatory screen state of
/// `03_design_system.md` is a branch here, and the domain's own two states —
/// "nicht ermittelbar" per method and "published report is stale" — are first
/// class rather than edge cases.
class ValuationSection extends StatelessWidget {
  const ValuationSection({
    super.key,
    required this.state,
    this.onRetry,
    this.onPublish,
    this.onApprove,
    this.onAcceptSuggestion,
    this.onJumpToFactor,
    this.onCreateCase,
  });

  final ValuationCaseState state;
  final VoidCallback? onRetry;

  /// Null when the caller may not publish — the button is then absent rather
  /// than present-and-failing.
  final VoidCallback? onPublish;
  final VoidCallback? onApprove;
  final void Function(String factorId)? onAcceptSuggestion;
  final void Function(String factorId)? onJumpToFactor;
  final VoidCallback? onCreateCase;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        NxSectionHeader(
          title: 'Wertermittlung',
          description:
              'Verfahren nach ImmoWertV und Investmentrechnung, zusammengeführt '
              'zu einem Verkehrswert.',
          trailing: state.valuationCase == null
              ? null
              : ValuationStatusBadge(status: state.valuationCase!.status),
          actions: _actions(),
        ),
        const SizedBox(height: 12),
        _body(context),
      ],
    );
  }

  List<Widget> _actions() => <Widget>[
    if (onPublish != null)
      FilledButton.tonal(
        onPressed: onPublish,
        child: const Text('Bericht veröffentlichen'),
      ),
    if (onApprove != null)
      OutlinedButton(onPressed: onApprove, child: const Text('Freigeben')),
  ];

  Widget _body(BuildContext context) {
    switch (state.loadPhase) {
      case ValuationLoadPhase.idle:
      case ValuationLoadPhase.loading:
        return const _LoadingSkeleton();
      case ValuationLoadPhase.forbidden:
        return NxEmptyState(
          icon: Icons.lock_outline,
          title: 'Kein Zugriff auf Bewertungen',
          description:
              state.message ??
              'Für diesen Arbeitsbereich fehlt die Berechtigung „Bewertung '
                  'lesen".',
        );
      case ValuationLoadPhase.empty:
        return NxEmptyState(
          icon: Icons.calculate_outlined,
          title: 'Noch keine Bewertung',
          description:
              'Lege einen Bewertungsfall an, um Ertrags-, Sach- und '
              'Vergleichswert sowie DCF zu rechnen.',
          primaryAction: onCreateCase == null
              ? null
              : FilledButton(
                  onPressed: onCreateCase,
                  child: const Text('Bewertung anlegen'),
                ),
        );
      case ValuationLoadPhase.error:
        return NxEmptyState(
          icon: Icons.error_outline,
          title: 'Bewertung konnte nicht geladen werden',
          description:
              state.message ?? 'Bitte erneut versuchen.',
          primaryAction: onRetry == null
              ? null
              : OutlinedButton(
                  onPressed: onRetry,
                  child: const Text('Erneut versuchen'),
                ),
        );
      case ValuationLoadPhase.ready:
        return _ReadyBody(
          state: state,
          onAcceptSuggestion: onAcceptSuggestion,
          onJumpToFactor: onJumpToFactor,
          onPublish: onPublish,
        );
    }
  }
}

class _ReadyBody extends StatelessWidget {
  const _ReadyBody({
    required this.state,
    this.onAcceptSuggestion,
    this.onJumpToFactor,
    this.onPublish,
  });

  final ValuationCaseState state;
  final void Function(String factorId)? onAcceptSuggestion;
  final void Function(String factorId)? onJumpToFactor;
  final VoidCallback? onPublish;

  @override
  Widget build(BuildContext context) {
    final report = state.liveReport;
    if (report == null) {
      return const NxEmptyState(
        icon: Icons.calculate_outlined,
        title: 'Noch kein Ergebnis',
        description: 'Es liegen keine Faktoren vor, aus denen gerechnet werden '
            'könnte.',
      );
    }

    final results = report.methodResults.entries.toList()
      ..sort((a, b) => a.key.index.compareTo(b.key.index));
    final leading = results
        .where((entry) => entry.value is MethodValue)
        .map((entry) => entry.key)
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ActionNotice(state: state),
        MarketValueCard(
          opinion: report.opinion,
          isStale: state.isReportStale,
          onRecompute: onPublish,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1100
                ? 3
                : constraints.maxWidth >= 700
                ? 2
                : 1;
            final spacing = 16.0;
            final width =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: <Widget>[
                for (final entry in results)
                  SizedBox(
                    width: width,
                    child: ValuationMethodCard(
                      method: entry.key,
                      result: entry.value,
                      initiallyExpanded: entry.key == leading,
                      onAcceptSuggestion: onAcceptSuggestion,
                      onJumpToFactor: onJumpToFactor,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _InvestmentMetrics(state: state),
        const SizedBox(height: 16),
        Text(
          'Annahmen',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        AssumptionLedgerTable(assumptions: report.assumptionLedger),
      ],
    );
  }
}

/// Renders the outcome of the last mutation attempt — including the two that
/// are not failures of the user's making: the read-only backend and the closed
/// (approved) record.
class _ActionNotice extends StatelessWidget {
  const _ActionNotice({required this.state});

  final ValuationCaseState state;

  @override
  Widget build(BuildContext context) {
    final (label, kind) = switch (state.actionPhase) {
      ValuationActionPhase.readOnly => (
        'Schreibgeschützt bis migriert',
        NxBadgeKind.warning,
      ),
      ValuationActionPhase.approvedImmutable => (
        'Freigegeben – unveränderlich',
        NxBadgeKind.info,
      ),
      ValuationActionPhase.conflict => (
        'Versionskonflikt',
        NxBadgeKind.error,
      ),
      ValuationActionPhase.forbidden => ('Keine Berechtigung', NxBadgeKind.error),
      ValuationActionPhase.failed => ('Aktion fehlgeschlagen', NxBadgeKind.error),
      _ => (null, NxBadgeKind.neutral),
    };
    if (label == null) return const SizedBox.shrink();

    final conflict = state.versionConflict;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NxCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            NxStatusBadge(label: label, kind: kind),
            if (state.actionMessage != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(state.actionMessage!),
            ],
            if (conflict != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Erwartete Version ${conflict.expectedVersion}, '
                'aktuelle Version ${conflict.actualVersion}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InvestmentMetrics extends StatelessWidget {
  const _InvestmentMetrics({required this.state});

  final ValuationCaseState state;

  @override
  Widget build(BuildContext context) {
    final investment = state.liveReport?.investment;
    if (investment == null || investment.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        SizedBox(
          width: 220,
          child: KpiCard(label: 'IRR', value: formatPercent(investment.irr)),
        ),
        SizedBox(
          width: 220,
          child: KpiCard(
            label: 'NPV',
            value: formatEuro(investment.npvAtDiscountRate),
            subtitle: investment.discountRate == null
                ? null
                : 'bei ${formatPercent(investment.discountRate)} Kalkulationszins',
          ),
        ),
        SizedBox(
          width: 220,
          child: KpiCard(
            label: 'Equity Multiple',
            value: investment.equityMultiple == null
                ? notDeterminable
                : formatBreakdownAmount(investment.equityMultiple, 'x'),
          ),
        ),
      ],
    );
  }
}

/// Static placeholders in the eventual layout — deliberately not a spinner:
/// the design system asks for a skeleton that matches what is coming, and a
/// spinning indicator says "busy" without saying "what".
class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  static const Key skeletonKey = Key('valuation-section-skeleton');

  @override
  Widget build(BuildContext context) {
    final placeholder = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Column(
      key: skeletonKey,
      children: <Widget>[
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: NxCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(height: 16, width: 160, color: placeholder),
                  const SizedBox(height: 12),
                  Container(height: 28, width: 220, color: placeholder),
                  const SizedBox(height: 12),
                  Container(
                    height: 12,
                    width: double.infinity,
                    color: placeholder,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
