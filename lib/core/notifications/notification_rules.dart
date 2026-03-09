import '../models/portfolio.dart';
import '../models/settings.dart';

class NotificationSuggestion {
  const NotificationSuggestion({
    required this.entityType,
    required this.entityId,
    required this.kind,
    required this.message,
    required this.dueAt,
  });

  final String entityType;
  final String entityId;
  final String kind;
  final String message;
  final int? dueAt;
}

class NotificationRules {
  const NotificationRules();

  List<NotificationSuggestion> evaluateFromSnapshots({
    required List<PropertyKpiSnapshotRecord> snapshots,
    required AppSettingsRecord settings,
  }) {
    final byProperty = <String, List<PropertyKpiSnapshotRecord>>{};
    for (final snapshot in snapshots) {
      byProperty.putIfAbsent(
        snapshot.propertyId,
        () => <PropertyKpiSnapshotRecord>[],
      );
      byProperty[snapshot.propertyId]!.add(snapshot);
    }

    final suggestions = <NotificationSuggestion>[];
    final vacancyThreshold = settings.notificationVacancyThreshold;
    final noiDropThreshold = settings.notificationNoiDropThreshold;
    if (vacancyThreshold == null && noiDropThreshold == null) {
      return suggestions;
    }

    for (final entry in byProperty.entries) {
      final list =
          entry.value..sort((a, b) => a.periodDate.compareTo(b.periodDate));
      final latest = list.isNotEmpty ? list.last : null;
      final previous = list.length >= 2 ? list[list.length - 2] : null;
      if (latest == null) {
        continue;
      }

      if (vacancyThreshold != null && latest.occupancy != null) {
        final vacancy = 1 - latest.occupancy!;
        if (vacancy > vacancyThreshold) {
          suggestions.add(
            NotificationSuggestion(
              entityType: 'property',
              entityId: latest.propertyId,
              kind: 'threshold',
              message:
                  'Vacancy ${(vacancy * 100).toStringAsFixed(1)}% is above threshold ${(vacancyThreshold * 100).toStringAsFixed(1)}%.',
              dueAt: null,
            ),
          );
        }
      }

      if (noiDropThreshold != null &&
          latest.noi != null &&
          previous?.noi != null &&
          previous!.noi! != 0) {
        final change = (latest.noi! - previous.noi!) / previous.noi!;
        if (change < -noiDropThreshold) {
          suggestions.add(
            NotificationSuggestion(
              entityType: 'property',
              entityId: latest.propertyId,
              kind: 'threshold',
              message:
                  'NOI dropped ${(change.abs() * 100).toStringAsFixed(1)}% compared to previous snapshot.',
              dueAt: null,
            ),
          );
        }
      }
    }

    return suggestions;
  }
}
