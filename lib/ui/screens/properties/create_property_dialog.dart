import 'package:flutter/material.dart';

import '../../../core/models/property.dart';
import '../../i18n/app_strings.dart';
import '../../theme/app_theme.dart';
import '../../utils/number_parse.dart';

class CreatePropertyDraft {
  const CreatePropertyDraft({
    required this.name,
    required this.address,
    required this.city,
    required this.zip,
    required this.country,
    required this.propertyType,
    required this.units,
  });

  final String name;
  final String address;
  final String city;
  final String zip;
  final String country;
  final String propertyType;
  final int units;
}

class PropertyTypeOption {
  const PropertyTypeOption({required this.value, required this.label});

  final String value;
  final String label;
}

const List<PropertyTypeOption> propertyTypeOptions = <PropertyTypeOption>[
  PropertyTypeOption(value: 'single_family', label: 'Single Family'),
  PropertyTypeOption(value: 'multi_family', label: 'Multi Family'),
  PropertyTypeOption(value: 'apartment', label: 'Apartment'),
  PropertyTypeOption(value: 'commercial', label: 'Commercial Asset'),
];

String propertyTypeDisplayLabel(String propertyType) {
  final normalized = propertyType.trim().toLowerCase();
  for (final option in propertyTypeOptions) {
    if (option.value == normalized) {
      return option.label;
    }
  }
  if (normalized.isEmpty) {
    return 'Property';
  }
  return normalized
      .split('_')
      .map(
        (segment) =>
            segment.isEmpty
                ? segment
                : '${segment[0].toUpperCase()}${segment.substring(1)}',
      )
      .join(' ');
}

class CreatePropertyDialog extends StatefulWidget {
  const CreatePropertyDialog({super.key, required this.onCreateProperty});

  final Future<PropertyRecord?> Function(CreatePropertyDraft draft)
  onCreateProperty;

  @override
  State<CreatePropertyDialog> createState() => _CreatePropertyDialogState();
}

class _CreatePropertyDialogState extends State<CreatePropertyDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _zipController = TextEditingController();
  final _countryController = TextEditingController(text: 'DE');
  final _unitsController = TextEditingController(text: '1');
  String _propertyType = propertyTypeOptions.first.value;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _zipController.dispose();
    _countryController.dispose();
    _unitsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      title: Text(s.text('Create Property')),
      content: SizedBox(
        width: 720,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.text(
                    'Start with the basics. You can add strategy, financial assumptions, rent data and documents after the property is created.',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.semanticColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.section),
                _DialogSection(
                  title: s.text('Basic Information'),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _nameController,
                        enabled: !_isSubmitting,
                        autofocus: true,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(labelText: s.text('Name')),
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _addressController,
                        enabled: !_isSubmitting,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: s.text('Address'),
                        ),
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 520;
                          if (compact) {
                            return Column(
                              children: [
                                _buildCityZipCountryRow(context, compact: true),
                              ],
                            );
                          }
                          return _buildCityZipCountryRow(
                            context,
                            compact: false,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.component),
                _DialogSection(
                  title: s.text('Property Details'),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 520;
                      if (compact) {
                        return Column(
                          children: [
                            _buildPropertyTypeField(context),
                            const SizedBox(height: 12),
                            _buildUnitsField(context),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: _buildPropertyTypeField(context),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: _buildUnitsField(context)),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _isSubmitting ? null : () => Navigator.of(context).pop(null),
          child: Text(s.text('Cancel')),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          child:
              _isSubmitting
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : Text(s.text('Create Property')),
        ),
      ],
    );
  }

  Widget _buildCityZipCountryRow(
    BuildContext context, {
    required bool compact,
  }) {
    final cityField = TextFormField(
      controller: _cityController,
      enabled: !_isSubmitting,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(labelText: context.strings.text('City')),
      validator: _required,
    );
    final zipField = TextFormField(
      controller: _zipController,
      enabled: !_isSubmitting,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(labelText: context.strings.text('ZIP')),
      validator: _required,
    );
    final countryField = TextFormField(
      controller: _countryController,
      enabled: !_isSubmitting,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(labelText: context.strings.text('Country')),
      validator: _required,
    );

    if (compact) {
      return Column(
        children: [
          cityField,
          const SizedBox(height: 12),
          zipField,
          const SizedBox(height: 12),
          countryField,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: cityField),
        const SizedBox(width: 12),
        Expanded(child: zipField),
        const SizedBox(width: 12),
        SizedBox(width: 120, child: countryField),
      ],
    );
  }

  Widget _buildPropertyTypeField(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: _propertyType,
      decoration: InputDecoration(
        labelText: context.strings.text('Property Type'),
      ),
      items: propertyTypeOptions
          .map(
            (option) => DropdownMenuItem<String>(
              value: option.value,
              child: Text(context.strings.text(option.label)),
            ),
          )
          .toList(growable: false),
      onChanged:
          _isSubmitting
              ? null
              : (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _propertyType = value;
                });
              },
    );
  }

  Widget _buildUnitsField(BuildContext context) {
    return TextFormField(
      controller: _unitsController,
      enabled: !_isSubmitting,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: context.strings.text('Units')),
      validator: _validateUnits,
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final property = await widget.onCreateProperty(
        CreatePropertyDraft(
          name: _nameController.text.trim(),
          address: _addressController.text.trim(),
          city: _cityController.text.trim(),
          zip: _zipController.text.trim(),
          country: _countryController.text.trim(),
          propertyType: _propertyType,
          units: parseIntFlexible(_unitsController.text.trim()) ?? 1,
        ),
      );
      if (!mounted || property == null) {
        return;
      }
      Navigator.of(context).pop(property);
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return context.strings.text('Required');
    }
    return null;
  }

  String? _validateUnits(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final units = parseIntFlexible(trimmed);
    if (units == null || units <= 0) {
      return context.strings.text('Enter a valid unit count.');
    }
    return null;
  }
}

class _DialogSection extends StatelessWidget {
  const _DialogSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.semanticColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadiusTokens.md),
        border: Border.all(color: context.semanticColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
