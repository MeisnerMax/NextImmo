/// The ticket category vocabulary (MAINTENANCE-CATEGORY-01,
/// `screens/maintenance_tickets.md` §7.2).
///
/// `maintenance_tickets.category` is free text server-side and stays that way.
/// A workspace that has been categorising its tickets its own way for a year
/// would have that vocabulary silently rejected by an enum migration, and the
/// filter exists precisely to make sense of what is already there — the local
/// demo data alone carries `electrical`, `elevator`, `hvac` and `water`, none
/// of which appear below.
///
/// So this list is a **suggestion**, not a schema. Everywhere it is offered,
/// the values a workspace actually uses are offered beside it, and an
/// unfamiliar stored value is shown verbatim rather than mapped to
/// "Sonstiges" — which would claim a classification nobody made.
library;

/// The curated seven, in the order the spec names them.
///
/// Deliberately absent from the legacy list: `renovation` and `modernization`,
/// which are CapEx measures rather than tickets, and `warranty`, a legacy
/// shadow value no dropdown could ever produce. `inspection` is new, as the
/// anchor for recurring checks.
const List<String> curatedMaintenanceCategories = <String>[
  'damage',
  'defect',
  'repair',
  'maintenance',
  'inspection',
  'minor_repair',
  'general',
];

/// The German label for a curated key, or the key itself for anything else.
///
/// Returning the raw key is the point: a value this build does not know is
/// still a real category somebody chose, and inventing a label for it would
/// hide that.
String maintenanceCategoryLabel(String category) => switch (category) {
  'damage' => 'Schaden',
  'defect' => 'Mangel',
  'repair' => 'Reparatur',
  'maintenance' => 'Wartung',
  'inspection' => 'Prüfung/Begehung',
  'minor_repair' => 'Kleinreparatur',
  'general' => 'Allgemein',
  _ => category,
};

/// True when this build has no label for the value — so a caller can mark it
/// as the workspace's own rather than passing it off as vocabulary.
bool isCuratedMaintenanceCategory(String category) =>
    curatedMaintenanceCategories.contains(category);

/// The curated list plus whatever a workspace actually uses, deduplicated and
/// in a stable order: curated first, then the workspace's own, alphabetically.
///
/// Curated first because it is what a new workspace should reach for; the
/// workspace's own after, because a list that reordered itself as tickets were
/// created would move the option under the reader's cursor.
List<String> maintenanceCategoryOptions(Iterable<String> inUse) {
  final own = inUse
      .where((category) => !isCuratedMaintenanceCategory(category))
      .toSet()
      .toList(growable: false)
    ..sort();
  return <String>[...curatedMaintenanceCategories, ...own];
}
