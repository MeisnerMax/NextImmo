/// Property media (`PROPERTY-MEDIA-DATA-01`): a photo or plan of a building.
///
/// The bytes live in a private bucket; this is the metadata and the authority
/// on what is shown. A [PropertyMediaDto] therefore carries a *path*, never a
/// URL — a URL for a private object is a short-lived credential, and one
/// stored in a DTO would outlive its own validity and invite being logged.
library;

import 'dart:typed_data';

enum PropertyMediaKind { photo, floorPlan, sitePlan, exterior, interior }

extension PropertyMediaKindWire on PropertyMediaKind {
  String get wireValue => switch (this) {
    PropertyMediaKind.photo => 'photo',
    PropertyMediaKind.floorPlan => 'floor_plan',
    PropertyMediaKind.sitePlan => 'site_plan',
    PropertyMediaKind.exterior => 'exterior',
    PropertyMediaKind.interior => 'interior',
  };

  /// German product label (Foundation §19).
  String get label => switch (this) {
    PropertyMediaKind.photo => 'Foto',
    PropertyMediaKind.floorPlan => 'Grundriss',
    PropertyMediaKind.sitePlan => 'Lageplan',
    PropertyMediaKind.exterior => 'Außenansicht',
    PropertyMediaKind.interior => 'Innenansicht',
  };
}

PropertyMediaKind propertyMediaKindFromWire(Object? value) {
  return switch (value) {
    'floor_plan' => PropertyMediaKind.floorPlan,
    'site_plan' => PropertyMediaKind.sitePlan,
    'exterior' => PropertyMediaKind.exterior,
    'interior' => PropertyMediaKind.interior,
    _ => PropertyMediaKind.photo,
  };
}

enum PropertyMediaStatus { active, archived }

class PropertyMediaDto {
  const PropertyMediaDto({
    required this.id,
    required this.workspaceId,
    required this.propertyId,
    required this.storagePath,
    required this.fileName,
    required this.contentType,
    required this.byteSize,
    required this.kind,
    required this.sortOrder,
    required this.isCover,
    required this.status,
    required this.version,
    this.title,
  });

  final String id;
  final String workspaceId;
  final String propertyId;

  /// `{workspace}/{property}/{media}/{filename}` in the private bucket. Not a
  /// URL: see the library note.
  final String storagePath;

  final String fileName;
  final String contentType;
  final int byteSize;
  final PropertyMediaKind kind;
  final int sortOrder;

  /// The one image that represents the property. The database enforces that
  /// there is at most one per property; the client never has to reconcile two.
  final bool isCover;

  final PropertyMediaStatus status;
  final int version;
  final String? title;

  /// What to show under the image: the operator's own caption where there is
  /// one, otherwise the file name. Never an empty line.
  String get displayTitle {
    final trimmed = title?.trim() ?? '';
    return trimmed.isEmpty ? fileName : trimmed;
  }
}

/// A file chosen for upload, with the parts the contract needs. Deliberately
/// not a `dart:io` File: the web build has none.
class PropertyMediaUpload {
  const PropertyMediaUpload({
    required this.fileName,
    required this.contentType,
    required this.bytes,
  });

  /// The image types the bucket accepts. Checked client-side to fail fast with
  /// a sentence a user can act on, never as the authority — the table's own
  /// constraint decides.
  static const Set<String> acceptedContentTypes = <String>{
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  /// Mirrors the bucket's `file_size_limit`, for the same reason.
  static const int maxByteSize = 20971520;

  final String fileName;
  final String contentType;
  final Uint8List bytes;

  int get byteSize => bytes.length;
}
