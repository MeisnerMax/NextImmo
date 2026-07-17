import 'package:flutter/material.dart';

import '../../../ui/components/nx_card.dart';
import '../../../ui/components/nx_empty_state.dart';
import '../../../ui/components/nx_status_badge.dart';
import '../../../ui/theme/app_theme.dart';
import '../../portfolio_property/application/property_repository.dart';
import '../../portfolio_property/domain/property_dto.dart';
import '../application/reference_slice_controller.dart';

class ReferencePropertyDetailPanel extends StatefulWidget {
  const ReferencePropertyDetailPanel({
    super.key,
    required this.state,
    required this.canUpdate,
    required this.showBack,
    required this.onBack,
    required this.onUpdate,
    required this.onRetry,
  });

  final ReferenceSliceState state;
  final bool canUpdate;
  final bool showBack;
  final VoidCallback onBack;
  final Future<void> Function(PropertyUpdateDto changes) onUpdate;
  final Future<void> Function() onRetry;

  @override
  State<ReferencePropertyDetailPanel> createState() =>
      _ReferencePropertyDetailPanelState();
}

class _ReferencePropertyDetailPanelState
    extends State<ReferencePropertyDetailPanel> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _zip = TextEditingController();
  final _city = TextEditingController();
  final _country = TextEditingController();
  final _propertyType = TextEditingController();
  final _units = TextEditingController();
  final _notes = TextEditingController();
  String? _loadedPropertyId;
  PropertyStatus _status = PropertyStatus.active;

  @override
  void initState() {
    super.initState();
    _loadProperty(widget.state.selectedProperty);
  }

  @override
  void didUpdateWidget(covariant ReferencePropertyDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final property = widget.state.selectedProperty;
    if (property?.id != _loadedPropertyId) {
      _loadProperty(property);
    }
  }

  void _loadProperty(PropertyDto? property) {
    _loadedPropertyId = property?.id;
    if (property == null) {
      return;
    }
    _name.text = property.name;
    _address.text = property.addressLine1;
    _zip.text = property.zip;
    _city.text = property.city;
    _country.text = property.country;
    _propertyType.text = property.propertyType;
    _units.text = property.units.toString();
    _notes.text = property.notes ?? '';
    _status = property.status;
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _zip.dispose();
    _city.dispose();
    _country.dispose();
    _propertyType.dispose();
    _units.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final property = state.selectedProperty;
    if (state.propertyDetailPhase == PropertyDetailPhase.loading) {
      return const NxCard(child: Center(child: CircularProgressIndicator()));
    }
    if (state.propertyDetailPhase == PropertyDetailPhase.notFound) {
      return _message(
        title: 'Property not found',
        description: state.message ?? 'The selected property is unavailable.',
        icon: Icons.search_off_outlined,
      );
    }
    if (state.propertyDetailPhase == PropertyDetailPhase.forbidden) {
      return _message(
        title: 'Property access denied',
        description: state.message ?? 'The selected property is not permitted.',
        icon: Icons.block_outlined,
      );
    }
    if (state.propertyDetailPhase == PropertyDetailPhase.error) {
      return _message(
        title: 'Unable to load property',
        description: state.message ?? 'Property details could not be loaded.',
        icon: Icons.error_outline,
      );
    }
    if (property == null) {
      return const NxEmptyState(
        title: 'Select a property',
        description: 'Choose a property to inspect its cloud record.',
        icon: Icons.home_work_outlined,
      );
    }

    return NxCard(
      child: ListView(
        key: const Key('reference-property-detail-scroll'),
        children: [
          if (widget.showBack)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('reference-compact-back'),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to properties'),
              ),
            ),
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                property.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              NxStatusBadge(
                label: property.status.name,
                kind:
                    property.status == PropertyStatus.active
                        ? NxBadgeKind.success
                        : NxBadgeKind.neutral,
              ),
              NxStatusBadge(label: 'Version ${property.version}'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${property.addressLine1}, ${property.zip} ${property.city}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.section),
          _mutationFeedback(context),
          if (widget.canUpdate) ...[
            Text(
              'Edit property',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.component),
            _buildForm(),
          ] else
            const NxEmptyState(
              title: 'Read-only access',
              description: 'Your workspace role cannot update this property.',
              icon: Icons.visibility_outlined,
            ),
        ],
      ),
    );
  }

  Widget _message({
    required String title,
    required String description,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showBack)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to properties'),
            ),
          ),
        Expanded(
          child: NxEmptyState(
            title: title,
            description: description,
            icon: icon,
          ),
        ),
      ],
    );
  }

  Widget _mutationFeedback(BuildContext context) {
    final state = widget.state;
    final retryable =
        state.failureKind ==
            PropertyRepositoryFailureKind.infrastructureFailure ||
        state.failureKind == PropertyRepositoryFailureKind.mutationInProgress;
    final feedback = switch (state.mutationPhase) {
      PropertyMutationPhase.submitting ||
      PropertyMutationPhase.retrying => const LinearProgressIndicator(),
      PropertyMutationPhase.succeeded => const _FeedbackBanner(
        icon: Icons.check_circle_outline,
        message: 'Property saved successfully.',
      ),
      PropertyMutationPhase.conflict => _FeedbackBanner(
        icon: Icons.sync_problem_outlined,
        message:
            'Version conflict. Server version '
            '${state.versionConflict?.actualVersion ?? 'unknown'} is shown; '
            'your form input is preserved.',
      ),
      PropertyMutationPhase.forbidden => _FeedbackBanner(
        icon: Icons.block_outlined,
        message: state.message ?? 'Property updates are not permitted.',
      ),
      PropertyMutationPhase.failed => _FeedbackBanner(
        icon: Icons.error_outline,
        message: state.message ?? 'Property update failed.',
        action:
            retryable
                ? TextButton(
                  onPressed: widget.onRetry,
                  child: const Text('Retry'),
                )
                : null,
      ),
      _ => const SizedBox.shrink(),
    };
    if (feedback is SizedBox) {
      return feedback;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.component),
      child: feedback,
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final twoColumns = constraints.maxWidth >= 720;
          final fieldWidth =
              twoColumns
                  ? (constraints.maxWidth - AppSpacing.component) / 2
                  : constraints.maxWidth;
          return Wrap(
            key: const Key('reference-edit-form'),
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            children: [
              _field(fieldWidth, _name, 'Name'),
              _field(fieldWidth, _address, 'Address'),
              _field(fieldWidth, _zip, 'ZIP'),
              _field(fieldWidth, _city, 'City'),
              _field(fieldWidth, _country, 'Country'),
              _field(fieldWidth, _propertyType, 'Property type'),
              _field(
                fieldWidth,
                _units,
                'Units',
                keyboardType: TextInputType.number,
                validator: (value) {
                  final units = int.tryParse(value ?? '');
                  return units == null || units < 0
                      ? 'Enter a non-negative whole number.'
                      : null;
                },
              ),
              SizedBox(
                width: fieldWidth,
                child: DropdownButtonFormField<PropertyStatus>(
                  value: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    for (final status in PropertyStatus.values)
                      DropdownMenuItem(value: status, child: Text(status.name)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _status = value);
                    }
                  },
                ),
              ),
              SizedBox(
                width: constraints.maxWidth,
                child: TextFormField(
                  controller: _notes,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  minLines: 2,
                  maxLines: 4,
                ),
              ),
              SizedBox(
                width: constraints.maxWidth,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    key: const Key('reference-save-property'),
                    onPressed:
                        widget.state.mutationPhase ==
                                    PropertyMutationPhase.submitting ||
                                widget.state.mutationPhase ==
                                    PropertyMutationPhase.retrying
                            ? null
                            : _submit,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save changes'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _field(
    double width,
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return SizedBox(
      width: width,
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label),
        validator:
            validator ??
            (value) =>
                value == null || value.trim().isEmpty
                    ? 'This field is required.'
                    : null,
      ),
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    widget.onUpdate(
      PropertyUpdateDto(
        name: _name.text.trim(),
        addressLine1: _address.text.trim(),
        zip: _zip.text.trim(),
        city: _city.text.trim(),
        country: _country.text.trim(),
        propertyType: _propertyType.text.trim(),
        units: int.parse(_units.text),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        status: _status,
      ),
    );
  }
}

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return NxCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message)),
          if (action != null) action!,
        ],
      ),
    );
  }
}
