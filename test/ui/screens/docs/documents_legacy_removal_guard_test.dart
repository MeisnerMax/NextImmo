import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// DOCUMENTS-V2 acceptance criterion 1 (`documents.md` §18): the legacy
/// four-tab host, the int tab provider and the palette jump no longer exist
/// in the build; and the binding signed-URL rule (§6.7/§20.4): no URL dialog,
/// no clipboard copy of a signed URL anywhere in the documents surfaces.
///
/// Source-text guard in the style of `app_runtime_guard_test.dart`: a
/// resurrection usually arrives as a pasted import, which is exactly the level
/// this catches.
void main() {
  const removedFiles = <String>[
    'lib/ui/screens/docs/documents_screen.dart',
    'lib/ui/screens/docs/legacy_document_rules_tabs.dart',
  ];

  const forbiddenSymbols = <String>[
    'documentsRequestedTabProvider',
    'jump_missing_documents',
    'showDocumentSignedUrlDialog',
    'LegacyDocumentTypesTab',
    'LegacyRequiredDocumentsTab',
  ];

  const documentSurfaces = <String>[
    'lib/ui/screens/docs',
    'lib/ui/screens/property_detail/property_documents_panel.dart',
    'lib/features/documents_compliance/application',
  ];

  Iterable<File> dartFilesUnder(String path) sync* {
    final entity = FileSystemEntity.typeSync(path);
    if (entity == FileSystemEntityType.file) {
      yield File(path);
      return;
    }
    if (entity != FileSystemEntityType.directory) {
      return;
    }
    yield* Directory(path)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
  }

  test('the legacy documents host and registry tabs are gone', () {
    for (final path in removedFiles) {
      expect(File(path).existsSync(), isFalse, reason: '$path must not exist');
    }
  });

  test(
    'no lib source references the removed host, provider or palette jump',
    () {
      final offenders = <String>[];
      for (final file in dartFilesUnder('lib')) {
        final text = file.readAsStringSync();
        for (final symbol in forbiddenSymbols) {
          if (text.contains(symbol)) {
            offenders.add('${file.path}: $symbol');
          }
        }
      }
      expect(offenders, isEmpty);
    },
  );

  test('document surfaces never display, copy or log a signed URL', () {
    final offenders = <String>[];
    for (final root in documentSurfaces) {
      for (final file in dartFilesUnder(root)) {
        final text = file.readAsStringSync();
        for (final marker in <RegExp>[
          RegExp(r'Clipboard\.setData'),
          RegExp(r'SelectableText\('),
          RegExp(r'Link kopieren'),
          RegExp(r'Download-Link'),
          RegExp(r'(?<![A-Za-z_])print\('),
          RegExp(r'(?<![A-Za-z_])debugPrint\('),
          RegExp(r'(?<![A-Za-z_.])log\('),
        ]) {
          if (marker.hasMatch(text)) {
            offenders.add('${file.path}: ${marker.pattern}');
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
