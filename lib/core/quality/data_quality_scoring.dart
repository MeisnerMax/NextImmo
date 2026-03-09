import 'data_quality_rules_v2.dart';

class AssetQualityFacts {
  const AssetQualityFacts({
    required this.assetId,
    required this.addressLine1,
    required this.zip,
    required this.city,
    required this.propertyType,
    required this.units,
    required this.epcRating,
    required this.epcValidUntil,
    required this.latestRentRollPeriod,
    required this.latestRentRollOccupancyRate,
    required this.hasApprovedBudgetCurrentYear,
    required this.latestLedgerPostedAt,
    required this.latestCovenantCheckAt,
    required this.hasMissingRequiredDocuments,
  });

  final String assetId;
  final String addressLine1;
  final String zip;
  final String city;
  final String propertyType;
  final int units;
  final String? epcRating;
  final int? epcValidUntil;
  final String? latestRentRollPeriod;
  final double? latestRentRollOccupancyRate;
  final bool hasApprovedBudgetCurrentYear;
  final int? latestLedgerPostedAt;
  final int? latestCovenantCheckAt;
  final bool hasMissingRequiredDocuments;
}

class DataQualityAssetScore {
  const DataQualityAssetScore({
    required this.assetId,
    required this.score,
    required this.issues,
  });

  final String assetId;
  final int score;
  final List<DataQualityIssueV2> issues;
}

class DataQualityPortfolioScore {
  const DataQualityPortfolioScore({
    required this.portfolioId,
    required this.score,
    required this.assets,
    required this.issues,
    required this.moduleIssueCounts,
  });

  final String portfolioId;
  final int score;
  final List<DataQualityAssetScore> assets;
  final List<DataQualityIssueV2> issues;
  final Map<String, int> moduleIssueCounts;
}

class DataQualityScoring {
  const DataQualityScoring();

  DataQualityPortfolioScore scorePortfolio({
    required String portfolioId,
    required List<String> assetIds,
    required List<DataQualityIssueV2> issues,
  }) {
    final issuesByAsset = <String, List<DataQualityIssueV2>>{};
    for (final issue in issues) {
      issuesByAsset.putIfAbsent(issue.entityId, () => <DataQualityIssueV2>[]);
      issuesByAsset[issue.entityId]!.add(issue);
    }

    final assetScores = assetIds
        .map((assetId) {
          final assetIssues =
              issuesByAsset[assetId] ?? const <DataQualityIssueV2>[];
          return DataQualityAssetScore(
            assetId: assetId,
            score: _scoreAsset(assetIssues),
            issues: assetIssues,
          );
        })
        .toList(growable: false);

    final moduleIssueCounts = <String, int>{};
    for (final issue in issues) {
      moduleIssueCounts.update(
        issue.module,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }

    final portfolioScore =
        assetScores.isEmpty
            ? 100
            : (assetScores.fold<int>(0, (sum, asset) => sum + asset.score) /
                    assetScores.length)
                .round();

    return DataQualityPortfolioScore(
      portfolioId: portfolioId,
      score: portfolioScore.clamp(0, 100),
      assets: assetScores,
      issues: issues,
      moduleIssueCounts: moduleIssueCounts,
    );
  }

  int _scoreAsset(List<DataQualityIssueV2> issues) {
    var score = 100;
    for (final issue in issues) {
      score -= _deduction(issue.severity);
    }
    return score.clamp(0, 100);
  }

  int _deduction(String severity) {
    switch (severity) {
      case 'error':
        return 20;
      case 'warning':
        return 10;
      case 'info':
        return 5;
      default:
        return 8;
    }
  }
}
