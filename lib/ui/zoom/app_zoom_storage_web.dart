import 'dart:html' as html;

class AppZoomStorage {
  const AppZoomStorage._();

  static const String _key = 'neximmo.ui_zoom_scale';

  static Future<double?> readScale() async {
    final value = html.window.localStorage[_key];
    if (value == null || value.isEmpty) {
      return null;
    }
    return double.tryParse(value);
  }

  static Future<void> writeScale(double scale) async {
    html.window.localStorage[_key] = scale.toString();
  }
}
