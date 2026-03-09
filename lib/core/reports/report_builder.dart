import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/reports_dto.dart';
import '../models/report_templates.dart';

class ReportBuilder {
  const ReportBuilder();

  Future<void> savePdf({
    required String outputPath,
    required ReportExportDto dto,
    required ReportTemplateRecord template,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build:
            (context) => [
              pw.Header(
                level: 0,
                child: pw.Text(
                  template.reportTitle ?? 'Deal Report: ${dto.property.name}',
                ),
              ),
              if (template.investorName != null)
                pw.Paragraph(text: 'Investor: ${template.investorName}'),
              pw.Text('${dto.property.addressLine1}, ${dto.property.city}'),
              pw.SizedBox(height: 12),
              if (template.includeOverview) ..._buildOverview(dto),
              if (template.includeInputs) ..._buildInputs(dto),
              if (template.includeCashflowTable) ..._buildCashflow(dto),
              if (template.includeAmortization) ..._buildAmortization(dto),
              if (template.includeSensitivity) ..._buildSensitivity(dto),
              if (template.includeEsg && dto.esgProfile != null)
                ..._buildEsg(dto),
              if (template.includeComps) ..._buildComps(dto),
              if (template.includeCriteria && dto.criteria != null)
                ..._buildCriteria(dto),
              if (template.includeOffer) ..._buildOffer(dto),
              if (template.reportDisclaimer != null)
                pw.Paragraph(text: 'Disclaimer: ${template.reportDisclaimer}'),
            ],
      ),
    );

    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(await doc.save());
  }

  List<pw.Widget> _buildOverview(ReportExportDto dto) {
    final m = dto.analysis.metrics;
    return [
      pw.Header(level: 1, child: pw.Text('Overview')),
      pw.Bullet(
        text:
            'Monthly Cashflow (Y1): ${m.monthlyCashflowYear1.toStringAsFixed(2)}',
      ),
      pw.Bullet(text: 'Cap Rate: ${(m.capRate * 100).toStringAsFixed(2)}%'),
      pw.Bullet(
        text: 'Cash on Cash: ${(m.cashOnCash * 100).toStringAsFixed(2)}%',
      ),
      pw.Bullet(
        text:
            'IRR: ${m.irr == null ? 'N/A' : '${(m.irr! * 100).toStringAsFixed(2)}%'}',
      ),
      pw.Bullet(text: 'DSCR: ${m.dscr?.toStringAsFixed(2) ?? 'N/A'}'),
      pw.Bullet(text: 'Valuation Mode: ${m.valuationMode}'),
      if (m.exitStabilizedNoi != null)
        pw.Bullet(
          text:
              'Stabilized NOI Used: ${m.exitStabilizedNoi!.toStringAsFixed(2)}',
        ),
      pw.Bullet(text: 'Exit Sale Price: ${m.exitSalePrice.toStringAsFixed(2)}'),
      pw.Bullet(text: 'Exit Sale Costs: ${m.exitSaleCosts.toStringAsFixed(2)}'),
      pw.Bullet(
        text: 'Exit Loan Payoff: ${m.exitLoanPayoff.toStringAsFixed(2)}',
      ),
      pw.Bullet(text: 'Exit Net Sale: ${m.exitNetSale.toStringAsFixed(2)}'),
    ];
  }

  List<pw.Widget> _buildInputs(ReportExportDto dto) {
    final inputs = dto.inputs;
    return [
      pw.Header(level: 1, child: pw.Text('Inputs')),
      pw.Bullet(
        text: 'Purchase Price: ${inputs.purchasePrice.toStringAsFixed(2)}',
      ),
      pw.Bullet(text: 'Rehab Budget: ${inputs.rehabBudget.toStringAsFixed(2)}'),
      pw.Bullet(
        text: 'Rent Monthly: ${inputs.rentMonthlyTotal.toStringAsFixed(2)}',
      ),
      pw.Bullet(text: 'Financing Mode: ${inputs.financingMode}'),
    ];
  }

  List<pw.Widget> _buildCashflow(ReportExportDto dto) {
    final rows =
        dto.analysis.proformaYears
            .map(
              (year) => [
                '${year.yearIndex}',
                year.gsi.toStringAsFixed(0),
                year.noi.toStringAsFixed(0),
                year.cashflowBeforeTax.toStringAsFixed(0),
              ],
            )
            .toList();

    return [
      pw.Header(level: 1, child: pw.Text('Cashflow Table')),
      pw.TableHelper.fromTextArray(
        headers: const ['Year', 'GSI', 'NOI', 'Cashflow'],
        data: rows,
      ),
    ];
  }

  List<pw.Widget> _buildAmortization(ReportExportDto dto) {
    final entries = dto.analysis.amortizationSchedule.take(24).toList();
    if (entries.isEmpty) {
      return [
        pw.Header(level: 1, child: pw.Text('Amortization')),
        pw.Text('No debt schedule.'),
      ];
    }

    return [
      pw.Header(level: 1, child: pw.Text('Amortization (first 24 months)')),
      pw.TableHelper.fromTextArray(
        headers: const ['Month', 'Payment', 'Interest', 'Principal', 'Balance'],
        data:
            entries
                .map(
                  (e) => [
                    '${e.monthIndex}',
                    e.payment.toStringAsFixed(2),
                    e.interest.toStringAsFixed(2),
                    e.principal.toStringAsFixed(2),
                    e.balance.toStringAsFixed(2),
                  ],
                )
                .toList(),
      ),
    ];
  }

  List<pw.Widget> _buildCriteria(ReportExportDto dto) {
    final criteria = dto.criteria!;
    return [
      pw.Header(level: 1, child: pw.Text('Criteria')),
      pw.Paragraph(text: 'Passed: ${criteria.passed ? 'Yes' : 'No'}'),
      ...criteria.evaluations.map(
        (eval) => pw.Bullet(
          text:
              '${eval.rule.fieldKey} ${eval.rule.operator} ${eval.rule.targetValue} -> ${eval.unknown ? 'unknown' : (eval.pass ? 'pass' : 'fail')}',
        ),
      ),
    ];
  }

  List<pw.Widget> _buildSensitivity(ReportExportDto dto) {
    final metrics = dto.analysis.metrics;
    return [
      pw.Header(level: 1, child: pw.Text('Sensitivity Snapshot')),
      pw.Bullet(
        text: 'Base Cap Rate: ${(metrics.capRate * 100).toStringAsFixed(2)}%',
      ),
      pw.Bullet(
        text:
            'Base Cash on Cash: ${(metrics.cashOnCash * 100).toStringAsFixed(2)}%',
      ),
      pw.Bullet(
        text:
            'Base IRR: ${metrics.irr == null ? 'N/A' : '${(metrics.irr! * 100).toStringAsFixed(2)}%'}',
      ),
      pw.Bullet(
        text:
            'Interactive rent and purchase sensitivity grid is available in the Analysis tab.',
      ),
    ];
  }

  List<pw.Widget> _buildEsg(ReportExportDto dto) {
    final profile = dto.esgProfile!;
    return [
      pw.Header(level: 1, child: pw.Text('ESG')),
      pw.Bullet(text: 'EPC Rating: ${profile.epcRating ?? 'N/A'}'),
      pw.Bullet(
        text:
            'EPC Valid Until: ${profile.epcValidUntil == null ? 'N/A' : DateTime.fromMillisecondsSinceEpoch(profile.epcValidUntil!).toIso8601String().substring(0, 10)}',
      ),
      pw.Bullet(
        text:
            'Emissions (kgCO2/m2): ${profile.emissionsKgCo2M2?.toStringAsFixed(2) ?? 'N/A'}',
      ),
      pw.Bullet(text: 'Target Rating: ${profile.targetRating ?? 'N/A'}'),
      if (profile.notes != null && profile.notes!.trim().isNotEmpty)
        pw.Paragraph(text: 'Notes: ${profile.notes}'),
    ];
  }

  List<pw.Widget> _buildComps(ReportExportDto dto) {
    final salesSelected =
        dto.salesComps.where((comp) => comp.selected).toList();
    final rentalSelected =
        dto.rentalComps.where((comp) => comp.selected).toList();

    final salesRows =
        salesSelected
            .take(10)
            .map(
              (comp) => <String>[
                comp.address,
                comp.price.toStringAsFixed(0),
                comp.weight.toStringAsFixed(2),
              ],
            )
            .toList();

    final rentalRows =
        rentalSelected
            .take(10)
            .map(
              (comp) => <String>[
                comp.address,
                comp.rentMonthly.toStringAsFixed(0),
                comp.weight.toStringAsFixed(2),
              ],
            )
            .toList();

    return [
      pw.Header(level: 1, child: pw.Text('Comps')),
      pw.Paragraph(
        text:
            'Sales selected: ${salesSelected.length}, Rental selected: ${rentalSelected.length}',
      ),
      if (salesRows.isNotEmpty)
        pw.TableHelper.fromTextArray(
          headers: const <String>['Sales Address', 'Price', 'Weight'],
          data: salesRows,
        ),
      if (salesRows.isEmpty)
        pw.Paragraph(text: 'No selected sales comps available.'),
      pw.SizedBox(height: 8),
      if (rentalRows.isNotEmpty)
        pw.TableHelper.fromTextArray(
          headers: const <String>['Rental Address', 'Rent', 'Weight'],
          data: rentalRows,
        ),
      if (rentalRows.isEmpty)
        pw.Paragraph(text: 'No selected rental comps available.'),
    ];
  }

  List<pw.Widget> _buildOffer(ReportExportDto dto) {
    final metrics = dto.analysis.metrics;
    return [
      pw.Header(level: 1, child: pw.Text('Offer Calculator Context')),
      pw.Bullet(
        text:
            'Total Cash Invested: ${metrics.totalCashInvested.toStringAsFixed(2)}',
      ),
      pw.Bullet(
        text: 'Exit Cashflow: ${metrics.exitCashflow.toStringAsFixed(2)}',
      ),
      pw.Bullet(
        text: 'Cash on Cash: ${(metrics.cashOnCash * 100).toStringAsFixed(2)}%',
      ),
      pw.Bullet(
        text:
            'IRR: ${metrics.irr == null ? 'N/A' : '${(metrics.irr! * 100).toStringAsFixed(2)}%'}',
      ),
    ];
  }
}
