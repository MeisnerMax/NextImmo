/// Shared presentation helpers for the three documents_compliance surfaces
/// (SCR-020 / SCR-051 / SCR-052).
///
/// Deliberately tiny and format-only: no domain logic lives here, so the three
/// screens cannot drift on how a date or a file size reads.
library;

/// Day-precision German date. Documents carry validity and due dates, never
/// times that a user acts on, so the time part is intentionally dropped.
String formatDocumentDate(DateTime? value) {
  if (value == null) {
    return '—';
  }
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day.$month.${local.year}';
}

/// Binary units, matching what a desktop file manager shows for the same file.
String formatDocumentByteSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  const units = <String>['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final rendered =
      value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '$rendered ${units[unitIndex]}';
}

/// Short hash preview. The full 64-character digest is never useful on screen,
/// but the head is enough to compare two versions by eye.
String formatContentHashPreview(String contentHash) {
  final normalized = contentHash.trim();
  if (normalized.length <= 12) {
    return normalized;
  }
  return '${normalized.substring(0, 12)}…';
}
