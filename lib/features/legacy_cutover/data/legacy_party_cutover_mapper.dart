/// P2-X01-AP4 stage 1: legacy `tenants` to `public.parties` / `public.party_roles`.
///
/// A tenant in the legacy core is a contact with an implicit tenant role. The
/// target splits that into an identity (`parties`) and a time-boundable role
/// (`party_roles`), so one source row produces one row in each — and both
/// reconcile separately.
library;

import 'package:uuid/uuid.dart';

import '../application/legacy_cutover.dart';
import 'legacy_cutover_fields.dart';

/// Namespace suffixes for the deterministic UUIDv5 target identifiers. Changing
/// one of these re-points every target row, so they are part of the contract.
const _partyNamespace = 'neximmo/p2-x01/party';
const _partyRoleNamespace = 'neximmo/p2-x01/party-role';

/// Source columns without a target. `status` (`active`/`prospect`) is a leasing
/// state, not an identity attribute — the target models it through the leasing
/// aggregate, so carrying it onto the party would duplicate a truth.
const Set<String> _excludedTenantFields = <String>{
  'alternative_contact',
  'billing_contact',
  'move_in_reference',
  'status',
};

const Set<String> _knownTenantFields = <String>{
  'created_at',
  'display_name',
  'email',
  'id',
  'legal_name',
  'notes',
  'phone',
  'updated_at',
  ..._excludedTenantFields,
};

/// Tokens that mark an organization. The legacy core has no party-type column,
/// but the target requires one, so it is derived — deterministically and with a
/// per-row warning, never silently.
const List<String> _organizationTokens = <String>[
  'ag',
  'e.k.',
  'gbr',
  'gmbh',
  'group',
  'holding',
  'inc',
  'investment',
  'kg',
  'ltd',
  'mbh',
  'ohg',
  'se',
  'ug',
];

class LegacyPartyCutoverMapper {
  const LegacyPartyCutoverMapper();

