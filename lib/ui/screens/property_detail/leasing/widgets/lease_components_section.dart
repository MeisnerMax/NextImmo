import 'package:flutter/material.dart';

import '../../../../../features/leasing_operations/application/leases_controller.dart';
import '../../../../../features/leasing_operations/domain/lease_component_dto.dart';
import '../../../../components/nx_card.dart';
import '../../../../components/nx_section_header.dart';
import 'lease_lifecycle.dart';

/// The rent components in force on a date (LEASING-COMPONENTS-01).
///
/// The section exists to answer a question the card above it cannot: the three
/// flat figures on a lease are what the contract was signed at, and they have
/// no date attached. A rent increase does not change them. This says what is
/// payable *now*, and says when "now" is.
///
/// **The design decision that matters is how a missing component is drawn.**
/// A dash or a zero in a money column reads as "nothing owed", and that is
/// exactly the reading DEC-029 forbids: where no component covers the date,
/// nothing has been *recorded*, which is a different statement. So an unrecorded
/// type is written out in words, in the muted role rather than the money role,
/// and the section says once at the bottom what the absence means.
class LeaseComponentsSection extends StatelessWidget {
  const LeaseComponentsSection({
    super.key,
    required this.phase,
    required this.components,
    required this.onRetry,
    this.inceptionNote = true,
  });

  final LeaseComponentsPhase phase;
  final LeaseComponentsAsOfDto? components;
  final VoidCallback onRetry;

  /// Whether to explain how this section relates to the contract figures above
  /// it. On by default; off where the section stands alone.
  final bool inceptionNote;

