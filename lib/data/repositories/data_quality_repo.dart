import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AssetQualitySnapshot {
  const AssetQualitySnapshot({
    required this.assetId,
    required this.name,
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
  final String name;
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

class PortfolioQualitySnapshot {
  const PortfolioQualitySnapshot({
    required this.portfolioId,
    required this.assets,
  });

  final String portfolioId;
  final List<AssetQualitySnapshot> assets;
}

class DataQualityRepo {
  const DataQualityRepo(this._db);

  final Database _db;

  Future<PortfolioQualitySnapshot> loadPortfolioSnapshot({
    required String portfolioId,
  }) async {
    final assetRows = await _db.rawQuery(
      '''
      SELECT p.id, p.name, p.address_line1, p.zip, p.city, p.property_type, p.units
      FROM properties p
      INNER JOIN portfolio_properties pp ON pp.property_id = p.id
      WHERE pp.portfolio_id = ? AND p.archived = 0
      ORDER BY p.name COLLATE NOCASE
      ''',
      <Object?>[portfolioId],
    );
    final assetIds = assetRows
        .map((row) => row['id']! as String)
        .toList(growable: false);
    if (assetIds.isEmpty) {
      return PortfolioQualitySnapshot(
        portfolioId: portfolioId,
        assets: const <AssetQualitySnapshot>[],
      );
    }

    final esgByAsset = await _loadEsgByAsset(assetIds);
    final rentRollByAsset = await _loadRentRollByAsset(assetIds);
    final budgetApprovedByAsset = await _loadApprovedBudgetFlags(assetIds);
    final latestLedgerByAsset = await _loadLatestLedgerEntry(assetIds);
    final latestCovenantByAsset = await _loadLatestCovenantCheck(assetIds);
    final missingRequiredDocsByAsset = await _loadMissingRequiredDocFlags(
      assetIds,
    );

    final assets = assetRows
        .map((row) {
          final assetId = row['id']! as String;
          final esg = esgByAsset[assetId];
          final rentRoll = rentRollByAsset[assetId];
          return AssetQualitySnapshot(
            assetId: assetId,
            name: row['name']! as String,
            addressLine1: (row['address_line1'] as String?) ?? '',
            zip: (row['zip'] as String?) ?? '',
            city: (row['city'] as String?) ?? '',
            propertyType: (row['property_type'] as String?) ?? '',
            units: ((row['units'] as num?) ?? 0).toInt(),
            epcRating: esg?['epc_rating'] as String?,
            epcValidUntil: (esg?['epc_valid_until'] as num?)?.toInt(),
            latestRentRollPeriod: rentRoll?['period_key'] as String?,
            latestRentRollOccupancyRate:
                (rentRoll?['occupancy_rate'] as num?)?.toDouble(),
            hasApprovedBudgetCurrentYear: budgetApprovedByAsset.contains(
              assetId,
            ),
            latestLedgerPostedAt:
                (latestLedgerByAsset[assetId] as num?)?.toInt(),
            latestCovenantCheckAt:
                (latestCovenantByAsset[assetId] as num?)?.toInt(),
            hasMissingRequiredDocuments: missingRequiredDocsByAsset.contains(
              assetId,
            ),
          );
        })
        .toList(growable: false);

    return PortfolioQualitySnapshot(portfolioId: portfolioId, assets: assets);
  }

  Future<Map<String, Map<String, Object?>>> _loadEsgByAsset(
    List<String> assetIds,
  ) async {
    final placeholders = List<String>.filled(assetIds.length, '?').join(',');
    final rows = await _db.rawQuery(
      'SELECT property_id, epc_rating, epc_valid_until FROM esg_profiles WHERE property_id IN ($placeholders)',
      <Object?>[...assetIds],
    );
    return <String, Map<String, Object?>>{
      for (final row in rows) row['property_id']! as String: row,
    };
  }

  Future<Map<String, Map<String, Object?>>> _loadRentRollByAsset(
    List<String> assetIds,
  ) async {
    final placeholders = List<String>.filled(assetIds.length, '?').join(',');
    final rows = await _db.rawQuery(
      '''
      SELECT r.asset_property_id, r.period_key, r.occupancy_rate
      FROM rent_roll_snapshots r
      INNER JOIN (
        SELECT asset_property_id, MAX(period_key) AS max_period
        FROM rent_roll_snapshots
        WHERE asset_property_id IN ($placeholders)
        GROUP BY asset_property_id
      ) x ON x.asset_property_id = r.asset_property_id AND x.max_period = r.period_key
      ''',
      <Object?>[...assetIds],
    );
    return <String, Map<String, Object?>>{
      for (final row in rows) row['asset_property_id']! as String: row,
    };
  }

  Future<Set<String>> _loadApprovedBudgetFlags(List<String> assetIds) async {
    final placeholders = List<String>.filled(assetIds.length, '?').join(',');
    final currentYear = DateTime.now().year;
    final rows = await _db.rawQuery(
      '''
      SELECT DISTINCT entity_id
      FROM budgets
      WHERE entity_type = 'asset_property'
        AND fiscal_year = ?
        AND status = 'approved'
        AND entity_id IN ($placeholders)
      ''',
      <Object?>[currentYear, ...assetIds],
    );
    return rows.map((row) => row['entity_id']! as String).toSet();
  }

  Future<Map<String, Object?>> _loadLatestLedgerEntry(
    List<String> assetIds,
  ) async {
    final placeholders = List<String>.filled(assetIds.length, '?').join(',');
    final rows = await _db.rawQuery(
      '''
      SELECT entity_id, MAX(posted_at) AS latest_posted_at
      FROM ledger_entries
      WHERE entity_type = 'asset_property' AND entity_id IN ($placeholders)
      GROUP BY entity_id
      ''',
      <Object?>[...assetIds],
    );
    return <String, Object?>{
      for (final row in rows)
        row['entity_id']! as String: row['latest_posted_at'],
    };
  }

  Future<Map<String, Object?>> _loadLatestCovenantCheck(
    List<String> assetIds,
  ) async {
    final placeholders = List<String>.filled(assetIds.length, '?').join(',');
    final rows = await _db.rawQuery(
      '''
      SELECT l.asset_property_id, MAX(cc.checked_at) AS latest_checked_at
      FROM loans l
      INNER JOIN covenants c ON c.loan_id = l.id
      INNER JOIN covenant_checks cc ON cc.covenant_id = c.id
      WHERE l.asset_property_id IN ($placeholders)
      GROUP BY l.asset_property_id
      ''',
      <Object?>[...assetIds],
    );
    return <String, Object?>{
      for (final row in rows)
        row['asset_property_id']! as String: row['latest_checked_at'],
    };
  }

  Future<Set<String>> _loadMissingRequiredDocFlags(
    List<String> assetIds,
  ) async {
    final placeholders = List<String>.filled(assetIds.length, '?').join(',');
    final rows = await _db.rawQuery(
      '''
      SELECT p.id AS property_id
      FROM properties p
      INNER JOIN required_documents r
        ON r.entity_type IN ('property', 'asset_property')
       AND r.required = 1
       AND (r.property_type IS NULL OR r.property_type = p.property_type)
      LEFT JOIN documents d
        ON d.entity_type IN ('property', 'asset_property')
       AND d.entity_id = p.id
       AND d.type_id = r.type_id
      WHERE p.id IN ($placeholders)
        AND d.id IS NULL
      GROUP BY p.id
      ''',
      <Object?>[...assetIds],
    );
    return rows.map((row) => row['property_id']! as String).toSet();
  }
}
