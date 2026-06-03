import 'dart:io';

/// Lightweight, dependency-free connectivity check — the Flutter analog of MAUI's
/// `Connectivity.Current.NetworkAccess`. We do a DNS lookup of the given host
/// instead of pulling in a native plugin (keeps the iOS build untouched).
///
/// Deliberately FAIL-OPEN: any ambiguous result returns `true` (assume online),
/// so a flaky DNS resolver can never wrongly block a legitimate login. Only a
/// clean "no addresses / socket error" — the real offline signal — returns false.
class NetworkCheck {
  NetworkCheck._();

  static Future<bool> hasInternet(String hostOrUrl) async {
    var host = hostOrUrl;
    final uri = Uri.tryParse(hostOrUrl);
    if (uri != null && uri.host.isNotEmpty) host = uri.host;
    try {
      final result = await InternetAddress.lookup(host).timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false; // definitively offline / host unreachable
    } catch (_) {
      return true; // timeout or anything else — don't block the user
    }
  }
}
