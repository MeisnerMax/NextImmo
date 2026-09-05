import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neximmo_app/features/identity_access/application/workspace_session_scope.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_media_controller.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_media_port.dart';
import 'package:neximmo_app/features/portfolio_property/application/property_repository.dart';
import 'package:neximmo_app/features/portfolio_property/domain/property_media_dto.dart';
import 'package:neximmo_app/features/portfolio_property/presentation/property_media_panel.dart';
import 'package:neximmo_app/ui/theme/app_theme.dart';

/// The media gallery (`PROPERTY-MEDIA-DATA-01`).
///
/// The bucket is private, so a tile renders from a short-lived signed URL. The
/// states worth pinning are the honest ones: a missing URL is a placeholder
/// rather than a broken image, a read-only membership sees pictures but no
/// actions, and archiving is named as archiving rather than as deletion.
void main() {
  testWidgets('renders a tile per image and marks the cover', (tester) async {
    await _pump(tester, <PropertyMediaDto>[
      _media(id: 'media-1', isCover: true, title: 'Vorderansicht'),
      _media(id: 'media-2', kind: PropertyMediaKind.floorPlan),
    ]);

    expect(find.byKey(const Key('property-media-tile-media-1')), findsOneWidget);
    expect(find.byKey(const Key('property-media-tile-media-2')), findsOneWidget);
    expect(find.text('Titelbild'), findsOneWidget);
    expect(find.text('Grundriss'), findsOneWidget);
  });

  testWidgets('a picture without a title shows its file name', (tester) async {
    await _pump(tester, <PropertyMediaDto>[_media(id: 'media-1')]);

    expect(find.text('front.jpg'), findsOneWidget);
  });

  testWidgets('a missing signed url is a placeholder, not a broken image', (
    tester,
  ) async {
    await _pump(
      tester,
      <PropertyMediaDto>[_media(id: 'media-1')],
      signedUrlFails: true,
    );

    expect(
      find.byKey(const Key('property-media-tile-placeholder')),
      findsOneWidget,
    );
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('without property.update there are pictures but no actions', (
    tester,
  ) async {
    await _pump(
      tester,
      <PropertyMediaDto>[_media(id: 'media-1')],
      permissions: const <String>{'property.read'},
    );

    expect(find.byKey(const Key('property-media-tile-media-1')), findsOneWidget);
    expect(find.byKey(const Key('property-media-menu-media-1')), findsNothing);
    final add = tester.widget<FilledButton>(
      find.byKey(const Key('property-media-add')),
    );
    expect(add.onPressed, isNull, reason: 'disabled, not hidden');
  });

  testWidgets('an empty property invites the first upload when permitted', (
    tester,
  ) async {
    await _pump(tester, const <PropertyMediaDto>[]);

    expect(find.byKey(const Key('property-media-empty')), findsOneWidget);
    expect(find.textContaining('Lade das erste Foto'), findsOneWidget);
  });

  testWidgets('a read-only membership sees a different empty sentence', (
    tester,
  ) async {
    await _pump(
      tester,
      const <PropertyMediaDto>[],
      permissions: const <String>{'property.read'},
    );

    expect(find.textContaining('keine Bilder hinterlegt'), findsOneWidget);
  });

  testWidgets('a failed read offers a retry', (tester) async {
    await _pump(
      tester,
      const <PropertyMediaDto>[],
      failure: PropertyRepositoryFailureKind.infrastructureFailure,
    );

    expect(find.byKey(const Key('property-media-error')), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
  });

  testWidgets('setting the cover goes through the contract', (tester) async {
    final port = _FakePort(<PropertyMediaDto>[_media(id: 'media-1')]);
    await _pumpPort(tester, port);

    await tester.tap(find.byKey(const Key('property-media-menu-media-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Als Titelbild setzen'));
    await tester.pumpAndSettle();

    expect(port.updates.single.isCover, isTrue);
    expect(port.updates.single.mediaId, 'media-1');
  });

  testWidgets('archiving is confirmed, and says the file is kept', (
    tester,
  ) async {
    final port = _FakePort(<PropertyMediaDto>[_media(id: 'media-1')]);
    await _pumpPort(tester, port);

    await tester.tap(find.byKey(const Key('property-media-menu-media-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archivieren'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('property-media-archive-dialog')),
      findsOneWidget,
    );
    expect(find.textContaining('nicht gelöscht'), findsOneWidget);
    expect(port.updates, isEmpty, reason: 'nothing happens before the answer');

    await tester.tap(find.byKey(const Key('property-media-archive-confirm')));
    await tester.pumpAndSettle();
    expect(port.updates.single.archived, isTrue);
  });

  testWidgets('a title can be cleared back to the file name', (tester) async {
    final port = _FakePort(<PropertyMediaDto>[
      _media(id: 'media-1', title: 'Alt'),
    ]);
    await _pumpPort(tester, port);

    await tester.tap(find.byKey(const Key('property-media-menu-media-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Titel bearbeiten'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('property-media-title-input')),
      '',
    );
    await tester.tap(find.byKey(const Key('property-media-title-save')));
    await tester.pumpAndSettle();

    expect(port.updates.single.title, '');
  });

  for (final size in const <Size>[Size(390, 844), Size(1400, 900)]) {
    testWidgets('lays out without overflow at $size', (tester) async {
      await _pump(tester, <PropertyMediaDto>[
        _media(id: 'media-1', isCover: true),
        _media(id: 'media-2'),
        _media(id: 'media-3'),
      ], size: size);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('property-media-gallery')), findsOneWidget);
    });
  }
}

PropertyMediaDto _media({
  required String id,
  bool isCover = false,
  String? title,
  PropertyMediaKind kind = PropertyMediaKind.photo,
}) {
  return PropertyMediaDto(
    id: id,
    workspaceId: 'workspace-a',
    propertyId: 'property-a',
    storagePath: 'workspace-a/property-a/$id/front.jpg',
    fileName: 'front.jpg',
    contentType: 'image/jpeg',
    byteSize: 2048,
    kind: kind,
    sortOrder: 0,
    isCover: isCover,
    status: PropertyMediaStatus.active,
    version: 1,
    title: title,
  );
}

Future<void> _pump(
  WidgetTester tester,
  List<PropertyMediaDto> media, {
  Set<String> permissions = const <String>{'property.read', 'property.update'},
  PropertyRepositoryFailureKind? failure,
  bool signedUrlFails = false,
  Size size = const Size(1400, 900),
}) {
  return _pumpPort(
    tester,
    _FakePort(media, failure: failure, signedUrlFails: signedUrlFails),
    permissions: permissions,
    size: size,
  );
}

Future<void> _pumpPort(
  WidgetTester tester,
  _FakePort port, {
  Set<String> permissions = const <String>{'property.read', 'property.update'},
  Size size = const Size(1400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        workspaceSessionScopeProvider.overrideWithValue(
          WorkspaceSessionScope(
            workspaceId: 'workspace-a',
            actorId: 'actor-1',
            permissions: permissions,
            mutationsSupported: true,
          ),
        ),
        propertyMediaPortProvider.overrideWithValue(port),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: PropertyMediaPanel(propertyId: 'property-a'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakePort implements PropertyMediaPort {
  _FakePort(this.media, {this.failure, this.signedUrlFails = false});

  List<PropertyMediaDto> media;
  final PropertyRepositoryFailureKind? failure;
  final bool signedUrlFails;
  final List<UpdatePropertyMediaCommand> updates =
      <UpdatePropertyMediaCommand>[];

  @override
  Future<PropertyRepositoryResult<List<PropertyMediaDto>>> list({
    required String workspaceId,
    required String propertyId,
    bool includeArchived = false,
  }) async {
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
  ) async => PropertyRepositorySuccess<PropertyMediaDto>(media.first);

  @override
  Future<PropertyRepositoryResult<PropertyMediaDto>> update(
    UpdatePropertyMediaCommand command,
  ) async {
    updates.add(command);
    return PropertyRepositorySuccess<PropertyMediaDto>(media.first);
  }

  @override
  Future<PropertyRepositoryResult<String>> signedUrl({
    required String storagePath,
  }) async {
    if (signedUrlFails) {
      return const PropertyRepositoryFailure<String>(
        kind: PropertyRepositoryFailureKind.infrastructureFailure,
        message: 'fail',
      );
    }
    return const PropertyRepositorySuccess<String>('https://example.test/x');
  }
}
