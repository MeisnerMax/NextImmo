/// `Investment → Performance → Ergebnis` (FINANCE-01a,
/// `PROPERTY_PERFORMANCE_V2.md`): what has actually been booked against this
/// property, per account and per currency.
///
/// The spec plans four local areas here — `Übersicht`, `Ergebnis & Cashflow`,
/// `Budget & Forecast`, `Debt & Covenants`. This screen is the part of the
/// second one the ledger foundation can honestly serve, and it says so on the
/// screen rather than in a commit message: a notice names what is booked, what
/// is not yet computed, and which package will compute it.
///
/// Three rules it enforces at the render layer:
///
///   * **No result line.** Income and expense are shown as separate subtotals
///     per currency, and nothing subtracts one from the other. A net result is
///     a formula, and §7 requires a definition version to travel with any
///     computed figure; that versioning is `FINANCE-01b`. A subtotal *within*
///     one account class in one currency is a sum of like things and needs no
///     version, which is why those are offered and the difference is not.
///   * **Currencies never merge.** One section per currency. There is no
///     conversion, because a reporting currency needs an approved rate source
///     with a rate date.
///   * **Provisional says so.** While any covered period is open, the figures
///     carry a notice naming how many, so a half-booked month cannot be read
///     as a closed one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/components/nx_card.dart';
import '../../../ui/components/nx_empty_state.dart';
import '../../../ui/components/nx_list_skeleton.dart';
import '../../../ui/components/nx_notice.dart';
import '../../../ui/theme/app_theme.dart';
import '../../portfolio_property/presentation/property_presentation.dart';
import '../application/property_finance_controller.dart';
import '../domain/finance_actuals_dto.dart';

/// German label for an account class.
String financeAccountTypeLabel(FinanceAccountType type, String rawKey) {
  return switch (type) {
    FinanceAccountType.income => 'Erträge',
    FinanceAccountType.expense => 'Aufwendungen',
    FinanceAccountType.asset => 'Aktiva',
    FinanceAccountType.liability => 'Passiva',
    FinanceAccountType.equity => 'Eigenkapital',
    // A class this build cannot name keeps the server's key, so a newer
    // server's account class is visible instead of missing from the statement.
    FinanceAccountType.unknown => rawKey,
  };
}

/// Two decimals and a German decimal comma, with the currency after the
/// number. No `intl` dependency exists in this app and none is added here.
String formatFinanceAmount(num amount, String currencyCode) {
  final text = amount.toDouble().toStringAsFixed(2).replaceAll('.', ',');
  return '$text $currencyCode';
}

class PropertyFinancePanel extends ConsumerStatefulWidget {
  const PropertyFinancePanel({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<PropertyFinancePanel> createState() =>
      _PropertyFinancePanelState();
}

class _PropertyFinancePanelState extends ConsumerState<PropertyFinancePanel> {
  @override
  Widget build(BuildContext context) {
    final provider = propertyFinanceControllerProvider(widget.propertyId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    switch (state.phase) {
      case PropertyFinancePhase.idle:
        return const SizedBox.shrink();
      case PropertyFinancePhase.loading:
        return const SingleChildScrollView(
          key: Key('property-finance-loading'),
          padding: EdgeInsets.all(AppSpacing.component),
          child: NxListSkeleton(rows: 5),
        );
      case PropertyFinancePhase.forbidden:
        return NxEmptyState(
          key: const Key('property-finance-forbidden'),
          title: 'Kein Zugriff auf die Zahlen',
          description:
              state.message ??
              'Für diese Ansicht fehlt eine Berechtigung.',
          icon: Icons.lock_outline,
        );
      case PropertyFinancePhase.error:
        return NxEmptyState.error(
          key: const Key('property-finance-error'),
          title: 'Buchungen konnten nicht geladen werden',
          description:
              state.message ?? 'Die Buchungen sind derzeit nicht verfügbar.',
          onRetry: controller.load,
        );
      case PropertyFinancePhase.empty:
        return ListView(
          key: const Key('property-finance-empty-view'),
          padding: const EdgeInsets.all(AppSpacing.component),
          children: const <Widget>[
            NxEmptyState(
              key: Key('property-finance-empty'),
              title: 'Noch nichts gebucht',
              description:
                  'Für dieses Objekt liegen im gewählten Zeitraum keine '
                  'Buchungen vor. Das ist keine Null — es ist noch nichts '
                  'erfasst.',
              icon: Icons.receipt_long_outlined,
            ),
            SizedBox(height: AppSpacing.component),
            _ScopeNotice(),
          ],
        );
      case PropertyFinancePhase.ready:
        return _Statement(actuals: state.actuals!, onReload: controller.load);
    }
  }
}

class _Statement extends StatelessWidget {
  const _Statement({required this.actuals, required this.onReload});

  final PropertyFinanceActualsDto actuals;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const Key('property-finance'),
      padding: const EdgeInsets.all(AppSpacing.component),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Stand: ${formatPropertyTimestamp(actuals.asOf)}',
                key: const Key('property-finance-as-of'),
                style: theme.textTheme.bodySmall,
              ),
            ),
            TextButton.icon(
              key: const Key('property-finance-refresh'),
              onPressed: onReload,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Aktualisieren'),
            ),
          ],
        ),
        if (actuals.isProvisional) ...[
          const SizedBox(height: AppSpacing.xs),
          NxNotice(
            key: const Key('property-finance-provisional'),
            kind: NxNoticeKind.warning,
            icon: Icons.hourglass_empty,
            title: 'Vorläufige Zahlen',
            message:
                '${actuals.openPeriods} von ${actuals.coveredPeriods} '
                'einbezogenen Perioden sind noch offen. Die Beträge können '
                'sich noch ändern.',
          ),
        ],
        const SizedBox(height: AppSpacing.component),
        for (final currency in actuals.currencies) ...[
          _CurrencySection(actuals: actuals, currencyCode: currency),
          const SizedBox(height: AppSpacing.component),
        ],
        _PeriodCoverage(periods: actuals.periods),
        const SizedBox(height: AppSpacing.component),
        const _ScopeNotice(),
      ],
    );
  }
}

