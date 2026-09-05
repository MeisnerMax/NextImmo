import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/property_media_port.dart';
import '../application/property_repository.dart';
import '../domain/property_media_dto.dart';

/// The seam between the media port and the Supabase SDK.
abstract interface class PropertyMediaSupabaseGateway {
  String? get currentUserId;

  Future<List<Map<String, dynamic>>> listMedia({
    required String workspaceId,
    required String propertyId,
    required bool includeArchived,
  });

  Future<Object?> callRpc(String function, Map<String, Object?> parameters);

  Future<void> uploadObject({
    required String path,
    required String contentType,
    required Uint8List bytes,
  });

  Future<String> createSignedUrl({
    required String path,
    required int ttlSeconds,
  });

  Future<List<Map<String, dynamic>>> listCovers({
    required String workspaceId,
    required List<String> propertyIds,
  });

  /// Path to signed URL, for the paths the service could sign.
  Future<Map<String, String>> createSignedUrls({
    required List<String> paths,
    required int ttlSeconds,
  });
}

class SupabasePropertyMediaGateway implements PropertyMediaSupabaseGateway {
  SupabasePropertyMediaGateway(this._client);

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<List<Map<String, dynamic>>> listMedia({
    required String workspaceId,
    required String propertyId,
    required bool includeArchived,
  }) async {
    var query = _client
        .from('property_media')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('property_id', propertyId);
    if (!includeArchived) {
      // Archiving is the media tombstone: the marker, not the enum, decides
      // what is served, exactly as it does for a property (DEBT-012).
      query = query.isFilter('deleted_at', null);
    }
    final rows = await query
        .order('sort_order', ascending: true)
        .order('id', ascending: true);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<Object?> callRpc(String function, Map<String, Object?> parameters) {
    return _client.rpc(function, params: parameters);
  }

  @override
  Future<void> uploadObject({
    required String path,
    required String contentType,
    required Uint8List bytes,
  }) async {
    await _client.storage
        .from(PropertyMediaPort.bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType),
        );
  }

  @override
  Future<String> createSignedUrl({
    required String path,
    required int ttlSeconds,
  }) {
    return _client.storage
        .from(PropertyMediaPort.bucket)
        .createSignedUrl(path, ttlSeconds);
  }

  @override
  Future<List<Map<String, dynamic>>> listCovers({
    required String workspaceId,
    required List<String> propertyIds,
  }) async {
    final rows = await _client
        .from('property_media')
        .select()
        .eq('workspace_id', workspaceId)
        .inFilter('property_id', propertyIds)
        .eq('is_cover', true)
        .isFilter('deleted_at', null);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<Map<String, String>> createSignedUrls({
    required List<String> paths,
    required int ttlSeconds,
  }) async {
    // The result variant, not the deprecated one: it distinguishes a path that
    // could not be signed from one that simply was not asked for, and a cover
    // whose object is gone must show a placeholder rather than a dead link.
    final signed = await _client.storage
        .from(PropertyMediaPort.bucket)
        .createSignedUrlsResult(paths, ttlSeconds);
    return <String, String>{
      for (final entry in signed)
        if (entry is SignedUrlSuccess) entry.path: entry.signedUrl,
    };
  }
}

/// Supabase-backed property media (`PROPERTY-MEDIA-DATA-01`).
///
/// Uploading is two steps, in this order: bytes to the private bucket, then
/// the RPC that records them. The server verifies an object exists at the
/// declared path before it writes a row, so an upload that fails leaves an
/// orphan object rather than a row pointing at nothing — the harmless
/// direction. The reverse order could not be made safe.
class SupabasePropertyMediaAdapter implements PropertyMediaPort {
  SupabasePropertyMediaAdapter({required SupabaseClient client})
    : _gateway = SupabasePropertyMediaGateway(client);

  SupabasePropertyMediaAdapter.withGateway(this._gateway);

  final PropertyMediaSupabaseGateway _gateway;

  @override
  Future<PropertyRepositoryResult<List<PropertyMediaDto>>> list({
    required String workspaceId,
    required String propertyId,
    bool includeArchived = false,
  }) async {
    try {
      final rows = await _gateway.listMedia(
        workspaceId: workspaceId,
        propertyId: propertyId,
        includeArchived: includeArchived,
      );
      return PropertyRepositorySuccess<List<PropertyMediaDto>>(
        List<PropertyMediaDto>.unmodifiable(rows.map(_parseMedia)),
      );
    } catch (_) {
      return const PropertyRepositoryFailure<List<PropertyMediaDto>>(
        kind: PropertyRepositoryFailureKind.infrastructureFailure,
        message: 'The property media could not be loaded.',
      );
    }
  }

