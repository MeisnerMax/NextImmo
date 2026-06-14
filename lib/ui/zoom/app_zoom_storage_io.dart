import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class AppZoomStorage {
  const AppZoomStorage._();

  static Future<double?> readScale() async {
    final file = await _settingsFile();
    if (!await file.exists()) {
      return null;
    }
    final content = await file.readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;
    return (data['scale'] as num?)?.toDouble();
  }

  static Future<void> writeScale(double scale) async {
    final file = await _settingsFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(<String, Object?>{'scale': scale}));
  }

  static Future<File> _settingsFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}ui_zoom.json');
  }
}
