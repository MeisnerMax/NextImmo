import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/contacts_parties/application/party_repository.dart';
import 'package:neximmo_app/features/contacts_parties/data/supabase_party_repository_adapter.dart';
import 'package:neximmo_app/features/contacts_parties/domain/party_dto.dart';

void main() {
  group('SupabasePartyRepositoryAdapter', () {
    late _FakePartySupabaseGateway gateway;
    late SupabasePartyRepositoryAdapter repository;

    setUp(() {
      gateway = _FakePartySupabaseGateway();
      repository = SupabasePartyRepositoryAdapter.withGateway(gateway);
    });

    test('searches a page and forwards the role-scoped filter', () async {
      gateway.partiesResult = <Map<String, dynamic>>[
        _partySummaryJson(id: 'party-a'),
        _partySummaryJson(id: 'party-b'),
        _partySummaryJson(id: 'party-c'),
      ];

      final result = await repository.search(
        const PartyListQuery(
          workspaceId: 'workspace-a',
          roleType: PartyRoleType.tenant,
          page: PartyPageRequest(limit: 2),
        ),
      );

      expect(gateway.partiesWorkspaceId, 'workspace-a');
      expect(gateway.partiesRoleType, 'tenant');
      expect(gateway.partiesLimit, 3); // limit + 1 for has-next probe.
      expect(gateway.partiesIncludeMerged, isFalse);
      final page = (result as PartyRepositorySuccess<PartyPageResult>).value;
      expect(page.items.map((party) => party.id), <String>['party-a', 'party-b']);
      expect(page.nextCursor, 'party-b');
    });

    test('returns no cursor on the final page', () async {
      gateway.partiesResult = <Map<String, dynamic>>[
        _partySummaryJson(id: 'party-a'),
      ];

      final result = await repository.search(
        const PartyListQuery(workspaceId: 'workspace-a'),
      );

      final page = (result as PartyRepositorySuccess<PartyPageResult>).value;
      expect(page.nextCursor, isNull);
    });

    test('rejects a party row from a foreign workspace', () async {
      gateway.partiesResult = <Map<String, dynamic>>[
        _partySummaryJson(id: 'party-a', workspaceId: 'workspace-b'),
      ];

      final result = await repository.search(
        const PartyListQuery(workspaceId: 'workspace-a'),
      );

      expect(
        (result as PartyRepositoryFailure<PartyPageResult>).kind,
        PartyRepositoryFailureKind.infrastructureFailure,
      );
    });

    test('reads a party by id', () async {
      gateway.getPartyResult = <Map<String, dynamic>>[_partyJson()];

      final result = await repository.getById(
        workspaceId: 'workspace-a',
        partyId: 'party-a',
      );

      final party = (result as PartyRepositorySuccess<PartyDto>).value;
      expect(party.id, 'party-a');
      expect(party.type, PartyType.person);
      expect(party.email, 'alice@example.test');
    });

    test('maps an empty getById to not found', () async {
      gateway.getPartyResult = <Map<String, dynamic>>[];

      final result = await repository.getById(
        workspaceId: 'workspace-a',
        partyId: 'missing',
      );

      expect(
        (result as PartyRepositoryFailure<PartyDto>).kind,
        PartyRepositoryFailureKind.notFound,
      );
    });

    test('rejects actor mismatch before calling the create RPC', () async {
      gateway.currentUserId = 'someone-else';

      final result = await repository.create(_createCommand());

      expect(gateway.rpcCalls, 0);
      expect(
        (result as PartyRepositoryFailure<PartyDto>).kind,
        PartyRepositoryFailureKind.forbidden,
      );
    });

    test('creates through the RPC with the serialized draft', () async {
      gateway.rpcResult = <String, Object?>{'ok': true, 'entity': _partyJson()};

      final result = await repository.create(_createCommand());

      expect(gateway.rpcFunction, 'create_party');
      expect(gateway.rpcParameters, <String, Object?>{
        'p_workspace_id': 'workspace-a',
        'p_party_type': 'person',
        'p_display_name': 'Alice Example',
        'p_mutation_id': 'mutation-a',
        'p_correlation_id': 'correlation-a',
        'p_legal_name': null,
        'p_email': 'alice@example.test',
        'p_phone': '+49 30 111',
        'p_notes': null,
        'p_reason': 'Onboarding',
      });
      expect((result as PartyRepositorySuccess<PartyDto>).value.id, 'party-a');
    });

    test('updates through the RPC with the full changes object', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': true,
        'entity': _partyJson(version: 2, legalName: 'Alice GmbH'),
      };

      final result = await repository.update(
        UpdatePartyCommand(
          context: _context(),
          partyId: 'party-a',
          expectedVersion: 1,
          changes: const PartyUpdateDto(
            type: PartyType.person,
            displayName: 'Alice Example',
            legalName: 'Alice GmbH',
            email: 'alice@example.test',
            phone: '+49 30 999',
          ),
        ),
      );

      expect(gateway.rpcFunction, 'update_party');
      expect(gateway.rpcParameters, <String, Object?>{
        'p_workspace_id': 'workspace-a',
        'p_party_id': 'party-a',
        'p_expected_version': 1,
        'p_mutation_id': 'mutation-a',
        'p_correlation_id': 'correlation-a',
        'p_changes': <String, Object?>{
          'party_type': 'person',
          'display_name': 'Alice Example',
          'legal_name': 'Alice GmbH',
          'email': 'alice@example.test',
          'phone': '+49 30 999',
          'notes': null,
        },
        'p_reason': 'Onboarding',
      });
      final party = (result as PartyRepositorySuccess<PartyDto>).value;
      expect(party.version, 2);
      expect(party.legalName, 'Alice GmbH');
    });

    test('maps a party version conflict including the current party', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'version_conflict',
          'message': 'Party version is stale',
          'expected_version': 1,
          'actual_version': 4,
          'current_entity': _partyJson(version: 4),
        },
      };

      final result = await repository.update(
        UpdatePartyCommand(
          context: _context(),
          partyId: 'party-a',
          expectedVersion: 1,
          changes: const PartyUpdateDto(
            type: PartyType.person,
            displayName: 'Alice Example',
          ),
        ),
      );
      final failure = result as PartyRepositoryFailure<PartyDto>;

      expect(failure.kind, PartyRepositoryFailureKind.versionConflict);
      expect(failure.versionConflict?.expectedVersion, 1);
      expect(failure.versionConflict?.actualVersion, 4);
      expect(failure.versionConflict?.currentParty?.version, 4);
      expect(failure.versionConflict?.currentRole, isNull);
    });

    test('merges through the RPC with both expected versions', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': true,
        'entity': _partyJson(version: 2),
      };

      final result = await repository.merge(
        MergePartiesCommand(
          context: _context(),
          targetPartyId: 'party-a',
          sourcePartyId: 'party-b',
          expectedTargetVersion: 1,
          expectedSourceVersion: 1,
        ),
      );

      expect(gateway.rpcFunction, 'merge_parties');
      expect(gateway.rpcParameters, <String, Object?>{
        'p_workspace_id': 'workspace-a',
        'p_target_party_id': 'party-a',
        'p_source_party_id': 'party-b',
        'p_expected_target_version': 1,
        'p_expected_source_version': 1,
        'p_mutation_id': 'mutation-a',
        'p_correlation_id': 'correlation-a',
        'p_reason': 'Onboarding',
      });
      expect(result, isA<PartyRepositorySuccess<PartyDto>>());
    });

    test('assigns a contractor role with a serialized details payload', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': true,
        'entity': _roleJson(roleType: 'contractor'),
      };

      final result = await repository.assign(
        AssignPartyRoleCommand(
          context: _context(),
          partyId: 'party-a',
          roleType: PartyRoleType.contractor,
          validFrom: DateTime.utc(2026, 7, 22, 10),
          contractorDetails: ContractorDetailsInput(
            tradeCategory: 'Plumbing',
            hourlyRate: 85.5,
            ratingQuality: 4.5,
            insuranceCertExpiry: DateTime.utc(2027, 1, 15),
          ),
        ),
      );

      expect(gateway.rpcFunction, 'assign_party_role');
      expect(gateway.rpcParameters, <String, Object?>{
        'p_workspace_id': 'workspace-a',
        'p_party_id': 'party-a',
        'p_role_type': 'contractor',
        'p_mutation_id': 'mutation-a',
        'p_correlation_id': 'correlation-a',
        'p_valid_from': '2026-07-22T10:00:00.000Z',
        'p_valid_until': null,
        'p_details': <String, Object?>{
          'trade_category': 'Plumbing',
          'hourly_rate': 85.5,
          'service_area': null,
          'rating_price': null,
          'rating_quality': 4.5,
          'rating_speed': null,
          'rating_communication': null,
          'rating_punctuality': null,
          'insurance_cert_expiry': '2027-01-15',
          'is_active': true,
        },
        'p_reason': 'Onboarding',
      });
      final role = (result as PartyRepositorySuccess<PartyRoleDto>).value;
      expect(role.roleType, PartyRoleType.contractor);
    });

    test('assigns a plain role with a null details payload', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': true,
        'entity': _roleJson(roleType: 'tenant'),
      };

      await repository.assign(
        AssignPartyRoleCommand(
          context: _context(),
          partyId: 'party-a',
          roleType: PartyRoleType.tenant,
        ),
      );

      expect(gateway.rpcParameters?['p_details'], isNull);
      expect(gateway.rpcParameters?['p_valid_from'], isNull);
    });

    test('maps a role version conflict including the current role', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'version_conflict',
          'message': 'Party role version is stale',
          'expected_version': 1,
          'actual_version': 2,
          'current_entity': _roleJson(version: 2),
        },
      };

      final result = await repository.end(
        EndPartyRoleCommand(
          context: _context(),
          partyRoleId: 'role-a',
          expectedVersion: 1,
        ),
      );
      final failure = result as PartyRepositoryFailure<PartyRoleDto>;

      expect(failure.kind, PartyRepositoryFailureKind.versionConflict);
      expect(failure.versionConflict?.currentRole?.version, 2);
      expect(failure.versionConflict?.currentParty, isNull);
    });

    test('lists roles for a party', () async {
      gateway.rolesResult = <Map<String, dynamic>>[
        _roleJson(roleType: 'tenant'),
        _roleJson(id: 'role-b', roleType: 'contractor', validUntil: '2026-08-01T00:00:00Z'),
      ];

      final result = await repository.listForParty(
        workspaceId: 'workspace-a',
        partyId: 'party-a',
      );

      final roles = (result as PartyRepositorySuccess<List<PartyRoleDto>>).value;
      expect(roles.first.roleType, PartyRoleType.tenant);
      expect(roles.first.isOpen, isTrue);
      expect(roles.last.roleType, PartyRoleType.contractor);
      expect(roles.last.isOpen, isFalse);
    });

    test('reads contractor details and maps an empty result to null', () async {
      gateway.contractorResult = <Map<String, dynamic>>[_contractorJson()];
      final present = await repository.getContractorDetails(
        workspaceId: 'workspace-a',
        partyId: 'party-a',
      );
      final details =
          (present as PartyRepositorySuccess<ContractorDetailsDto?>).value;
      expect(details?.tradeCategory, 'Plumbing');
      expect(details?.hourlyRate, 85.5);

      gateway.contractorResult = <Map<String, dynamic>>[];
      final absent = await repository.getContractorDetails(
        workspaceId: 'workspace-a',
        partyId: 'party-b',
      );
      expect(
        (absent as PartyRepositorySuccess<ContractorDetailsDto?>).value,
        isNull,
      );
    });

    test('detects duplicates and reports the match reasons', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': true,
        'entity': <Object?>[
          _candidateJson(matchEmail: true),
          _candidateJson(id: 'party-b', matchName: true),
        ],
      };

      final result = await repository.detect(
        const PartyDuplicateQuery(
          workspaceId: 'workspace-a',
          email: 'alice@example.test',
        ),
      );

      expect(gateway.rpcFunction, 'detect_party_duplicates');
      expect(gateway.rpcParameters, <String, Object?>{
        'p_workspace_id': 'workspace-a',
        'p_display_name': null,
        'p_email': 'alice@example.test',
        'p_phone': null,
      });
      final candidates =
          (result as PartyRepositorySuccess<List<PartyDuplicateCandidate>>)
              .value;
      expect(candidates.first.matchEmail, isTrue);
      expect(candidates.last.matchName, isTrue);
    });

    test('maps a forbidden duplicate envelope to a forbidden failure', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{'code': 'forbidden', 'message': 'nope'},
      };

      final result = await repository.detect(
        const PartyDuplicateQuery(
          workspaceId: 'workspace-a',
          email: 'alice@example.test',
        ),
      );

      expect(
        (result as PartyRepositoryFailure<List<PartyDuplicateCandidate>>).kind,
        PartyRepositoryFailureKind.forbidden,
      );
    });

    test('hides malformed responses and gateway exception details', () async {
      gateway.rpcResult = <String, Object?>{'entity': _partyJson()};
      final malformed = await repository.create(_createCommand());

      gateway.rpcError = StateError('sensitive Postgrest detail');
      final failedCommand = await repository.create(_createCommand());

      gateway.partiesError = StateError('sensitive Postgrest detail');
      final failedRead = await repository.search(
        const PartyListQuery(workspaceId: 'workspace-a'),
      );

      for (final failure in <PartyRepositoryFailure<dynamic>>[
        malformed as PartyRepositoryFailure<PartyDto>,
        failedCommand as PartyRepositoryFailure<PartyDto>,
        failedRead as PartyRepositoryFailure<PartyPageResult>,
      ]) {
        expect(failure.kind, PartyRepositoryFailureKind.infrastructureFailure);
        expect(failure.message, isNot(contains('sensitive')));
        expect(failure.message, isNot(contains('Postgrest')));
      }
    });
  });
}

