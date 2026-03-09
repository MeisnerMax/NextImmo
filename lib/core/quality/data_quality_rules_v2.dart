class DataQualityRuleV2 {
  const DataQualityRuleV2({
    required this.id,
    required this.entityType,
    required this.fieldKey,
    required this.severity,
    required this.module,
    required this.description,
    required this.fixHint,
    required this.relatedScreenRoute,
  });

  final String id;
  final String entityType;
  final String fieldKey;
  final String severity;
  final String module;
  final String description;
  final String fixHint;
  final String relatedScreenRoute;
}

class DataQualityIssueV2 {
  const DataQualityIssueV2({
    required this.entityType,
    required this.entityId,
    required this.ruleId,
    required this.module,
    required this.message,
    required this.severity,
    required this.fixHint,
    required this.relatedScreenRoute,
  });

  final String entityType;
  final String entityId;
  final String ruleId;
  final String module;
  final String message;
  final String severity;
  final String fixHint;
  final String relatedScreenRoute;
}

class DataQualityRulesV2 {
  static const DataQualityRuleV2 missingAddress = DataQualityRuleV2(
    id: 'asset_missing_address',
    entityType: 'asset_property',
    fieldKey: 'address',
    severity: 'error',
    module: 'asset',
    description: 'Address fields are incomplete.',
    fixHint: 'Open property details and fill all address fields.',
    relatedScreenRoute: 'property_overview',
  );

  static const DataQualityRuleV2 missingPropertyType = DataQualityRuleV2(
    id: 'asset_missing_property_type',
    entityType: 'asset_property',
    fieldKey: 'property_type',
    severity: 'warning',
    module: 'asset',
    description: 'Property type is missing.',
    fixHint: 'Set the property type in property details.',
    relatedScreenRoute: 'property_overview',
  );

  static const DataQualityRuleV2 missingUnitsCount = DataQualityRuleV2(
    id: 'asset_missing_units_count',
    entityType: 'asset_property',
    fieldKey: 'units',
    severity: 'warning',
    module: 'asset',
    description: 'Units count is missing or invalid.',
    fixHint: 'Set a valid units count in property details.',
    relatedScreenRoute: 'property_overview',
  );

  static const DataQualityRuleV2 missingEpc = DataQualityRuleV2(
    id: 'esg_missing_epc',
    entityType: 'asset_property',
    fieldKey: 'epc_rating',
    severity: 'warning',
    module: 'esg',
    description: 'EPC rating is missing.',
    fixHint: 'Open ESG dashboard and add EPC rating.',
    relatedScreenRoute: 'esg_dashboard',
  );

  static const DataQualityRuleV2 epcExpiringSoon = DataQualityRuleV2(
    id: 'esg_epc_expiring_soon',
    entityType: 'asset_property',
    fieldKey: 'epc_valid_until',
    severity: 'warning',
    module: 'esg',
    description: 'EPC expiry is within configured threshold.',
    fixHint: 'Schedule EPC renewal and update ESG profile.',
    relatedScreenRoute: 'esg_dashboard',
  );

  static const DataQualityRuleV2 rentRollMissing = DataQualityRuleV2(
    id: 'rent_roll_missing_recent_snapshot',
    entityType: 'asset_property',
    fieldKey: 'rent_roll_snapshot',
    severity: 'error',
    module: 'rent_roll',
    description: 'No recent rent roll snapshot is available.',
    fixHint: 'Generate a new rent roll snapshot.',
    relatedScreenRoute: 'property_rent_roll',
  );

  static const DataQualityRuleV2 rentRollMissingOccupancy = DataQualityRuleV2(
    id: 'rent_roll_missing_occupancy',
    entityType: 'asset_property',
    fieldKey: 'occupancy_rate',
    severity: 'warning',
    module: 'rent_roll',
    description: 'Latest rent roll snapshot has no occupancy.',
    fixHint: 'Regenerate or correct rent roll data.',
    relatedScreenRoute: 'property_rent_roll',
  );

  static const DataQualityRuleV2 missingApprovedBudget = DataQualityRuleV2(
    id: 'budget_missing_approved_current_year',
    entityType: 'asset_property',
    fieldKey: 'approved_budget',
    severity: 'warning',
    module: 'budget',
    description: 'No approved budget exists for current fiscal year.',
    fixHint: 'Approve a current-year budget.',
    relatedScreenRoute: 'property_budget_vs_actual',
  );

  static const DataQualityRuleV2 staleLedger = DataQualityRuleV2(
    id: 'ledger_stale_entries',
    entityType: 'asset_property',
    fieldKey: 'last_ledger_entry',
    severity: 'warning',
    module: 'ledger',
    description: 'No recent ledger activity exists.',
    fixHint: 'Add or import latest ledger entries.',
    relatedScreenRoute: 'ledger',
  );

  static const DataQualityRuleV2 staleCovenantChecks = DataQualityRuleV2(
    id: 'covenant_missing_current_quarter_check',
    entityType: 'asset_property',
    fieldKey: 'covenant_check',
    severity: 'warning',
    module: 'covenants',
    description: 'No covenant checks in current quarter.',
    fixHint: 'Run covenant checks for current quarter.',
    relatedScreenRoute: 'property_covenants',
  );

  static const DataQualityRuleV2 missingRequiredDocuments = DataQualityRuleV2(
    id: 'docs_missing_required',
    entityType: 'asset_property',
    fieldKey: 'required_documents',
    severity: 'warning',
    module: 'documents',
    description: 'Required documents are missing.',
    fixHint: 'Open Documents and upload missing required files.',
    relatedScreenRoute: 'documents',
  );
}
