import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_media_controller.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_media_port.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/data/supabase_property_media_adapter.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_media_dto.dart';

/// PROPERTY-MEDIA-DATA-01 on the client.
///
/// The order of the two upload steps is the security-relevant part: bytes
/// first, then the row. The server refuses a row whose object does not exist,
/// so a failed upload leaves an orphan object — the harmless direction. A
/// client that registered first could publish a record pointing at nothing, or
/// at somebody else's bytes.
void main() {
  group('SupabasePropertyMediaAdapter', () {
    late _FakeGateway gateway;
    late SupabasePropertyMediaAdapter adapter;

    setUp(() {
      gateway = _FakeGateway();
      adapter = SupabasePropertyMediaAdapter.withGateway(gateway);
    });

    test('uploads the bytes before it registers the row', () async {
      gateway.rpcResult = _mediaPayload();

      final result = await adapter.register(_command());

      expect(gateway.calls, <String>[
        'upload',
        'rpc',
      ], reason: 'a row may never precede the object it points at');
      expect(result, isA<PropertyRepositorySuccess<PropertyMediaDto>>());
    });

    test('the path is under this workspace and this property', () async {
      gateway.rpcResult = _mediaPayload();

      await adapter.register(_command());

      expect(
        gateway.uploadedPath,
        startsWith('workspace-a/property-a/'),
        reason: 'the server rejects anything else, and the policy too',
      );
      expect(gateway.parameters?['p_storage_path'], gateway.uploadedPath);
    });

    test('a file name is reduced to path-safe characters, and the original '
        'is kept', () async {
      gateway.rpcResult = _mediaPayload();

      await adapter.register(
        _command(fileName: 'Vorderansicht Süd (2026).jpg'),
      );

      expect(gateway.uploadedPath, isNot(contains(' ')));
      expect(gateway.uploadedPath, isNot(contains('(')));
      expect(
        gateway.parameters?['p_file_name'],
        'Vorderansicht Süd (2026).jpg',
        reason: 'the row keeps what the user recognises',
      );
    });

    test('a non-image is refused before anything is uploaded', () async {
      final result = await adapter.register(
        _command(contentType: 'application/pdf'),
      );

      expect(
        (result as PropertyRepositoryFailure<PropertyMediaDto>).kind,
        PropertyRepositoryFailureKind.validationFailed,
      );
      expect(result.field, 'contentType');
      expect(gateway.calls, isEmpty);
    });

    test('an oversized image is refused before anything is uploaded', () async {
      final result = await adapter.register(
        _command(bytes: Uint8List(PropertyMediaUpload.maxByteSize + 1)),
      );

      expect(
        (result as PropertyRepositoryFailure<PropertyMediaDto>).field,
        'byteSize',
      );
      expect(gateway.calls, isEmpty);
    });

    test('a failed upload never registers a row', () async {
      gateway.uploadError = StateError('offline');

      final result = await adapter.register(_command());

      expect(
        (result as PropertyRepositoryFailure<PropertyMediaDto>).kind,
        PropertyRepositoryFailureKind.infrastructureFailure,
      );
      expect(gateway.calls, <String>['upload']);
    });

    test('a command from another actor is refused', () async {
      gateway.currentUserId = 'someone-else';

      final result = await adapter.register(_command());

      expect(
        (result as PropertyRepositoryFailure<PropertyMediaDto>).kind,
        PropertyRepositoryFailureKind.forbidden,
      );
      expect(gateway.calls, isEmpty);
    });

    test('maps the canonical row the server wrote back', () async {
      gateway.rpcResult = _mediaPayload(isCover: true, kind: 'floor_plan');

      final media =
          (await adapter.register(_command())
                  as PropertyRepositorySuccess<PropertyMediaDto>)
              .value;

      expect(media.kind, PropertyMediaKind.floorPlan);
      expect(media.isCover, isTrue);
      expect(media.status, PropertyMediaStatus.active);
      expect(media.version, 1);
    });

    test('a version conflict is reported as one, not swallowed', () async {
      gateway.rpcResult = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'version_conflict',
          'message': 'Media was changed by someone else',
        },
      };

      final result = await adapter.update(
        UpdatePropertyMediaCommand(
          context: _context(),
          propertyId: 'property-a',
          mediaId: 'media-1',
          expectedVersion: 1,
          title: 'Neu',
        ),
      );

      expect(
        (result as PropertyRepositoryFailure<PropertyMediaDto>).kind,
        PropertyRepositoryFailureKind.dependencyConflict,
      );
    });

    test('the signed url is asked for with the agreed lifetime', () async {
      gateway.signedUrl = 'https://example.test/signed';

      final result = await adapter.signedUrl(storagePath: 'w/p/m/f.jpg');

      expect(
        (result as PropertyRepositorySuccess<String>).value,
        'https://example.test/signed',
      );
      expect(
        gateway.signedTtlSeconds,
        PropertyMediaPort.signedUrlTtl.inSeconds,
      );
    });

    test('covers are read for a whole page in one query', () async {
      gateway.rows = <Map<String, dynamic>>[_mediaRow(isCover: true)];

      final covers =
          (await adapter.covers(
                    workspaceId: 'workspace-a',
                    propertyIds: <String>['property-a', 'property-b'],
                  )
                  as PropertyRepositorySuccess<Map<String, PropertyMediaDto>>)
              .value;

      expect(
        gateway.coveredPropertyIds,
        <String>['property-a', 'property-b'],
        reason: 'one query for the page, never one per row',
      );
      expect(covers.keys, <String>['property-a']);
      expect(
        covers['property-a']!.isCover,
        isTrue,
        reason: 'a property without a cover is simply absent',
      );
    });

    test('an empty page asks nothing', () async {
      final covers = await adapter.covers(
        workspaceId: 'workspace-a',
        propertyIds: const <String>[],
      );

      expect(
        covers,
        isA<PropertyRepositorySuccess<Map<String, PropertyMediaDto>>>(),
      );
      expect(gateway.coveredPropertyIds, isNull);
    });

    test(
      'several paths are signed in one call, with the agreed lifetime',
      () async {
        final urls =
            (await adapter.signedUrls(
                      storagePaths: <String>['w/p/a/x.jpg', 'w/p/b/y.jpg'],
                    )
                    as PropertyRepositorySuccess<Map<String, String>>)
                .value;

        expect(gateway.batchSignedPaths, hasLength(2));
        expect(
          gateway.signedTtlSeconds,
          PropertyMediaPort.signedUrlTtl.inSeconds,
        );
        expect(urls, hasLength(2));
      },
    );

    test('the list excludes archived images by default', () async {
      gateway.rows = <Map<String, dynamic>>[_mediaRow()];

      await adapter.list(workspaceId: 'workspace-a', propertyId: 'property-a');

      expect(gateway.listedIncludeArchived, isFalse);
    });
  });

  group('PropertyMediaController', () {
    test(
      'without property.update the actions are refused with the reason',
      () async {
        final port = _FakePort();
        final controller = _controller(
          port,
          permissions: const <String>{'property.read'},
        );
        await controller.load();

        await controller.makeCover(_media());

        expect(controller.state.actionPhase, PropertyMediaActionPhase.failed);
        expect(controller.state.actionMessage, contains('property.update'));
        expect(port.updates, isEmpty);
      },
    );

    test(
      'a signed url is fetched per image and held outside the DTO',
      () async {
        final port = _FakePort()..media = <PropertyMediaDto>[_media()];
        final controller = _controller(port);

        await controller.load();

        expect(controller.state.phase, PropertyMediaPhase.ready);
        expect(controller.state.signedUrls['media-1'], isNotNull);
        expect(port.signedPaths, <String>[
          'workspace-a/property-a/m1/front.jpg',
        ]);
      },
    );

    test('an image whose url fails still leaves the gallery usable', () async {
      final port =
          _FakePort()
            ..media = <PropertyMediaDto>[_media()]
            ..signedUrlFails = true;
      final controller = _controller(port);

      await controller.load();

      expect(controller.state.phase, PropertyMediaPhase.ready);
      expect(controller.state.signedUrls, isEmpty);
    });

    test('a mutation reloads the canonical list, because one change can move '
        'the cover', () async {
      final port = _FakePort()..media = <PropertyMediaDto>[_media()];
      final controller = _controller(port);
      await controller.load();
      final listsBefore = port.lists;

      await controller.makeCover(_media());

      expect(port.updates.single.isCover, isTrue);
      expect(port.updates.single.expectedVersion, 1);
      expect(port.lists, greaterThan(listsBefore));
      expect(controller.state.actionPhase, PropertyMediaActionPhase.succeeded);
    });

    test('archiving is an update, never a delete', () async {
      final port = _FakePort()..media = <PropertyMediaDto>[_media()];
      final controller = _controller(port);
      await controller.load();

      await controller.archive(_media());

      expect(port.updates.single.archived, isTrue);
    });

    test('an empty property says so rather than failing', () async {
      final port = _FakePort();
      final controller = _controller(port);

      await controller.load();

      expect(controller.state.phase, PropertyMediaPhase.empty);
    });

    test('a forbidden read clears whatever was on screen', () async {
      final port = _FakePort()..media = <PropertyMediaDto>[_media()];
      final controller = _controller(port);
      await controller.load();

      port.failure = PropertyRepositoryFailureKind.forbidden;
      await controller.load();

      expect(controller.state.phase, PropertyMediaPhase.forbidden);
      expect(controller.state.media, isEmpty);
      expect(controller.state.signedUrls, isEmpty);
    });
  });
}

