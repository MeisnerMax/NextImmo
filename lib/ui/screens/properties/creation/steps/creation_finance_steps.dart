import 'package:flutter/material.dart';

import 'package:neximmo_app/core/models/property_creation.dart';
import 'package:neximmo_app/ui/components/nx_form_section_card.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';
import '../property_creation_support.dart';
import '../widgets/creation_summary_widgets.dart';

/// Step 5 — acquisition or existing-stock financials, depending on the reason.
class CreationPurchaseStep extends StatelessWidget {
  const CreationPurchaseStep({
    super.key,
    required this.draft,
    required this.assessment,
    required this.onChanged,
  });

  final PropertyCreationDraft draft;
  final PropertyCreationAssessment assessment;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final fields = CreationFieldFactory(onChanged);
    final acquisition = draft.isAcquisitionCase;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NxFormSectionCard(
          title: acquisition ? 'Kaufdaten' : 'Bestandsdaten',
          margin: EdgeInsets.zero,
          body: acquisition
              ? CreationFieldGrid(
                  children: [
                    fields.number('Angebotspreis', draft.offerPrice,
                        (v) => draft.offerPrice = v),
                    fields.number('Kaufpreis', draft.purchasePrice,
                        (v) => draft.purchasePrice = v),
                    fields.date('Kaufdatum', draft.purchaseDate,
                        (v) => draft.purchaseDate = v),
                    fields.date('Notartermin', draft.notaryDate,
                        (v) => draft.notaryDate = v),
                    fields.text('Verkaeufer', draft.seller,
                        (v) => draft.seller = v),
                    fields.text('Makler', draft.broker,
                        (v) => draft.broker = v),
                    fields.number('Grunderwerbsteuer',
                        draft.propertyTransferTax,
                        (v) => draft.propertyTransferTax = v),
                    fields.number('Notarkosten', draft.notaryCosts,
                        (v) => draft.notaryCosts = v),
                    fields.number('Grundbuchkosten', draft.landRegistryCosts,
                        (v) => draft.landRegistryCosts = v),
                    fields.number('Maklercourtage', draft.brokerFee,
                        (v) => draft.brokerFee = v),
                    fields.number('Sonstige Erwerbskosten',
                        draft.otherAcquisitionCosts,
                        (v) => draft.otherAcquisitionCosts = v),
                    fields.date('Uebergang Nutzen und Lasten',
                        draft.transferBenefitsDate,
                        (v) => draft.transferBenefitsDate = v),
                  ],
                )
              : CreationFieldGrid(
                  children: [
                    fields.number('Urspruenglicher Kaufpreis',
                        draft.originalPurchasePrice,
                        (v) => draft.originalPurchasePrice = v),
                    fields.date('Urspruengliches Kaufdatum',
                        draft.originalPurchaseDate,
                        (v) => draft.originalPurchaseDate = v),
                    fields.number('Aktueller Buchwert', draft.bookValue,
                        (v) => draft.bookValue = v),
                    fields.number('Aktueller Marktwert', draft.marketValue,
                        (v) => draft.marketValue = v),
                    fields.text('Letzte interne Bewertung',
                        draft.lastInternalValuation,
                        (v) => draft.lastInternalValuation = v),
                    fields.date('Bewertung zum Stichtag', draft.valuationDate,
                        (v) => draft.valuationDate = v),
                    fields.text('Historische Notizen', draft.historicNotes,
                        (v) => draft.historicNotes = v, maxLines: 4),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.component),
        CreationMetricStrip(
          items: [
            CreationMetricItem('Preis/qm',
                formatCreationCurrency(assessment.metrics.purchasePricePerSqm)),
            CreationMetricItem('Nebenkosten',
                formatCreationCurrency(assessment.metrics.acquisitionCosts)),
            CreationMetricItem('NK-Quote',
                formatCreationPercent(assessment.metrics.acquisitionCostRatio)),
            CreationMetricItem('Gesamtinvestition',
                formatCreationCurrency(assessment.metrics.totalInvestment)),
            CreationMetricItem('Faktor Ist',
                formatCreationNumber(assessment.metrics.purchaseFactorActual)),
            CreationMetricItem('Faktor Soll',
                formatCreationNumber(assessment.metrics.purchaseFactorTarget)),
          ],
        ),
      ],
    );
  }
}

/// Step 6 — optional financing block.
class CreationFinancingStep extends StatelessWidget {
  const CreationFinancingStep({
    super.key,
    required this.draft,
    required this.assessment,
    required this.onChanged,
  });

  final PropertyCreationDraft draft;
  final PropertyCreationAssessment assessment;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final fields = CreationFieldFactory(onChanged);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NxFormSectionCard(
          title: 'Finanzierung optional',
          margin: EdgeInsets.zero,
          body: CreationFieldGrid(
            children: [
              fields.switchTile('Darlehen vorhanden', draft.hasLoan,
                  (v) => draft.hasLoan = v),
              fields.number('Darlehensbetrag', draft.loanAmount,
                  (v) => draft.loanAmount = v),
              fields.number('Eigenkapital', draft.equity,
                  (v) => draft.equity = v),
              fields.number('Zinssatz Prozent', draft.interestRate,
                  (v) => draft.interestRate = v),
              fields.number('Tilgung Prozent', draft.amortizationRate,
                  (v) => draft.amortizationRate = v),
              fields.text('Zinsbindung', draft.fixedInterestPeriod,
                  (v) => draft.fixedInterestPeriod = v),
              fields.intField('Laufzeit Jahre', draft.termYears,
                  (v) => draft.termYears = v),
              fields.number('Monatliche Rate', draft.monthlyRate,
                  (v) => draft.monthlyRate = v),
              fields.number('Jaehrlicher Kapitaldienst', draft.annualDebtService,
                  (v) => draft.annualDebtService = v),
              fields.text('Bank', draft.bank, (v) => draft.bank = v),
              fields.text('Darlehensnummer', draft.loanNumber,
                  (v) => draft.loanNumber = v),
              fields.number('Restschuld', draft.remainingDebt,
                  (v) => draft.remainingDebt = v),
              fields.switchTile('Sondertilgung moeglich', draft.specialRepayment,
                  (v) => draft.specialRepayment = v),
              fields.text('Finanzierungsnotizen', draft.financingNotes,
                  (v) => draft.financingNotes = v, maxLines: 4),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        CreationMetricStrip(
          items: [
            CreationMetricItem('LTV',
                formatCreationPercent(assessment.metrics.loanToValue)),
            CreationMetricItem('EK-Quote',
                formatCreationPercent(assessment.metrics.equityRatio)),
            CreationMetricItem('Kapitaldienst p.a.',
                formatCreationCurrency(draft.annualDebtService)),
            CreationMetricItem('Kapitaldienst mtl.',
                formatCreationCurrency(draft.monthlyRate)),
          ],
        ),
      ],
    );
  }
}
