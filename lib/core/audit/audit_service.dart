import '../models/audit_log.dart';

class AuditService {
  const AuditService();

  List<AuditDiffItem> buildDiff(
    Map<String, Object?> beforeMap,
    Map<String, Object?> afterMap,
  ) {
    final before = _flatten(beforeMap);
    final after = _flatten(afterMap);
    final keys = <String>{...before.keys, ...after.keys}.toList()..sort();
    final result = <AuditDiffItem>[];
    for (final key in keys) {
      final oldValue = before[key];
      final newValue = after[key];
      if (_equals(oldValue, newValue)) {
        continue;
      }
      result.add(
        AuditDiffItem(fieldKey: key, before: oldValue, after: newValue),
      );
    }
    return result;
  }

  Map<String, Object?> _flatten(
    Map<String, Object?> source, {
    String prefix = '',
  }) {
    final out = <String, Object?>{};
    final keys = source.keys.toList()..sort();
    for (final key in keys) {
      final value = source[key];
      final path = prefix.isEmpty ? key : '$prefix.$key';
      if (value is Map<String, Object?>) {
        out.addAll(_flatten(value, prefix: path));
        continue;
      }
      if (value is List) {
        for (var i = 0; i < value.length; i++) {
          final item = value[i];
          final itemPath = '$path[$i]';
          if (item is Map<String, Object?>) {
            out.addAll(_flatten(item, prefix: itemPath));
          } else {
            out[itemPath] = item;
          }
        }
        continue;
      }
      out[path] = value;
    }
    return out;
  }

  bool _equals(Object? x, Object? y) {
    if (x == null && y == null) {
      return true;
    }
    if (x is num && y is num) {
      return x.toDouble() == y.toDouble();
    }
    return x == y;
  }
}