  LegacyCutoverEntityResult map({
    required List<Map<String, Object?>> tenants,
    required LegacyCutoverRequest request,
  }) {
    final partyTargets = <Map<String, Object?>>[];
    final roleTargets = <Map<String, Object?>>[];
    final partyMappings = <LegacyCutoverMapping>[];
    final roleMappings = <LegacyCutoverMapping>[];
    final issues = <LegacyCutoverIssue>[];
    final idsBySourceId = <String, String>{};
    var rejectedParties = 0;

    for (final row in sortedLegacyRows(tenants)) {
      final rowIssues = <LegacyCutoverIssue>[];
      final sourceId = requiredSourceId(
        row,
        LegacyCutoverEntity.party,
        rowIssues,
      );
      reportUnknownFields(
        row,
        known: _knownTenantFields,
        entity: LegacyCutoverEntity.party,
        sourceId: sourceId,
        issues: rowIssues,
      );
      reportExcludedFields(
        row,
        excluded: _excludedTenantFields,
        entity: LegacyCutoverEntity.party,
        sourceId: sourceId,
        issues: rowIssues,
      );

      final displayName = requiredText(
        row,
        key: 'display_name',
        maxLength: 200,
        entity: LegacyCutoverEntity.party,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final legalName = optionalText(
        row,
        key: 'legal_name',
        maxLength: 200,
        entity: LegacyCutoverEntity.party,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final email = optionalEmail(
        row,
        key: 'email',
        entity: LegacyCutoverEntity.party,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final phone = optionalText(
        row,
        key: 'phone',
        maxLength: 50,
        entity: LegacyCutoverEntity.party,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final notes = optionalText(
        row,
        key: 'notes',
        maxLength: 10000,
        entity: LegacyCutoverEntity.party,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final createdAt = requiredTimestamp(
        row,
        key: 'created_at',
        entity: LegacyCutoverEntity.party,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final updatedAt = requiredTimestamp(
        row,
        key: 'updated_at',
        entity: LegacyCutoverEntity.party,
        sourceId: sourceId,
        issues: rowIssues,
      );

      issues.addAll(rowIssues);
      if (rowIssues.any((issue) => issue.isError) ||
          sourceId == null ||
          displayName == null ||
          createdAt == null ||
          updatedAt == null) {
        rejectedParties++;
        continue;
      }

      final partyType = _inferPartyType(displayName, legalName);
      issues.add(
        LegacyCutoverIssue(
          code: 'mapping.party_type_inferred',
          severity: LegacyCutoverIssueSeverity.warning,
          entity: LegacyCutoverEntity.party,
          sourceId: sourceId,
          field: 'party_type',
        ),
      );

      final partyId = const Uuid().v5(
        request.targetWorkspaceId,
        '$_partyNamespace/$sourceId',
      );
      idsBySourceId[sourceId] = partyId;
      final party = <String, Object?>{
        'created_at': createdAt,
        'created_by': request.actorId,
        'deleted_at': null,
        'display_name': displayName,
        'email': email,
        'id': partyId,
        'legal_name': legalName,
        'merged_into_party_id': null,
        'notes': notes,
        'party_type': partyType,
        'phone': phone,
        'updated_at': updatedAt,
        'updated_by': request.actorId,
        'version': 1,
        'workspace_id': request.targetWorkspaceId,
      };
      partyTargets.add(party);
      partyMappings.add(
        LegacyCutoverMapping(
          entity: LegacyCutoverEntity.party,
          sourceId: sourceId,
          targetId: partyId,
          sourceChecksum: legacyRowChecksum(row),
          targetChecksum: legacyRowChecksum(party),
        ),
      );

      // Every migrated tenant carries exactly one open tenant role. The target
      // enforces at most one open role per type, so a re-run updates it rather
      // than stacking duplicates.
      final roleId = const Uuid().v5(
        request.targetWorkspaceId,
        '$_partyRoleNamespace/$sourceId/tenant',
      );
      final role = <String, Object?>{
        'created_at': createdAt,
        'created_by': request.actorId,
        'id': roleId,
        'party_id': partyId,
        'role_type': 'tenant',
        'updated_at': updatedAt,
        'updated_by': request.actorId,
        'valid_from': createdAt,
        'valid_until': null,
        'version': 1,
        'workspace_id': request.targetWorkspaceId,
      };
      roleTargets.add(role);
      roleMappings.add(
        LegacyCutoverMapping(
          entity: LegacyCutoverEntity.partyRole,
          sourceId: sourceId,
          targetId: roleId,
          sourceChecksum: legacyRowChecksum(row),
          targetChecksum: legacyRowChecksum(role),
        ),
      );
    }

    return LegacyCutoverEntityResult(
      targets: <LegacyCutoverEntity, List<Map<String, Object?>>>{
        LegacyCutoverEntity.party: partyTargets,
        LegacyCutoverEntity.partyRole: roleTargets,
      },
      summaries: <LegacyCutoverEntitySummary>[
        buildSummary(
          entity: LegacyCutoverEntity.party,
          sourceRows: tenants.length,
          targets: partyTargets,
          sourceRowsData: sortedLegacyRows(tenants),
          rejectedRows: rejectedParties,
          issues: issues,
        ),
        buildSummary(
          entity: LegacyCutoverEntity.partyRole,
          sourceRows: tenants.length,
          targets: roleTargets,
          sourceRowsData: sortedLegacyRows(tenants),
          rejectedRows: rejectedParties,
          issues: issues,
        ),
      ],
      mappings: <LegacyCutoverMapping>[...partyMappings, ...roleMappings],
      issues: issues,
      targetIdsBySourceId: idsBySourceId,
    );
  }

  String _inferPartyType(String displayName, String? legalName) {
    final haystack = '$displayName ${legalName ?? ''}'.toLowerCase();
    final words = haystack.split(RegExp(r'[^a-z0-9.]+'));
    return words.any(_organizationTokens.contains) ||
            _organizationTokens.any(
              (token) => token.length > 3 && haystack.contains(token),
            )
        ? 'organization'
        : 'person';
  }
}
