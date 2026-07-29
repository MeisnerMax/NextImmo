import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/documents_compliance/application/document_providers.dart';
import '../../../../features/documents_compliance/domain/document_dto.dart';
import '../../../../features/documents_compliance/application/document_repository.dart';
import '../../../../features/identity_access/application/workspace_session_scope.dart';

/// The workspace document-type registry, loaded once per surface.
///
/// Every documents screen needs it twice — to name a document's type in a list
/// and to offer the type choices when creating one — and the registry is a
/// small workspace table, so it is fetched once here rather than per row. A
/// failure resolves to an empty registry on purpose: a missing type name must
/// degrade to "—", never take a whole screen into its error state.
final documentTypeRegistryProvider =
    FutureProvider.autoDispose<List<DocumentTypeDto>>((ref) async {
      final workspaceId = ref.watch(workspaceSessionScopeProvider).workspaceId;
      if (workspaceId == null) {
        return const <DocumentTypeDto>[];
      }
      final result = await ref
          .watch(requirementPolicyProvider)
          .listTypes(workspaceId: workspaceId);
      return switch (result) {
        DocumentRepositorySuccess<List<DocumentTypeDto>>(:final value) => value,
        DocumentRepositoryFailure<List<DocumentTypeDto>>() =>
          const <DocumentTypeDto>[],
      };
    });

/// Name lookup over an already-loaded registry — the shape the tables expect,
/// so no widget issues a read per row.
String? documentTypeName(
  List<DocumentTypeDto> types,
  String? documentTypeId,
) {
  if (documentTypeId == null) {
    return null;
  }
  for (final type in types) {
    if (type.id == documentTypeId) {
      return type.name;
    }
  }
  return null;
}
