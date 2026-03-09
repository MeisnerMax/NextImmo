import 'dart:convert';

class ScenarioVersionRecord {
  static const String _notesMetaPrefix = '__nx_meta__:';

  const ScenarioVersionRecord({
    required this.id,
    required this.scenarioId,
    required this.label,
    required this.notes,
    required this.archived,
    required this.createdAt,
    required this.createdBy,
    required this.baseHash,
    required this.parentVersionId,
  });

  final String id;
  final String scenarioId;
  final String label;
  final String? notes;
  final bool archived;
  final int createdAt;
  final String? createdBy;
  final String baseHash;
  final String? parentVersionId;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'scenario_id': scenarioId,
      'label': label,
      'notes': _encodeNotes(notes: notes, archived: archived),
      'created_at': createdAt,
      'created_by': createdBy,
      'base_hash': baseHash,
      'parent_version_id': parentVersionId,
    };
  }

  factory ScenarioVersionRecord.fromMap(Map<String, Object?> map) {
    final notesPayload = _decodeNotes(map['notes'] as String?);
    return ScenarioVersionRecord(
      id: map['id']! as String,
      scenarioId: map['scenario_id']! as String,
      label: map['label']! as String,
      notes: notesPayload.notes,
      archived: notesPayload.archived,
      createdAt: (map['created_at']! as num).toInt(),
      createdBy: map['created_by'] as String?,
      baseHash: map['base_hash']! as String,
      parentVersionId: map['parent_version_id'] as String?,
    );
  }

  ScenarioVersionRecord copyWith({
    String? label,
    Object? notes = _sentinel,
    bool? archived,
  }) {
    return ScenarioVersionRecord(
      id: id,
      scenarioId: scenarioId,
      label: label ?? this.label,
      notes: identical(notes, _sentinel) ? this.notes : notes as String?,
      archived: archived ?? this.archived,
      createdAt: createdAt,
      createdBy: createdBy,
      baseHash: baseHash,
      parentVersionId: parentVersionId,
    );
  }

  static _NotesPayload _decodeNotes(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const _NotesPayload(notes: null, archived: false);
    }
    if (!raw.startsWith(_notesMetaPrefix)) {
      return _NotesPayload(notes: raw, archived: false);
    }
    final payload = raw.substring(_notesMetaPrefix.length);
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        return _NotesPayload(notes: raw, archived: false);
      }
      final rawNotes = decoded['notes'] as String?;
      final notes =
          rawNotes == null || rawNotes.trim().isEmpty ? null : rawNotes;
      final archived = decoded['archived'] == true || decoded['archived'] == 1;
      return _NotesPayload(notes: notes, archived: archived);
    } catch (_) {
      return _NotesPayload(notes: raw, archived: false);
    }
  }

  static String? _encodeNotes({
    required String? notes,
    required bool archived,
  }) {
    final normalizedNotes =
        notes == null || notes.trim().isEmpty ? null : notes.trim();
    if (!archived) {
      return normalizedNotes;
    }
    final encoded = jsonEncode(<String, Object?>{
      'archived': true,
      'notes': normalizedNotes,
    });
    return '$_notesMetaPrefix$encoded';
  }

  static const Object _sentinel = Object();
}

class _NotesPayload {
  const _NotesPayload({required this.notes, required this.archived});

  final String? notes;
  final bool archived;
}

class ScenarioVersionBlobRecord {
  const ScenarioVersionBlobRecord({
    required this.id,
    required this.versionId,
    required this.snapshotJson,
    required this.createdAt,
  });

  final String id;
  final String versionId;
  final String snapshotJson;
  final int createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'version_id': versionId,
      'snapshot_json': snapshotJson,
      'created_at': createdAt,
    };
  }

  factory ScenarioVersionBlobRecord.fromMap(Map<String, Object?> map) {
    return ScenarioVersionBlobRecord(
      id: map['id']! as String,
      versionId: map['version_id']! as String,
      snapshotJson: map['snapshot_json']! as String,
      createdAt: (map['created_at']! as num).toInt(),
    );
  }
}
