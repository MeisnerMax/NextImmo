/// Domain DTOs for the canonical Party aggregate (P2-D02, DOM-003).
///
/// A [PartyDto] is one canonical identity with a shared id; functional roles
/// ([PartyRoleType]) are time-boundable [PartyRoleDto]s and role-specific
/// attributes live in per-role satellites such as [ContractorDetailsDto].
library;

enum PartyType { person, organization }

enum PartyRoleType { tenant, contractor, buyer, bank, company }

/// Compact projection used by search/list results.
class PartySummaryDto {
  const PartySummaryDto({
    required this.id,
    required this.workspaceId,
    required this.type,
    required this.displayName,
    required this.version,
    this.legalName,
    this.email,
    this.phone,
    this.deletedAt,
  });

  final String id;
  final String workspaceId;
  final PartyType type;
  final String displayName;
  final int version;
  final String? legalName;
  final String? email;
  final String? phone;
  final DateTime? deletedAt;

  bool get isMerged => deletedAt != null;
}

class PartyDto extends PartySummaryDto {
  const PartyDto({
    required super.id,
    required super.workspaceId,
    required super.type,
    required super.displayName,
    super.legalName,
    super.email,
    super.phone,
    this.notes,
    this.mergedIntoPartyId,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
    required super.version,
    super.deletedAt,
  });

  final String? notes;

  /// The surviving party this one was folded into, set only on a tombstoned
  /// (merged) party.
  final String? mergedIntoPartyId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final String updatedBy;

  PartySummaryDto toSummary() => PartySummaryDto(
    id: id,
    workspaceId: workspaceId,
    type: type,
    displayName: displayName,
    version: version,
    legalName: legalName,
    email: email,
    phone: phone,
    deletedAt: deletedAt,
  );
}

class PartyRoleDto {
  const PartyRoleDto({
    required this.id,
    required this.workspaceId,
    required this.partyId,
    required this.roleType,
    required this.validFrom,
    required this.version,
    this.validUntil,
  });

  final String id;
  final String workspaceId;
  final String partyId;
  final PartyRoleType roleType;
  final DateTime validFrom;
  final int version;
  final DateTime? validUntil;

  /// A role with no `validUntil` is currently open (time-unbounded).
  bool get isOpen => validUntil == null;
}

/// Per-role satellite for the contractor role (money as decimal).
class ContractorDetailsDto {
  const ContractorDetailsDto({
    required this.partyId,
    required this.workspaceId,
    required this.tradeCategory,
    required this.isActive,
    required this.version,
    this.hourlyRate,
    this.serviceArea,
    this.ratingPrice,
    this.ratingQuality,
    this.ratingSpeed,
    this.ratingCommunication,
    this.ratingPunctuality,
    this.insuranceCertExpiry,
  });

  final String partyId;
  final String workspaceId;
  final String tradeCategory;
  final bool isActive;
  final int version;
  final double? hourlyRate;
  final String? serviceArea;
  final double? ratingPrice;
  final double? ratingQuality;
  final double? ratingSpeed;
  final double? ratingCommunication;
  final double? ratingPunctuality;
  final DateTime? insuranceCertExpiry;
}

/// One duplicate-detection candidate: an existing party plus which normalized
/// attributes matched the probe.
class PartyDuplicateCandidate {
  const PartyDuplicateCandidate({
    required this.party,
    required this.matchEmail,
    required this.matchPhone,
    required this.matchName,
  });

  final PartySummaryDto party;
  final bool matchEmail;
  final bool matchPhone;
  final bool matchName;
}

/// Input for [create]. Free-text fields are normalized server-side.
class PartyDraft {
  const PartyDraft({
    required this.type,
    required this.displayName,
    this.legalName,
    this.email,
    this.phone,
    this.notes,
  });

  final PartyType type;
  final String displayName;
  final String? legalName;
  final String? email;
  final String? phone;
  final String? notes;
}

/// Full desired identity state for [update]; every field is sent, so a null
/// clears the field and a value sets it (matching [PropertyUpdateDto]'s
/// whole-record shape).
class PartyUpdateDto {
  const PartyUpdateDto({
    required this.type,
    required this.displayName,
    this.legalName,
    this.email,
    this.phone,
    this.notes,
  });

  final PartyType type;
  final String displayName;
  final String? legalName;
  final String? email;
  final String? phone;
  final String? notes;
}

/// Contractor satellite attributes supplied when assigning the contractor role.
class ContractorDetailsInput {
  const ContractorDetailsInput({
    required this.tradeCategory,
    this.hourlyRate,
    this.serviceArea,
    this.ratingPrice,
    this.ratingQuality,
    this.ratingSpeed,
    this.ratingCommunication,
    this.ratingPunctuality,
    this.insuranceCertExpiry,
    this.isActive = true,
  });

  final String tradeCategory;
  final double? hourlyRate;
  final String? serviceArea;
  final double? ratingPrice;
  final double? ratingQuality;
  final double? ratingSpeed;
  final double? ratingCommunication;
  final double? ratingPunctuality;
  final DateTime? insuranceCertExpiry;
  final bool isActive;
}
