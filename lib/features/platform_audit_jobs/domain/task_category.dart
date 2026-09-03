/// The typed client vocabulary over the free-text `tasks.category` column
/// (TASKS-NOTIFICATIONS shared contract §7.5). The template spelling won over
/// the two other legacy vocabularies because the ten standard templates carry
/// it and a migration would otherwise have to rewrite content.
///
/// Unknown server values are **displayed and preserved, never offered**:
/// [tryFromWire] returns null for them so a caller keeps showing (and keeps
/// writing back) the raw string, while [fromWire]'s [TaskCategory.general]
/// fallback is only for places that must pick a concrete member, such as a
/// create dialog's default. Writing `fromWire(raw).wireName` back over an
/// unknown value would silently rewrite it to `general` — exactly the
/// edit-cycle loss the shared test plan (§17) guards against.
library;

enum TaskCategory {
  general('general'),
  letting('letting'),
  maintenance('maintenance'),
  renovation('renovation'),
  finance('finance'),
  document('document'),
  compliance('compliance'),
  valuation('valuation');

  const TaskCategory(this.wireName);

  final String wireName;

  /// Exact wire match, null for anything the vocabulary does not know.
  static TaskCategory? tryFromWire(String? value) {
    for (final category in TaskCategory.values) {
      if (category.wireName == value) {
        return category;
      }
    }
    return null;
  }

  /// [tryFromWire] with the §7.5 fallback for callers that need a concrete
  /// member. Never use this to normalize a value that goes back to the server.
  static TaskCategory fromWire(String? value) =>
      tryFromWire(value) ?? TaskCategory.general;
}