PropertyMediaController _controller(
  _FakePort port, {
  Set<String> permissions = const <String>{'property.read', 'property.update'},
}) {
  var counter = 0;
  return PropertyMediaController(
    propertyId: 'property-a',
    port: port,
    scope: WorkspaceSessionScope(
      workspaceId: 'workspace-a',
      actorId: 'actor-1',
      permissions: permissions,
      mutationsSupported: true,
    ),
    idFactory: () => 'id-${++counter}',
  );
}

PropertyMediaDto _media() => const PropertyMediaDto(
  id: 'media-1',
  workspaceId: 'workspace-a',
  propertyId: 'property-a',
  storagePath: 'workspace-a/property-a/m1/front.jpg',
  fileName: 'front.jpg',
  contentType: 'image/jpeg',
  byteSize: 1024,
  kind: PropertyMediaKind.photo,
  sortOrder: 0,
  isCover: false,
  status: PropertyMediaStatus.active,
  version: 1,
);

PropertyCreateContext _context() => const PropertyCreateContext(
  workspaceId: 'workspace-a',
  actorId: 'actor-1',
  mutationId: 'mutation-1',
  correlationId: 'correlation-1',
);

RegisterPropertyMediaCommand _command({
  String fileName = 'front.jpg',
  String contentType = 'image/jpeg',
  Uint8List? bytes,
}) {
  return RegisterPropertyMediaCommand(
    context: _context(),
    propertyId: 'property-a',
    upload: PropertyMediaUpload(
      fileName: fileName,
      contentType: contentType,
      bytes: bytes ?? Uint8List.fromList(<int>[1, 2, 3]),
    ),
  );
}