PartyCommandContext _context() {
  return const PartyCommandContext(
    workspaceId: 'workspace-a',
    actorId: 'actor-a',
    mutationId: 'mutation-a',
    correlationId: 'correlation-a',
    reason: 'Onboarding',
  );
}

CreatePartyCommand _createCommand() {
  return CreatePartyCommand(
    context: _context(),
    draft: const PartyDraft(
      type: PartyType.person,
      displayName: 'Alice Example',
      email: 'alice@example.test',
      phone: '+49 30 111',
    ),
  );
}

Map<String, dynamic> _partySummaryJson({
  String id = 'party-a',
  String workspaceId = 'workspace-a',
}) {
  return <String, dynamic>{
    'id': id,
    'workspace_id': workspaceId,
    'party_type': 'person',
    'display_name': 'Alice Example',
    'legal_name': null,
    'email': 'alice@example.test',
    'phone': '+49 30 111',
    'version': 1,
    'deleted_at': null,
  };
}

Map<String, dynamic> _partyJson({
  String id = 'party-a',
  String workspaceId = 'workspace-a',
  int version = 1,
  String? legalName,
}) {
  return <String, dynamic>{
    'id': id,
    'workspace_id': workspaceId,
    'party_type': 'person',
    'display_name': 'Alice Example',
    'legal_name': legalName,
    'email': 'alice@example.test',
    'phone': '+49 30 111',
    'notes': null,
    'merged_into_party_id': null,
    'created_at': '2026-07-20T10:00:00Z',
    'updated_at': '2026-07-21T11:00:00Z',
    'created_by': 'actor-a',
    'updated_by': 'actor-a',
    'version': version,
    'deleted_at': null,
  };
}

