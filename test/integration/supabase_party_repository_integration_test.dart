import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/contacts_parties/application/party_repository.dart';
import 'package:neximmo_app/features/contacts_parties/domain/party_dto.dart';
import 'package:neximmo_app/features/contacts_parties/data/supabase_party_repository_adapter.dart';

import 'support/supabase_mfa_test_helper.dart';

void main() {
  const url = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const workspaceId = 'd1000000-0000-0000-0000-000000000001';
  const adminId = 'da000000-0000-0000-0000-000000000001';

  var mutationCounter = 0;
  PartyCommandContext context(String actorId, {String? reason}) {
    mutationCounter++;
    final suffix = mutationCounter.toString().padLeft(2, '0');
    return PartyCommandContext(
      workspaceId: workspaceId,
      actorId: actorId,
      mutationId: 'd5000000-0000-0000-0000-0000000000$suffix',
      correlationId: 'd6000000-0000-0000-0000-0000000000$suffix',
      reason: reason,
    );
  }

  test(
    'real client drives the party lifecycle end to end',
    () async {
      expect(url, isNotEmpty, reason: 'SUPABASE_URL dart define is required.');
      expect(
        publishableKey,
        isNotEmpty,
        reason: 'SUPABASE_PUBLISHABLE_KEY dart define is required.',
      );
      expect(
        Uri.tryParse(url)?.host,
        anyOf('127.0.0.1', 'localhost', '::1'),
        reason: 'This integration test is restricted to local Supabase.',
      );

      final adminClient = createSupabaseTestClient(url, publishableKey);
      final viewerClient = createSupabaseTestClient(url, publishableKey);
      try {
        await adminClient.auth.signInWithPassword(
          email: 'p2-d02-admin@example.test',
          password: 'NexImmo-Test-2026!',
        );
        final adminRepo = SupabasePartyRepositoryAdapter(client: adminClient);

        // Create the canonical contractor party (no AAL2 gate for parties).
        final created =
            (await adminRepo.create(
                  CreatePartyCommand(
                    context: context(adminId, reason: 'integration create'),
                    draft: const PartyDraft(
                      type: PartyType.organization,
                      displayName: 'Acme Plumbing',
                      email: 'acme@example.test',
                      phone: '+49 30 123',
                    ),
                  ),
                ))
                as PartyRepositorySuccess<PartyDto>;
        final acme = created.value;
        expect(acme.version, 1);
        expect(acme.type, PartyType.organization);

        // Assign the contractor role, writing the satellite.
        final role =
            (await adminRepo.assign(
                  AssignPartyRoleCommand(
                    context: context(adminId),
                    partyId: acme.id,
                    roleType: PartyRoleType.contractor,
                    contractorDetails: const ContractorDetailsInput(
                      tradeCategory: 'Plumbing',
                      hourlyRate: 85.5,
                      ratingQuality: 4.5,
                    ),
                  ),
                ))
                as PartyRepositorySuccess<PartyRoleDto>;
        expect(role.value.roleType, PartyRoleType.contractor);
        expect(role.value.isOpen, isTrue);

        final details =
            (await adminRepo.getContractorDetails(
                  workspaceId: workspaceId,
                  partyId: acme.id,
                ))
                as PartyRepositorySuccess<ContractorDetailsDto?>;
        expect(details.value?.tradeCategory, 'Plumbing');
        expect(details.value?.hourlyRate, 85.5);

        // A second party in a different role.
        final tenant =
            (await adminRepo.create(
                  CreatePartyCommand(
                    context: context(adminId),
                    draft: const PartyDraft(
                      type: PartyType.person,
                      displayName: 'Tina Tenant',
                      email: 'tina@example.test',
                    ),
                  ),
                ))
                as PartyRepositorySuccess<PartyDto>;
        await adminRepo.assign(
          AssignPartyRoleCommand(
            context: context(adminId),
            partyId: tenant.value.id,
            roleType: PartyRoleType.tenant,
          ),
        );

        // Role-scoped read: only the contractor party surfaces.
        final contractors =
            (await adminRepo.search(
                  const PartyListQuery(
                    workspaceId: workspaceId,
                    roleType: PartyRoleType.contractor,
                  ),
                ))
                as PartyRepositorySuccess<PartyPageResult>;
        expect(contractors.value.items.map((party) => party.id), <String>[
          acme.id,
        ]);

        // Duplicate detection matches the contractor on its normalized email.
        final duplicatesBefore =
            (await adminRepo.detect(
                  const PartyDuplicateQuery(
                    workspaceId: workspaceId,
                    email: 'ACME@example.test',
                  ),
                ))
                as PartyRepositorySuccess<List<PartyDuplicateCandidate>>;
        expect(duplicatesBefore.value, hasLength(1));
        expect(duplicatesBefore.value.single.matchEmail, isTrue);

        // Create a duplicate of the contractor and merge it in.
        final duplicate =
            (await adminRepo.create(
                  CreatePartyCommand(
                    context: context(adminId),
                    draft: const PartyDraft(
                      type: PartyType.organization,
                      displayName: 'Acme Plumbing GmbH',
                      email: 'acme@example.test',
                    ),
                  ),
                ))
                as PartyRepositorySuccess<PartyDto>;

        final merged =
            (await adminRepo.merge(
                  MergePartiesCommand(
                    context: context(adminId, reason: 'integration merge'),
                    targetPartyId: acme.id,
                    sourcePartyId: duplicate.value.id,
                    expectedTargetVersion: acme.version,
                    expectedSourceVersion: duplicate.value.version,
                  ),
                ))
                as PartyRepositorySuccess<PartyDto>;
        expect(merged.value.version, greaterThan(acme.version));

        // The merged source is tombstoned and points at the survivor.
        final tombstoned =
            (await adminRepo.getById(
                  workspaceId: workspaceId,
                  partyId: duplicate.value.id,
                ))
                as PartyRepositorySuccess<PartyDto>;
        expect(tombstoned.value.isMerged, isTrue);
        expect(tombstoned.value.mergedIntoPartyId, acme.id);

        // The tombstoned duplicate no longer surfaces as a candidate.
        final duplicatesAfter =
            (await adminRepo.detect(
                  const PartyDuplicateQuery(
                    workspaceId: workspaceId,
                    email: 'acme@example.test',
                  ),
                ))
                as PartyRepositorySuccess<List<PartyDuplicateCandidate>>;
        expect(duplicatesAfter.value, hasLength(1));

        // A stale update returns a structured conflict carrying the current
        // party.
        final stale = await adminRepo.update(
          UpdatePartyCommand(
            context: context(adminId),
            partyId: acme.id,
            expectedVersion: acme.version,
            changes: const PartyUpdateDto(
              type: PartyType.organization,
              displayName: 'Acme Plumbing',
              email: 'acme@example.test',
            ),
          ),
        );
        final conflict = stale as PartyRepositoryFailure<PartyDto>;
        expect(conflict.kind, PartyRepositoryFailureKind.versionConflict);
        expect(conflict.versionConflict?.currentParty?.version, merged.value.version);

        final updated =
            (await adminRepo.update(
                  UpdatePartyCommand(
                    context: context(adminId),
                    partyId: acme.id,
                    expectedVersion: merged.value.version,
                    changes: const PartyUpdateDto(
                      type: PartyType.organization,
                      displayName: 'Acme Plumbing Berlin',
                      email: 'acme@example.test',
                    ),
                  ),
                ))
                as PartyRepositorySuccess<PartyDto>;
        expect(updated.value.displayName, 'Acme Plumbing Berlin');

        // The viewer holds workspace.read only: parties are invisible (RLS)
        // and the duplicate RPC is forbidden, distinctly from an empty result.
        await viewerClient.auth.signInWithPassword(
          email: 'p2-d02-viewer@example.test',
          password: 'NexImmo-Test-2026!',
        );
        final viewerRepo = SupabasePartyRepositoryAdapter(client: viewerClient);

        final viewerSearch =
            (await viewerRepo.search(
                  const PartyListQuery(workspaceId: workspaceId),
                ))
                as PartyRepositorySuccess<PartyPageResult>;
        expect(viewerSearch.value.items, isEmpty);

        final viewerDetect = await viewerRepo.detect(
          const PartyDuplicateQuery(
            workspaceId: workspaceId,
            email: 'acme@example.test',
          ),
        );
        expect(
          (viewerDetect
                  as PartyRepositoryFailure<List<PartyDuplicateCandidate>>)
              .kind,
          PartyRepositoryFailureKind.forbidden,
        );
      } finally {
        await viewerClient.auth.signOut();
        await adminClient.auth.signOut();
      }
    },
    skip: url.isEmpty || publishableKey.isEmpty
        ? 'Requires the local Supabase integration harness.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
