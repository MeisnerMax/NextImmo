import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../application/document_migration_dry_run.dart';

/// Reads the bytes behind a legacy `documents.file_path` and reports what they
/// really are. Kept behind an interface so the dry-run mapper stays pure and so
/// tests can describe a file system without touching one.
abstract interface class DocumentContentProbeReader {
  Future<DocumentContentProbe> probe(String filePath);
}

/// The real local file system. Hashes by streaming, so a large scan does not
/// have to hold a document in memory.
class FileSystemDocumentContentProbeReader
    implements DocumentContentProbeReader {
  const FileSystemDocumentContentProbeReader();

  @override
  Future<DocumentContentProbe> probe(String filePath) async {
    final file = File(filePath);
    try {
      if (!file.existsSync()) {
        return const DocumentContentProbe.missing();
      }
      final byteSize = await file.length();
      final digest = await sha256.bind(file.openRead()).first;
      return DocumentContentProbe(
        exists: true,
        byteSize: byteSize,
        sha256Hex: digest.toString(),
      );
    } on FileSystemException catch (error) {
      // An unreadable file is a blocking finding, never a silent skip.
      return DocumentContentProbe(exists: true, readError: error.osError?.message ?? 'unreadable');
    }
  }
}

/// What is already in the private `documents` bucket, keyed by object path.
///
/// The default is deliberately empty: a first dry run is expected to happen
/// *before* anything is uploaded, and the report then lists exactly which
/// objects still have to be pushed ([DocumentMigrationDryRunReport.pendingUploadPaths]).
abstract interface class UploadedDocumentObjectInventory {
  Future<Map<String, DocumentObjectProbe>> list();
}

class EmptyUploadedDocumentObjectInventory
    implements UploadedDocumentObjectInventory {
  const EmptyUploadedDocumentObjectInventory();

  @override
  Future<Map<String, DocumentObjectProbe>> list() async =>
      const <String, DocumentObjectProbe>{};
}

/// Read-only [DocumentMigrationSource] over the legacy SQLite tables. Reads raw
/// rows (not record models) so the dry-run mapper can flag any unmapped column,
/// and probes each referenced local file so content can be hashed before any
/// link is switched.
class SqliteDocumentsComplianceMigrationSource
    implements DocumentMigrationSource {
  const SqliteDocumentsComplianceMigrationSource(
    this._database, {
    DocumentContentProbeReader contentReader =
        const FileSystemDocumentContentProbeReader(),
    UploadedDocumentObjectInventory uploadedObjects =
        const EmptyUploadedDocumentObjectInventory(),
  }) : _contentReader = contentReader,
       _uploadedObjects = uploadedObjects;

  final Database _database;
  final DocumentContentProbeReader _contentReader;
  final UploadedDocumentObjectInventory _uploadedObjects;

  @override
  Future<DocumentMigrationSourceSnapshot> read() async {
    final documentTypes = await _database.query(
      'document_types',
      orderBy: 'id ASC',
    );
    final documents = await _database.query('documents', orderBy: 'id ASC');
    final documentMetadata = await _database.query(
      'document_metadata',
      orderBy: 'id ASC',
    );
    final requiredDocuments = await _database.query(
      'required_documents',
      orderBy: 'id ASC',
    );
    final checklistEntries = await _database.query(
      'property_document_checklist',
      orderBy: 'id ASC',
    );

    final paths = <String>{
      for (final row in documents)
        if (row['file_path'] case final String path when path.trim().isNotEmpty)
          path.trim(),
    }.toList(growable: false)..sort();

    final contentProbes = <String, DocumentContentProbe>{};
    for (final path in paths) {
      contentProbes[path] = await _contentReader.probe(path);
    }

    return DocumentMigrationSourceSnapshot(
      documentTypes: _rows(documentTypes),
      documents: _rows(documents),
      documentMetadata: _rows(documentMetadata),
      requiredDocuments: _rows(requiredDocuments),
      checklistEntries: _rows(checklistEntries),
      contentProbes: contentProbes,
      uploadedObjects: await _uploadedObjects.list(),
    );
  }

  static List<Map<String, Object?>> _rows(List<Map<String, Object?>> rows) =>
      rows.map(Map<String, Object?>.from).toList(growable: false);
}