  /// The five the server knows, in the order a rent statement reads.
  static const List<LeaseComponentType> _ordered = <LeaseComponentType>[
    LeaseComponentType.baseRent,
    LeaseComponentType.serviceChargeAdvance,
    LeaseComponentType.heatingAdvance,
    LeaseComponentType.parking,
    LeaseComponentType.other,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NxCard(
      key: const Key('lease-components-section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          NxSectionHeader(
            title: 'Mietbestandteile',
            description: switch (phase) {
              LeaseComponentsPhase.ready when components != null =>
                'Stand ${formatLeaseDate(components!.asOfDate)}. '
                    'Serverseitig ermittelt, im Screen nicht nachgerechnet.',
              _ => 'Zeitversionierte Bestandteile dieses Vertrags.',
            },
          ),
          const SizedBox(height: 8),
          ..._body(context, theme),
        ],
      ),
    );
  }

  List<Widget> _body(BuildContext context, ThemeData theme) {
    switch (phase) {
      case LeaseComponentsPhase.idle:
        return const <Widget>[SizedBox.shrink()];
      case LeaseComponentsPhase.loading:
        return const <Widget>[
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(
              key: Key('lease-components-loading'),
            ),
          ),
        ];
      case LeaseComponentsPhase.forbidden:
        return <Widget>[
          Text(
            'Kein Zugriff auf die Mietbestandteile',
            key: const Key('lease-components-forbidden'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Die Bestandteile benötigen die Berechtigung (lease.read).',
            style: theme.textTheme.bodySmall,
          ),
        ];
      case LeaseComponentsPhase.error:
        return <Widget>[
          Text(
            'Mietbestandteile konnten nicht geladen werden',
            key: const Key('lease-components-error'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Erneut versuchen'),
            ),
          ),
        ];
      case LeaseComponentsPhase.ready:
        return _rows(theme);
    }
  }

  List<Widget> _rows(ThemeData theme) {
    final resolved = components;
    if (resolved == null) {
      return const <Widget>[SizedBox.shrink()];
    }

    final unknown = resolved.components
        .where((c) => c.componentType == LeaseComponentType.unknown)
        .toList(growable: false);

    if (resolved.components.isEmpty) {
      return <Widget>[
        Text(
          'Für dieses Datum ist kein Bestandteil erfasst',
          key: const Key('lease-components-empty'),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          _absenceExplanation,
          style: theme.textTheme.bodySmall,
        ),
      ];
    }

    final total = resolved.recordedTotal;
    return <Widget>[
      for (final type in _ordered)
        _ComponentRow(
          label: _typeLabel(type),
          component: resolved.ofType(type),
        ),
      // An unfamiliar type is shown rather than dropped: leaving it out would
      // understate what a tenant pays, and this build cannot know what it is.
      for (final component in unknown)
        _ComponentRow(
          label: component.rawTypeKey ?? 'Unbekannter Bestandteil',
          component: component,
          unfamiliar: true,
        ),
      const Divider(height: 24),
      _ComponentTotalRow(total: total),
      const SizedBox(height: 8),
      Text(
        total == null
            ? 'Die erfassten Bestandteile lauten auf verschiedene Währungen '
                  'und werden deshalb nicht summiert.'
            : _absenceExplanation,
        style: theme.textTheme.bodySmall,
      ),
      if (inceptionNote) ...<Widget>[
        const SizedBox(height: 8),
        Text(
          'Die Beträge unter „Miete und Nebenkosten" sind die Zahlen bei '
          'Vertragsabschluss und ändern sich nicht. Wo hier ein Bestandteil '
          'steht, gilt dieser.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    ];
  }

  static const String _absenceExplanation =
      'Nicht erfasst heißt nicht null: für einen Zeitraum ohne Bestandteil '
      'liegt keine Angabe vor.';

  static String _typeLabel(LeaseComponentType type) => switch (type) {
    LeaseComponentType.baseRent => 'Grundmiete',
    LeaseComponentType.serviceChargeAdvance => 'Betriebskostenvorauszahlung',
    LeaseComponentType.heatingAdvance => 'Heizkostenvorauszahlung',
    LeaseComponentType.parking => 'Stellplatz',
    LeaseComponentType.other => 'Sonstiges',
    LeaseComponentType.unknown => 'Unbekannter Bestandteil',
  };
}

class _ComponentRow extends StatelessWidget {
  const _ComponentRow({
    required this.label,
    required this.component,
    this.unfamiliar = false,
  });

  final String label;
  final LeaseComponentDto? component;
  final bool unfamiliar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolved = component;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontStyle: FontStyle.italic,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: unfamiliar
                  ? theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)
                  : theme.textTheme.bodyMedium,
            ),
          ),
          Expanded(
            flex: 4,
            child: resolved == null
                // Words, not a dash: a dash in a money column is read as zero.
                ? Text('nicht erfasst', style: muted, textAlign: TextAlign.end)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text(
                        formatLeaseMoney(
                          resolved.amount,
                          resolved.currencyCode,
                        ),
                        style: theme.textTheme.bodyMedium,
                      ),
                      Text(
                        _periodLabel(resolved),
                        style: theme.textTheme.bodySmall,
                        textAlign: TextAlign.end,
                      ),
                      if (_vatLabel(resolved) case final String vat)
                        Text(
                          vat,
                          style: theme.textTheme.bodySmall,
                          textAlign: TextAlign.end,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static String _periodLabel(LeaseComponentDto component) {
    final from = formatLeaseDate(component.validFrom);
    return component.isOpenEnded
        ? 'seit $from'
        : '$from – ${formatLeaseDate(component.validTo)}';
  }

  /// Null where there is nothing honest to say, which is the exempt case and
  /// the case of a mode this build does not know.
  static String? _vatLabel(LeaseComponentDto component) {
    switch (component.vatMode) {
      case LeaseComponentVatMode.exempt:
        return null;
      case LeaseComponentVatMode.unknown:
        return 'Steuerbehandlung unbekannt';
      case LeaseComponentVatMode.gross:
        final rate = component.vatRatePercent;
        return rate == null ? 'brutto' : 'brutto, enthält ${_rate(rate)} MwSt.';
      case LeaseComponentVatMode.net:
        final gross = component.grossMonthly;
        final rate = component.vatRatePercent;
        if (gross == null || rate == null) {
          // A net amount without a rate cannot be grossed up, and printing the
          // net figure as if it were the whole story would be the lie.
          return 'netto, Steuersatz nicht erfasst';
        }
        return 'netto, brutto '
            '${formatLeaseMoney(gross, component.currencyCode)} '
            '(${_rate(rate)})';
    }
  }

  static String _rate(double rate) {
    final rounded = rate.roundToDouble();
    final text = rate == rounded
        ? rounded.toStringAsFixed(0)
        : rate.toStringAsFixed(2);
    return '$text %';
  }
}

class _ComponentTotalRow extends StatelessWidget {
  const _ComponentTotalRow({required this.total});

  final ({double amount, String currencyCode})? total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolved = total;
    return Row(
      children: <Widget>[
        Expanded(
          flex: 3,
          child: Text(
            'Summe der erfassten Bestandteile',
            style: theme.textTheme.titleSmall,
          ),
        ),
        Expanded(
          flex: 4,
          child: Text(
            resolved == null
                // Never a number here: a total across currencies looks
                // authoritative and means nothing.
                ? 'nicht summierbar'
                : formatLeaseMoney(resolved.amount, resolved.currencyCode),
            key: const Key('lease-components-total'),
            style: theme.textTheme.titleSmall,
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