Map<String, dynamic> _mediaRow({bool isCover = false, String kind = 'photo'}) {
  return <String, dynamic>{
    'id': 'media-1',
    'workspace_id': 'workspace-a',
    'property_id': 'property-a',
    'storage_path': 'workspace-a/property-a/m1/front.jpg',
    'file_name': 'front.jpg',
    'content_type': 'image/jpeg',
    'byte_size': 1024,
    'kind': kind,
    'title': null,
    'sort_order': 0,
    'is_cover': isCover,
    'status': 'active',
    'version': 1,
  };
}

Map<String, Object?> _mediaPayload({
  bool isCover = false,
  String kind = 'photo',
}) {
  return <String, Object?>{
    'ok': true,
    'media': _mediaRow(isCover: isCover, kind: kind),
  };
}

class _FakeGateway implements PropertyMediaSupabaseGateway {
  @override
  String? currentUserId = 'actor-1';

  final List<String> calls = <String>[];
  List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];
  Object? rpcResult;
  Object? uploadError;
  String? uploadedPath;
  Map<String, Object?>? parameters;
  String signedUrl = 'https://example.test/signed';
  int? signedTtlSeconds;
  bool? listedIncludeArchived;
  List<String>? coveredPropertyIds;
  List<String>? batchSignedPaths;

  @override
  Future<List<Map<String, dynamic>>> listMedia({
    required String workspaceId,
    required String propertyId,
    required bool includeArchived,
  }) async {
    listedIncludeArchived = includeArchived;
    return rows;
  }

  @override
  Future<Object?> callRpc(String function, Map<String, Object?> params) async {
    calls.add('rpc');
    parameters = params;
    return rpcResult;
  }

  @override
  Future<void> uploadObject({
    required String path,
    required String contentType,
    required Uint8List bytes,
  }) async {
    calls.add('upload');
    uploadedPath = path;
    if (uploadError != null) {
      throw uploadError!;
    }
  }

  @override
  Future<String> createSignedUrl({
    required String path,
    required int ttlSeconds,
  }) async {
    signedTtlSeconds = ttlSeconds;
    return signedUrl;
  }

  @override
  Future<List<Map<String, dynamic>>> listCovers({
    required String workspaceId,
    required List<String> propertyIds,
  }) async {
    coveredPropertyIds = propertyIds;
    return rows;
  }

  @override
  Future<Map<String, String>> createSignedUrls({
    required List<String> paths,
    required int ttlSeconds,
  }) async {
    batchSignedPaths = paths;
    signedTtlSeconds = ttlSeconds;
    return <String, String>{for (final path in paths) path: signedUrl};
  }
}