Map<String, dynamic> _roleJson({
  String id = 'role-a',
  String workspaceId = 'workspace-a',
  String roleType = 'tenant',
  int version = 1,
  String? validUntil,
}) {
  return <String, dynamic>{
    'id': id,
    'workspace_id': workspaceId,
    'party_id': 'party-a',
    'role_type': roleType,
    'valid_from': '2026-07-20T10:00:00Z',
    'valid_until': validUntil,
    'version': version,
  };
}

Map<String, dynamic> _contractorJson() {
  return <String, dynamic>{
    'party_id': 'party-a',
    'workspace_id': 'workspace-a',
    'trade_category': 'Plumbing',
    'hourly_rate': 85.5,
    'service_area': null,
    'rating_price': null,
    'rating_quality': 4.5,
    'rating_speed': null,
    'rating_communication': null,
    'rating_punctuality': null,
    'insurance_cert_expiry': null,
    'is_active': true,
    'version': 1,
  };
}

Map<String, dynamic> _candidateJson({
  String id = 'party-a',
  bool matchEmail = false,
  bool matchPhone = false,
  bool matchName = false,
}) {
  return <String, dynamic>{
    'id': id,
    'workspace_id': 'workspace-a',
    'party_type': 'person',
    'display_name': 'Alice Example',
    'legal_name': null,
    'email': 'alice@example.test',
    'phone': '+49 30 111',
    'version': 1,
    'match_email': matchEmail,
    'match_phone': matchPhone,
    'match_name': matchName,
  };
}

