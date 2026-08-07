import 'package:flutter/material.dart';

import '../../../../../features/valuation/application/valuation_case_controller.dart';
import '../../../../../features/valuation/domain/valuation_case_dto.dart';
import '../../../../../features/valuation/domain/valuation_factor.dart';
import '../../../../../features/valuation/domain/valuation_factor_catalog.dart';
import '../../../../../features/valuation/domain/valuation_method.dart';
import '../../../../components/nx_form_section_card.dart';
import '../../../../components/nx_section_header.dart';
import '../../../../components/nx_status_badge.dart';
import 'valuation_factor_row.dart';

/// The factor entry surface (Welle 5, AP2): one card per method, each showing
/// how far it is from being computable.
///
/// Three properties this is built around:
///
/// * **Progress is honest.** The "4 von 6" comes from
///   [ValuationFactorGroup.progress], which counts an alternative once and
///   counts half of a two-part path as nothing.
/// * **Saving is explicit and batched.** One command per save carries every
///   changed factor, so the case version moves once instead of once per field —
///   autosave per keystroke would produce a version conflict against itself.
/// * **Nothing is written implicitly.** Unparseable input leaves the stored
///   factor untouched instead of writing a zero, and a suggestion becomes
///   `accepted` only through its own action.
class ValuationFactorsSection extends StatefulWidget {
  const ValuationFactorsSection({
    super.key,
    required this.state,
    this.onSave,
    this.onAcceptSuggestion,
    this.onClearFactor,
    this.focusFactorId,
  });

  final ValuationCaseState state;

  /// Null when the caller may not write — the fields then render read-only and
  /// the save action is absent rather than failing.
  final void Function(List<ValuationFactorDto> changed)? onSave;
  final void Function(String factorId)? onAcceptSuggestion;
  final void Function(String factorId)? onClearFactor;

  /// Set by the "Zur Eingabe" jump from a missing-factor reason; the matching
  /// group opens expanded.
  final String? focusFactorId;

  @override
  State<ValuationFactorsSection> createState() =>
      _ValuationFactorsSectionState();
}

class _ValuationFactorsSectionState extends State<ValuationFactorsSection> {
  /// Field text per factor id, seeded from the stored factors and kept across
  /// rebuilds so typing is not undone by a realtime refresh.
  final Map<String, String> _draft = <String, String>{};
  final Set<String> _dirty = <String>{};
  final Map<ValuationMethodKind, GlobalKey> _groupKeys =
      <ValuationMethodKind, GlobalKey>{};

  @override
  void didUpdateWidget(ValuationFactorsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A reload after a successful save is the moment to drop the local draft:
    // the stored factors are now authoritative again.
    if (widget.state.actionPhase == ValuationActionPhase.succeeded &&
        oldWidget.state.actionPhase != ValuationActionPhase.succeeded) {
      _draft.clear();
      _dirty.clear();
    }
    if (widget.focusFactorId != null &&
        widget.focusFactorId != oldWidget.focusFactorId) {
      _scrollTo(widget.focusFactorId!);
    }
  }

  /// Brings the group owning [factorId] into view — the other half of the
  /// "Zur Eingabe" jump offered by a missing-factor reason.
  void _scrollTo(String factorId) {
    for (final group in ValuationFactorCatalog.groups) {
      if (!group.factors.any((spec) => spec.id == factorId)) continue;
      final context = _groupKeys[group.method]?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(context, duration: kThemeAnimationDuration);
      }
      return;
    }
  }

  ValuationFactorDto? _stored(String factorId) => widget.state.detail?.factors
      .where((factor) => factor.factorId == factorId)
      .firstOrNull;

  String _textFor(ValuationFactorSpec spec) {
    final draft = _draft[spec.id];
    if (draft != null) return draft;
    return formatFactorInput(_stored(spec.id)?.value, spec.kind);
  }

  bool _has(String factorId) {
    final stored = _stored(factorId);
    return stored != null && stored.provenance.isUsable;
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = widget.onSave != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        NxSectionHeader(
          title: 'Bewertungsfaktoren',
          description:
              'Je Verfahren die Werte, die es braucht. Systemvorschläge zählen '
              'erst, wenn du sie übernimmst.',
          actions: <Widget>[
            if (canWrite)
              FilledButton(
                onPressed: _dirty.isEmpty ? null : _save,
                child: Text(
                  _dirty.isEmpty
                      ? 'Gespeichert'
                      : '${_dirty.length} Änderung(en) speichern',
                ),
              ),
          ],
        ),
        if (!canWrite)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: NxStatusBadge(
              label: 'Schreibgeschützt — nur Ansicht',
              kind: NxBadgeKind.warning,
            ),
          ),
        const SizedBox(height: 12),
        for (final group in ValuationFactorCatalog.groups)
          _GroupCard(
            key: _groupKeys.putIfAbsent(group.method, () => GlobalKey()),
            group: group,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (group.note != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      group.note!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                for (final spec in group.factors)
                  ValuationFactorRow(
                    spec: spec,
                    provenance: _stored(spec.id)?.provenance,
                    source: _stored(spec.id)?.source,
                    draftText: _textFor(spec),
                    enabled: canWrite,
                    onChanged: (raw) => setState(() {
                      _draft[spec.id] = raw;
                      _dirty.add(spec.id);
                    }),
                    onAcceptSuggestion:
                        widget.onAcceptSuggestion == null ||
                            _stored(spec.id)?.provenance !=
                                FactorProvenance.suggestedDefault
                        ? null
                        : () => widget.onAcceptSuggestion!(spec.id),
                    onClear: widget.onClearFactor == null
                        ? null
                        : () => widget.onClearFactor!(spec.id),
                  ),
              ],
            ),
            progress: group.progress(_has),
          ),
      ],
    );
  }

  void _save() {
    final changed = <ValuationFactorDto>[];
    for (final id in _dirty) {
      final spec = ValuationFactorCatalog.specFor(id);
      final raw = _draft[id];
      if (spec == null || raw == null) continue;
      final value = parseFactorInput(raw, spec.kind);
      // Unparseable or emptied input is not a zero — it is left to the explicit
      // "Wert entfernen" action, so a typo never overwrites a good value.
      if (value == null) continue;
      changed.add(
        ValuationFactorDto(
          caseId: widget.state.valuationCase!.id,
          factorId: spec.id,
          label: spec.label,
          provenance: FactorProvenance.userProvided,
          confidence: ConfidenceBand.high,
          value: value,
          unit: spec.unit,
        ),
      );
    }
    if (changed.isEmpty) return;
    widget.onSave!(changed);
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    super.key,
    required this.group,
    required this.body,
    required this.progress,
  });

  final ValuationFactorGroup group;
  final Widget body;
  final ({int satisfied, int total}) progress;

  @override
  Widget build(BuildContext context) {
    final isComplete = progress.satisfied == progress.total;
    return NxFormSectionCard(
      title: group.method.labelDe,
      trailing: NxStatusBadge(
        label: '${progress.satisfied} von ${progress.total}',
        kind: isComplete ? NxBadgeKind.success : NxBadgeKind.warning,
      ),
      body: body,
    );
  }
}
