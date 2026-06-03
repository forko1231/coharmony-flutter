import 'package:url_launcher/url_launcher.dart';

/// Thin wrapper over `url_launcher` for the app's external links — legal pages
/// (MAUI used `Browser.OpenAsync`) and external maps navigation (the location-record
/// "Navigate" action). Returns false on failure so callers can show a fallback.
class ExternalLauncher {
  ExternalLauncher._();

  /// Opens [url] in the external browser. Returns false if it couldn't launch.
  static Future<bool> openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Opens the platform's maps app at [lat]/[lng]. Tries the `geo:` scheme first
  /// (Android / any maps app), falling back to a Google Maps web URL.
  static Future<bool> openMaps(double lat, double lng, {String? label}) async {
    final query = label != null && label.isNotEmpty ? '$lat,$lng($label)' : '$lat,$lng';
    try {
      final geo = Uri.parse('geo:$lat,$lng?q=${Uri.encodeComponent(query)}');
      if (await canLaunchUrl(geo)) {
        return await launchUrl(geo);
      }
    } catch (_) {/* fall through to web */}
    return openUrl('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
  }
}
