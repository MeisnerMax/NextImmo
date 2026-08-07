import '../../../core/models/contractor.dart';
import '../../../core/models/operations.dart';
import '../../../core/models/property_modules.dart';
import '../../../data/repositories/contractor_repo.dart';
import '../../../data/repositories/lease_repo.dart';
import '../../../data/repositories/property_modules_repo.dart';
import '../application/party_repository.dart';
import '../domain/party_dto.dart';

/// Read-only projection of the parallel legacy contacts / tenants / contractors
/// stores onto the canonical party contract (P2-D02 step 5, mirroring the
/// P1-006 property adapter). Tenants project onto person parties with a tenant
/// role, contractors onto organization parties with a contractor role plus the
/// contractor satellite, and contacts onto parties whose role is derived from
/// `contacts.role` (only tenant/contractor/buyer/bank/company map to a role;
/// other contacts are identity-only). All mutations are blocked with
/// [PartyRepositoryFailureKind.dependencyConflict] — the local schema has no
/// party version, shared identity or audited command envelope.
abstract interface class LegacyPartyReadSource {
  Future<List<TenantRecord>> listTenants();

  Future<List<ContractorRecord>> listContractors();

  Future<List<ContactRecord>> listContacts();
}

/// [LegacyPartyReadSource] backed by the concrete local repositories.
class RepositoryLegacyPartyReadSource implements LegacyPartyReadSource {
  const RepositoryLegacyPartyReadSource({
    required LeaseRepo leaseRepo,
    required ContractorRepository contractorRepo,
    required PropertyModulesRepo propertyModulesRepo,
  }) : _leaseRepo = leaseRepo,
       _contractorRepo = contractorRepo,
       _propertyModulesRepo = propertyModulesRepo;

  final LeaseRepo _leaseRepo;
  final ContractorRepository _contractorRepo;
  final PropertyModulesRepo _propertyModulesRepo;

  @override
  Future<List<TenantRecord>> listTenants() => _leaseRepo.listTenants();

  @override
  Future<List<ContractorRecord>> listContractors() =>
      _contractorRepo.listContractors();

  @override
  Future<List<ContactRecord>> listContacts() =>
      _propertyModulesRepo.listAllContacts();
}

