/// The property-kind gate for the whole leasing area (Welle 3, AP5 follow-up).
///
/// A hotel has guests and a sale object has buyers; neither has tenants,
/// units-to-let, leases or a rent roll. The legacy app knew that but applied it
/// **on the tenants tab only**, so the same hotel still offered units, leases
/// and a pipeline right next to it. The gate therefore moved here: one place,
/// applied to the whole area, which is the only way it actually guards
/// anything.
///
/// Two deliberate properties:
///
///   * **It fails open.** An unknown or not-yet-loaded property does not hide
///     the leasing area. This is a suitability gate, not a permission gate —
///     permissions fail closed elsewhere, and hiding a rental property's leases
///     because its record had not loaded yet would be the worse error.
///   * **It reads the property kind from the legacy property state**, which is
///     where the kind lives today. That is a temporary source: once the
///     property contract carries the kind, only this file changes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/models/property.dart';
import '../../../../components/nx_card.dart';
import '../../../../state/property_state.dart';
import '../../../../theme/app_theme.dart';

class LeasingAreaGate extends ConsumerWidget {
  const LeasingAreaGate({
    super.key,
    required this.propertyId,
    required this.child,
  });

  final String propertyId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final properties = ref.watch(propertiesControllerProvider).valueOrNull;
    final property = properties
        ?.where((record) => record.id == propertyId)
        .firstOrNull;
    if (property == null ||
        propertySupportsRentalOperations(property.propertyType)) {
      return child;
    }
    return _NonRentalNotice(property: property);
  }
}

class _NonRentalNotice extends StatelessWidget {
  const _NonRentalNotice({required this.property});

  final PropertyRecord property;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = switch (propertyKindFromType(property.propertyType)) {
      PropertyKind.sale =>
        'Dieses Objekt ist als Verkaufsobjekt angelegt. Vermietung — '
            'Einheiten, Mieter, Verträge, Pipeline und Rent Roll — ist hier '
            'deaktiviert; verwende Kaufinteressenten, Besichtigungen und '
            'Angebote.',
      PropertyKind.condoSale =>
        'Dieses Objekt ist als Eigentumswohnungs-Verkauf angelegt. Statt '
            'Vermietung gehören hierher Käufer, Interessenten und '
            'Reservierungen.',
      PropertyKind.hotel =>
        'Dieses Objekt ist als Hotel angelegt. Statt Vermietung gehören '
            'hierher Gäste, Reservierungen und Zimmer.',
      PropertyKind.other =>
        'Für diese Objektart ist keine Vermietung aktiviert.',
      PropertyKind.rental || PropertyKind.mixed =>
        'Für dieses Objekt ist keine Vermietung aktiviert.',
    };
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: NxCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.info_outline, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
