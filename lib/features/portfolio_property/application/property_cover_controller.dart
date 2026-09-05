/// Cover images for a page of the property list (`PROPERTY-MEDIA-DATA-01`).
///
/// One read for a whole page, never one per row. A list that fires a query per
/// visible property turns a scroll into a thundering herd, and the picture it
/// would show is the same either way.
///
/// The signed URLs live here rather than in the list state, for the same
/// reason they are absent from the media DTO: a URL for a private object is a
/// five-minute credential, and one carried alongside domain data invites being
/// persisted, restored or logged.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../identity_access/application/workspace_session_scope.dart';
import '../domain/property_media_dto.dart';
import 'property_media_controller.dart';
import 'property_media_port.dart';
import 'property_repository.dart';

class PropertyCoverState {
  const PropertyCoverState({this.urls = const <String, String>{}});

  /// Property id to a signed URL for its cover. A property that has no cover,
  /// or whose link could not be issued, is simply absent — the row then shows
  /// a neutral placeholder rather than a broken image.
  final Map<String, String> urls;
}

class PropertyCoverController extends StateNotifier<PropertyCoverState> {
  PropertyCoverController({
    required PropertyMediaPort port,
    required WorkspaceSessionScope scope,
  }) : _port = port,
       _scope = scope,
       super(const PropertyCoverState());

  final PropertyMediaPort _port;
  final WorkspaceSessionScope _scope;

  /// Property ids already asked for, so a rebuild does not re-ask. Cleared
  /// only by a new controller, which a workspace switch produces.
  final Set<String> _requested = <String>{};
  bool _loading = false;

  /// Loads the covers of any [propertyIds] not fetched yet, in one round trip.
  Future<void> ensure(List<String> propertyIds) async {
    final workspaceId = _scope.workspaceId;
    if (workspaceId == null || _loading) {
      return;
    }
    final missing =
        propertyIds.where((id) => !_requested.contains(id)).toList();
    if (missing.isEmpty) {
      return;
    }
    _loading = true;
    _requested.addAll(missing);
    try {
      final covers = await _port.covers(
        workspaceId: workspaceId,
        propertyIds: missing,
      );
      if (covers is! PropertyRepositorySuccess<Map<String, PropertyMediaDto>>) {
        return;
      }
      if (covers.value.isEmpty) {
        return;
      }
      final byPath = <String, String>{
        for (final entry in covers.value.entries)
          entry.value.storagePath: entry.key,
      };
      final signed = await _port.signedUrls(storagePaths: byPath.keys.toList());
      if (signed is! PropertyRepositorySuccess<Map<String, String>>) {
        return;
      }
      if (!mounted) {
        return;
      }
      state = PropertyCoverState(
        urls: Map<String, String>.unmodifiable(<String, String>{
          ...state.urls,
          for (final entry in signed.value.entries)
            if (byPath[entry.key] != null) byPath[entry.key]!: entry.value,
        }),
      );
    } finally {
      _loading = false;
    }
  }
}

final propertyCoverControllerProvider = StateNotifierProvider.autoDispose
    .family<PropertyCoverController, PropertyCoverState, String>((
      ref,
      workspaceId,
    ) {
      return PropertyCoverController(
        port: ref.watch(propertyMediaPortProvider),
        scope: ref.watch(workspaceSessionScopeProvider),
      );
    });
