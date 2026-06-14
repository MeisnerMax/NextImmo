import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../../core/services/datasheet_export_service.dart';

Future<String?> saveDatasheetArtifact(
  DatasheetExportArtifact artifact,
) async {
  final location = await getSaveLocation(
    suggestedName: artifact.suggestedFileName,
    acceptedTypeGroups: <XTypeGroup>[
      XTypeGroup(
        label: artifact.fileExtension.toUpperCase(),
        extensions: <String>[artifact.fileExtension],
      ),
    ],
  );
  if (location == null) {
    return null;
  }

  final file = File(location.path);
  await file.parent.create(recursive: true);
  final bytes = artifact.bytes;
  if (bytes == null) {
    await file.writeAsString(artifact.content);
  } else {
    await file.writeAsBytes(bytes);
  }
  return location.path;
}