class _FakePartySupabaseGateway implements PartySupabaseGateway {
  @override
  String? currentUserId = 'actor-a';

  List<Map<String, dynamic>> partiesResult = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> getPartyResult = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> rolesResult = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> contractorResult = <Map<String, dynamic>>[];
  Object? rpcResult;
  Object? partiesError;
  Object? rpcError;

  String? partiesWorkspaceId;
  String? partiesRoleType;
  int? partiesLimit;
  bool? partiesIncludeMerged;
  int rpcCalls = 0;
  String? rpcFunction;
  Map<String, Object?>? rpcParameters;

  @override
  Future<List<Map<String, dynamic>>> listParties({
    required String workspaceId,
    required String? afterId,
    required int limit,
    required bool includeMerged,
    required String? roleType,
  }) async {
    if (partiesError != null) {
      throw partiesError!;
    }
    partiesWorkspaceId = workspaceId;
    partiesRoleType = roleType;
    partiesLimit = limit;
    partiesIncludeMerged = includeMerged;
    return partiesResult;
  }

  @override
  Future<List<Map<String, dynamic>>> getParty({
    required String workspaceId,
    required String partyId,
  }) async {
    return getPartyResult;
  }

  @override
  Future<List<Map<String, dynamic>>> listRoles({
    required String workspaceId,
    required String partyId,
  }) async {
    return rolesResult;
  }

  @override
  Future<List<Map<String, dynamic>>> getContractorDetails({
    required String workspaceId,
    required String partyId,
  }) async {
    return contractorResult;
  }

  @override
  Future<Object?> callRpc(String function, Map<String, Object?> parameters) async {
    rpcCalls++;
    rpcFunction = function;
    rpcParameters = parameters;
    if (rpcError != null) {
      throw rpcError!;
    }
    return rpcResult;
  }
}
