import 'dart:io';

import 'package:csv/csv.dart';

import '../models/analysis_result.dart';

class CsvExporter {
  const CsvExporter();

  Future<void> exportCashflow({
    required String outputPath,
    required AnalysisResult analysis,
  }) async {
    final rows = <List<dynamic>>[
      <dynamic>[
        'year',
        'gsi',
        'vacancy_loss',
        'egi',
        'opex',
        'noi',
        'debt_service',
        'cashflow',
      ],
      ...analysis.proformaYears.map(
        (year) => <dynamic>[
          year.yearIndex,
          year.gsi,
          year.vacancyLoss,
          year.egi,
          year.opex,
          year.noi,
          year.debtService,
          year.cashflowBeforeTax,
        ],
      ),
    ];

    final csv = const ListToCsvConverter().convert(rows);
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(csv);
  }

  Future<void> exportAmortization({
    required String outputPath,
    required AnalysisResult analysis,
  }) async {
    final rows = <List<dynamic>>[
      <dynamic>['month', 'payment', 'interest', 'principal', 'balance'],
      ...analysis.amortizationSchedule.map(
        (entry) => <dynamic>[
          entry.monthIndex,
          entry.payment,
          entry.interest,
          entry.principal,
          entry.balance,
        ],
      ),
    ];

    final csv = const ListToCsvConverter().convert(rows);
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(csv);
  }
}
