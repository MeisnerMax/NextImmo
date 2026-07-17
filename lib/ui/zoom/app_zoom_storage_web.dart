import 'package:web/web.dart' as web;

class AppZoomStorage {
  const AppZoomStorage._();

  static const String _key = 'neximmo.ui_zoom_scale';

  static Future<double?> readScale() async {
    final value = web.window.localStorage.getItem(_key);
    if (value == null || value.isEmpty) {
      return null;
    }
    return double.tryParse(value);
  }

  static Future<void> writeScale(double scale) async {
    web.window.localStorage.setItem(_key, scale.toString());
  }
}
