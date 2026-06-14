import 'dart:convert';

import 'package:csv/csv.dart';

import '../models/investment_modules.dart';

enum DatasheetExportFormat {
  json,
  csv,
  pdf,
}

class DatasheetExportArtifact {
  const DatasheetExportArtifact({
    required this.format,
    required this.fileExtension,
    required this.mimeType,
    required this.suggestedFileName,
    required this.content,
    this.bytes,
  });

  final DatasheetExportFormat format;
  final String fileExtension;
  final String mimeType;
  final String suggestedFileName;
  final String content;
  final List<int>? bytes;
}

class DatasheetExportService {
  const DatasheetExportService();

  DatasheetExportArtifact prepareFromDatasheet({
    required ModuleDatasheet datasheet,
    required DatasheetExportFormat format,
  }) {
    return _prepare(
      payload: datasheet.toJson(),
      fallbackJson: null,
      title: datasheet.title,
      module: datasheet.module,
      createdAt: datasheet.createdAt,
      format: format,
    );
  }

  DatasheetExportArtifact prepareFromStoredRow({
    required Map<String, Object?> row,
    required DatasheetExportFormat format,
  }) {
    final payloadJson = row['payload_json'] as String?;
    final decodedPayload = payloadJson == null || payloadJson.isEmpty
        ? <String, Object?>{}
        : jsonDecode(payloadJson) as Map;
    final payload = Map<String, Object?>.from(decodedPayload);
    return _prepare(
      payload: payload,
      fallbackJson: row['export_json'] as String?,
      title: row['title'] as String? ?? 'datasheet',
      module: row['module'] as String? ?? 'datasheet',
      createdAt: (row['created_at'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      format: format,
    );
  }

  DatasheetExportArtifact _prepare({
    required Map<String, Object?> payload,
    required String? fallbackJson,
    required String title,
    required String module,
    required int createdAt,
    required DatasheetExportFormat format,
  }) {
    switch (format) {
      case DatasheetExportFormat.json:
        return DatasheetExportArtifact(
          format: format,
          fileExtension: 'json',
          mimeType: 'application/json',
          suggestedFileName: _fileName(title, module, createdAt, 'json'),
          content: fallbackJson ??
              const JsonEncoder.withIndent('  ').convert(payload),
        );
      case DatasheetExportFormat.csv:
        return DatasheetExportArtifact(
          format: format,
          fileExtension: 'csv',
          mimeType: 'text/csv',
          suggestedFileName: _fileName(title, module, createdAt, 'csv'),
          content: _toCsv(payload),
        );
      case DatasheetExportFormat.pdf:
        return DatasheetExportArtifact(
          format: format,
          fileExtension: 'pdf',
          mimeType: 'application/pdf',
          suggestedFileName: _fileName(title, module, createdAt, 'pdf'),
          content: '',
          bytes: _toPdfBytes(payload, title: title, module: module),
        );
    }
  }

  String _toCsv(Map<String, Object?> payload) {
    final rows = <List<dynamic>>[
      <dynamic>['section', 'key', 'value'],
    ];
    for (final entry in payload.entries) {
      _appendRows(rows, entry.key, entry.key, entry.value);
    }
    return const ListToCsvConverter().convert(rows);
  }

  void _appendRows(
    List<List<dynamic>> rows,
    String section,
    String key,
    Object? value,
  ) {
    if (value is Map) {
      for (final nested in value.entries) {
        _appendRows(
          rows,
          section,
          '$key.${nested.key}',
          nested.value as Object?,
        );
      }
      return;
    }
    if (value is List) {
      for (var i = 0; i < value.length; i += 1) {
        _appendRows(rows, section, '$key[$i]', value[i] as Object?);
      }
      return;
    }
    rows.add(<dynamic>[section, key, value ?? '']);
  }

  List<int> _toPdfBytes(
    Map<String, Object?> payload, {
    required String title,
    required String module,
  }) {
    final lines = <String>[
      title,
      'Modul: $module',
      'Erstellt: ${_dateText(payload['created_at'])}',
      '',
    ];
    for (final entry in payload.entries) {
      if (entry.key == 'id') {
        continue;
      }
      lines.add(_sectionTitle(entry.key));
      _appendPdfLines(lines, entry.key, entry.value);
      lines.add('');
    }

    final pages = _chunkLines(lines, 48);
    final objects = <String>[];
    final pageObjectIds = <int>[];
    final contentObjectIds = <int>[];
    final fontObjectId = 3 + pages.length * 2;
    for (var i = 0; i < pages.length; i += 1) {
      pageObjectIds.add(3 + i * 2);
      contentObjectIds.add(4 + i * 2);
    }

    objects.add('1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n');
    objects.add(
      '2 0 obj\n<< /Type /Pages /Kids [${pageObjectIds.map((id) => '$id 0 R').join(' ')}] /Count ${pages.length} >>\nendobj\n',
    );
    for (var i = 0; i < pages.length; i += 1) {
      final pageId = pageObjectIds[i];
      final contentId = contentObjectIds[i];
      final stream = _pdfPageStream(pages[i]);
      objects.add(
        '$pageId 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 $fontObjectId 0 R >> >> /Contents $contentId 0 R >>\nendobj\n',
      );
      objects.add(
        '$contentId 0 obj\n<< /Length ${stream.length} >>\nstream\n$stream\nendstream\nendobj\n',
      );
    }
    objects.add(
      '$fontObjectId 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n',
    );

    final buffer = StringBuffer('%PDF-1.4\n');
    final offsets = <int>[0];
    for (final object in objects) {
      offsets.add(buffer.length);
      buffer.write(object);
    }
    final xrefOffset = buffer.length;
    buffer
      ..write('xref\n')
      ..write('0 ${objects.length + 1}\n')
      ..write('0000000000 65535 f \n');
    for (final offset in offsets.skip(1)) {
      buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    buffer
      ..write('trailer\n')
      ..write('<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
      ..write('startxref\n')
      ..write('$xrefOffset\n')
      ..write('%%EOF\n');
    return latin1.encode(buffer.toString());
  }

  void _appendPdfLines(List<String> lines, String key, Object? value) {
    if (value is Map) {
      for (final nested in value.entries) {
        _appendPdfLines(lines, '$key.${nested.key}', nested.value as Object?);
      }
      return;
    }
    if (value is List) {
      if (value.isEmpty) {
        lines.add('$key: []');
        return;
      }
      for (var i = 0; i < value.length; i += 1) {
        _appendPdfLines(lines, '$key[$i]', value[i] as Object?);
      }
      return;
    }
    final text = '$key: ${value ?? ''}';
    lines.addAll(_wrapLine(text, 94));
  }

  List<List<String>> _chunkLines(List<String> lines, int maxLines) {
    final chunks = <List<String>>[];
    for (var index = 0; index < lines.length; index += maxLines) {
      final end = index + maxLines > lines.length ? lines.length : index + maxLines;
      chunks.add(lines.sublist(index, end));
    }
    return chunks.isEmpty ? <List<String>>[const <String>[]] : chunks;
  }

  List<String> _wrapLine(String line, int maxLength) {
    final sanitized = _pdfText(line);
    if (sanitized.length <= maxLength) {
      return <String>[sanitized];
    }
    final chunks = <String>[];
    var remaining = sanitized;
    while (remaining.length > maxLength) {
      chunks.add(remaining.substring(0, maxLength));
      remaining = '  ${remaining.substring(maxLength)}';
    }
    chunks.add(remaining);
    return chunks;
  }

  String _pdfPageStream(List<String> lines) {
    final buffer = StringBuffer()
      ..writeln('BT')
      ..writeln('/F1 9 Tf')
      ..writeln('45 795 Td')
      ..writeln('13 TL');
    for (final line in lines) {
      buffer
        ..write('(')
        ..write(_escapePdfString(line))
        ..writeln(') Tj T*');
    }
    buffer.write('ET');
    return buffer.toString();
  }

  String _sectionTitle(String value) {
    return value.replaceAll('_', ' ').toUpperCase();
  }

  String _dateText(Object? value) {
    final millis = (value as num?)?.toInt();
    if (millis == null) {
      return DateTime.now().toIso8601String();
    }
    return DateTime.fromMillisecondsSinceEpoch(millis).toIso8601String();
  }

  String _pdfText(String value) {
    return value.replaceAll(RegExp(r'[^\x20-\x7E]'), '?');
  }

  String _escapePdfString(String value) {
    return _pdfText(value)
        .replaceAll(r'\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)');
  }

  String _fileName(String title, String module, int createdAt, String extension) {
    final safeTitle = _safeFilePart(title);
    final safeModule = _safeFilePart(module);
    return '${safeModule}_${safeTitle}_$createdAt.$extension';
  }

  String _safeFilePart(String value) {
    final cleaned = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return cleaned.isEmpty ? 'datasheet' : cleaned;
  }
}
