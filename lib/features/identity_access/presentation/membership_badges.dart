import '../../../ui/components/nx_status_badge.dart';
import '../application/membership_admin_repository.dart';

/// German status labels and badge kinds for [MembershipStatus], kept beside
/// the domain enum's consumers per Foundation §12 (the badge text, not the
/// color, carries the meaning).
String membershipStatusLabel(MembershipStatus status) {
  return switch (status) {
    MembershipStatus.invited => 'Eingeladen',
    MembershipStatus.active => 'Aktiv',
    MembershipStatus.suspended => 'Suspendiert',
    MembershipStatus.revoked => 'Entzogen',
  };
}

NxBadgeKind membershipStatusBadgeKind(MembershipStatus status) {
  return switch (status) {
    MembershipStatus.invited => NxBadgeKind.info,
    MembershipStatus.active => NxBadgeKind.success,
    MembershipStatus.suspended => NxBadgeKind.warning,
    MembershipStatus.revoked => NxBadgeKind.error,
  };
}
