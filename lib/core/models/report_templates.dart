class ReportTemplateRecord {
  const ReportTemplateRecord({
    required this.id,
    required this.name,
    required this.includeOverview,
    required this.includeInputs,
    required this.includeCashflowTable,
    required this.includeAmortization,
    required this.includeSensitivity,
    required this.includeEsg,
    required this.includeComps,
    required this.includeCriteria,
    required this.includeOffer,
    required this.isDefault,
    this.reportTitle,
    this.reportDisclaimer,
    this.investorName,
    this.brandingName,
    this.brandingCompany,
    this.brandingEmail,
    this.brandingPhone,
    this.brandingLogoPath,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final bool includeOverview;
  final bool includeInputs;
  final bool includeCashflowTable;
  final bool includeAmortization;
  final bool includeSensitivity;
  final bool includeEsg;
  final bool includeComps;
  final bool includeCriteria;
  final bool includeOffer;
  final bool isDefault;
  final String? reportTitle;
  final String? reportDisclaimer;
  final String? investorName;
  final String? brandingName;
  final String? brandingCompany;
  final String? brandingEmail;
  final String? brandingPhone;
  final String? brandingLogoPath;
  final int createdAt;
  final int updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'include_overview': includeOverview ? 1 : 0,
      'include_inputs': includeInputs ? 1 : 0,
      'include_cashflow_table': includeCashflowTable ? 1 : 0,
      'include_amortization': includeAmortization ? 1 : 0,
      'include_sensitivity': includeSensitivity ? 1 : 0,
      'include_esg': includeEsg ? 1 : 0,
      'include_comps': includeComps ? 1 : 0,
      'include_criteria': includeCriteria ? 1 : 0,
      'include_offer': includeOffer ? 1 : 0,
      'is_default': isDefault ? 1 : 0,
      'report_title': reportTitle,
      'report_disclaimer': reportDisclaimer,
      'investor_name': investorName,
      'branding_name': brandingName,
      'branding_company': brandingCompany,
      'branding_email': brandingEmail,
      'branding_phone': brandingPhone,
      'branding_logo_path': brandingLogoPath,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory ReportTemplateRecord.fromMap(Map<String, Object?> map) {
    return ReportTemplateRecord(
      id: map['id']! as String,
      name: map['name']! as String,
      includeOverview: ((map['include_overview'] as num?) ?? 1) == 1,
      includeInputs: ((map['include_inputs'] as num?) ?? 1) == 1,
      includeCashflowTable: ((map['include_cashflow_table'] as num?) ?? 1) == 1,
      includeAmortization: ((map['include_amortization'] as num?) ?? 1) == 1,
      includeSensitivity: ((map['include_sensitivity'] as num?) ?? 0) == 1,
      includeEsg: ((map['include_esg'] as num?) ?? 0) == 1,
      includeComps: ((map['include_comps'] as num?) ?? 1) == 1,
      includeCriteria: ((map['include_criteria'] as num?) ?? 1) == 1,
      includeOffer: ((map['include_offer'] as num?) ?? 1) == 1,
      isDefault: ((map['is_default'] as num?) ?? 0) == 1,
      reportTitle: map['report_title'] as String?,
      reportDisclaimer: map['report_disclaimer'] as String?,
      investorName: map['investor_name'] as String?,
      brandingName: map['branding_name'] as String?,
      brandingCompany: map['branding_company'] as String?,
      brandingEmail: map['branding_email'] as String?,
      brandingPhone: map['branding_phone'] as String?,
      brandingLogoPath: map['branding_logo_path'] as String?,
      createdAt: (map['created_at']! as num).toInt(),
      updatedAt: (map['updated_at']! as num).toInt(),
    );
  }
}

class ReportRecord {
  const ReportRecord({
    required this.id,
    required this.propertyId,
    required this.scenarioId,
    required this.templateId,
    required this.pdfPath,
    required this.createdAt,
  });

  final String id;
  final String propertyId;
  final String scenarioId;
  final String templateId;
  final String pdfPath;
  final int createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'property_id': propertyId,
      'scenario_id': scenarioId,
      'template_id': templateId,
      'pdf_path': pdfPath,
      'created_at': createdAt,
    };
  }

  factory ReportRecord.fromMap(Map<String, Object?> map) {
    return ReportRecord(
      id: map['id']! as String,
      propertyId: map['property_id']! as String,
      scenarioId: map['scenario_id']! as String,
      templateId: map['template_id']! as String,
      pdfPath: map['pdf_path']! as String,
      createdAt: (map['created_at']! as num).toInt(),
    );
  }
}
