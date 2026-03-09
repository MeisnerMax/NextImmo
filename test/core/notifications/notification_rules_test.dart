import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/core/models/portfolio.dart';
import 'package:neximmo_app/core/models/settings.dart';
import 'package:neximmo_app/core/notifications/notification_rules.dart';

void main() {
  test('creates threshold alerts for vacancy and noi drop', () {
    const rules = NotificationRules();
    final settings = AppSettingsRecord(
      notificationVacancyThreshold: 0.1,
      notificationNoiDropThreshold: 0.15,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    final snapshots = <PropertyKpiSnapshotRecord>[
      const PropertyKpiSnapshotRecord(
        id: 's1',
        propertyId: 'p1',
        scenarioId: null,
        periodDate: '2025-01-01',
        noi: 10000,
        occupancy: 0.95,
        capex: null,
        valuation: null,
        source: 'manual',
        createdAt: 1,
      ),
      const PropertyKpiSnapshotRecord(
        id: 's2',
        propertyId: 'p1',
        scenarioId: null,
        periodDate: '2025-02-01',
        noi: 7000,
        occupancy: 0.8,
        capex: null,
        valuation: null,
        source: 'manual',
        createdAt: 2,
      ),
    ];

    final notifications = rules.evaluateFromSnapshots(
      snapshots: snapshots,
      settings: settings,
    );

    expect(notifications.length, 2);
    expect(notifications.any((n) => n.message.contains('Vacancy')), isTrue);
    expect(notifications.any((n) => n.message.contains('NOI dropped')), isTrue);
  });
}
