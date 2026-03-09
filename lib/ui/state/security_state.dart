import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/security.dart';
import '../../core/models/settings.dart';
import '../../core/security/password_hasher.dart';
import '../../data/repositories/inputs_repo.dart';
import '../../data/repositories/security_repo.dart';
import 'app_state.dart';

class SecurityState {
  const SecurityState({
    required this.settings,
    required this.context,
    required this.isLocked,
  });

  final AppSettingsRecord settings;
  final SecurityContextRecord context;
  final bool isLocked;

  SecurityState copyWith({
    AppSettingsRecord? settings,
    SecurityContextRecord? context,
    bool? isLocked,
  }) {
    return SecurityState(
      settings: settings ?? this.settings,
      context: context ?? this.context,
      isLocked: isLocked ?? this.isLocked,
    );
  }
}

final securityControllerProvider =
    AsyncNotifierProvider<SecurityController, SecurityState>(
      SecurityController.new,
    );

final activeUserRoleProvider = Provider<String>((ref) {
  final state = ref.watch(securityControllerProvider).valueOrNull;
  return state?.context.user.role ?? 'admin';
});
final activeUserIdProvider = Provider<String?>((ref) {
  return ref.watch(securityControllerProvider).valueOrNull?.context.user.id;
});
final activeWorkspaceIdProvider = Provider<String?>((ref) {
  return ref.watch(securityControllerProvider).valueOrNull?.context.workspace.id;
});
final activeSecurityContextProvider = Provider<SecurityContextRecord?>((ref) {
  return ref.watch(securityControllerProvider).valueOrNull?.context;
});

class SecurityController extends AsyncNotifier<SecurityState> {
  @override
  Future<SecurityState> build() async {
    await _securityRepo.bootstrapDefaults();
    final settings = await _inputsRepo.getSettings();
    final context = await _securityRepo.getActiveContext();
    return SecurityState(
      settings: settings,
      context: context,
      isLocked: settings.securityAppLockEnabled,
    );
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(build);
  }

  Future<bool> unlock(String password) async {
    final current = state.valueOrNull;
    if (current == null) {
      return false;
    }
    if (!current.settings.securityAppLockEnabled) {
      state = AsyncValue.data(current.copyWith(isLocked: false));
      return true;
    }
    final hash = current.settings.securityPasswordHash;
    final salt = current.settings.securityPasswordSalt;
    if (hash == null || salt == null) {
      return false;
    }
    final ok = _hasher.verify(
      password: password,
      salt: salt,
      expectedHash: hash,
    );
    if (!ok) {
      return false;
    }
    await _securityRepo.startSession(
      workspaceId: current.context.workspace.id,
      userId: current.context.user.id,
    );
    state = AsyncValue.data(current.copyWith(isLocked: false));
    return true;
  }

  void lock() {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    if (!current.settings.securityAppLockEnabled) {
      return;
    }
    state = AsyncValue.data(current.copyWith(isLocked: true));
  }

  Future<void> switchWorkspace(String workspaceId) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    await _securityRepo.setActiveWorkspace(workspaceId);
    final settings = await _inputsRepo.getSettings();
    final context = await _securityRepo.getActiveContext();
    state = AsyncValue.data(
      current.copyWith(settings: settings, context: context),
    );
  }

  Future<void> switchUser(String userId) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    await _securityRepo.setActiveUser(userId);
    final settings = await _inputsRepo.getSettings();
    final context = await _securityRepo.getActiveContext();
    await _securityRepo.startSession(
      workspaceId: context.workspace.id,
      userId: context.user.id,
    );
    state = AsyncValue.data(
      current.copyWith(settings: settings, context: context),
    );
  }

  Future<void> setAppLock({required bool enabled, String? password}) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    String? nextHash = current.settings.securityPasswordHash;
    String? nextSalt = current.settings.securityPasswordSalt;
    int? nextUpdatedAt = current.settings.securityPasswordUpdatedAt;
    if (enabled) {
      final trimmed = (password ?? '').trim();
      if (trimmed.isEmpty && (nextHash == null || nextSalt == null)) {
        throw StateError('Password is required to enable app lock.');
      }
      if (trimmed.isNotEmpty) {
        nextSalt = _hasher.generateSalt();
        nextHash = _hasher.hashPassword(password: trimmed, salt: nextSalt);
        nextUpdatedAt = DateTime.now().millisecondsSinceEpoch;
      }
    }
    final updated = current.settings.copyWith(
      securityAppLockEnabled: enabled,
      securityPasswordHash: nextHash,
      securityPasswordSalt: nextSalt,
      securityPasswordUpdatedAt: nextUpdatedAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _inputsRepo.updateSettings(updated);
    state = AsyncValue.data(
      current.copyWith(
        settings: updated,
        isLocked: enabled ? current.isLocked : false,
      ),
    );
  }

  Future<void> changeAppLockPassword(String password) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    final trimmed = password.trim();
    if (trimmed.isEmpty) {
      throw StateError('Password must not be empty.');
    }
    final salt = _hasher.generateSalt();
    final hash = _hasher.hashPassword(password: trimmed, salt: salt);
    final updated = current.settings.copyWith(
      securityPasswordHash: hash,
      securityPasswordSalt: salt,
      securityPasswordUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _inputsRepo.updateSettings(updated);
    state = AsyncValue.data(current.copyWith(settings: updated));
  }

  Future<List<WorkspaceRecord>> listWorkspaces() {
    return _securityRepo.listWorkspaces();
  }

  Future<List<LocalUserRecord>> listUsers(String workspaceId) {
    return _securityRepo.listUsers(workspaceId);
  }

  Future<LocalUserRecord> createUser({
    required String workspaceId,
    required String displayName,
    String? email,
    required String role,
  }) {
    return _securityRepo.createUser(
      workspaceId: workspaceId,
      displayName: displayName,
      email: email,
      role: role,
    );
  }

  Future<void> deleteUser(String userId) {
    return _deleteUserAndRefresh(userId);
  }

  SecurityRepo get _securityRepo => ref.read(securityRepositoryProvider);
  InputsRepository get _inputsRepo => ref.read(inputsRepositoryProvider);
  PasswordHasher get _hasher => ref.read(passwordHasherProvider);

  Future<void> _deleteUserAndRefresh(String userId) async {
    final current = state.valueOrNull;
    await _securityRepo.deleteUser(userId);
    if (current == null) {
      return;
    }
    final settings = await _inputsRepo.getSettings();
    final context = await _securityRepo.getActiveContext();
    state = AsyncValue.data(
      current.copyWith(settings: settings, context: context),
    );
  }
}
