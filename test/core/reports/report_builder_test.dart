import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/engine/analysis_engine.dart';
import 'package:neximmo_app/core/models/inputs.dart';
import 'package:neximmo_app/core/models/property.dart';
import 'package:neximmo_app/core/models/report_templates.dart';
import 'package:neximmo_app/core/models/reports_dto.dart';
import 'package:neximmo_app/core/models/scenario.dart';
import 'package:neximmo_app/core/models/settings.dart';
import 'package:neximmo_app/core/reports/report_builder.dart';

void main() {
  test('respects include section flags in generated pdf footprint', () async {
    const engine = AnalysisEngine();
    const builder = ReportBuilder();
    final settings = AppSettingsRecord(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final inputs = ScenarioInputs.defaults(
      scenarioId: 's1',
      settings: settings,
    ).copyWith(
      purchasePrice: 200000,
      rentMonthlyTotal: 1800,
      financingMode: 'cash',
    );
    final analysis = engine.run(
      inputs: inputs,
      settings: settings,
      incomeLines: const [],
      expenseLines: const [],
    );
    final dto = ReportExportDto(
      property: const PropertyRecord(
        id: 'p1',
        name: 'Prop',
        addressLine1: 'Street 1',
        zip: '12345',
        city: 'Berlin',
        country: 'DE',
        propertyType: 'single_family',
        units: 1,
        createdAt: 0,
        updatedAt: 0,
      ),
      scenario: const ScenarioRecord(
        id: 's1',
        propertyId: 'p1',
        name: 'Base',
        strategyType: 'rental',
        isBase: true,
        createdAt: 0,
        updatedAt: 0,
      ),
      inputs: inputs,
      analysis: analysis,
      criteria: null,
      salesComps: const [],
      rentalComps: const [],
      esgProfile: null,
    );

    final minimal = ReportTemplateRecord(
      id: 't-min',
      name: 'Minimal',
      includeOverview: false,
      includeInputs: false,
      includeCashflowTable: false,
      includeAmortization: false,
      includeSensitivity: false,
      includeEsg: false,
      includeComps: false,
      includeCriteria: false,
      includeOffer: false,
      isDefault: false,
      createdAt: 0,
      updatedAt: 0,
    );
    final full = ReportTemplateRecord(
      id: 't-full',
      name: 'Full',
      includeOverview: true,
      includeInputs: true,
      includeCashflowTable: true,
      includeAmortization: true,
      includeSensitivity: true,
      includeEsg: true,
      includeComps: true,
      includeCriteria: true,
      includeOffer: true,
      isDefault: false,
      createdAt: 0,
      updatedAt: 0,
    );

    final dir = await Directory.systemTemp.createTemp('report_builder_test_');
    final minimalPath = '${dir.path}/minimal.pdf';
    final fullPath = '${dir.path}/full.pdf';

    await builder.savePdf(outputPath: minimalPath, dto: dto, template: minimal);
    await builder.savePdf(outputPath: fullPath, dto: dto, template: full);

    final minimalBytes = await File(minimalPath).readAsBytes();
    final fullBytes = await File(fullPath).readAsBytes();

    expect(minimalBytes.isNotEmpty, isTrue);
    expect(fullBytes.isNotEmpty, isTrue);
    expect(fullBytes.length, greaterThan(minimalBytes.length));

    await dir.delete(recursive: true);
  });
}
