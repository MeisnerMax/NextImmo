/// P2-X01-AP4 stage 2: legacy `units` to `public.units`.
///
/// The source column `sqft` is a misnomer: its values (19..312 for units,
/// hundreds to thousands for properties) are square metres, so it maps to
/// `area_sqm` one to one. No unit conversion is applied, and applying one would
/// corrupt every area in the workspace.
library;

import 'package:uuid/uuid.dart';

import '../application/legacy_cutover.dart';
import 'legacy_cutover_fields.dart';

const _unitNamespace = 'neximmo/p2-x01/unit';

/// Must match the namespace the property cutover derives its ids from, or the
/// `units_property_fkey` foreign key would point at nothing.
const _propertyNamespace = 'neximmo/p1-012/property';

/// The workspace currency used when the source carries a rent but no currency.
/// The legacy `units` table has no currency column at all, while the target
/// refuses a money amount without one (DEC-011). Every lease in the source is
/// EUR, so EUR is the only consistent derivation — reported per row rather than
/// assumed silently.
const _inferredCurrencyCode = 'EUR';

const Set<String> _unitStatuses = <String>{'vacant', 'occupied', 'offline'};

const Set<String> _knownUnitFields = <String>{
  'asset_property_id',
  'baths',
  'beds',
  'created_at',
  'expected_ready_date',
  'floor',
  'id',
  'market_rent_monthly',
  'marketing_status',
  'next_action',
  'notes',
  'offline_reason',
  'renovation_status',
  'sqft',
  'status',
  'target_rent_monthly',
  'unit_code',
  'unit_type',
  'updated_at',
  'vacancy_reason',
  'vacancy_since',
};

class LegacyUnitCutoverMapper {
  const LegacyUnitCutoverMapper();

