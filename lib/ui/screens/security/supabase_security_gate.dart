import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/reference_slice/application/reference_slice_controller.dart';
import '../../../features/reference_slice/presentation/reference_slice_screen.dart';
import '../../navigation/app_navigation.dart';
import '../../shell/app_scaffold.dart';

class SupabaseSecurityGate extends ConsumerWidget {
  const SupabaseSecurityGate({super.key, required this.routeTarget});

  final CloudRouteTarget routeTarget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(referenceSliceControllerProvider);
    final controller = ref.read(referenceSliceControllerProvider.notifier);

    if (state.authPhase == ReferenceAuthPhase.authenticated &&
        state.workspacePhase == WorkspacePhase.selected &&
        state.selectedWorkspace != null &&
        state.totpEnrollment == null) {
      return AppScaffold.cloud(routeTarget: routeTarget);
    }

    return Scaffold(
      body: ReferenceSliceView(
        state: state,
        referencePresentation: false,
        showCompactDetail: false,
        onBackToList: () {},
        onRefreshWorkspaces: controller.refreshWorkspaces,
        onSelectWorkspace: controller.selectWorkspace,
        onReloadProperties: controller.reloadProperties,
        onLoadNextPage: controller.loadNextPropertyPage,
        onOpenProperty: controller.openProperty,
        onUpdateProperty: controller.updateSelectedProperty,
        onRetryUpdate: controller.retryUpdate,
        onSignInWithPassword: controller.signInWithPassword,
        onBeginTotpEnrollment: controller.beginTotpEnrollment,
        onVerifyTotp: controller.verifyTotp,
        onSignOut: controller.signOut,
      ),
    );
  }
}
