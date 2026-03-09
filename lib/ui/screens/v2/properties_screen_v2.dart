import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_status_badge.dart';
import '../../state/app_state.dart';
import '../../state/property_state.dart';
import '../../state/ui_feature_flags.dart';
import '../../templates/list_filter_template.dart';
import '../../theme/app_theme.dart';
import '../../utils/number_parse.dart';
import '../property_detail/property_shell.dart';
import 'property_detail/property_shell_v2.dart';

class PropertiesScreenV2 extends ConsumerStatefulWidget {
  const PropertiesScreenV2({super.key});

  @override
  ConsumerState<PropertiesScreenV2> createState() => _PropertiesScreenV2State();
}

class _PropertiesScreenV2State extends ConsumerState<PropertiesScreenV2> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedPropertyId = ref.watch(selectedPropertyIdProvider);
    final propertyShellV2Enabled = ref.watch(
      uiScreenFlagProvider(UiScreenFlag.propertyShellV2),
    );
    if (selectedPropertyId != null) {
      if (propertyShellV2Enabled) {
        return const PropertyShellV2();
      }
      return const PropertyShell();
    }

    final propertiesAsync = ref.watch(propertiesControllerProvider);
    final controller = ref.read(propertiesControllerProvider.notifier);

    return ListFilterTemplate(
      title: 'Properties',
      breadcrumbs: const ['Portfolio', 'Properties'],
      subtitle:
          'Manage assets, filter the portfolio, and open each property workflow.',
      primaryAction: ElevatedButton.icon(
        onPressed: () => _openCreateDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New Property'),
      ),
      secondaryActions: [
        OutlinedButton(
          onPressed: controller.reload,
          child: const Text('Refresh'),
        ),
      ],
      filters: ListFilterBar(
        children: [
          SizedBox(
            width: context.viewport == AppViewport.mobile ? 180 : 260,
            child: TextField(
              controller: _searchController,
              onChanged:
                  (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
              decoration: const InputDecoration(
                labelText: 'Search properties',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
        ],
      ),
      content: propertiesAsync.when(
        data: (properties) {
          final filtered = properties
              .where((property) {
                if (_query.isEmpty) {
                  return true;
                }
                final haystack =
                    '${property.name} ${property.addressLine1} ${property.city} ${property.propertyType}'
                        .toLowerCase();
                return haystack.contains(_query);
              })
              .toList(growable: false);
          if (filtered.isEmpty) {
            return NxEmptyState(
              title: properties.isEmpty ? 'No properties yet' : 'No match',
              description:
                  properties.isEmpty
                      ? 'Create your first property to start portfolio analysis.'
                      : 'Try another filter or clear the current search.',
              icon: Icons.home_work_outlined,
              primaryAction:
                  properties.isEmpty
                      ? ElevatedButton.icon(
                        onPressed: () => _openCreateDialog(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('Create Property'),
                      )
                      : null,
            );
          }

          return NxCard(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 980),
                child: SingleChildScrollView(
                  child: DataTable(
                    sortAscending: false,
                    sortColumnIndex: 3,
                    columns: const [
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('Address')),
                      DataColumn(label: Text('Type')),
                      DataColumn(label: Text('Updated ↓')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: filtered
                        .map(
                          (property) => DataRow(
                            cells: [
                              DataCell(Text(property.name)),
                              DataCell(
                                Text(
                                  '${property.addressLine1}, ${property.city}',
                                ),
                              ),
                              DataCell(
                                NxStatusBadge(
                                  label: property.propertyType,
                                  kind: NxBadgeKind.info,
                                ),
                              ),
                              DataCell(
                                Text(
                                  DateTime.fromMillisecondsSinceEpoch(
                                    property.updatedAt,
                                  ).toIso8601String(),
                                ),
                              ),
                              DataCell(
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    TextButton(
                                      onPressed: () {
                                        ref
                                            .read(
                                              selectedScenarioIdProvider
                                                  .notifier,
                                            )
                                            .state = null;
                                        ref
                                            .read(
                                              selectedPropertyIdProvider
                                                  .notifier,
                                            )
                                            .state = property.id;
                                        ref
                                                .read(
                                                  propertyDetailPageProvider
                                                      .notifier,
                                                )
                                                .state =
                                            PropertyDetailPage.overview;
                                      },
                                      child: const Text('Open'),
                                    ),
                                    TextButton(
                                      onPressed:
                                          () => controller.archive(
                                            property.id,
                                            true,
                                          ),
                                      child: const Text('Archive'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
      ),
    );
  }

  Future<void> _openCreateDialog(BuildContext context, WidgetRef ref) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController();
    final address = TextEditingController();
    final city = TextEditingController(text: 'Berlin');
    final zip = TextEditingController(text: '10115');
    final country = TextEditingController(text: 'DE');
    final type = TextEditingController(text: 'single_family');
    final units = TextEditingController(text: '1');
    final strategy = TextEditingController(text: 'rental');
    final price = TextEditingController(text: '250000');
    final rent = TextEditingController(text: '1800');
    final rehab = TextEditingController(text: '20000');
    final financing = TextEditingController(text: 'loan');

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Property'),
          content: SizedBox(
            width: 500,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Name'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: address,
                      decoration: const InputDecoration(labelText: 'Address'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: city,
                      decoration: const InputDecoration(labelText: 'City'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: zip,
                      decoration: const InputDecoration(labelText: 'ZIP'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: country,
                      decoration: const InputDecoration(labelText: 'Country'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: type,
                      decoration: const InputDecoration(
                        labelText: 'Property Type',
                      ),
                    ),
                    TextFormField(
                      controller: units,
                      decoration: const InputDecoration(labelText: 'Units'),
                    ),
                    TextFormField(
                      controller: strategy,
                      decoration: const InputDecoration(
                        labelText: 'Strategy (rental/flip/brrrr)',
                      ),
                    ),
                    TextFormField(
                      controller: price,
                      decoration: const InputDecoration(
                        labelText: 'Purchase Price',
                      ),
                    ),
                    TextFormField(
                      controller: rent,
                      decoration: const InputDecoration(
                        labelText: 'Rent Monthly',
                      ),
                    ),
                    TextFormField(
                      controller: rehab,
                      decoration: const InputDecoration(
                        labelText: 'Rehab Budget',
                      ),
                    ),
                    TextFormField(
                      controller: financing,
                      decoration: const InputDecoration(
                        labelText: 'Financing (cash/loan)',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) {
                  return;
                }

                final property = await ref
                    .read(propertiesControllerProvider.notifier)
                    .createPropertyWithBaseScenario(
                      name: name.text.trim(),
                      address: address.text.trim(),
                      city: city.text.trim(),
                      zip: zip.text.trim(),
                      country: country.text.trim(),
                      propertyType: type.text.trim(),
                      units: parseIntFlexible(units.text) ?? 1,
                      strategyType: strategy.text.trim(),
                      purchasePrice: parseDoubleFlexible(price.text) ?? 0,
                      rentMonthly: parseDoubleFlexible(rent.text) ?? 0,
                      rehabBudget: parseDoubleFlexible(rehab.text) ?? 0,
                      financingMode: financing.text.trim(),
                    );

                if (property != null && context.mounted) {
                  ref.read(selectedScenarioIdProvider.notifier).state = null;
                  ref.read(propertyDetailPageProvider.notifier).state =
                      PropertyDetailPage.overview;
                  ref.read(selectedPropertyIdProvider.notifier).state =
                      property.id;
                  Navigator.of(context).pop(true);
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    if (created == true) {
      ref.read(propertiesControllerProvider.notifier).reload();
    }

    name.dispose();
    address.dispose();
    city.dispose();
    zip.dispose();
    country.dispose();
    type.dispose();
    units.dispose();
    strategy.dispose();
    price.dispose();
    rent.dispose();
    rehab.dispose();
    financing.dispose();
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }
    return null;
  }
}
