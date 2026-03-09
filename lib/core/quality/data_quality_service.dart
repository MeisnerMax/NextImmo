import '../models/esg.dart';
import '../models/property.dart';
import 'data_quality_rules_v2.dart';
import 'data_quality_scoring.dart';

class DataQualityIssue {
  const DataQualityIssue({
    required this.severity,
    required this.code,
    required this.message,
    required this.entityType,
    required this.entityId,
  });

  final String severity;
  final String code;
  final String message;
  final String entityType;
  final String entityId;
}

class DataQualityService {
  const DataQualityService();

  List<DataQualityIssue> evaluate({
    required List<PropertyRecord> properties,
    required List<EsgProfileRecord> esgProfiles,
  }) {
    final issues = <DataQualityIssue>[];

    final esgByProperty = <String, EsgProfileRecord>{
      for (final profile in esgProfiles) profile.propertyId: profile,
    };

    for (final property in properties) {
      if (property.name.trim().isEmpty) {
        issues.add(
          DataQualityIssue(
            severity: 'error',
            code: 'missing_name',
            message: 'Property name is missing.',
            entityType: 'property',
            entityId: property.id,
          ),
        );
      }

      final profile = esgByProperty[property.id];
      if (profile == null || (profile.epcRating ?? '').trim().isEmpty) {
        issues.add(
          DataQualityIssue(
            severity: 'warning',
            code: 'missing_epc_rating',
            message: 'EPC rating is missing.',
            entityType: 'property',
            entityId: property.id,
          ),
        );
      }
      if (profile != null &&
          profile.emissionsKgCo2M2 != null &&
          profile.emissionsKgCo2M2! < 0) {
        issues.add(
          DataQualityIssue(
            severity: 'error',
            code: 'invalid_emissions',
            message: 'Emissions cannot be negative.',
            entityType: 'property',
            entityId: property.id,
          ),
        );
      }
    }

    return issues;
  }

  DataQualityPortfolioScore evaluatePortfolioV2({
    required String portfolioId,
    required List<AssetQualityFacts> assets,
    required int epcExpiryWarningDays,
    required int rentRollStaleMonths,
    required int ledgerStaleDays,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final epcCutoff = today.add(Duration(days: epcExpiryWarningDays));
    final ledgerCutoff = today.subtract(Duration(days: ledgerStaleDays));
    final staleRentRollCutoff = DateTime(
      today.year,
      today.month - rentRollStaleMonths,
    );
    final quarterStart = _quarterStart(today);

    final issues = <DataQualityIssueV2>[];
    for (final asset in assets) {
      if (asset.addressLine1.trim().isEmpty ||
          asset.zip.trim().isEmpty ||
          asset.city.trim().isEmpty) {
        issues.add(
          _issueFromRule(
            rule: DataQualityRulesV2.missingAddress,
            assetId: asset.assetId,
          ),
        );
      }
      if (asset.propertyType.trim().isEmpty) {
        issues.add(
          _issueFromRule(
            rule: DataQualityRulesV2.missingPropertyType,
            assetId: asset.assetId,
          ),
        );
      }
      if (asset.units <= 0) {
        issues.add(
          _issueFromRule(
            rule: DataQualityRulesV2.missingUnitsCount,
            assetId: asset.assetId,
          ),
        );
      }

      if ((asset.epcRating ?? '').trim().isEmpty) {
        issues.add(
          _issueFromRule(
            rule: DataQualityRulesV2.missingEpc,
            assetId: asset.assetId,
          ),
        );
      }
      if (asset.epcValidUntil != null &&
          DateTime.fromMillisecondsSinceEpoch(
            asset.epcValidUntil!,
          ).isBefore(epcCutoff)) {
        issues.add(
          _issueFromRule(
            rule: DataQualityRulesV2.epcExpiringSoon,
            assetId: asset.assetId,
          ),
        );
      }

      if (_isRentRollStale(asset.latestRentRollPeriod, staleRentRollCutoff)) {
        issues.add(
          _issueFromRule(
            rule: DataQualityRulesV2.rentRollMissing,
            assetId: asset.assetId,
          ),
        );
      }
      if (asset.latestRentRollPeriod != null &&
          asset.latestRentRollOccupancyRate == null) {
        issues.add(
          _issueFromRule(
            rule: DataQualityRulesV2.rentRollMissingOccupancy,
            assetId: asset.assetId,
          ),
        );
      }

      if (!asset.hasApprovedBudgetCurrentYear) {
        issues.add(
          _issueFromRule(
            rule: DataQualityRulesV2.missingApprovedBudget,
            assetId: asset.assetId,
          ),
        );
      }

      if (asset.latestLedgerPostedAt == null ||
          DateTime.fromMillisecondsSinceEpoch(
            asset.latestLedgerPostedAt!,
          ).isBefore(ledgerCutoff)) {
        issues.add(
          _issueFromRule(
            rule: DataQualityRulesV2.staleLedger,
            assetId: asset.assetId,
          ),
        );
      }

      if (asset.latestCovenantCheckAt == null ||
          DateTime.fromMillisecondsSinceEpoch(
            asset.latestCovenantCheckAt!,
          ).isBefore(quarterStart)) {
        issues.add(
          _issueFromRule(
            rule: DataQualityRulesV2.staleCovenantChecks,
            assetId: asset.assetId,
          ),
        );
      }

      if (asset.hasMissingRequiredDocuments) {
        issues.add(
          _issueFromRule(
            rule: DataQualityRulesV2.missingRequiredDocuments,
            assetId: asset.assetId,
          ),
        );
      }
    }

    return const DataQualityScoring().scorePortfolio(
      portfolioId: portfolioId,
      assetIds: assets.map((asset) => asset.assetId).toList(growable: false),
      issues: issues,
    );
  }

  DataQualityIssueV2 _issueFromRule({
    required DataQualityRuleV2 rule,
    required String assetId,
  }) {
    return DataQualityIssueV2(
      entityType: rule.entityType,
      entityId: assetId,
      ruleId: rule.id,
      module: rule.module,
      message: rule.description,
      severity: rule.severity,
      fixHint: rule.fixHint,
      relatedScreenRoute: rule.relatedScreenRoute,
    );
  }

  DateTime _quarterStart(DateTime date) {
    final quarter = ((date.month - 1) ~/ 3);
    final quarterMonth = (quarter * 3) + 1;
    return DateTime(date.year, quarterMonth, 1);
  }

  bool _isRentRollStale(String? periodKey, DateTime cutoff) {
    if (periodKey == null) {
      return true;
    }
    final parts = periodKey.split('-');
    if (parts.length != 2) {
      return true;
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null || month < 1 || month > 12) {
      return true;
    }
    final parsed = DateTime(year, month, 1);
    return parsed.isBefore(DateTime(cutoff.year, cutoff.month, 1));
  }
}
