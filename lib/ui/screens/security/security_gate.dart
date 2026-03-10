import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/app_strings.dart';
import '../../shell/app_scaffold.dart';
import '../../state/security_state.dart';
import 'lock_screen.dart';

class SecurityGate extends ConsumerWidget {
  const SecurityGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final securityAsync = ref.watch(securityControllerProvider);
    return securityAsync.when(
      data: (state) {
        if (state.isLocked) {
          return LockScreen(
            onUnlock: (password) {
              return ref
                  .read(securityControllerProvider.notifier)
                  .unlock(password);
            },
          );
        }
        return const AppScaffold();
      },
      loading:
          () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
      error:
          (error, _) => Scaffold(
            body: Center(
              child: Text(
                context.strings.errorWithPrefix(
                  context.strings.text('Security initialization failed'),
                  error,
                ),
              ),
            ),
          ),
    );
  }
}
