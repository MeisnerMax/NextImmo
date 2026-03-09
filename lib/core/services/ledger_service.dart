class LedgerService {
  const LedgerService();

  String derivePeriodKey(int postedAt) {
    final dt = DateTime.fromMillisecondsSinceEpoch(postedAt);
    final month = dt.month.toString().padLeft(2, '0');
    return '${dt.year}-$month';
  }

  double computeSignedAmount({
    required String direction,
    required double amount,
  }) {
    final normalized = direction.trim().toLowerCase();
    if (amount < 0) {
      throw StateError('Ledger amount must be positive.');
    }
    switch (normalized) {
      case 'in':
        return amount;
      case 'out':
        return -amount;
      default:
        throw StateError('Unsupported direction: $direction');
    }
  }
}
