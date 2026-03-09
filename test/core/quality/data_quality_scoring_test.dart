import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/quality/data_quality_scoring.dart';
import 'package:neximmo_app/core/quality/data_quality_service.dart';

void main() {
  test('scores portfolio deterministically from rule issues', () {
    final service = DataQualityService();
    final result = service.evaluatePortfolioV2(
      portfolioId: 'p1',
      assets: const <AssetQualityFacts>[
        AssetQualityFacts(
          assetId: 'a1',
          addressLine1: '',
          zip: '',
          city: '',
          propertyType: '',
          units: 0,
          epcRating: null,
          epcValidUntil: null,
          latestRentRollPeriod: null,
          latestRentRollOccupancyRate: null,
          hasApprovedBudgetCurrentYear: false,
          latestLedgerPostedAt: null,
          latestCovenantCheckAt: null,
          hasMissingRequiredDocuments: true,
        ),
        AssetQualityFacts(
          assetId: 'a2',
          addressLine1: 'Street',
          zip: '10000',
          city: 'Berlin',
          propertyType: 'multifamily',
          units: 10,
          epcRating: 'B',
          epcValidUntil: 1893456000000,
          latestRentRollPeriod: '2026-03',
          latestRentRollOccupancyRate: 0.95,
          hasApprovedBudgetCurrentYear: true,
          latestLedgerPostedAt: 1764547200000,
          latestCovenantCheckAt: 1764547200000,
          hasMissingRequiredDocuments: false,
        ),
      ],
      epcExpiryWarningDays: 90,
      rentRollStaleMonths: 1,
      ledgerStaleDays: 30,
    );

    expect(result.assets.length, 2);
    expect(result.issues.isNotEmpty, isTrue);
    expect(result.score, inInclusiveRange(0, 100));
    expect(result.moduleIssueCounts.keys, contains('asset'));
  });
}
