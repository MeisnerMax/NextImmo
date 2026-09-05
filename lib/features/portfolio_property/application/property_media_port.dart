import '../domain/property_media_dto.dart';
import 'property_repository.dart';

/// Registers an uploaded image against a property (`PROPERTY-MEDIA-DATA-01`).
class RegisterPropertyMediaCommand {
  const RegisterPropertyMediaCommand({
    required this.context,
    required this.propertyId,
    required this.upload,
    this.kind = PropertyMediaKind.photo,
    this.title,
    this.isCover = false,
  });

  final PropertyCreateContext context;
  final String propertyId;
  final PropertyMediaUpload upload;
  final PropertyMediaKind kind;
  final String? title;

  /// Ask for the cover explicitly. The server makes the first image of a
  /// property its cover anyway, so this is for "make *this* one the cover".
  final bool isCover;
}

/// Edits an image's presentation, or archives it.
///
/// There is no delete. Archiving stops the image being served and keeps the
/// record auditable; the bytes are immutable by policy and are reclaimed by an
/// operations job, not by a client.
class UpdatePropertyMediaCommand {
  const UpdatePropertyMediaCommand({
    required this.context,
    required this.propertyId,
    required this.mediaId,
    required this.expectedVersion,
    this.title,
    this.kind,
    this.sortOrder,
    this.isCover,
    this.archived,
  });

  final PropertyCreateContext context;
  final String propertyId;
  final String mediaId;
  final int expectedVersion;

  /// Null leaves the stored value; an empty string clears the caption.
  final String? title;
  final PropertyMediaKind? kind;
  final int? sortOrder;
  final bool? isCover;
  final bool? archived;
}

/// The property media contract.
///
/// Uploading is two steps on purpose: the bytes go to the private bucket
/// first, then [register] records them. The server checks that an object
/// really exists at the declared path before it writes a row, so the order
/// cannot be inverted and a row can never point at nothing.
abstract interface class PropertyMediaPort {
  /// The private bucket. Named here so no caller invents another one.
  static const String bucket = 'property-media';

  /// Short enough that a leaked URL is worth little, long enough to load a
  /// gallery over a slow connection. Signed URLs are never stored.
  static const Duration signedUrlTtl = Duration(minutes: 5);

  /// Active images of a property, in their stored order.
  Future<PropertyRepositoryResult<List<PropertyMediaDto>>> list({
    required String workspaceId,
    required String propertyId,
    bool includeArchived = false,
  });

  /// Uploads the bytes and records them. Resolves with the canonical row the
  /// server wrote back.
  Future<PropertyRepositoryResult<PropertyMediaDto>> register(
    RegisterPropertyMediaCommand command,
  );

  Future<PropertyRepositoryResult<PropertyMediaDto>> update(
    UpdatePropertyMediaCommand command,
  );

  /// A short-lived URL for one image. Issued on demand and never persisted:
  /// for a private object a URL is a credential, not an address.
  Future<PropertyRepositoryResult<String>> signedUrl({
    required String storagePath,
  });

  /// The cover image of each of [propertyIds] that has one, keyed by property.
  ///
  /// One query for a whole page, not one per row: a list that fires a read per
  /// visible property turns a scroll into a thundering herd, and the count it
  /// would report is the same either way.
  Future<PropertyRepositoryResult<Map<String, PropertyMediaDto>>> covers({
    required String workspaceId,
    required List<String> propertyIds,
  });

  /// Signs several paths in one call. Paths that cannot be signed are absent
  /// from the result rather than mapped to an empty string.
  Future<PropertyRepositoryResult<Map<String, String>>> signedUrls({
    required List<String> storagePaths,
  });
}

/// `{workspace}/{property}/{media}/{filename}` — the bucket's convention,
/// built in one place so no caller can invent a path the server will reject.
///
/// The file name is reduced to characters that survive a URL and a file system
/// unchanged; the original is kept in the row, which is what the user sees.
String storageObjectPath({
  required String workspaceId,
  required String propertyId,
  required String mediaId,
  required String fileName,
}) {
  final safe = fileName
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
      .replaceAll(RegExp(r'_+'), '_');
  final name = safe.isEmpty ? 'image' : safe;
  return '$workspaceId/$propertyId/$mediaId/$name';
}
