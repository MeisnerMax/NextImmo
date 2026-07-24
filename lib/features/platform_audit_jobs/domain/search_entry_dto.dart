/// Derived search-index DTOs (P2-D04, DOM-010).
///
/// DOM-010 states the search index is *derived and not a source of truth*, and
/// the schema takes that literally: a search entry carries no version token, no
/// audit trail and no mutation receipt, and it is the one platform table with a
/// delete path. Everything in this file therefore looks deliberately unlike
/// [TaskDto]/[ImportJobDto] — there is no `version`, and a reindex is a
/// content-addressed upsert keyed by (workspace, entityType, entityId) whose
/// correct semantics are last-writer-wins.
library;

import 'platform_entity_type.dart';

class SearchEntryDto {
  const SearchEntryDto({
    required this.id,
    required this.workspaceId,
    required this.entity,
    required this.title,
    required this.updatedAt,
    required this.createdAt,
    required this.createdBy,
    required this.updatedBy,
    this.subtitle,
    this.body,
  });

  final String id;
  final String workspaceId;

  /// The indexed entity. Also the natural key: at most one entry exists per
  /// (workspace, entity).
  final PlatformEntityRef entity;
  final String title;
  final DateTime updatedAt;
  final DateTime createdAt;
  final String createdBy;
  final String updatedBy;
  final String? subtitle;
  final String? body;
}

/// The projected content one owning domain writes for one of its entities. The
/// shape stays domain-agnostic (generic title/subtitle/body) so DOM-010 carries
/// no business models: each domain projects its own entities into it.
class SearchEntryContent {
  const SearchEntryContent({required this.title, this.subtitle, this.body});

  final String title;
  final String? subtitle;
  final String? body;
}

/// The outcome of `remove_search_entry`. Removal is idempotent, so removing an
/// absent entry is a success — [removed] reports whether a row actually went
/// away, which is information, not an error condition.
class SearchEntryRemoval {
  const SearchEntryRemoval({
    required this.workspaceId,
    required this.entity,
    required this.removed,
  });

  final String workspaceId;
  final PlatformEntityRef entity;
  final bool removed;
}