class LegacySqlitePartyRepositoryAdapter
    implements
        PartyRepository,
        PartySearchPort,
        PartyRoleRepository,
        DuplicateDetectionPort {
  LegacySqlitePartyRepositoryAdapter({
    required LegacyPartyReadSource source,
    required String legacyWorkspaceId,
  }) : _source = source,
       _legacyWorkspaceId = legacyWorkspaceId;

  static const int unsupportedVersion = 0;
  static const String _legacyActor = 'legacy';

  final LegacyPartyReadSource _source;
  final String _legacyWorkspaceId;

  // --- PartySearchPort ---

  @override
  Future<PartyRepositoryResult<PartyPageResult>> search(
    PartyListQuery query,
  ) async {
    final scopeFailure = _scopeFailure<PartyPageResult>(query.workspaceId);
    if (scopeFailure != null) {
      return scopeFailure;
    }

    try {
      final parties = await _loadAll();
      final filtered =
          parties
              .where(
                (entry) =>
                    query.roleType == null ||
                    entry.role?.roleType == query.roleType,
              )
              .toList(growable: false)
            ..sort((a, b) => a.party.id.compareTo(b.party.id));

      final cursor = query.page.cursor;
      final page = <PartySummaryDto>[];
      var reachedCursor = cursor == null;
      String? nextCursor;
      for (final entry in filtered) {
        if (!reachedCursor) {
          if (entry.party.id == cursor) {
            reachedCursor = true;
          }
          continue;
        }
        if (page.length == query.page.limit) {
          nextCursor = page.last.id;
          break;
        }
        page.add(entry.party.toSummary());
      }
      return PartyRepositorySuccess<PartyPageResult>(
        PartyPageResult(items: page, nextCursor: nextCursor),
      );
    } catch (_) {
      return _loadFailure<PartyPageResult>();
    }
  }

  // --- PartyRepository ---

  @override
  Future<PartyRepositoryResult<PartyDto>> getById({
    required String workspaceId,
    required String partyId,
  }) async {
    final scopeFailure = _scopeFailure<PartyDto>(workspaceId);
    if (scopeFailure != null) {
      return scopeFailure;
    }

    try {
      final parties = await _loadAll();
      for (final entry in parties) {
        if (entry.party.id == partyId) {
          return PartyRepositorySuccess<PartyDto>(entry.party);
        }
      }
      return const PartyRepositoryFailure<PartyDto>(
        kind: PartyRepositoryFailureKind.notFound,
        message: 'Party not found in the local store.',
      );
    } catch (_) {
      return _loadFailure<PartyDto>();
    }
  }

  @override
  Future<PartyRepositoryResult<PartyDto>> create(CreatePartyCommand command) =>
      _blockedMutation<PartyDto>(command.context.workspaceId);

  @override
  Future<PartyRepositoryResult<PartyDto>> update(UpdatePartyCommand command) =>
      _blockedMutation<PartyDto>(command.context.workspaceId);

  @override
  Future<PartyRepositoryResult<PartyDto>> merge(MergePartiesCommand command) =>
      _blockedMutation<PartyDto>(command.context.workspaceId);

  // --- PartyRoleRepository ---

  @override
  Future<PartyRepositoryResult<List<PartyRoleDto>>> listForParty({
    required String workspaceId,
    required String partyId,
  }) async {
    final scopeFailure = _scopeFailure<List<PartyRoleDto>>(workspaceId);
    if (scopeFailure != null) {
      return scopeFailure;
    }

    try {
      final parties = await _loadAll();
      for (final entry in parties) {
        if (entry.party.id == partyId) {
          return PartyRepositorySuccess<List<PartyRoleDto>>(
            entry.role == null ? const [] : <PartyRoleDto>[entry.role!],
          );
        }
      }
      return const PartyRepositorySuccess<List<PartyRoleDto>>(<PartyRoleDto>[]);
    } catch (_) {
      return _loadFailure<List<PartyRoleDto>>();
    }
  }

  @override
  Future<PartyRepositoryResult<ContractorDetailsDto?>> getContractorDetails({
    required String workspaceId,
    required String partyId,
  }) async {
    final scopeFailure = _scopeFailure<ContractorDetailsDto?>(workspaceId);
    if (scopeFailure != null) {
      return scopeFailure;
    }

    try {
      final parties = await _loadAll();
      for (final entry in parties) {
        if (entry.party.id == partyId) {
          return PartyRepositorySuccess<ContractorDetailsDto?>(
            entry.contractorDetails,
          );
        }
      }
      return const PartyRepositorySuccess<ContractorDetailsDto?>(null);
    } catch (_) {
      return _loadFailure<ContractorDetailsDto?>();
    }
  }

  @override
  Future<PartyRepositoryResult<PartyRoleDto>> assign(
    AssignPartyRoleCommand command,
  ) => _blockedMutation<PartyRoleDto>(command.context.workspaceId);

  @override
  Future<PartyRepositoryResult<PartyRoleDto>> end(EndPartyRoleCommand command) =>
      _blockedMutation<PartyRoleDto>(command.context.workspaceId);

  // --- DuplicateDetectionPort ---

  @override
  Future<PartyRepositoryResult<List<PartyDuplicateCandidate>>> detect(
    PartyDuplicateQuery query,
  ) async {
    final scopeFailure =
        _scopeFailure<List<PartyDuplicateCandidate>>(query.workspaceId);
    if (scopeFailure != null) {
      return scopeFailure;
    }

    final email = _normalizeEmail(query.email);
    final name = _normalizeName(query.displayName);
    final phone = _normalizePhone(query.phone);

    try {
      final parties = await _loadAll();
      final candidates = <PartyDuplicateCandidate>[];
      for (final entry in parties) {
        final party = entry.party;
        final matchEmail =
            email != null && _normalizeEmail(party.email) == email;
        final matchPhone =
            phone != null && _normalizePhone(party.phone) == phone;
        final matchName =
            name != null && _normalizeName(party.displayName) == name;
        if (matchEmail || matchPhone || matchName) {
          candidates.add(
            PartyDuplicateCandidate(
              party: party.toSummary(),
              matchEmail: matchEmail,
              matchPhone: matchPhone,
              matchName: matchName,
            ),
          );
        }
      }
      candidates.sort((a, b) => a.party.id.compareTo(b.party.id));
      return PartyRepositorySuccess<List<PartyDuplicateCandidate>>(candidates);
    } catch (_) {
      return _loadFailure<List<PartyDuplicateCandidate>>();
    }
  }

  // --- projection ---

  Future<List<_LegacyParty>> _loadAll() async {
    final results = await Future.wait(<Future<List<_LegacyParty>>>[
      _source.listTenants().then(
        (rows) => rows.map(_mapTenant).toList(growable: false),
      ),
      _source.listContractors().then(
        (rows) => rows.map(_mapContractor).toList(growable: false),
      ),
      _source.listContacts().then(
        (rows) => rows.map(_mapContact).toList(growable: false),
      ),
    ]);
    return results.expand((entries) => entries).toList(growable: false);
  }

  _LegacyParty _mapTenant(TenantRecord record) {
    final party = _party(
      id: record.id,
      type: PartyType.person,
      displayName: record.displayName,
      legalName: record.legalName,
      email: record.email,
      phone: record.phone,
      notes: record.notes,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
    );
    return _LegacyParty(
      party: party,
      role: _role(party, PartyRoleType.tenant),
    );
  }

  _LegacyParty _mapContractor(ContractorRecord record) {
    final party = _party(
      id: record.id,
      type: PartyType.organization,
      displayName: record.companyName,
      legalName: null,
      email: record.email,
      phone: record.phone,
      notes: record.notes,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
    );
    return _LegacyParty(
      party: party,
      role: _role(party, PartyRoleType.contractor),
      contractorDetails: ContractorDetailsDto(
        partyId: party.id,
        workspaceId: _legacyWorkspaceId,
        tradeCategory: record.tradeCategory,
        isActive: record.isActive,
        version: unsupportedVersion,
        hourlyRate: record.hourlyRate,
        serviceArea: record.serviceAreas.isEmpty
            ? null
            : record.serviceAreas.join(', '),
        ratingPrice: record.ratingPrice,
        ratingQuality: record.ratingQuality,
        ratingSpeed: record.ratingSpeed,
        ratingCommunication: record.ratingCommunication,
        ratingPunctuality: record.ratingPunctuality,
        insuranceCertExpiry: record.insuranceCertExpiry == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                record.insuranceCertExpiry!,
                isUtc: true,
              ),
      ),
    );
  }

  _LegacyParty _mapContact(ContactRecord record) {
    final party = _party(
      id: record.id,
      type: PartyType.person,
      displayName: record.displayName,
      legalName: record.legalName,
      email: record.email,
      phone: record.phone,
      notes: record.notes,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
    );
    final roleType = _contactRoleType(record.role);
    return _LegacyParty(
      party: party,
      role: roleType == null ? null : _role(party, roleType),
    );
  }

  PartyDto _party({
    required String id,
    required PartyType type,
    required String displayName,
    required String? legalName,
    required String? email,
    required String? phone,
    required String? notes,
    required int createdAt,
    required int updatedAt,
  }) {
    return PartyDto(
      id: id,
      workspaceId: _legacyWorkspaceId,
      type: type,
      displayName: displayName,
      legalName: legalName,
      email: email,
      phone: phone,
      notes: notes,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt, isUtc: true),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt, isUtc: true),
      createdBy: _legacyActor,
      updatedBy: _legacyActor,
      version: unsupportedVersion,
    );
  }

  PartyRoleDto _role(PartyDto party, PartyRoleType roleType) {
    return PartyRoleDto(
      id: '${party.id}:${roleType.name}',
      workspaceId: _legacyWorkspaceId,
      partyId: party.id,
      roleType: roleType,
      validFrom: party.createdAt,
      version: unsupportedVersion,
    );
  }

  static PartyRoleType? _contactRoleType(String role) {
    switch (role.trim().toLowerCase()) {
      case 'tenant':
        return PartyRoleType.tenant;
      case 'contractor':
        return PartyRoleType.contractor;
      case 'buyer':
        return PartyRoleType.buyer;
      case 'bank':
        return PartyRoleType.bank;
      case 'company':
        return PartyRoleType.company;
      default:
        return null;
    }
  }

  static String? _normalizeEmail(String? value) {
    final trimmed = value?.trim().toLowerCase();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static String? _normalizeName(String? value) {
    final trimmed = value?.trim().toLowerCase();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static String? _normalizePhone(String? value) {
    if (value == null) {
      return null;
    }
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.isEmpty ? null : digits;
  }

  Future<PartyRepositoryResult<T>> _blockedMutation<T>(
    String workspaceId,
  ) async {
    final scopeFailure = _scopeFailure<T>(workspaceId);
    if (scopeFailure != null) {
      return scopeFailure;
    }
    return const PartyRepositoryFailure(
      kind: PartyRepositoryFailureKind.dependencyConflict,
      message:
          'Legacy SQLite party administration is blocked: the local schema has '
          'no shared party identity, durable version or audited command '
          'envelope.',
    );
  }

  PartyRepositoryFailure<T>? _scopeFailure<T>(String workspaceId) {
    if (workspaceId == _legacyWorkspaceId) {
      return null;
    }
    return PartyRepositoryFailure<T>(
      kind: PartyRepositoryFailureKind.forbidden,
      message: 'The legacy SQLite database is bound to another workspace.',
    );
  }

  PartyRepositoryFailure<T> _loadFailure<T>() {
    return const PartyRepositoryFailure(
      kind: PartyRepositoryFailureKind.infrastructureFailure,
      message: 'Legacy SQLite parties could not be loaded.',
    );
  }
}

class _LegacyParty {
  const _LegacyParty({
    required this.party,
    this.role,
    this.contractorDetails,
  });

  final PartyDto party;
  final PartyRoleDto? role;
  final ContractorDetailsDto? contractorDetails;
}
