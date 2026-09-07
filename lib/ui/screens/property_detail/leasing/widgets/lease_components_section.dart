import 'package:flutter/material.dart';

import '../../../../../features/leasing_operations/application/leases_controller.dart';
import '../../../../../features/leasing_operations/domain/lease_component_dto.dart';
import '../../../../../features/leasing_operations/domain/warm_rent_dto.dart';
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
    this.warmRent,
    this.canMutate = false,
    this.onAdd,
    this.onEdit,
    this.onClose,
    this.onShowHistory,
    this.inceptionNote = true,
  });

  final LeaseComponentsPhase phase;
  final LeaseComponentsAsOfDto? components;
  final VoidCallback onRetry;

  /// The server's warm rent for this lease (WARM-RENT-01).
  ///
  /// This section used to sum the components itself, and the header said it
  /// did not — a claim DEC-026 exists to prevent and P2-D05b is the precedent
  /// for pulling back. The figure now comes from the one place that owns the
  /// composition rule, and where it is null this section shows no total rather
  /// than inventing one.
  final WarmRentDto? warmRent;

  /// Whether this member may write components (`lease.manage`). The server
  /// checks it too; this only decides whether an action is offered, so nobody
  /// spends a round trip on a certain refusal.
  final bool canMutate;

  /// Opens the form. The argument preselects the type, so the action on an
  /// unrecorded row lands in the form already knowing what it is for.
  final void Function(LeaseComponentType? preselectedType)? onAdd;
  final void Function(LeaseComponentDto component)? onEdit;
  final void Function(LeaseComponentDto component)? onClose;

  /// Opens the full history (LEASING-COMPONENTS-02). Null where the host has
  /// no way to load it -- the action is then absent rather than offered and
  /// dead.
  final VoidCallback? onShowHistory;

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
            actions: <Widget>[
              if (onShowHistory != null)
                TextButton.icon(
                  key: const Key('lease-components-history'),
                  onPressed: onShowHistory,
                  icon: const Icon(Icons.history, size: 18),
                  label: const Text('Verlauf'),
                ),
            ],
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

    return <Widget>[
      for (final type in _ordered)
        _ComponentRow(
          label: _typeLabel(type),
          component: resolved.ofType(type),
          coverage: _coverageOf(resolved, type),
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
      _WarmRentRow(warmRent: warmRent),
      const SizedBox(height: 8),
      Text(
        warmRent == null || warmRent!.hasFigure
            ? _absenceExplanation
            : _noWarmRentExplanation(warmRent!),
        style: theme.textTheme.bodySmall,
      ),
      ..._historyNotice(theme, resolved),
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

  /// The gap that the date alone cannot show.
  ///
  /// A type can be in force today and still have a hole earlier in the term —
  /// base rent recorded January to June and August onwards reads as complete
  /// on any September date, and July is unknown to everyone. That is the half
  /// of DEC-029 that had no surface at all until LEASING-COMPONENTS-01c, and
  /// it is reported here rather than left for a reader to notice.
  ///
  /// Deliberately not an error colour: an incomplete history is a normal state
  /// of a system being filled in, not a fault. It is a statement, and it names
  /// the first gap so there is somewhere to start.
  List<Widget> _historyNotice(
    ThemeData theme,
    LeaseComponentsAsOfDto resolved,
  ) {
    final withGaps = <LeaseComponentCoverageType>[
      for (final entry in resolved.coverage)
        for (final type in entry.types)
          if (type.hasGap) type,
    ];
    if (withGaps.isEmpty) {
      return const <Widget>[];
    }
    final parts = <String>[
      for (final type in withGaps)
        '${_typeLabel(type.componentType)} '
            '(${type.gapCount == 1 ? 'Lücke' : '${type.gapCount} Lücken'}'
            '${type.firstGapFrom == null ? '' : ', erste ab '
                '${formatLeaseDate(type.firstGapFrom)}'})',
    ];
    return <Widget>[
      const SizedBox(height: 8),
      Text(
        'Historie unvollständig: ${parts.join(', ')}. '
        'Für diese Zeiträume liegt keine Angabe vor — sie werden nicht aus '
        'den Vertragsbeginn-Zahlen ergänzt.',
        key: const Key('lease-components-history-gaps'),
        style: theme.textTheme.bodySmall,
      ),
    ];
  }

  /// The server's verdict on one type, across every lease in scope.
  ///
  /// The contract view queries one lease, so there is at most one entry; the
  /// lookup is written to survive the property-scoped read without pretending
  /// it can attribute a gap to the right lease from here.
  static LeaseComponentCoverageType? _coverageOf(
    LeaseComponentsAsOfDto resolved,
    LeaseComponentType type,
  ) {
    for (final entry in resolved.coverage) {
      final match = entry.ofType(type);
      if (match != null) {
        return match;
      }
    }
    return null;
  }

  /// Why the server withheld the figure, in the words of the reason it did.
  ///
  /// Read off the server's own answer rather than re-derived here: this
  /// section used to work the reason out a second time, which is how a
  /// sentence starts naming the wrong cause.
  static String _noWarmRentExplanation(WarmRentDto warm) {
    if (warm.hasGap) {
      final names = warm.gapTypes.map(_typeLabel).join(', ');
      return 'Keine Warmmiete für diesen Stichtag: $names ist für andere '
          'Zeiträume erfasst, für diesen nicht. Die übrigen Bestandteile zu '
          'summieren ergäbe eine plausible, falsche Zahl.';
    }
    if (warm.includedTypes.isEmpty) {
      return 'Keine Warmmiete: für diesen Vertrag ist kein Bestandteil '
          'erfasst, aus dem sie sich ergäbe.';
    }
    return 'Keine Warmmiete: die erfassten Bestandteile lassen sich nicht zu '
        'einer Zahl addieren — verschiedene Währungen, oder Netto neben '
        'steuerfrei, wovon eines bereits ein Zahlbetrag ist.';
  }

  static const String _absenceExplanation =
      'Nicht erfasst heißt nicht null: für diesen Stichtag liegt kein '
      'Bestandteil dieser Art vor. Er kann fehlen oder beendet sein — welches '
      'von beidem, zeigt der Verlauf.';

  // The words themselves live in `lease_lifecycle.dart`, because the history
  // dialog names the same types and two copies would eventually disagree.
  static String _typeLabel(LeaseComponentType type) =>
      leaseComponentTypeLabel(type);
}

