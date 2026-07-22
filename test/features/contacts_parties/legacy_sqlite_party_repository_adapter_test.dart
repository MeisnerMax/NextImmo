import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/contractor.dart';
import 'package:neximmo_app/core/models/operations.dart';
import 'package:neximmo_app/core/models/property_modules.dart';
import 'package:neximmo_app/features/contacts_parties/application/party_repository.dart';
import 'package:neximmo_app/features/contacts_parties/data/legacy_sqlite_party_repository_adapter.dart';
import 'package:neximmo_app/features/contacts_parties/domain/party_dto.dart';

const String _workspace = 'legacy-workspace';

void main() {
  group('LegacySqlitePartyRepositoryAdapter', () {
    late _FakeLegacyPartyReadSource source;
    late LegacySqlitePartyRepositoryAdapter repository;

    setUp(() {
      source = _FakeLegacyPartyReadSource();
      repository = LegacySqlitePartyRepositoryAdapter(
        source: source,
        legacyWorkspaceId: _workspace,
      );
    });

    test('projects tenants, contractors and contacts onto parties', () async {
      final result = await repository.search(
        const PartyListQuery(workspaceId: _workspace),
      );

      final page = (result as PartyRepositorySuccess<PartyPageResult>).value;
      // Sorted by id: contractor 'c1', contact 'k1', tenant 't1'.
      expect(page.items.map((party) => party.id), <String>['c1', 'k1', 't1']);
      final contractor = page.items.firstWhere((party) => party.id == 'c1');
      expect(contractor.type, PartyType.organization);
      expect(contractor.displayName, 'Acme Plumbing');
    });

    test('role-scopes the search to a single functional role', () async {
      final result = await repository.search(
        const PartyListQuery(
          workspaceId: _workspace,
          roleType: PartyRoleType.contractor,
        ),
      );

      final page = (result as PartyRepositorySuccess<PartyPageResult>).value;
      expect(page.items.map((party) => party.id), <String>['c1']);
    });

    test('paginates with a keyset cursor', () async {
      final firstPage = await repository.search(
        const PartyListQuery(
          workspaceId: _workspace,
          page: PartyPageRequest(limit: 2),
        ),
      );
      final first = (firstPage as PartyRepositorySuccess<PartyPageResult>).value;
      expect(first.items.map((party) => party.id), <String>['c1', 'k1']);
      expect(first.nextCursor, 'k1');

      final secondPage = await repository.search(
        PartyListQuery(
          workspaceId: _workspace,
          page: PartyPageRequest(limit: 2, cursor: first.nextCursor),
        ),
      );
      final second =
          (secondPage as PartyRepositorySuccess<PartyPageResult>).value;
      expect(second.items.map((party) => party.id), <String>['t1']);
      expect(second.nextCursor, isNull);
    });

    test('reads a party by id and reports missing ids', () async {
      final found = await repository.getById(
        workspaceId: _workspace,
        partyId: 't1',
      );
      expect(
        (found as PartyRepositorySuccess<PartyDto>).value.displayName,
        'Tina Tenant',
      );

      final missing = await repository.getById(
        workspaceId: _workspace,
        partyId: 'nope',
      );
      expect(
        (missing as PartyRepositoryFailure<PartyDto>).kind,
        PartyRepositoryFailureKind.notFound,
      );
    });

    test('derives one role per legacy party', () async {
      final tenantRoles = await repository.listForParty(
        workspaceId: _workspace,
        partyId: 't1',
      );
      expect(
        (tenantRoles as PartyRepositorySuccess<List<PartyRoleDto>>)
            .value
            .single
            .roleType,
        PartyRoleType.tenant,
      );

      // The contact carries role 'other', which maps to no functional role.
      final contactRoles = await repository.listForParty(
        workspaceId: _workspace,
        partyId: 'k1',
      );
      expect(
        (contactRoles as PartyRepositorySuccess<List<PartyRoleDto>>).value,
        isEmpty,
      );
    });

    test('maps a buyer contact onto the buyer role', () async {
      source.contacts = <ContactRecord>[_contact(id: 'k2', role: 'buyer')];

      final roles = await repository.listForParty(
        workspaceId: _workspace,
        partyId: 'k2',
      );
      expect(
        (roles as PartyRepositorySuccess<List<PartyRoleDto>>)
            .value
            .single
            .roleType,
        PartyRoleType.buyer,
      );
    });

    test('projects the contractor satellite and null for others', () async {
      final contractor = await repository.getContractorDetails(
        workspaceId: _workspace,
        partyId: 'c1',
      );
      final details =
          (contractor as PartyRepositorySuccess<ContractorDetailsDto?>).value;
      expect(details?.tradeCategory, 'Sanitär');
      expect(details?.serviceArea, 'Berlin, Potsdam');
      expect(details?.isActive, isTrue);

      final tenant = await repository.getContractorDetails(
        workspaceId: _workspace,
        partyId: 't1',
      );
      expect(
        (tenant as PartyRepositorySuccess<ContractorDetailsDto?>).value,
        isNull,
      );
    });

    test('detects duplicates over normalized identity', () async {
      final byEmail = await repository.detect(
        const PartyDuplicateQuery(
          workspaceId: _workspace,
          email: 'TINA@example.test',
        ),
      );
      final emailMatches =
          (byEmail as PartyRepositorySuccess<List<PartyDuplicateCandidate>>)
              .value;
      expect(emailMatches.single.party.id, 't1');
      expect(emailMatches.single.matchEmail, isTrue);

      final byName = await repository.detect(
        const PartyDuplicateQuery(
          workspaceId: _workspace,
          displayName: 'acme plumbing',
        ),
      );
      expect(
        (byName as PartyRepositorySuccess<List<PartyDuplicateCandidate>>)
            .value
            .single
            .party
            .id,
        'c1',
      );
    });

    test('blocks every mutation with a dependency conflict', () async {
      final results = <PartyRepositoryResult<Object?>>[
        await repository.create(
          CreatePartyCommand(
            context: _context(),
            draft: const PartyDraft(
              type: PartyType.person,
              displayName: 'New',
            ),
          ),
        ),
        await repository.update(
          UpdatePartyCommand(
            context: _context(),
            partyId: 't1',
            expectedVersion: 1,
            changes: const PartyUpdateDto(
              type: PartyType.person,
              displayName: 'New',
            ),
          ),
        ),
        await repository.merge(
          MergePartiesCommand(
            context: _context(),
            targetPartyId: 't1',
            sourcePartyId: 'k1',
            expectedTargetVersion: 1,
            expectedSourceVersion: 1,
          ),
        ),
        await repository.assign(
          AssignPartyRoleCommand(
            context: _context(),
            partyId: 't1',
            roleType: PartyRoleType.tenant,
          ),
        ),
        await repository.end(
          EndPartyRoleCommand(
            context: _context(),
            partyRoleId: 't1:tenant',
            expectedVersion: 1,
          ),
        ),
      ];

      for (final result in results) {
        expect(
          (result as PartyRepositoryFailure).kind,
          PartyRepositoryFailureKind.dependencyConflict,
        );
      }
    });

    test('fails closed for a foreign workspace', () async {
      final read = await repository.search(
        const PartyListQuery(workspaceId: 'other-workspace'),
      );
      expect(
        (read as PartyRepositoryFailure<PartyPageResult>).kind,
        PartyRepositoryFailureKind.forbidden,
      );

      final write = await repository.create(
        CreatePartyCommand(
          context: const PartyCommandContext(
            workspaceId: 'other-workspace',
            actorId: 'actor',
            mutationId: 'mutation',
            correlationId: 'correlation',
          ),
          draft: const PartyDraft(type: PartyType.person, displayName: 'New'),
        ),
      );
      expect(
        (write as PartyRepositoryFailure<PartyDto>).kind,
        PartyRepositoryFailureKind.forbidden,
      );
    });
  });
}

