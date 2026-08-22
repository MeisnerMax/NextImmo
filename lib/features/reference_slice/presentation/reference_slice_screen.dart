import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../ui/components/nx_card.dart';
import '../../../ui/components/nx_empty_state.dart';
import '../../../ui/components/nx_page_header.dart';
import '../../../ui/components/nx_status_badge.dart';
import '../../../ui/navigation/app_navigation.dart';
import '../../../ui/theme/app_theme.dart';
import '../../identity_access/application/identity_access_repository.dart';
import '../../portfolio_property/domain/property_dto.dart';
import '../application/reference_slice_controller.dart';
import 'reference_property_detail_panel.dart';

class ReferenceSliceScreen extends ConsumerStatefulWidget {
  const ReferenceSliceScreen({
    super.key,
    this.initialPropertyId,
    this.embeddedInShell = false,
  });

  final String? initialPropertyId;
  final bool embeddedInShell;

  @override
  ConsumerState<ReferenceSliceScreen> createState() =>
      _ReferenceSliceScreenState();
}

class _ReferenceSliceScreenState extends ConsumerState<ReferenceSliceScreen> {
  bool _showCompactDetail = false;
  bool _initialPropertyHandled = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(referenceSliceControllerProvider);
    final controller = ref.read(referenceSliceControllerProvider.notifier);
    ref.listen<ReferenceSliceState>(referenceSliceControllerProvider, (
      _,
      next,
    ) {
      _openInitialProperty(next);
    });
    _openInitialProperty(state);
    final view = ReferenceSliceView(
      state: state,
      referencePresentation: !widget.embeddedInShell,
      showCompactDetail: _showCompactDetail,
      onBackToList: _backToList,
      onRefreshWorkspaces: controller.refreshWorkspaces,
      onSelectWorkspace: controller.selectWorkspace,
      onReloadProperties: controller.reloadProperties,
      onLoadNextPage: controller.loadNextPropertyPage,
      onOpenProperty: (propertyId) async {
        final navigator = Navigator.of(context);
        final currentRouteName = ModalRoute.of(context)?.settings.name;
        await controller.openProperty(propertyId);
        if (mounted) {
          final route = referencePropertyRoute(propertyId);
          if (currentRouteName != route) {
            navigator.pushNamed(route);
          } else {
            setState(() => _showCompactDetail = true);
          }
        }
      },
      onUpdateProperty: controller.updateSelectedProperty,
      onRetryUpdate: controller.retryUpdate,
      onSignInWithPassword: controller.signInWithPassword,
      onBeginTotpEnrollment: controller.beginTotpEnrollment,
      onResumeTotpEnrollment: controller.resumeTotpEnrollment,
      onRestartTotpEnrollment: controller.restartTotpEnrollment,
      onVerifyTotp: controller.verifyTotp,
      onSignOut: controller.signOut,
      onOpenMembers:
          () => Navigator.of(context).pushNamed(referenceMembersRoute),
    );
    return widget.embeddedInShell ? view : Scaffold(body: view);
  }

  void _openInitialProperty(ReferenceSliceState state) {
    final propertyId = widget.initialPropertyId;
    if (_initialPropertyHandled ||
        propertyId == null ||
        state.selectedWorkspace == null) {
      return;
    }
    _initialPropertyHandled = true;
    if (state.selectedProperty?.id == propertyId) {
      _showCompactDetail = true;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await ref
          .read(referenceSliceControllerProvider.notifier)
          .openProperty(propertyId);
      if (mounted) {
        setState(() => _showCompactDetail = true);
      }
    });
  }

  void _backToList() {
    if (widget.initialPropertyId != null) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
        return;
      }
      Navigator.of(context).pushReplacementNamed(referencePropertiesRoute);
      return;
    }
    setState(() => _showCompactDetail = false);
  }
}

class ReferenceSliceView extends StatefulWidget {
  const ReferenceSliceView({
    super.key,
    required this.state,
    required this.showCompactDetail,
    required this.onBackToList,
    required this.onRefreshWorkspaces,
    required this.onSelectWorkspace,
    required this.onReloadProperties,
    required this.onLoadNextPage,
    required this.onOpenProperty,
    required this.onUpdateProperty,
    required this.onRetryUpdate,
    required this.onSignInWithPassword,
    required this.onBeginTotpEnrollment,
    required this.onResumeTotpEnrollment,
    required this.onRestartTotpEnrollment,
    required this.onVerifyTotp,
    required this.onSignOut,
    this.onOpenMembers,
    this.referencePresentation = true,
  });

