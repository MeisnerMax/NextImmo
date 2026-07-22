import 'package:flutter/material.dart';

import 'package:neximmo_app/core/models/property_creation.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';
import 'package:neximmo_app/ui/utils/number_parse.dart';
import '../property_creation_support.dart';

/// Inline editor for a single unit draft (former private `_UnitEditor`).
class CreationUnitEditor extends StatelessWidget {
  const CreationUnitEditor({
    super.key,
    required this.unit,
    required this.onChanged,
    required this.onDuplicate,
    required this.onRemove,
  });

  final PropertyCreationUnitDraft unit;
  final VoidCallback onChanged;
  final VoidCallback onDuplicate;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: semantic.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        border: Border.all(color: semantic.border),
      ),
      child: Column(
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              creationWorkflowField(
                context,
                _inlineText('Einheitennummer', unit.unitCode,
                    (v) => unit.unitCode = v),
              ),
              creationWorkflowField(
                context,
                _inlineText('Nutzung', unit.useType, (v) => unit.useType = v),
              ),
              creationWorkflowField(
                context,
                _inlineText('Etage', unit.floor, (v) => unit.floor = v),
              ),
              creationWorkflowField(
                context,
                _inlineNumber('Flaeche', unit.area, (v) => unit.area = v),
              ),
              IconButton(
                tooltip: 'Duplizieren',
                onPressed: onDuplicate,
                icon: const Icon(Icons.copy_outlined),
              ),
              IconButton(
                tooltip: 'Entfernen',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              creationWorkflowField(
                context,
                _inlineNumber('Zimmer optional', unit.rooms,
                    (v) => unit.rooms = v),
              ),
              creationWorkflowField(
                context,
                DropdownButtonFormField<String>(
                  value: unit.status,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'rented', child: Text('Vermietet')),
                    DropdownMenuItem(
                        value: 'occupied', child: Text('Vermietet')),
                    DropdownMenuItem(value: 'vacant', child: Text('Leer')),
                    DropdownMenuItem(
                        value: 'owner_occupied', child: Text('Eigengenutzt')),
                    DropdownMenuItem(
                        value: 'for_sale', child: Text('Zum Verkauf')),
                    DropdownMenuItem(
                        value: 'reserved', child: Text('Reserviert')),
                    DropdownMenuItem(value: 'sold', child: Text('Verkauft')),
                    DropdownMenuItem(
                        value: 'hotel_room_active',
                        child: Text('Hotelzimmer aktiv')),
                    DropdownMenuItem(
                        value: 'renovation', child: Text('In Sanierung')),
                    DropdownMenuItem(value: 'inactive', child: Text('Inaktiv')),
                    DropdownMenuItem(
                        value: 'offline', child: Text('Nicht nutzbar')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      unit.status = value;
                      onChanged();
                    }
                  },
                ),
              ),
              creationWorkflowField(
                context,
                _inlineNumber('Kaltmiete', unit.coldRent,
                    (v) => unit.coldRent = v),
              ),
              creationWorkflowField(
                context,
                _inlineNumber('Nebenkosten', unit.serviceCharge,
                    (v) => unit.serviceCharge = v),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              creationWorkflowField(
                context,
                _inlineText('Stellplatzzuordnung', unit.parkingAssignment,
                    (v) => unit.parkingAssignment = v),
              ),
              creationWorkflowField(
                context,
                _inlineText('Notizen', unit.notes, (v) => unit.notes = v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _inlineText(String label, String value, ValueChanged<String> setter) {
    return TextFormField(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      onChanged: (value) {
        setter(value);
        onChanged();
      },
    );
  }

  Widget _inlineNumber(
      String label, double? value, ValueChanged<double?> setter) {
    return TextFormField(
      initialValue: value == null ? '' : trimCreationNumber(value),
      decoration: InputDecoration(labelText: label),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (value) {
        setter(parseDoubleFlexible(value));
        onChanged();
      },
    );
  }
}

/// Inline editor for a single tenant draft (former private `_TenantEditor`).
class CreationTenantEditor extends StatelessWidget {
  const CreationTenantEditor({
    super.key,
    required this.tenant,
    required this.unitCodes,
    required this.onChanged,
    required this.onRemove,
  });

  final PropertyCreationTenantDraft tenant;
  final List<String> unitCodes;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: semantic.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        border: Border.all(color: semantic.border),
      ),
      child: Column(
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              creationWorkflowField(
                context,
                _inlineText('Mietername', tenant.tenantName,
                    (v) => tenant.tenantName = v),
              ),
              creationWorkflowField(
                context,
                DropdownButtonFormField<String>(
                  value: unitCodes.contains(tenant.unitCode)
                      ? tenant.unitCode
                      : (unitCodes.isEmpty ? null : unitCodes.first),
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Einheit'),
                  items: [
                    for (final code in unitCodes)
                      DropdownMenuItem(value: code, child: Text(code)),
                  ],
                  onChanged: (value) {
                    tenant.unitCode = value ?? '';
                    onChanged();
                  },
                ),
              ),
              IconButton(
                tooltip: 'Entfernen',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              creationWorkflowField(
                context,
                _inlineDate('Mietbeginn', tenant.leaseStart,
                    (v) => tenant.leaseStart = v),
              ),
              creationWorkflowField(
                context,
                _inlineDate('Mietende', tenant.leaseEnd,
                    (v) => tenant.leaseEnd = v),
              ),
              creationWorkflowField(
                context,
                _inlineText('Kuendigungsfrist', tenant.noticePeriod,
                    (v) => tenant.noticePeriod = v),
              ),
              creationWorkflowField(
                context,
                _inlineNumber('Kaltmiete', tenant.coldRent,
                    (v) => tenant.coldRent = v),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              creationWorkflowField(
                context,
                _inlineNumber('Nebenkosten', tenant.serviceCharges,
                    (v) => tenant.serviceCharges = v),
              ),
              creationWorkflowField(
                context,
                _inlineNumber('Kaution', tenant.deposit,
                    (v) => tenant.deposit = v),
              ),
              creationWorkflowField(
                context,
                _inlineText('Zahlungsstatus', tenant.paymentStatus,
                    (v) => tenant.paymentStatus = v),
              ),
              creationWorkflowField(
                context,
                _inlineText('Notizen', tenant.notes, (v) => tenant.notes = v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _inlineText(String label, String value, ValueChanged<String> setter) {
    return TextFormField(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      onChanged: (value) {
        setter(value);
        onChanged();
      },
    );
  }

  Widget _inlineNumber(
      String label, double? value, ValueChanged<double?> setter) {
    return TextFormField(
      initialValue: value == null ? '' : trimCreationNumber(value),
      decoration: InputDecoration(labelText: label),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (value) {
        setter(parseDoubleFlexible(value));
        onChanged();
      },
    );
  }

  Widget _inlineDate(String label, int? value, ValueChanged<int?> setter) {
    return TextFormField(
      initialValue: value == null ? '' : formatCreationDate(value),
      decoration: InputDecoration(labelText: label, hintText: 'YYYY-MM-DD'),
      onChanged: (value) {
        setter(parseCreationDate(value));
        onChanged();
      },
    );
  }
}