PartyCommandContext _context() {
  return const PartyCommandContext(
    workspaceId: _workspace,
    actorId: 'actor',
    mutationId: 'mutation',
    correlationId: 'correlation',
  );
}

TenantRecord _tenant() {
  return const TenantRecord(
    id: 't1',
    displayName: 'Tina Tenant',
    legalName: null,
    email: 'tina@example.test',
    phone: '+49 30 5',
    alternativeContact: null,
    billingContact: null,
    status: null,
    moveInReference: null,
    notes: null,
    createdAt: 1000,
    updatedAt: 2000,
  );
}

ContractorRecord _contractor() {
  return const ContractorRecord(
    id: 'c1',
    companyName: 'Acme Plumbing',
    tradeCategory: 'Sanitär',
    contactName: 'Carla Contractor',
    phone: '+49 30 7',
    email: 'acme@example.test',
    address: 'Berlin',
    hourlyRate: 85.5,
    serviceAreas: <String>['Berlin', 'Potsdam'],
    notes: null,
    createdAt: 1500,
    updatedAt: 2500,
    ratingQuality: 4.5,
    isActive: true,
  );
}

ContactRecord _contact({String id = 'k1', String role = 'other'}) {
  return ContactRecord(
    id: id,
    displayName: 'Karl Contact',
    role: role,
    email: 'karl@example.test',
    phone: '+49 30 9',
    createdAt: 1200,
    updatedAt: 2200,
  );
}

class _FakeLegacyPartyReadSource implements LegacyPartyReadSource {
  List<TenantRecord> tenants = <TenantRecord>[_tenant()];
  List<ContractorRecord> contractors = <ContractorRecord>[_contractor()];
  List<ContactRecord> contacts = <ContactRecord>[_contact()];

  @override
  Future<List<TenantRecord>> listTenants() async => tenants;

  @override
  Future<List<ContractorRecord>> listContractors() async => contractors;

  @override
  Future<List<ContactRecord>> listContacts() async => contacts;
}
