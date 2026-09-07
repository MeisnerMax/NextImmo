/// Supplier and utility contracts (`SUPPLIER-CONTRACTS-01`, P-3).
///
/// Lives beside the party DTOs because a supplier is a party: the contract
/// points at `public.parties`, not at a supplier table of its own. A company
/// that is both a contractor on tickets and the counterparty of a framework
/// agreement is one row with one name.
///
/// **The deadlines are the server's, and there is no setter for them.** They
/// are computed against the date the read was asked for, never stored — with
/// no scheduler anywhere in this product, a stored deadline goes stale the
/// moment somebody corrects an end date and nothing recomputes it. Every
/// derived field below therefore arrives on the answer and is `final`.
library;

enum SupplierContractStatus {
  /// Entered, not yet in force. Promoting it is an explicit, audited update.
  draft,
  active,

  /// Terminal, reachable only through its own command and only with a reason.
  ended,

  /// From a newer server.
  unknown,
}

SupplierContractStatus supplierContractStatusFromKey(String key) =>
    switch (key) {
      'draft' => SupplierContractStatus.draft,
      'active' => SupplierContractStatus.active,
      'ended' => SupplierContractStatus.ended,
      _ => SupplierContractStatus.unknown,
    };

String supplierContractStatusKey(SupplierContractStatus status) =>
    switch (status) {
      SupplierContractStatus.draft => 'draft',
      SupplierContractStatus.active => 'active',
      SupplierContractStatus.ended => 'ended',
      // Never sent: the command layer refuses it rather than guessing what an
      // unfamiliar status meant.
      SupplierContractStatus.unknown => 'unknown',
    };

class SupplierContractDto {
  const SupplierContractDto({
    required this.id,
    required this.workspaceId,
    required this.partyId,
    required this.title,
    required this.contractType,
    required this.status,
    required this.startDate,
    required this.autoRenew,
    required this.version,
    this.partyName,
    this.propertyId,
    this.scopeNote,
    this.endDate,
    this.noticePeriodDays,
    this.renewalTermMonths,
    this.annualValue,
    this.currencyCode,
    this.endedAt,
    this.endedReason,
    this.rawStatusKey,
    this.isEffective = false,
    this.noticeDeadline,
    this.daysToNotice,
    this.noticeDeadlinePassed = false,
    this.noticeWindowOpen = false,
    this.endsOn,
    this.renewsOn,
  });

  final String id;
  final String workspaceId;
  final String partyId;

  /// Joined in by the read. A party id alone is not a counterparty anybody can
  /// recognise on a list.
  final String? partyName;

  /// Null means the whole portfolio, which is what a framework contract
  /// usually is — not missing data.
  final String? propertyId;

  final String title;
  final String contractType;
  final String? scopeNote;
  final SupplierContractStatus status;
  final String? rawStatusKey;

  final DateTime startDate;

  /// Null is open-ended.
  final DateTime? endDate;

  /// Null means no notice period was agreed — a different statement from "the
  /// notice period is zero days", and the reason [noticeDeadline] can be null
  /// while [endDate] is not.
  final int? noticePeriodDays;

  final bool autoRenew;
  final int? renewalTermMonths;

  final double? annualValue;
  final String? currencyCode;

  final DateTime? endedAt;
  final String? endedReason;

  final int version;

  // --- Derived by the server against the date the read asked about ---

  /// Whether the contract was running on that date. Status decides first,
  /// dates second: a draft is not in force, and neither is one that ended.
  final bool isEffective;

  /// The last day notice can be given. Null when there is no end date or no
  /// agreed notice period.
  final DateTime? noticeDeadline;

  final int? daysToNotice;

  /// It is too late to stop this contract running on. The single most useful
  /// fact on the surface — and one a stored column would have got wrong the
  /// moment an end date was corrected.
  final bool noticeDeadlinePassed;

  final bool noticeWindowOpen;

  final DateTime? endsOn;

  /// The *next* renewal date, when the contract renews itself. Deliberately
  /// not a chain: an auto-renewing contract has infinitely many, and
  /// projecting them is a calendar that would want a scheduler.
  final DateTime? renewsOn;

  bool get isEnded => status == SupplierContractStatus.ended;

  /// Whether the contract covers the whole portfolio rather than one asset.
  bool get isPortfolioWide => propertyId == null;
}

/// One answer, with the date its deadlines were computed against.
class SupplierContractSetDto {
  const SupplierContractSetDto({
    required this.asOfDate,
    required this.contracts,
  });

  final DateTime asOfDate;

  /// Soonest end first, open-ended last — the thing about to run out is at the
  /// top.
  final List<SupplierContractDto> contracts;

  /// Contracts whose notice deadline has passed while they are still running.
  /// Computed here only as a filter over what the server already decided; the
  /// judgement itself is never re-made on this side.
  List<SupplierContractDto> get missedNotice => contracts
      .where((SupplierContractDto c) => c.noticeDeadlinePassed)
      .toList(growable: false);
}
