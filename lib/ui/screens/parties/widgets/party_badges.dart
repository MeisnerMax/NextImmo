import 'package:flutter/material.dart';

import '../../../../features/contacts_parties/domain/party_dto.dart';
import '../../../components/nx_status_badge.dart';

/// The single status vocabulary for the party domain (`03_design_system.md`:
/// one badge mapping per status enum, never a per-screen chip). Every party
/// surface — this directory today, the tenant/contractor role views in later
/// waves — renders `PartyType`, `PartyRoleType` and the merge tombstone through
/// these helpers.

String partyTypeLabel(PartyType type) {
  return switch (type) {
    PartyType.person => 'Person',
    PartyType.organization => 'Organisation',
  };
}

String partyRoleLabel(PartyRoleType role) {
  return switch (role) {
    PartyRoleType.tenant => 'Mieter',
    PartyRoleType.contractor => 'Dienstleister',
    PartyRoleType.buyer => 'Käufer',
    PartyRoleType.bank => 'Bank',
    PartyRoleType.company => 'Firma',
  };
}

class PartyTypeBadge extends StatelessWidget {
  const PartyTypeBadge({super.key, required this.type});

  final PartyType type;

  @override
  Widget build(BuildContext context) {
    return NxStatusBadge(
      label: partyTypeLabel(type),
      kind: switch (type) {
        PartyType.person => NxBadgeKind.info,
        PartyType.organization => NxBadgeKind.neutral,
      },
    );
  }
}

/// A functional role. Roles carry no severity, so they stay neutral and are
/// distinguished by their label — never by colour alone.
class PartyRoleBadge extends StatelessWidget {
  const PartyRoleBadge({super.key, required this.role, this.closed = false});

  final PartyRoleType role;

  /// A role with a `validUntil` in the past is closed rather than open.
  final bool closed;

  @override
  Widget build(BuildContext context) {
    return NxStatusBadge(
      label: closed ? '${partyRoleLabel(role)} (beendet)' : partyRoleLabel(role),
      kind: NxBadgeKind.neutral,
    );
  }
}

/// Lifecycle of the identity itself: live, or folded into another party. There
/// is no delete path — merge/tombstone is the only terminal state.
class PartyLifecycleBadge extends StatelessWidget {
  const PartyLifecycleBadge({super.key, required this.merged});

  final bool merged;

  @override
  Widget build(BuildContext context) {
    return NxStatusBadge(
      label: merged ? 'Zusammengeführt' : 'Aktiv',
      kind: merged ? NxBadgeKind.warning : NxBadgeKind.success,
    );
  }
}
