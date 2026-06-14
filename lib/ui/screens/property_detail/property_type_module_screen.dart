import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/property_modules.dart';
import '../../components/nx_card.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

class PropertyTypeModuleScreen extends ConsumerWidget {
  const PropertyTypeModuleScreen({
    super.key,
    required this.propertyId,
    required this.module,
  });

  final String propertyId;
  final PropertyTypeModule module;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(propertyModulesRepositoryProvider);
    final future = switch (module) {
      PropertyTypeModule.saleData => repo.getSaleDetails(propertyId),
      PropertyTypeModule.buyerInterests ||
      PropertyTypeModule.viewings ||
      PropertyTypeModule.saleOffers => repo.listBuyerInterests(propertyId),
      PropertyTypeModule.guests => repo.listContactsForProperty(
          propertyId: propertyId,
          role: 'guest',
        ),
      PropertyTypeModule.reservations => repo.listReservations(propertyId),
      PropertyTypeModule.parkingStorage ||
      PropertyTypeModule.unitSaleStatus => repo.listUnitSaleDetails(propertyId),
      PropertyTypeModule.housekeeping ||
      PropertyTypeModule.hotelRevenue => repo.listReservations(propertyId),
    };

    return FutureBuilder<Object?>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Fehler: ${snapshot.error}'));
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.page),
          child: _content(context, snapshot.data),
        );
      },
    );
  }

  Widget _content(BuildContext context, Object? data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.component),
        NxCard(child: _body(context, data)),
      ],
    );
  }

  Widget _body(BuildContext context, Object? data) {
    if (module == PropertyTypeModule.saleData) {
      final details = data as PropertySaleDetailsRecord?;
      if (details == null) {
        return _empty(_emptyText);
      }
      return _keyValues([
        _InfoLine('Status', details.saleStatus),
        _InfoLine('Angebotspreis', _money(details.askingPrice)),
        _InfoLine('Mindestpreis', _money(details.minimumPrice)),
        _InfoLine('Inseriert', _date(details.listedAt)),
        _InfoLine('Reserviert', _date(details.reservedAt)),
        _InfoLine('Verkauft', _date(details.soldAt)),
        _InfoLine('Notartermin', _date(details.notaryDate)),
        _InfoLine('Notizen', details.notes ?? '-'),
      ]);
    }

    if (data is List<BuyerInterestRecord>) {
      final rows = _filteredBuyerInterests(data);
      if (rows.isEmpty) {
        return _empty(_emptyText);
      }
      return _list(
        rows.map((row) {
          final amount = row.offerAmount ?? row.budgetAmount;
          return _ListLine(
            title: row.interestStatus,
            subtitle: [
              if (row.unitId != null) 'Einheit ${row.unitId}',
              if (amount != null) _money(amount),
              if (row.viewingAt != null) 'Besichtigung ${_date(row.viewingAt)}',
            ].join(' · '),
          );
        }).toList(growable: false),
      );
    }

    if (data is List<ContactRecord>) {
      if (data.isEmpty) {
        return _empty(_emptyText);
      }
      return _list(
        data.map((row) {
          return _ListLine(
            title: row.displayName,
            subtitle: [
              if (row.email != null) row.email!,
              if (row.phone != null) row.phone!,
            ].join(' · '),
          );
        }).toList(growable: false),
      );
    }

    if (data is List<ReservationRecord>) {
      if (data.isEmpty) {
        return _empty(_emptyText);
      }
      return _list(
        data.map((row) {
          return _ListLine(
            title: row.reservationStatus,
            subtitle:
                '${_date(row.checkIn)} bis ${_date(row.checkOut)} · ${_money(row.totalAmount)}',
          );
        }).toList(growable: false),
      );
    }

    if (data is List<UnitSaleDetailsRecord>) {
      if (data.isEmpty) {
        return _empty(_emptyText);
      }
      return _list(
        data.map((row) {
          return _ListLine(
            title: 'Einheit ${row.unitId}',
            subtitle: '${row.saleStatus} · ${_money(row.askingPrice)}',
          );
        }).toList(growable: false),
      );
    }

    return _empty(_emptyText);
  }

  List<BuyerInterestRecord> _filteredBuyerInterests(
    List<BuyerInterestRecord> rows,
  ) {
    return rows.where((row) {
      return switch (module) {
        PropertyTypeModule.viewings => row.viewingAt != null,
        PropertyTypeModule.saleOffers => row.offerAmount != null,
        _ => true,
      };
    }).toList(growable: false);
  }

  Widget _empty(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text)),
      ],
    );
  }

  Widget _keyValues(List<_InfoLine> lines) {
    return Wrap(
      spacing: AppSpacing.component,
      runSpacing: AppSpacing.component,
      children: [
        for (final line in lines)
          SizedBox(
            width: 220,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(line.value),
              ],
            ),
          ),
      ],
    );
  }

  Widget _list(List<_ListLine> lines) {
    return Column(
      children: [
        for (final line in lines)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(line.title),
            subtitle: line.subtitle.trim().isEmpty ? null : Text(line.subtitle),
          ),
      ],
    );
  }

  String get _title {
    return switch (module) {
      PropertyTypeModule.saleData => 'Verkaufsdaten',
      PropertyTypeModule.buyerInterests => 'Käufer/Interessenten',
      PropertyTypeModule.viewings => 'Besichtigungen',
      PropertyTypeModule.saleOffers => 'Angebote',
      PropertyTypeModule.reservations => 'Reservierungen',
      PropertyTypeModule.guests => 'Gäste',
      PropertyTypeModule.housekeeping => 'Housekeeping',
      PropertyTypeModule.hotelRevenue => 'Umsatz/Reporting',
      PropertyTypeModule.parkingStorage => 'Stellplätze/Keller',
      PropertyTypeModule.unitSaleStatus => 'Kaufpreise und Verkaufsstatus',
    };
  }

  String get _emptyText {
    return switch (module) {
      PropertyTypeModule.saleData =>
        'Für dieses Verkaufsobjekt sind noch keine Verkaufsdaten hinterlegt.',
      PropertyTypeModule.buyerInterests =>
        'Für dieses Verkaufsobjekt sind noch keine Interessenten hinterlegt.',
      PropertyTypeModule.viewings =>
        'Für dieses Verkaufsobjekt sind noch keine Besichtigungen hinterlegt.',
      PropertyTypeModule.saleOffers =>
        'Für dieses Verkaufsobjekt sind noch keine Angebote hinterlegt.',
      PropertyTypeModule.reservations =>
        'Für dieses Hotel sind noch keine Reservierungen vorhanden.',
      PropertyTypeModule.guests =>
        'Für dieses Hotel sind noch keine Gäste hinterlegt.',
      PropertyTypeModule.housekeeping =>
        'Für dieses Hotel sind noch keine Housekeeping-Daten vorhanden.',
      PropertyTypeModule.hotelRevenue =>
        'Für dieses Hotel sind noch keine Umsatzdaten vorhanden.',
      PropertyTypeModule.parkingStorage =>
        'Für dieses Objekt sind noch keine Stellplätze oder Kellerabteile gepflegt.',
      PropertyTypeModule.unitSaleStatus =>
        'Für diese Einheit ist noch kein Verkaufsstatus gepflegt.',
    };
  }

  String _money(double? value) {
    if (value == null) {
      return '-';
    }
    return '${value.toStringAsFixed(2)} EUR';
  }

  String _date(int? millis) {
    if (millis == null) {
      return '-';
    }
    return DateTime.fromMillisecondsSinceEpoch(millis)
        .toIso8601String()
        .substring(0, 10);
  }
}

enum PropertyTypeModule {
  saleData,
  buyerInterests,
  viewings,
  saleOffers,
  reservations,
  guests,
  housekeeping,
  hotelRevenue,
  parkingStorage,
  unitSaleStatus,
}

class _InfoLine {
  const _InfoLine(this.label, this.value);

  final String label;
  final String value;
}

class _ListLine {
  const _ListLine({required this.title, required this.subtitle});

  final String title;
  final String subtitle;
}

