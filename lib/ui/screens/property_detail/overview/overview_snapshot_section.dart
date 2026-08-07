import 'package:flutter/material.dart';

import '../../../../core/models/property.dart';
import '../../../components/nx_card.dart';
import '../../../components/nx_section_header.dart';
import '../../../components/nx_status_badge.dart';
import '../../../i18n/app_strings.dart';
import '../../../theme/app_theme.dart';
import '../../properties/create_property_dialog.dart';
import 'overview_view_model.dart';

/// Snapshot sections of the overview screen (SCR-011 section 3): master data,
/// purchase/legal, documents/administration, and financing figures, grouped in
/// token-based cards instead of the legacy hex-styled panels.
class OverviewSnapshotSection extends StatelessWidget {
  const OverviewSnapshotSection({
    super.key,
    required this.property,
    required this.summary,
    required this.onEdit,
  });

  final PropertyRecord? property;
  final OverviewDealSummary summary;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NxSectionHeader(
            title: 'Objekt-Stammdaten',
            actions: [
              if (property != null)
                FilledButton.tonalIcon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit, size: AppIconTokens.sm),
                  label: const Text('Bearbeiten'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1080 ? 2 : 1;
              final width =
                  columns == 2
                      ? (constraints.maxWidth - AppSpacing.component) / 2
                      : constraints.maxWidth;
              return Wrap(
                spacing: AppSpacing.component,
                runSpacing: AppSpacing.component,
                children: [
                  SizedBox(
                    width: width,
                    child: _SnapshotGroup(
                      title: 'Objektprofil',
                      rows: [
                        _SnapshotRow(
                          label: 'Adresse',
                          value: overviewPropertyAddress(property),
                        ),
                        _SnapshotRow(
                          label: 'Objektart',
                          value: propertyTypeDisplayLabel(
                            property?.propertyType ?? '',
                          ),
                        ),
                        _SnapshotRow(
                          label: 'Baujahr',
                          value: property?.yearBuilt?.toString() ?? 'N/A',
                        ),
                        _SnapshotRow(
                          label: 'Eigentümergesellschaft',
                          value: property?.ownerCompany ?? 'N/A',
                        ),
                        _SnapshotRow(
                          label: 'Grundstücksfläche',
                          value: property?.landArea != null
                              ? '${property!.landArea!.toStringAsFixed(1)} m²'
                              : 'N/A',
                        ),
                        _SnapshotRow(
                          label: 'Wohnfläche',
                          value: property?.residentialArea != null
                              ? '${property!.residentialArea!.toStringAsFixed(1)} m²'
                              : (summary.sizeM2 != null
                                  ? '${summary.sizeM2!.toStringAsFixed(1)} m²'
                                  : 'N/A'),
                        ),
                        _SnapshotRow(
                          label: 'Gewerbefläche',
                          value: property?.commercialArea != null
                              ? '${property!.commercialArea!.toStringAsFixed(1)} m²'
                              : 'N/A',
                        ),
                        _SnapshotRow(
                          label: 'Stellplätze',
                          value: property?.parkingSpots?.toString() ?? 'N/A',
                        ),
                        _SnapshotRow(
                          label: 'Einheiten',
                          value: property?.units.toString() ?? 'N/A',
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _SnapshotGroup(
                      title: 'Kauf & Rechtliches',
                      rows: [
                        _SnapshotRow(
                          label: 'Kaufpreis',
                          value: property?.purchasePrice != null
                              ? '€ ${formatOverviewNumber(property!.purchasePrice!)}'
                              : '€ ${formatOverviewNumber(summary.purchasePrice)}',
                        ),
                        _SnapshotRow(
                          label: 'Kaufdatum',
                          value: property?.purchaseDate != null
                              ? formatOverviewDate(property!.purchaseDate)
                              : 'N/A',
                        ),
                        _SnapshotRow(
                          label: 'Verkäufer',
                          value: property?.seller ?? 'N/A',
                        ),
                        _SnapshotRow(
                          label: 'Notar',
                          value: property?.notary ?? 'N/A',
                        ),
                        _SnapshotRow(
                          label: 'Grundbuchdaten',
                          value: property?.landRegistryDetails ?? 'N/A',
                        ),
                        _SnapshotRow(
                          label: 'Flurstück',
                          value: property?.parcel ?? 'N/A',
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _SnapshotGroup(
                      title: 'Dokumente & Verwaltung',
                      rows: [
                        _SnapshotRow(
                          label: 'Energieausweis',
                          value: property?.energyCertificate ?? 'N/A',
                        ),
                        _SnapshotRow(
                          label: 'Versicherungsdaten',
                          value: property?.insuranceDetails ?? 'N/A',
                        ),
                        _SnapshotRow(
                          label: 'Steuerliche Zuordnung',
                          value: property?.taxAssignment ?? 'N/A',
                        ),
                        _SnapshotRow(
                          label: 'Notizen',
                          value: property?.notes ?? 'N/A',
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _SnapshotGroup(
                      title: 'Finanzierung & Kennzahlen',
                      rows: [
                        _SnapshotRow(
                          label: 'Rehab-Budget',
                          value: formatOverviewNumber(summary.rehabBudget),
                        ),
                        _SnapshotRow(
                          label: 'Gesamtanschaffungskosten',
                          value: formatOverviewNumber(
                            summary.totalAcquisitionCost,
                          ),
                        ),
                        _SnapshotRow(
                          label: 'Eingebrachtes Eigenkapital',
                          value: formatOverviewNumber(
                            summary.totalEquityInvested,
                          ),
                        ),
                        _SnapshotRow(
                          label: 'LTV',
                          value:
                              summary.ltv == null
                                  ? 'N/A'
                                  : '${(summary.ltv! * 100).toStringAsFixed(2)}%',
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SnapshotRow {
  const _SnapshotRow({required this.label, required this.value});

  final String label;
  final String value;
}

class _SnapshotGroup extends StatelessWidget {
  const _SnapshotGroup({required this.title, required this.rows});

  final String title;
  final List<_SnapshotRow> rows;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: semantic.surfaceAlt,
        border: Border.all(color: semantic.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.component),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.strings.text(title),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final row in rows) _SnapshotRowLine(row: row),
          ],
        ),
      ),
    );
  }
}

class _SnapshotRowLine extends StatelessWidget {
  const _SnapshotRowLine({required this.row});

  final _SnapshotRow row;

  @override
  Widget build(BuildContext context) {
    final isLtv = row.label == 'LTV';
    Widget valueWidget = Text(
      row.value,
      textAlign: TextAlign.right,
      style: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(fontWeight: FontWeight.w700)
          .merge(context.tabularNumericStyle),
    );

    if (isLtv && row.value != 'N/A') {
      final doubleVal = double.tryParse(row.value.replaceAll('%', '').trim());
      if (doubleVal != null) {
        final NxBadgeKind kind;
        if (doubleVal < 60) {
          kind = NxBadgeKind.success;
        } else if (doubleVal <= 75) {
          kind = NxBadgeKind.warning;
        } else {
          kind = NxBadgeKind.error;
        }
        valueWidget = Align(
          alignment: Alignment.centerRight,
          child: NxStatusBadge(label: row.value, kind: kind),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              context.strings.text(row.label),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.semanticColors.textSecondary,
                  ),
            ),
          ),
          const SizedBox(width: AppSpacing.component),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }
}