  LegacyCutoverEntityResult map({
    required List<Map<String, Object?>> units,
    required LegacyCutoverRequest request,
  }) {
    final targets = <Map<String, Object?>>[];
    final mappings = <LegacyCutoverMapping>[];
    final issues = <LegacyCutoverIssue>[];
    final idsBySourceId = <String, String>{};
    var rejected = 0;

    for (final row in sortedLegacyRows(units)) {
      final rowIssues = <LegacyCutoverIssue>[];
      final sourceId = requiredSourceId(
        row,
        LegacyCutoverEntity.unit,
        rowIssues,
      );
      reportUnknownFields(
        row,
        known: _knownUnitFields,
        entity: LegacyCutoverEntity.unit,
        sourceId: sourceId,
        issues: rowIssues,
      );

      final propertySourceId = requiredText(
        row,
        key: 'asset_property_id',
        maxLength: 200,
        entity: LegacyCutoverEntity.unit,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final unitCode = requiredText(
        row,
        key: 'unit_code',
        maxLength: 100,
        entity: LegacyCutoverEntity.unit,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final unitType = optionalText(
        row,
        key: 'unit_type',
        maxLength: 100,
        entity: LegacyCutoverEntity.unit,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final status = _status(row, sourceId, rowIssues);
      final floor = optionalText(
        row,
        key: 'floor',
        maxLength: 50,
        entity: LegacyCutoverEntity.unit,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final areaSqm = _boundedNumber(
        row,
        key: 'sqft',
        minExclusive: true,
        max: 1000000,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final rooms = _boundedNumber(
        row,
        key: 'beds',
        max: 1000,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final bathrooms = _boundedNumber(
        row,
        key: 'baths',
        max: 1000,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final targetRent = _boundedNumber(
        row,
        key: 'target_rent_monthly',
        sourceId: sourceId,
        issues: rowIssues,
      );
      final marketRent = _boundedNumber(
        row,
        key: 'market_rent_monthly',
        sourceId: sourceId,
        issues: rowIssues,
      );
      final vacancyReason = optionalText(
        row,
        key: 'vacancy_reason',
        maxLength: 2000,
        entity: LegacyCutoverEntity.unit,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final offlineReason = optionalText(
        row,
        key: 'offline_reason',
        maxLength: 2000,
        entity: LegacyCutoverEntity.unit,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final marketingStatus = optionalText(
        row,
        key: 'marketing_status',
        maxLength: 100,
        entity: LegacyCutoverEntity.unit,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final renovationStatus = optionalText(
        row,
        key: 'renovation_status',
        maxLength: 100,
        entity: LegacyCutoverEntity.unit,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final nextAction = optionalText(
        row,
        key: 'next_action',
        maxLength: 2000,
        entity: LegacyCutoverEntity.unit,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final notes = optionalText(
        row,
        key: 'notes',
        maxLength: 10000,
        entity: LegacyCutoverEntity.unit,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final vacancySince = _optionalDate(
        row,
        key: 'vacancy_since',
        sourceId: sourceId,
        issues: rowIssues,
      );
      final expectedReadyDate = _optionalDate(
        row,
        key: 'expected_ready_date',
        sourceId: sourceId,
        issues: rowIssues,
      );
      final createdAt = requiredTimestamp(
        row,
        key: 'created_at',
        entity: LegacyCutoverEntity.unit,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final updatedAt = requiredTimestamp(
        row,
        key: 'updated_at',
        entity: LegacyCutoverEntity.unit,
        sourceId: sourceId,
        issues: rowIssues,
      );

      // The target ties the offline reason to the offline state; carrying it on
      // any other status would violate that invariant.
      if (offlineReason != null && status != 'offline') {
        rowIssues.add(
          fieldError(
            'source.offline_reason_without_offline_status',
            LegacyCutoverEntity.unit,
            sourceId,
            'offline_reason',
          ),
        );
      }

      String? currencyCode;
      if (targetRent != null || marketRent != null) {
        currencyCode = _inferredCurrencyCode;
        rowIssues.add(
          fieldWarning(
            'mapping.currency_inferred',
            LegacyCutoverEntity.unit,
            sourceId,
            'currency_code',
          ),
        );
      }

      issues.addAll(rowIssues);
      if (rowIssues.any((issue) => issue.isError) ||
          sourceId == null ||
          propertySourceId == null ||
          unitCode == null ||
          status == null ||
          createdAt == null ||
          updatedAt == null) {
        rejected++;
        continue;
      }

      final unitId = const Uuid().v5(
        request.targetWorkspaceId,
        '$_unitNamespace/$sourceId',
      );
      idsBySourceId[sourceId] = unitId;
      final target = <String, Object?>{
        'area_sqm': areaSqm,
        'bathrooms': bathrooms,
        'created_at': createdAt,
        'created_by': request.actorId,
        'currency_code': currencyCode,
        'expected_ready_date': expectedReadyDate,
        'floor': floor,
        'id': unitId,
        'market_rent_monthly': marketRent,
        'marketing_status': marketingStatus,
        'next_action': nextAction,
        'notes': notes,
        'offline_reason': offlineReason,
        'property_id': const Uuid().v5(
          request.targetWorkspaceId,
          '$_propertyNamespace/$propertySourceId',
        ),
        'renovation_status': renovationStatus,
        'rooms': rooms,
        'status': status,
        'target_rent_monthly': targetRent,
        'unit_code': unitCode,
        'unit_type': unitType,
        'updated_at': updatedAt,
        'updated_by': request.actorId,
        'vacancy_reason': vacancyReason,
        'vacancy_since': vacancySince,
        'version': 1,
        'workspace_id': request.targetWorkspaceId,
      };
      targets.add(target);
      mappings.add(
        LegacyCutoverMapping(
          entity: LegacyCutoverEntity.unit,
          sourceId: sourceId,
          targetId: unitId,
          sourceChecksum: legacyRowChecksum(row),
          targetChecksum: legacyRowChecksum(target),
        ),
      );
    }

    return LegacyCutoverEntityResult(
      targets: <LegacyCutoverEntity, List<Map<String, Object?>>>{
        LegacyCutoverEntity.unit: targets,
      },
      summaries: <LegacyCutoverEntitySummary>[
        buildSummary(
          entity: LegacyCutoverEntity.unit,
          sourceRows: units.length,
          targets: targets,
          sourceRowsData: sortedLegacyRows(units),
          rejectedRows: rejected,
          issues: issues,
        ),
      ],
      mappings: mappings,
      issues: issues,
      targetIdsBySourceId: idsBySourceId,
    );
  }

  String? _status(
    Map<String, Object?> row,
    String? sourceId,
    List<LegacyCutoverIssue> issues,
  ) {
    final value = row['status'];
    if (value is! String || !_unitStatuses.contains(value.trim())) {
      issues.add(
        fieldError(
          'source.invalid_unit_status',
          LegacyCutoverEntity.unit,
          sourceId,
          'status',
        ),
      );
      return null;
    }
    return value.trim();
  }

  double? _boundedNumber(
    Map<String, Object?> row, {
    required String key,
    required String? sourceId,
    required List<LegacyCutoverIssue> issues,
    bool minExclusive = false,
    num? max,
  }) {
    final value = row[key];
    if (value == null) {
      return null;
    }
    final invalid =
        value is! num ||
        !value.isFinite ||
        (minExclusive ? value <= 0 : value < 0) ||
        (max != null && value > max);
    if (invalid) {
      issues.add(
        fieldError(
          'source.invalid_number',
          LegacyCutoverEntity.unit,
          sourceId,
          key,
        ),
      );
      return null;
    }
    return value.toDouble();
  }

  /// The target stores a calendar date; the legacy core stores epoch millis.
  String? _optionalDate(
    Map<String, Object?> row, {
    required String key,
    required String? sourceId,
    required List<LegacyCutoverIssue> issues,
  }) {
    final iso = row[key] == null
        ? null
        : requiredTimestamp(
            row,
            key: key,
            entity: LegacyCutoverEntity.unit,
            sourceId: sourceId,
            issues: issues,
          );
    return iso?.substring(0, 10);
  }
}