  @override
  Future<PropertyRepositoryResult<PropertyMediaDto>> register(
    RegisterPropertyMediaCommand command,
  ) async {
    if (_gateway.currentUserId != command.context.actorId) {
      return const PropertyRepositoryFailure<PropertyMediaDto>(
        kind: PropertyRepositoryFailureKind.forbidden,
        message: 'The command actor does not match the authenticated user.',
      );
    }
    final upload = command.upload;
    if (!PropertyMediaUpload.acceptedContentTypes.contains(
      upload.contentType,
    )) {
      return const PropertyRepositoryFailure<PropertyMediaDto>(
        kind: PropertyRepositoryFailureKind.validationFailed,
        message: 'Nur JPEG-, PNG- und WebP-Bilder sind zulässig.',
        field: 'contentType',
      );
    }
    if (upload.byteSize <= 0 ||
        upload.byteSize > PropertyMediaUpload.maxByteSize) {
      return const PropertyRepositoryFailure<PropertyMediaDto>(
        kind: PropertyRepositoryFailureKind.validationFailed,
        message: 'Das Bild darf höchstens 20 MB groß sein.',
        field: 'byteSize',
      );
    }

    // The media id is minted here because it is a path segment, and the path
    // has to exist before the row does. The server never sees it as an id: it
    // mints the row's own id and only checks that the path is under this
    // property.
    final path = storageObjectPath(
      workspaceId: command.context.workspaceId,
      propertyId: command.propertyId,
      mediaId: command.context.mutationId,
      fileName: upload.fileName,
    );

    try {
      await _gateway.uploadObject(
        path: path,
        contentType: upload.contentType,
        bytes: upload.bytes,
      );
    } catch (_) {
      return const PropertyRepositoryFailure<PropertyMediaDto>(
        kind: PropertyRepositoryFailureKind.infrastructureFailure,
        message: 'Das Bild konnte nicht hochgeladen werden.',
      );
    }

    return _dispatch('register_property_media', <String, Object?>{
      'p_workspace_id': command.context.workspaceId,
      'p_property_id': command.propertyId,
      'p_mutation_id': command.context.mutationId,
      'p_correlation_id': command.context.correlationId,
      'p_storage_path': path,
      'p_file_name': upload.fileName,
      'p_content_type': upload.contentType,
      'p_byte_size': upload.byteSize,
      'p_kind': command.kind.wireValue,
      'p_title': command.title,
      'p_is_cover': command.isCover,
      'p_reason': command.context.reason,
    });
  }

  @override
  Future<PropertyRepositoryResult<PropertyMediaDto>> update(
    UpdatePropertyMediaCommand command,
  ) async {
    if (_gateway.currentUserId != command.context.actorId) {
      return const PropertyRepositoryFailure<PropertyMediaDto>(
        kind: PropertyRepositoryFailureKind.forbidden,
        message: 'The command actor does not match the authenticated user.',
      );
    }
    return _dispatch('update_property_media', <String, Object?>{
      'p_workspace_id': command.context.workspaceId,
      'p_property_id': command.propertyId,
      'p_media_id': command.mediaId,
      'p_expected_version': command.expectedVersion,
      'p_mutation_id': command.context.mutationId,
      'p_correlation_id': command.context.correlationId,
      'p_title': command.title,
      'p_kind': command.kind?.wireValue,
      'p_sort_order': command.sortOrder,
      'p_is_cover': command.isCover,
      'p_archived': command.archived,
      'p_reason': command.context.reason,
    });
  }

  @override
  Future<PropertyRepositoryResult<String>> signedUrl({
    required String storagePath,
  }) async {
    try {
      final url = await _gateway.createSignedUrl(
        path: storagePath,
        ttlSeconds: PropertyMediaPort.signedUrlTtl.inSeconds,
      );
      return PropertyRepositorySuccess<String>(url);
    } catch (_) {
      return const PropertyRepositoryFailure<String>(
        kind: PropertyRepositoryFailureKind.infrastructureFailure,
        message: 'Das Bild ist derzeit nicht abrufbar.',
      );
    }
  }

