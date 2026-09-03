import 'package:flutter/material.dart';

/// German presentation for the membership audit actions the server actually
/// writes (`private.finish_membership_mutation` call sites in the P2-D01
/// lifecycle migration). An action outside this map is a real stored event
/// that this build does not know — callers render it neutrally instead of
/// guessing a meaning.
String? membershipAuditActionLabel(String action) {
  return switch (action) {
    'membership.invite' => 'Mitglied eingeladen',
    'membership_invitation.invite' => 'Einladung angelegt',
    'membership.accept' => 'Einladung angenommen',
    'membership.role_change' => 'Rolle geändert',
    'membership.suspend' => 'Mitglied suspendiert',
    'membership.reactivate' => 'Mitglied reaktiviert',
    'membership.revoke' => 'Zugriff entzogen',
    'membership_invitation.revoke' => 'Einladung widerrufen',
    _ => null,
  };
}

/// Neutral fallback title for a stored-but-unknown membership event type.
const membershipAuditUnknownLabel = 'Mitgliedschafts-Ereignis';

IconData membershipAuditActionIcon(String action) {
  return switch (action) {
    'membership.invite' ||
    'membership_invitation.invite' => Icons.person_add_alt_outlined,
    'membership.accept' => Icons.mark_email_read_outlined,
    'membership.role_change' => Icons.manage_accounts_outlined,
    'membership.suspend' => Icons.pause_circle_outline,
    'membership.reactivate' => Icons.play_circle_outline,
    'membership.revoke' => Icons.person_off_outlined,
    'membership_invitation.revoke' => Icons.cancel_schedule_send_outlined,
    _ => Icons.history_outlined,
  };
}
