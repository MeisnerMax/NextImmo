import 'dart:io';

import 'package:archive/archive.dart';

class ZipEntryInput {
  const ZipEntryInput({required this.relativePath, required this.bytes});

  final String relativePath;
  final List<int> bytes;
}

class ZipService {
  const ZipService();

  Future<void> writeZip({
    required String outputZipPath,
    required List<ZipEntryInput> entries,
  }) async {
    final archive = Archive();
    for (final entry in entries) {
      archive.addFile(
        ArchiveFile(entry.relativePath, entry.bytes.length, entry.bytes),
      );
    }

    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      throw StateError('Could not encode ZIP archive.');
    }

    final file = File(outputZipPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(encoded, flush: true);
  }
}
