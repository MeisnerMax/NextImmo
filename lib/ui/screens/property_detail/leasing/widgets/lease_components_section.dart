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
    this.canMutate = false,
    this.onAdd,
    this.onEdit,
    this.onClose,
    this.inceptionNote = true,
  });

  final LeaseComponentsPhase phase;
  final LeaseComponentsAsOfDto? components;
  final VoidCallback onRetry;

  /// Whether this member may write components (`lease.manage`). The server
  /// checks it too; this only decides whether an action is offered, so nobody
  /// spends a round trip on a certain refusal.
  final bool canMutate;

  /// Opens the form. The argument preselects the type, so the action on an
  /// unrecorded row lands in the form already knowing what it is for.
  final void Function(LeaseComponentType? preselectedType)? onAdd;
  final void Function(LeaseComponentDto component)? onEdit;
  final void Function(LeaseComponentDto component)? onClose;

  /// Whether to explain how this section relates to the contract figures above
  /// it. On by default; off where the section stands alone.
  final bool inceptionNote;

  /// The total is summed in this widget, and that is a known deviation rather
  /// than an oversight.
  ///
  /// DEC-026 puts rent-schedule derivation on the server, and P2-D05b is the
  /// precedent where a client-side live calculation was pulled back a release
  /// later. A plain sum of rows the server already decided is a much smaller
  /// claim than a rule engine — but it is still arithmetic on money in a
  /// screen, so it is labelled as such above and belongs server-side with the
  /// warm-rent aggregate (P-7), which has to decide the same VAT question this
  /// widget currently answers alone.
  ///
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
                // Precise about which half is which. The components and the
                // decision of what is in force on this date come from the
                // server; the total below is summed here, and saying otherwise
                // would be the kind of claim DEC-026 exists to prevent.
                'Stand ${formatLeaseDate(components!.asOfDate)}. '
                    'Bestandteile serverseitig ermittelt; die Summe wird hier '
                    'gebildet.',
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
        if (canMutate && onAdd != null) ...<Widget>[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('lease-component-add'),
              onPressed: () => onAdd!(null),
              icon: const Icon(Icons.add),
              label: const Text('Bestandteil hinzufügen'),
            ),
          ),
        ],
      ];
    }

    final total = resolved.recordedTotal;
    return <Widget>[
      for (final type in _ordered)
        _ComponentRow(
          label: _typeLabel(type),
          component: resolved.ofType(type),
          canMutate: canMutate,
          onAdd: onAdd == null ? null : () => onAdd!(type),
          onEdit: onEdit,
          onClose: onClose,
        ),
      // An unfamiliar type is shown rather than dropped: leaving it out would
      // understate what a tenant pays, and this build cannot know what it is.
      for (final component in unknown)
        _ComponentRow(
          label: component.rawTypeKey ?? 'Unbekannter Bestandteil',
          component: component,
          unfamiliar: true,
          // Deliberately no actions: this build does not know what the type
          // means, so it must not offer to rewrite it.
          canMutate: false,
        ),
      const Divider(height: 24),
      _ComponentTotalRow(total: total),
      const SizedBox(height: 8),
      Text(
        total == null ? _noTotalExplanation(resolved) : _absenceExplanation,
        style: theme.textTheme.bodySmall,
      ),
      if (canMutate && onAdd != null) ...<Widget>[
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('lease-component-add'),
            onPressed: () => onAdd!(null),
            icon: const Icon(Icons.add),
            label: const Text('Bestandteil hinzufügen'),
          ),
        ),
      ],
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

  /// Why there is no total, in the words of the reason there is none. A single
  /// catch-all sentence would have named the currency case for a lease whose
  /// real problem is that net and gross amounts cannot be added.
  static String _noTotalExplanation(LeaseComponentsAsOfDto resolved) {
    final currencies = resolved.components
        .map((c) => c.currencyCode)
        .toSet();
    if (currencies.length > 1) {
      return 'Die erfassten Bestandteile lauten auf verschiedene Währungen '
          'und werden deshalb nicht summiert.';
    }
    if (resolved.components.any(
      (c) => c.vatMode == LeaseComponentVatMode.unknown,
    )) {
      return 'Für mindestens einen Bestandteil ist die Steuerbehandlung '
          'unbekannt, deshalb wird nicht summiert.';
    }
    return 'Netto- und Bruttobeträge stehen nebeneinander. Eine Summe daraus '
        'wäre weder das eine noch das andere, deshalb wird nicht summiert.';
  }

  /// Names both readings of an absent component, because they are different
  /// and this section cannot tell them apart.
  ///
  /// The as-of read returns what is in force on one date. A component that was
  /// ended — the returned parking space in the demo data is exactly this — is
  /// therefore absent today, and shows the same way as one that was never
  /// entered. "Nicht erfasst" is true for the date either way, but a reader who
  /// remembers the parking charge would take it for lost data unless the
  /// sentence says otherwise. The honest fix is a history read, which the
  /// server does not offer yet; until it does, this says so.
  static const String _absenceExplanation =
      'Nicht erfasst heißt nicht null: für diesen Stichtag liegt kein '
      'Bestandteil dieser Art vor. Er kann fehlen oder beendet sein — eine '
      'Historie zeigt dieser Abschnitt noch nicht.';

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
    this.canMutate = false,
    this.onAdd,
    this.onEdit,
    this.onClose,
  });

  final String label;
  final LeaseComponentDto? component;
  final bool unfamiliar;
  final bool canMutate;
  final VoidCallback? onAdd;
  final void Function(LeaseComponentDto component)? onEdit;
  final void Function(LeaseComponentDto component)? onClose;

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
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text(
                        'nicht erfasst',
                        style: muted,
                        textAlign: TextAlign.end,
                      ),
                      if (canMutate && onAdd != null)
                        TextButton(
                          onPressed: onAdd,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('erfassen'),
                        ),
                    ],
                  )
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
                      if (canMutate && (onEdit != null || onClose != null))
                        // A menu rather than two buttons: at 320px two labelled
                        // controls per row push the amount off the line, and
                        // the amount is what the row is for.
                        PopupMenuButton<String>(
                          key: Key('lease-component-actions-${resolved.id}'),
                          tooltip: 'Aktionen',
                          padding: EdgeInsets.zero,
                          onSelected: (value) {
                            if (value == 'edit') {
                              onEdit?.call(resolved);
                            } else if (value == 'close') {
                              onClose?.call(resolved);
                            }
                          },
                          itemBuilder: (context) => <PopupMenuEntry<String>>[
                            if (onEdit != null)
                              const PopupMenuItem<String>(
                                value: 'edit',
                                child: Text('Bearbeiten'),
                              ),
                            // Only what is still running can be ended. A
                            // component that already has an end date is changed
                            // through the form, where the date is a field
                            // rather than the whole action.
                            if (onClose != null && resolved.isOpenEnded)
                              const PopupMenuItem<String>(
                                value: 'close',
                                child: Text('Beenden'),
                              ),
                          ],
                          icon: const Icon(Icons.more_horiz, size: 20),
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

  final ({double amount, String currencyCode, bool isNet})? total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolved = total;
    return Row(
      children: <Widget>[
        Expanded(
          flex: 3,
          child: Text(
            // The label carries the qualifier rather than a footnote: a net
            // total read as a payable one is off by the tax rate.
            resolved != null && resolved.isNet
                ? 'Summe der erfassten Bestandteile (netto)'
                : 'Summe der erfassten Bestandteile',
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