  @override
  Future<PropertyRepositoryResult<Map<String, PropertyMediaDto>>> covers({
    required String workspaceId,
    required List<String> propertyIds,
  }) async {
    if (propertyIds.isEmpty) {
      return const PropertyRepositorySuccess<Map<String, PropertyMediaDto>>(
        <String, PropertyMediaDto>{},
      );
    }
    try {
      final rows = await _gateway.listCovers(
        workspaceId: workspaceId,
        propertyIds: propertyIds,
      );
      final covers = <String, PropertyMediaDto>{};
      for (final row in rows) {
        final media = _parseMedia(row);
        covers[media.propertyId] = media;
      }
      return PropertyRepositorySuccess<Map<String, PropertyMediaDto>>(
        Map<String, PropertyMediaDto>.unmodifiable(covers),
      );
    } catch (_) {
      return const PropertyRepositoryFailure<Map<String, PropertyMediaDto>>(
        kind: PropertyRepositoryFailureKind.infrastructureFailure,
        message: 'The property covers could not be loaded.',
      );
    }
  }

  @override
  Future<PropertyRepositoryResult<Map<String, String>>> signedUrls({
    required List<String> storagePaths,
  }) async {
    if (storagePaths.isEmpty) {
      return const PropertyRepositorySuccess<Map<String, String>>(
        <String, String>{},
      );
    }
    try {
      final urls = await _gateway.createSignedUrls(
        paths: storagePaths,
        ttlSeconds: PropertyMediaPort.signedUrlTtl.inSeconds,
      );
      return PropertyRepositorySuccess<Map<String, String>>(
        Map<String, String>.unmodifiable(urls),
      );
    } catch (_) {
      return const PropertyRepositoryFailure<Map<String, String>>(
        kind: PropertyRepositoryFailureKind.infrastructureFailure,
        message: 'Die Bilder sind derzeit nicht abrufbar.',
      );
    }
  }

  Future<PropertyRepositoryResult<PropertyMediaDto>> _dispatch(
    String function,
    Map<String, Object?> parameters,
  ) async {
    try {
      final payload = _asMap(await _gateway.callRpc(function, parameters));
      final ok = payload['ok'];
      if (ok == true) {
        return PropertyRepositorySuccess<PropertyMediaDto>(
          _parseMedia(_asMap(payload['media'])),
        );
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      final error = _asMap(payload['error']);
      final message =
          error['message'] is String
              ? error['message'] as String
              : 'Die Änderung konnte nicht gespeichert werden.';
      return switch (error['code']) {
        'forbidden' => PropertyRepositoryFailure<PropertyMediaDto>(
          kind: PropertyRepositoryFailureKind.forbidden,
          message: message,
        ),
        'not_found' => PropertyRepositoryFailure<PropertyMediaDto>(
          kind: PropertyRepositoryFailureKind.notFound,
          message: message,
        ),
        'validation_failed' => PropertyRepositoryFailure<PropertyMediaDto>(
          kind: PropertyRepositoryFailureKind.validationFailed,
          message: message,
          field: error['field'] is String ? error['field'] as String : null,
        ),
        'mutation_conflict' => PropertyRepositoryFailure<PropertyMediaDto>(
          kind: PropertyRepositoryFailureKind.mutationConflict,
          message: message,
        ),
        'in_progress' => PropertyRepositoryFailure<PropertyMediaDto>(
          kind: PropertyRepositoryFailureKind.mutationInProgress,
          message: message,
        ),
        // The server hands back the current record; it is reported as a
        // conflict so the surface can reload rather than overwrite.
        'version_conflict' => PropertyRepositoryFailure<PropertyMediaDto>(
          kind: PropertyRepositoryFailureKind.dependencyConflict,
          message: message,
        ),
        _ => const PropertyRepositoryFailure<PropertyMediaDto>(
          kind: PropertyRepositoryFailureKind.infrastructureFailure,
          message: 'Die Änderung konnte nicht gespeichert werden.',
        ),
      };
    } catch (_) {
      return const PropertyRepositoryFailure<PropertyMediaDto>(
        kind: PropertyRepositoryFailureKind.infrastructureFailure,
        message: 'Die Änderung konnte nicht gespeichert werden.',
      );
    }
  }
}

PropertyMediaDto _parseMedia(Map<String, dynamic> row) {
  return PropertyMediaDto(
    id: row['id'] as String,
    workspaceId: row['workspace_id'] as String,
    propertyId: row['property_id'] as String,
    storagePath: row['storage_path'] as String,
    fileName: row['file_name'] as String,
    contentType: row['content_type'] as String,
    byteSize: (row['byte_size'] as num).toInt(),
    kind: propertyMediaKindFromWire(row['kind']),
    sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
    isCover: row['is_cover'] == true,
    status:
        row['status'] == 'archived'
            ? PropertyMediaStatus.archived
            : PropertyMediaStatus.active,
    version: (row['version'] as num?)?.toInt() ?? 1,
    title: row['title'] as String?,
  );
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  throw const FormatException('Unexpected payload shape.');
}
