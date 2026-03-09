import 'package:uuid/uuid.dart';

import '../models/report_templates.dart';

class ReportTemplateFactory {
  const ReportTemplateFactory();

  ReportTemplateRecord defaultTemplate() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return ReportTemplateRecord(
      id: const Uuid().v4(),
      name: 'Default Template',
      includeOverview: true,
      includeInputs: true,
      includeCashflowTable: true,
      includeAmortization: true,
      includeSensitivity: false,
      includeEsg: false,
      includeComps: false,
      includeCriteria: true,
      includeOffer: true,
      isDefault: true,
      reportTitle: 'Deal Analysis Report',
      reportDisclaimer: 'For informational purposes only.',
      investorName: null,
      createdAt: now,
      updatedAt: now,
    );
  }
}