/// One currency, one section. The order of the classes is the order a reader
/// expects a statement in; the accounts inside keep the server's order.
class _CurrencySection extends StatelessWidget {
  const _CurrencySection({required this.actuals, required this.currencyCode});

  final PropertyFinanceActualsDto actuals;
  final String currencyCode;

  static const List<FinanceAccountType> _order = <FinanceAccountType>[
    FinanceAccountType.income,
    FinanceAccountType.expense,
    FinanceAccountType.asset,
    FinanceAccountType.liability,
    FinanceAccountType.equity,
    FinanceAccountType.unknown,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NxCard(
      key: Key('property-finance-currency-$currencyCode'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(currencyCode, style: theme.textTheme.titleSmall),
          if (actuals.currencies.length > 1)
            Text(
              'Eigene Währung, nicht mit den anderen verrechnet',
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: AppSpacing.sm),
          for (final type in _order)
            if (actuals.linesOf(type, currencyCode).isNotEmpty)
              _ClassBlock(
                type: type,
                currencyCode: currencyCode,
                lines: actuals.linesOf(type, currencyCode),
                subtotal: actuals.subtotalOf(type, currencyCode),
              ),
        ],
      ),
    );
  }
}

class _ClassBlock extends StatelessWidget {
  const _ClassBlock({
    required this.type,
    required this.currencyCode,
    required this.lines,
    required this.subtotal,
  });

  final FinanceAccountType type;
  final String currencyCode;
  final List<FinanceActualLine> lines;
  final num subtotal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = financeAccountTypeLabel(type, lines.first.accountTypeKey);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.component),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          for (final line in lines)
            _AccountRow(line: line, currencyCode: currencyCode),
          const Divider(height: AppSpacing.component),
          _AmountRow(
            fieldKey:
                'property-finance-subtotal-'
                '${_typeKey(type, lines.first.accountTypeKey)}-$currencyCode',
            label: 'Summe $label',
            value: formatFinanceAmount(subtotal, currencyCode),
            emphasised: true,
          ),
        ],
      ),
    );
  }

  static String _typeKey(FinanceAccountType type, String rawKey) =>
      type == FinanceAccountType.unknown ? rawKey : type.name;
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.line, required this.currencyCode});

  final FinanceActualLine line;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return _AmountRow(
      fieldKey: 'property-finance-account-${line.accountId}-$currencyCode',
      label: '${line.accountCode} · ${line.accountName}',
      caption: line.entries == 1 ? '1 Buchung' : '${line.entries} Buchungen',
      value: formatFinanceAmount(line.amount, currencyCode),
    );
  }
}

/// Label left, amount right.
///
/// The amount is the non-flexible child, so `Row` gives it its full intrinsic
/// width and the label takes what is left and wraps. That ordering is the
/// point: on a narrow screen a long account name loses a line, never a digit.
class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.fieldKey,
    required this.label,
    required this.value,
    this.caption,
    this.emphasised = false,
  });

  final String fieldKey;
  final String label;
  final String? caption;
  final String value;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = emphasised
        ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)
        : theme.textTheme.bodyMedium;
    return Semantics(
      key: Key(fieldKey),
      container: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: labelStyle),
                  if (caption != null)
                    Text(caption!, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(value, style: labelStyle, textAlign: TextAlign.right),
          ],
        ),
      ),
    );
  }
}

/// Which months the figures drew on, and which of them are final.
class _PeriodCoverage extends StatelessWidget {
  const _PeriodCoverage({required this.periods});

  final List<FinancePeriodCoverage> periods;

  @override
  Widget build(BuildContext context) {
    if (periods.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return NxCard(
      key: const Key('property-finance-periods'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Einbezogene Perioden', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.xs,
            children: [
              for (final period in periods)
                Semantics(
                  key: Key('property-finance-period-${period.periodId}'),
                  container: true,
                  label:
                      '${_month(period)}: '
                      '${period.isClosed ? 'abgeschlossen' : 'offen'}, '
                      '${period.entries} Buchungen',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _month(period),
                        style: theme.textTheme.labelMedium,
                      ),
                      Text(
                        period.isClosed ? 'abgeschlossen' : 'offen',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _month(FinancePeriodCoverage period) =>
      '${period.periodMonth.toString().padLeft(2, '0')}/${period.fiscalYear}';
}

/// What this screen does and does not yet answer. On the screen rather than
/// only in the specification, because a reader who expects an NOI and does not
/// find one deserves to be told why here.
class _ScopeNotice extends StatelessWidget {
  const _ScopeNotice();

  @override
  Widget build(BuildContext context) {
    return const NxNotice(
      key: Key('property-finance-scope'),
      kind: NxNoticeKind.info,
      icon: Icons.info_outline,
      title: 'Was hier steht — und was noch nicht',
      message:
          'Gezeigt werden die gebuchten Ist-Werte je Konto und Währung. '
          'NOI, Cashflow, Budgetabweichung und Covenants fehlen bewusst: '
          'jede dieser Größen ist eine Formel, und eine berechnete Zahl muss '
          'ihre Definitionsversion mitführen, damit sie nachrechenbar bleibt. '
          'Diese Versionierung liefert das nächste Inkrement (FINANCE-01b). '
          'Bis dahin wird summiert, was gebucht ist — und nichts daraus '
          'abgeleitet.',
    );
  }
}
