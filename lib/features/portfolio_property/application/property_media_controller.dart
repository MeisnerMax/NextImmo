/// Screen-facing orchestration for a property's media (`PROPERTY-MEDIA-DATA-01`).
///
/// One list, plus the short-lived signed URLs the gallery needs to render it.
/// The URLs are held here and never in the DTO: for a private object a URL is
/// a credential with a five-minute life, and one carried in a domain object
/// would outlive its own validity and invite being persisted or logged.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/property_media_dto.dart';
import 'property_media_port.dart';
import 'property_repository.dart';

const Object _unchanged = Object();

enum PropertyMediaPhase { idle, loading, ready, empty, forbidden, error }

enum PropertyMediaActionPhase { idle, submitting, succeeded, failed }

class PropertyMediaState {
  const PropertyMediaState({
    this.phase = PropertyMediaPhase.idle,
    this.media = const <PropertyMediaDto>[],
    this.signedUrls = const <String, String>{},
    this.message,
    this.actionPhase = PropertyMediaActionPhase.idle,
    this.actionMessage,
  });

  final PropertyMediaPhase phase;
  final List<PropertyMediaDto> media;

  /// Media id to signed URL. Absent means "not fetched or expired", which the
  /// gallery renders as a placeholder rather than a broken image.
  final Map<String, String> signedUrls;

  final String? message;
  final PropertyMediaActionPhase actionPhase;
  final String? actionMessage;

  PropertyMediaDto? get cover {
    for (final item in media) {
      if (item.isCover) {
        return item;
      }
    }
    return null;
  }

  PropertyMediaState copyWith({
    PropertyMediaPhase? phase,
    List<PropertyMediaDto>? media,
    Map<String, String>? signedUrls,
    Object? message = _unchanged,
    PropertyMediaActionPhase? actionPhase,
    Object? actionMessage = _unchanged,
  }) {
    return PropertyMediaState(
      phase: phase ?? this.phase,
      media: media ?? this.media,
      signedUrls: signedUrls ?? this.signedUrls,
      message:
          identical(message, _unchanged) ? this.message : message as String?,
      actionPhase: actionPhase ?? this.actionPhase,
      actionMessage:
          identical(actionMessage, _unchanged)
              ? this.actionMessage
              : actionMessage as String?,
    );
  }
}

typedef PropertyMediaIdFactory = String Function();

class PropertyMediaController extends StateNotifier<PropertyMediaState> {
  PropertyMediaController({
    required this.propertyId,
    required PropertyMediaPort port,
    required WorkspaceSessionScope scope,
    PropertyMediaIdFactory? idFactory,
  }) : _port = port,
       _scope = scope,
       _idFactory = idFactory ?? const Uuid().v4,
       super(const PropertyMediaState());

  static const String readPermission = 'property.read';
  static const String managePermission = 'property.update';

  final String propertyId;
  final PropertyMediaPort _port;
  final WorkspaceSessionScope _scope;
  final PropertyMediaIdFactory _idFactory;

  int _generation = 0;

  bool get canManage =>
      _scope.mutationsSupported &&
      _scope.permissions.contains(managePermission);