class _FakePort implements PropertyMediaPort {
  List<PropertyMediaDto> media = <PropertyMediaDto>[];
  PropertyRepositoryFailureKind? failure;
  bool signedUrlFails = false;
  int lists = 0;
  final List<String> signedPaths = <String>[];
  final List<UpdatePropertyMediaCommand> updates =
      <UpdatePropertyMediaCommand>[];

  @override
  Future<PropertyRepositoryResult<List<PropertyMediaDto>>> list({
    required String workspaceId,
    required String propertyId,
    bool includeArchived = false,
  }) async {
    lists++;
    final failure = this.failure;
    if (failure != null) {
      return PropertyRepositoryFailure<List<PropertyMediaDto>>(
        kind: failure,
        message: 'fail',
      );
    }
    return PropertyRepositorySuccess<List<PropertyMediaDto>>(media);
  }

  @override
  Future<PropertyRepositoryResult<PropertyMediaDto>> register(
    RegisterPropertyMediaCommand command,
  ) async => PropertyRepositorySuccess<PropertyMediaDto>(_media());

  @override
  Future<PropertyRepositoryResult<PropertyMediaDto>> update(
    UpdatePropertyMediaCommand command,
  ) async {
    updates.add(command);
    return PropertyRepositorySuccess<PropertyMediaDto>(_media());
  }

  @override
  Future<PropertyRepositoryResult<String>> signedUrl({
    required String storagePath,
  }) async {
    signedPaths.add(storagePath);
    if (signedUrlFails) {
      return const PropertyRepositoryFailure<String>(
        kind: PropertyRepositoryFailureKind.infrastructureFailure,
        message: 'fail',
      );
    }
    return const PropertyRepositorySuccess<String>('https://example.test/x');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used by this test');
}