  final ReferenceSliceState state;
  final bool showCompactDetail;
  final VoidCallback onBackToList;
  final Future<void> Function() onRefreshWorkspaces;
  final Future<void> Function(String workspaceId) onSelectWorkspace;
  final Future<void> Function() onReloadProperties;
  final Future<void> Function() onLoadNextPage;
  final Future<void> Function(String propertyId) onOpenProperty;
  final Future<void> Function(PropertyUpdateDto changes, {int? expectedVersion})
  onUpdateProperty;
  final Future<void> Function() onRetryUpdate;
  final Future<void> Function(String email, String password)
  onSignInWithPassword;
  final Future<void> Function() onBeginTotpEnrollment;
  final Future<void> Function({required String code}) onResumeTotpEnrollment;
  final Future<void> Function() onRestartTotpEnrollment;
  final Future<void> Function({required String factorId, required String code})
  onVerifyTotp;
  final Future<void> Function() onSignOut;
  final VoidCallback? onOpenMembers;
  final bool referencePresentation;

  @override
  State<ReferenceSliceView> createState() => _ReferenceSliceViewState();
}

class _ReferenceSliceViewState extends State<ReferenceSliceView> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _totpCodeController = TextEditingController();
  String _query = '';
  String? _selectedFactorId;
  bool _passwordObscured = true;

  @override
  void dispose() {
    _searchController.dispose();
    _emailController.dispose();
    // Drops the only in-memory copy of the password with the form.
    _passwordController.dispose();
    _totpCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    switch (state.authPhase) {
      case ReferenceAuthPhase.loading:
        return const Center(
          key: Key('reference-auth-loading'),
          child: CircularProgressIndicator(),
        );
      case ReferenceAuthPhase.unauthenticated:
        return _buildPasswordSignIn();
      case ReferenceAuthPhase.mfaRequired:
        return _buildMfaStepUp();
      case ReferenceAuthPhase.error:
        return _AuthState(
          key: const Key('reference-auth-error'),
          title: 'Authentication unavailable',
          description: state.message ?? 'Authentication could not be loaded.',
          icon: Icons.error_outline,
        );
      case ReferenceAuthPhase.authenticated:
        return _buildAuthenticated(context);
    }
  }

  Widget _buildAuthenticated(BuildContext context) {
    final state = widget.state;
    if (state.totpEnrollment != null) {
      return _buildTotpEnrollment();
    }
    final filteredProperties = state.properties
        .where((property) {
          if (_query.isEmpty) {
            return true;
          }
          return '${property.name} ${property.addressLine1} ${property.city}'
              .toLowerCase()
              .contains(_query);
        })
        .toList(growable: false);
    final canUpdate =
        state.assuranceLevel == AuthenticationAssuranceLevel.aal2 &&
        (state.selectedWorkspace?.allows(
              ReferenceSliceController.propertyUpdatePermission,
            ) ??
            false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth > AppBreakpoints.tabletMax;
        final compactDetail = !desktop && widget.showCompactDetail;
        final content =
            desktop
                ? Row(
                  key: const Key('reference-desktop-split'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 5,
                      child: _buildPropertyList(filteredProperties),
                    ),
                    const SizedBox(width: AppSpacing.component),
                    Expanded(
                      flex: 6,
                      child: _buildDetail(canUpdate: canUpdate),
                    ),
                  ],
                )
                : compactDetail
                ? _buildDetail(canUpdate: canUpdate, showBack: true)
                : _buildPropertyList(filteredProperties);

        return Padding(
          padding: EdgeInsets.all(context.adaptivePagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NxPageHeader(
                title: widget.referencePresentation ? 'Properties' : 'Objekte',
                breadcrumbs:
                    widget.referencePresentation
                        ? const ['Reference slice', 'Properties']
                        : const ['Objekte & Portfolio', 'Objekte'],
                subtitle: 'Workspace-scoped cloud property management.',
                trailing: _buildWorkspaceControl(),
                secondaryActions: [
                  if (widget.onOpenMembers != null)
                    OutlinedButton.icon(
                      key: const Key('reference-open-members'),
                      onPressed: widget.onOpenMembers,
                      icon: const Icon(Icons.group_outlined),
                      label: const Text('Members'),
                    ),
                  if (state.assuranceLevel != AuthenticationAssuranceLevel.aal2)
                    OutlinedButton.icon(
                      key: const Key('reference-start-mfa'),
                      onPressed:
                          _authActionBusy ? null : widget.onBeginTotpEnrollment,
                      icon: const Icon(Icons.phonelink_lock_outlined),
                      label: const Text('Set up MFA'),
                    ),
                  OutlinedButton.icon(
                    key: const Key('reference-sign-out'),
                    onPressed: _authActionBusy ? null : widget.onSignOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.component),
              Expanded(child: content),
            ],
          ),
        );
      },
    );
  }

  bool get _authActionBusy {
    return switch (widget.state.authActionPhase) {
      ReferenceAuthActionPhase.signingIn ||
      ReferenceAuthActionPhase.loadingFactors ||
      ReferenceAuthActionPhase.enrolling ||
      ReferenceAuthActionPhase.verifying ||
      ReferenceAuthActionPhase.signingOut => true,
      _ => false,
    };
  }

  // Single entry point for the button and for the keyboard submit, so both go
  // through the same busy check and cannot double-submit.
  void _submitPasswordSignIn() {
    if (_authActionBusy) {
      return;
    }
    widget.onSignInWithPassword(
      _emailController.text,
      _passwordController.text,
    );
  }

  Widget _buildPasswordSignIn() {
    final state = widget.state;
    return _AuthFormShell(
      key: const Key('reference-unauthenticated'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.lock_outline,
            size: 32,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: AppSpacing.component),
          Text(
            'Sign in to NexImmo',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Sign in with your email and password. '
            'A second factor is required afterwards.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.component),
          TextField(
            key: const Key('reference-auth-email'),
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: AppSpacing.component),
          TextField(
            key: const Key('reference-auth-password'),
            controller: _passwordController,
            // Never rendered in clear text unless the user asks, and never
            // written anywhere but this controller.
            obscureText: _passwordObscured,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onSubmitted:
                _authActionBusy ? null : (_) => _submitPasswordSignIn(),
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                key: const Key('reference-auth-password-visibility'),
                tooltip: _passwordObscured ? 'Show password' : 'Hide password',
                icon: Icon(
                  _passwordObscured
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed:
                    () => setState(
                      () => _passwordObscured = !_passwordObscured,
                    ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.component),
          FilledButton.icon(
            key: const Key('reference-auth-submit'),
            onPressed: _authActionBusy ? null : _submitPasswordSignIn,
            icon:
                state.authActionPhase == ReferenceAuthActionPhase.signingIn
                    ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.login_outlined),
            label: const Text('Sign in'),
          ),
          if (state.authMessage != null) ...[
            const SizedBox(height: AppSpacing.component),
            Text(
              state.authMessage!,
              key: const Key('reference-auth-message'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMfaStepUp() {
    final state = widget.state;
    if (state.authActionPhase == ReferenceAuthActionPhase.loadingFactors) {
      return const Center(
        key: Key('reference-mfa-loading'),
        child: CircularProgressIndicator(),
      );
    }
    // Enrolment now also runs below aal2, so the setup screen has to be
    // reachable from here and not only from the authenticated shell.
    if (state.totpEnrollment != null) {
      return _buildTotpEnrollment();
    }
    if (state.recoveryFactor != null) {
      return _buildInterruptedEnrollmentRecovery();
    }
    // No verified factor yet: there is nothing to challenge, so ask for setup
    // instead of a code. Deliberately never phrased as missing workspace
    // access -- the account has access, the session is simply not elevated.
    if (state.authActionPhase == ReferenceAuthActionPhase.enrollmentRequired) {
      return _AuthFormShell(
        key: const Key('reference-mfa-enrollment-required'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.phonelink_lock_outlined,
              size: 32,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.component),
            Text(
              'Set up multi-factor authentication',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'NexImmo requires an authenticator before workspace data can be '
              'accessed.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.component),
            FilledButton.icon(
              key: const Key('reference-mfa-begin-enrollment'),
              onPressed: _authActionBusy ? null : widget.onBeginTotpEnrollment,
              icon: const Icon(Icons.phonelink_lock_outlined),
              label: const Text('Set up authenticator'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              key: const Key('reference-mfa-enrollment-sign-out'),
              onPressed: _authActionBusy ? null : widget.onSignOut,
              child: const Text('Sign out'),
            ),
          ],
        ),
      );
    }
    final factors = state.totpFactors;
    final selected =
        factors.any((factor) => factor.id == _selectedFactorId)
            ? _selectedFactorId
            : factors.isEmpty
            ? null
            : factors.first.id;
    _selectedFactorId = selected;
    return _AuthFormShell(
      key: const Key('reference-mfa-required'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.phonelink_lock_outlined,
            size: 32,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: AppSpacing.component),
          Text(
            'Multi-factor authentication required',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Enter the current six-digit code from your authenticator.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (factors.length > 1) ...[
            const SizedBox(height: AppSpacing.component),
            DropdownButtonFormField<String>(
              key: const Key('reference-mfa-factor'),
              value: selected,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Authenticator'),
              items: [
                for (final factor in factors)
                  DropdownMenuItem(
                    value: factor.id,
                    child: Text(
                      factor.friendlyName ?? 'Authenticator',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _selectedFactorId = value),
            ),
          ],
          const SizedBox(height: AppSpacing.component),
          _buildTotpCodeField(),
          const SizedBox(height: AppSpacing.component),
          FilledButton.icon(
            key: const Key('reference-mfa-verify'),
            onPressed:
                _authActionBusy || selected == null
                    ? null
                    : () => widget.onVerifyTotp(
                      factorId: selected,
                      code: _totpCodeController.text,
                    ),
            icon: const Icon(Icons.verified_user_outlined),
            label: const Text('Verify'),
          ),
          TextButton(
            key: const Key('reference-mfa-sign-out'),
            onPressed: _authActionBusy ? null : widget.onSignOut,
            child: const Text('Sign out'),
          ),
          if (state.authMessage != null)
            Text(
              state.authMessage!,
              key: const Key('reference-auth-message'),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  // SECURITY-AAL-CLIENT-03. An enrolment that was started but never verified
  // leaves a factor that can neither be challenged nor re-created. The user is
  // told what happened and chooses: finish with the key already in their app,
  // or start over. No factor id, no secret and no provider text is rendered --
  // the controller has already reduced the situation to this choice.
  Widget _buildInterruptedEnrollmentRecovery() {
    final state = widget.state;
    return _AuthFormShell(
      key: const Key('reference-mfa-recovery'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.phonelink_lock_outlined,
            size: 32,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: AppSpacing.component),
          Text(
            'Authenticator setup incomplete',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your authenticator setup was interrupted before it was verified. '
            'If NexImmo is already in your authenticator app, enter its '
            'current code to continue. Otherwise restart the setup.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.component),
          _buildTotpCodeField(),
          const SizedBox(height: AppSpacing.component),
          FilledButton.icon(
            key: const Key('reference-mfa-recovery-continue'),
            onPressed:
                _authActionBusy
                    ? null
                    : () => widget.onResumeTotpEnrollment(
                      code: _totpCodeController.text,
                    ),
            icon: const Icon(Icons.verified_user_outlined),
            label: const Text('Continue existing setup'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            key: const Key('reference-mfa-recovery-restart'),
            onPressed: _authActionBusy ? null : widget.onRestartTotpEnrollment,
            icon: const Icon(Icons.restart_alt_outlined),
            label: const Text('Restart authenticator setup'),
          ),
          TextButton(
            key: const Key('reference-mfa-recovery-sign-out'),
            onPressed: _authActionBusy ? null : widget.onSignOut,
            child: const Text('Sign out'),
          ),
          if (state.authMessage != null)
            Text(
              state.authMessage!,
              key: const Key('reference-auth-message'),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  Widget _buildTotpEnrollment() {
    final enrollment = widget.state.totpEnrollment!;
    return _AuthFormShell(
      key: const Key('reference-mfa-enrollment'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Set up multi-factor authentication',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Add this setup key manually to your authenticator. It is shown only for this enrollment.',
          ),
          const SizedBox(height: AppSpacing.component),
          Container(
            padding: const EdgeInsets.all(AppSpacing.component),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadiusTokens.md),
            ),
            child: SelectableText(
              enrollment.secret,
              key: const Key('reference-mfa-enrollment-secret'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontFamily: 'monospace'),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: enrollment.secret));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Setup key copied.')),
                  );
                }
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copy setup key'),
            ),
          ),
          const SizedBox(height: AppSpacing.component),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: _buildTotpCodeField(),
          ),
          const SizedBox(height: AppSpacing.component),
          FilledButton.icon(
            key: const Key('reference-mfa-enrollment-verify'),
            onPressed:
                _authActionBusy
                    ? null
                    : () => widget.onVerifyTotp(
                      factorId: enrollment.factorId,
                      code: _totpCodeController.text,
                    ),
            icon: const Icon(Icons.verified_user_outlined),
            label: const Text('Enable MFA'),
          ),
          TextButton(
            key: const Key('reference-mfa-enrollment-sign-out'),
            onPressed: _authActionBusy ? null : widget.onSignOut,
            child: const Text('Sign out'),
          ),
          if (widget.state.authMessage != null) ...[
            const SizedBox(height: AppSpacing.component),
            Text(
              widget.state.authMessage!,
              key: const Key('reference-auth-message'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTotpCodeField() {
    return TextField(
      key: const Key('reference-mfa-code'),
      controller: _totpCodeController,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      maxLength: 6,
      decoration: const InputDecoration(labelText: 'Authenticator code'),
    );
  }

  Widget _buildWorkspaceControl() {
    final state = widget.state;
    if (state.workspacePhase == WorkspacePhase.loading) {
      return const SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (state.workspaces.isEmpty) {
      return IconButton(
        tooltip: 'Refresh workspaces',
        onPressed: widget.onRefreshWorkspaces,
        icon: const Icon(Icons.refresh),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: DropdownButtonFormField<String>(
        key: const Key('reference-workspace-selector'),
        value: state.selectedWorkspaceId,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Workspace'),
        items: [
          for (final access in state.workspaces)
            DropdownMenuItem(
              value: access.workspace.id,
              child: Text(
                access.workspace.name,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (value) {
          if (value != null) {
            widget.onSelectWorkspace(value);
          }
        },
      ),
    );
  }

  Widget _buildPropertyList(List<PropertySummaryDto> properties) {
    final state = widget.state;
    final body = switch (state.workspacePhase) {
      WorkspacePhase.empty => const NxEmptyState(
        title: 'No workspace access',
        description: 'No active workspace membership is available.',
        icon: Icons.domain_disabled_outlined,
      ),
      WorkspacePhase.error => NxEmptyState(
        title: 'Unable to load workspaces',
        description: state.message ?? 'Workspace access could not be loaded.',
        icon: Icons.error_outline,
        primaryAction: OutlinedButton(
          onPressed: widget.onRefreshWorkspaces,
          child: const Text('Retry'),
        ),
      ),
      WorkspacePhase.selectionRequired when state.selectedWorkspaceId == null =>
        const NxEmptyState(
          title: 'Select a workspace',
          description: 'Choose a workspace before loading properties.',
          icon: Icons.domain_outlined,
        ),
      _ => _buildPropertyPhase(properties),
    };

    return Column(
      key: const Key('reference-list-pane'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('reference-property-search'),
          controller: _searchController,
          onChanged:
              (value) => setState(() => _query = value.trim().toLowerCase()),
          decoration: const InputDecoration(
            labelText: 'Search properties',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        Expanded(child: body),
      ],
    );
  }

  Widget _buildPropertyPhase(List<PropertySummaryDto> properties) {
    final state = widget.state;
    return switch (state.propertyListPhase) {
      PropertyListPhase.idle => const NxEmptyState(
        title: 'Select a workspace',
        description: 'Property data is scoped to the active workspace.',
        icon: Icons.apartment_outlined,
      ),
      PropertyListPhase.loading when state.properties.isEmpty => const NxCard(
        child: Center(child: CircularProgressIndicator()),
      ),
      PropertyListPhase.empty => const NxEmptyState(
        title: 'No properties',
        description: 'This workspace has no active properties.',
        icon: Icons.home_work_outlined,
      ),
      PropertyListPhase.forbidden => const NxEmptyState(
        title: 'Property access denied',
        description: 'Your workspace role cannot read properties.',
        icon: Icons.block_outlined,
      ),
      PropertyListPhase.error => NxEmptyState(
        title: 'Unable to load properties',
        description: state.message ?? 'Property data could not be loaded.',
        icon: Icons.error_outline,
        primaryAction: OutlinedButton(
          onPressed: widget.onReloadProperties,
          child: const Text('Retry'),
        ),
      ),
      _ => _PropertyList(
        properties: properties,
        selectedPropertyId: state.selectedProperty?.id,
        loading: state.propertyListPhase == PropertyListPhase.loading,
        hasNextPage: state.nextCursor != null,
        onOpenProperty: widget.onOpenProperty,
        onLoadNextPage: widget.onLoadNextPage,
      ),
    };
  }

  Widget _buildDetail({required bool canUpdate, bool showBack = false}) {
    return ReferencePropertyDetailPanel(
      key: const Key('reference-detail-pane'),
      state: widget.state,
      canUpdate: canUpdate,
      showBack: showBack,
      onBack: widget.onBackToList,
      onUpdate: widget.onUpdateProperty,
      onRetry: widget.onRetryUpdate,
    );
  }
}

class _PropertyList extends StatelessWidget {
  const _PropertyList({
    required this.properties,
    required this.selectedPropertyId,
    required this.loading,
    required this.hasNextPage,
    required this.onOpenProperty,
    required this.onLoadNextPage,
  });

  final List<PropertySummaryDto> properties;
  final String? selectedPropertyId;
  final bool loading;
  final bool hasNextPage;
  final Future<void> Function(String propertyId) onOpenProperty;
  final Future<void> Function() onLoadNextPage;

  @override
  Widget build(BuildContext context) {
    if (properties.isEmpty) {
      return const NxEmptyState(
        title: 'No search results',
        description: 'Try a different property name, address or city.',
        icon: Icons.search_off_outlined,
      );
    }
    return NxCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: properties.length,
              itemBuilder: (context, index) {
                final property = properties[index];
                return _PropertyRow(
                  property: property,
                  selected: property.id == selectedPropertyId,
                  alternate: index.isOdd,
                  onTap: () => onOpenProperty(property.id),
                );
              },
            ),
          ),
          if (hasNextPage || loading)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child:
                  loading
                      ? const CircularProgressIndicator()
                      : OutlinedButton.icon(
                        onPressed: onLoadNextPage,
                        icon: const Icon(Icons.expand_more),
                        label: const Text('Load more'),
                      ),
            ),
        ],
      ),
    );
  }
}

/// High-density list row in the Liquid Enterprise register.
///
/// Selection is a left bracket rather than an enclosing fill, rows are
/// separated by background alternates rather than divider lines, and the
/// postal code is set in the mono face so codes line up down the column.
class _PropertyRow extends StatelessWidget {
  const _PropertyRow({
    required this.property,
    required this.selected,
    required this.alternate,
    required this.onTap,
  });

  final PropertySummaryDto property;
  final bool selected;
  final bool alternate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final primary = theme.colorScheme.primary;
    final bodySmall = theme.textTheme.bodySmall;

    return Material(
      key: Key('reference-property-${property.id}'),
      color:
          selected
              ? primary.withValues(alpha: 0.08)
              : alternate
              ? semantic.surfaceAlt.withValues(alpha: 0.35)
              : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              // Reserved even when unselected so the text never shifts.
              left: BorderSide(
                color: selected ? primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      property.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: selected ? primary : null,
                      ),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '${property.addressLine1}, '),
                          TextSpan(
                            text: property.zip,
                            style: context.dataMonoStyle.copyWith(
                              fontSize: bodySmall?.fontSize,
                              color: bodySmall?.color,
                            ),
                          ),
                          TextSpan(text: ' ${property.city}'),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              NxStatusBadge(
                label: property.status.name,
                kind: switch (property.status) {
                  PropertyStatus.active => NxBadgeKind.success,
                  PropertyStatus.draft => NxBadgeKind.warning,
                  PropertyStatus.archived => NxBadgeKind.neutral,
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthFormShell extends StatelessWidget {
  const _AuthFormShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: EdgeInsets.all(context.adaptivePagePadding),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: NxCard(child: child),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AuthState extends StatelessWidget {
  const _AuthState({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(context.adaptivePagePadding),
      child: NxEmptyState(title: title, description: description, icon: icon),
    );
  }
}