  Future<void> load() async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null) {
      return;
    }
    if (!_scope.permissions.contains(readPermission)) {
      state = state.copyWith(
        phase: PropertyMediaPhase.forbidden,
        media: const <PropertyMediaDto>[],
      );
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(phase: PropertyMediaPhase.loading, message: null);
    final result = await _port.list(
      workspaceId: workspaceId,
      propertyId: propertyId,
    );
    if (generation != _generation) {
      return;
    }
    switch (result) {
      case PropertyRepositorySuccess<List<PropertyMediaDto>>(:final value):
        state = state.copyWith(
          phase:
              value.isEmpty
                  ? PropertyMediaPhase.empty
                  : PropertyMediaPhase.ready,
          media: value,
          // A reload invalidates the previous URLs along with the rows they
          // belonged to; holding one for a row that is gone would show a
          // picture the list no longer claims.
          signedUrls: const <String, String>{},
        );
        await _refreshSignedUrls(generation);
      case PropertyRepositoryFailure<List<PropertyMediaDto>>(
        :final kind,
        :final message,
      ):
        state = state.copyWith(
          phase:
              kind == PropertyRepositoryFailureKind.forbidden
                  ? PropertyMediaPhase.forbidden
                  : PropertyMediaPhase.error,
          media: const <PropertyMediaDto>[],
          signedUrls: const <String, String>{},
          message: message,
        );
    }
  }

  Future<void> _refreshSignedUrls(int generation) async {
    final urls = <String, String>{};
    for (final item in state.media) {
      final result = await _port.signedUrl(storagePath: item.storagePath);
      if (generation != _generation) {
        return;
      }
      if (result case PropertyRepositorySuccess<String>(:final value)) {
        urls[item.id] = value;
      }
      // A failed URL is simply absent: the tile shows a placeholder and the
      // rest of the gallery still renders.
    }
    if (generation != _generation) {
      return;
    }
    state = state.copyWith(signedUrls: Map<String, String>.unmodifiable(urls));
  }

  Future<void> upload(
    PropertyMediaUpload upload, {
    PropertyMediaKind kind = PropertyMediaKind.photo,
    String? title,
    bool asCover = false,
  }) async {
    if (!await _guard()) {
      return;
    }
    final result = await _port.register(
      RegisterPropertyMediaCommand(
        context: _commandContext(),
        propertyId: propertyId,
        upload: upload,
        kind: kind,
        title: title,
        isCover: asCover,
      ),
    );
    await _settle(result, 'Bild hinzugefügt.');
  }

  Future<void> rename(PropertyMediaDto media, String title) =>
      _mutate(media, title: title, success: 'Bildtitel gespeichert.');

  Future<void> changeKind(PropertyMediaDto media, PropertyMediaKind kind) =>
      _mutate(media, kind: kind, success: 'Bildart gespeichert.');

  Future<void> makeCover(PropertyMediaDto media) =>
      _mutate(media, isCover: true, success: 'Titelbild gesetzt.');

  /// Archiving is the only removal: the bytes are immutable by policy, so an
  /// image leaves the gallery by ceasing to be served, not by being deleted.
  Future<void> archive(PropertyMediaDto media) =>
      _mutate(media, archived: true, success: 'Bild archiviert.');

  Future<void> _mutate(
    PropertyMediaDto media, {
    String? title,
    PropertyMediaKind? kind,
    bool? isCover,
    bool? archived,
    required String success,
  }) async {
    if (!await _guard()) {
      return;
    }
    final result = await _port.update(
      UpdatePropertyMediaCommand(
        context: _commandContext(),
        propertyId: propertyId,
        mediaId: media.id,
        expectedVersion: media.version,
        title: title,
        kind: kind,
        isCover: isCover,
        archived: archived,
      ),
    );
    await _settle(result, success);
  }

  Future<bool> _guard() async {
    if (!canManage) {
      state = state.copyWith(
        actionPhase: PropertyMediaActionPhase.failed,
        actionMessage:
            'Benötigt die Berechtigung (property.update) und eine '
            'MFA-bestätigte Sitzung (AAL2).',
      );
      return false;
    }
    if (_scope.workspaceId == null || _scope.actorId == null) {
      return false;
    }
    state = state.copyWith(
      actionPhase: PropertyMediaActionPhase.submitting,
      actionMessage: null,
    );
    return true;
  }

  Future<void> _settle(
    PropertyRepositoryResult<PropertyMediaDto> result,
    String success,
  ) async {
    switch (result) {
      case PropertyRepositorySuccess<PropertyMediaDto>():
        state = state.copyWith(
          actionPhase: PropertyMediaActionPhase.succeeded,
          actionMessage: success,
        );
        // The canonical list is the authority on order and on which image is
        // the cover; one mutation can move both.
        await load();
      case PropertyRepositoryFailure<PropertyMediaDto>(:final message):
        state = state.copyWith(
          actionPhase: PropertyMediaActionPhase.failed,
          actionMessage: message,
        );
    }
  }

  void clearAction() {
    state = state.copyWith(
      actionPhase: PropertyMediaActionPhase.idle,
      actionMessage: null,
    );
  }

  PropertyCreateContext _commandContext() {
    return PropertyCreateContext(
      workspaceId: _scope.workspaceId!,
      actorId: _scope.actorId!,
      mutationId: _idFactory(),
      correlationId: _idFactory(),
    );
  }
}

final propertyMediaPortProvider = Provider<PropertyMediaPort>(
  (ref) => throw StateError('PropertyMediaPort is not configured.'),
);

final propertyMediaControllerProvider = StateNotifierProvider.autoDispose
    .family<PropertyMediaController, PropertyMediaState, String>((
      ref,
      propertyId,
    ) {
      final controller = PropertyMediaController(
        propertyId: propertyId,
        port: ref.watch(propertyMediaPortProvider),
        scope: ref.watch(workspaceSessionScopeProvider),
      );
      controller.load();
      return controller;
    });