class _ComponentRow extends StatelessWidget {
  const _ComponentRow({
    required this.label,
    required this.component,
    this.coverage,
    this.unfamiliar = false,
    this.canMutate = false,
    this.onAdd,
    this.onEdit,
    this.onClose,
  });

  final String label;
  final LeaseComponentDto? component;

  /// What the server knows about this type across the whole term. Null when
  /// the type has no history at all for this lease — which is a different
  /// statement from "not in force today", and the row says which.
  final LeaseComponentCoverageType? coverage;

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
                        _absentLabel(),
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

  /// Two different absences, and until LEASING-COMPONENTS-01c they looked
  /// identical.
  ///
  /// A type nobody ever recorded and a type recorded for other periods but not
  /// this one are different facts: the first is a blank, the second is a hole
  /// somebody left. Only the second tells the reader there is something to go
  /// and find.
  String _absentLabel() {
    final entry = coverage;
    if (entry == null) {
      return 'nicht erfasst';
    }
    final since = entry.openGapFrom;
    if (since != null) {
      return 'seit ${formatLeaseDate(since)} nicht erfasst';
    }
    return 'für diesen Stichtag nicht erfasst';
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

/// The one figure this section shows, and the server owns it.
class _WarmRentRow extends StatelessWidget {
  const _WarmRentRow({required this.warmRent});

  final WarmRentDto? warmRent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warm = warmRent;
    // The label is the honest half. A total without a heating advance is a
    // cold rent plus service charges, and the legacy figure that called itself
    // warm rent while excluding heating is exactly the mistake this avoids.
    final label = warm == null
        ? 'Warmmiete'
        : warm.isWarm
        ? 'Warmmiete'
        : 'Miete ohne Heizkosten';
    final figure = _figure(warm);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              flex: 3,
              child: Text(label, style: theme.textTheme.titleSmall),
            ),
            Expanded(
              flex: 4,
              child: Text(
                figure,
                key: const Key('lease-components-total'),
                style: theme.textTheme.titleSmall,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
        if (warm != null && warm.grossMonthly != null &&
            warm.netMonthly != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'brutto ${formatLeaseMoney(warm.grossMonthly, warm.currencyCode)}',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.end,
            ),
          ),
      ],
    );
  }

  static String _figure(WarmRentDto? warm) {
    if (warm == null) {
      // The server did not answer — an older deployment, or a read that
      // failed. Saying "nicht ermittelt" is the truth; a number computed here
      // would not be.
      return 'nicht ermittelt';
    }
    if (warm.netMonthly != null) {
      return formatLeaseMoney(warm.netMonthly, warm.currencyCode);
    }
    if (warm.grossMonthly != null) {
      return formatLeaseMoney(warm.grossMonthly, warm.currencyCode);
    }
    return 'nicht ermittelbar';
  }
}
