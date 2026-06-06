import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'token_service.dart';

/// Port of `Services/BaseApiService.cs`.
///
/// Talks to the backend at [baseUrl]. Mirrors the C# behaviour: bearer auth via
/// [TokenService], a fresh `X-Request-ID` per request, automatic 401→refresh→retry,
/// and 402 (PaymentRequired) → subscription-required redirect (suppressed during
/// onboarding and for child accounts via injected guards).
///
/// Unlike the C# generic `PostAsync<TRequest,TResponse>`, Dart has no source-gen
/// serializer, so these methods take an already-encodable [body] (typically a
/// `request.toJson()` map) and return the decoded JSON (`Map`/`List`/primitive),
/// or null on failure — matching the C# `default(T)` contract. Callers map the
/// result into model classes.
class ApiClient {
  ApiClient({
    required this.tokenService,
    http.Client? httpClient,
    this.baseUrl = 'https://api.co-harmony.com',
    this.clientPlatform = 'Flutter',
    this.clientVersion = '1.0.0',
    this.timeout = const Duration(seconds: 30),
    this.isOnboardingCompleted,
    this.accountType,
    this.onSubscriptionRequired,
  }) : _http = httpClient ?? http.Client();

  final TokenService tokenService;
  final http.Client _http;
  final String baseUrl;
  final String clientPlatform;
  final String clientVersion;
  final Duration timeout;

  /// Guards for the 402 redirect, mirroring `BaseApiService` checks against
  /// `OnboardingState.IsCompleted` and the `AccountType` preference.
  final bool Function()? isOnboardingCompleted;
  final String Function()? accountType;
  final void Function()? onSubscriptionRequired;

  String? _authToken;

  void setAuthToken(String? token) =>
      _authToken = (token == null || token.isEmpty) ? null : token;

  String getAuthToken() => _authToken ?? '';

  Future<void> _ensureAuthToken() async {
    final token = await tokenService.getToken();
    setAuthToken(token.isNotEmpty ? token : null);
  }

  Future<bool> _handleAuthFailure() async {
    final newToken = await tokenService.refreshToken(this);
    if (newToken != null && newToken.isNotEmpty) {
      setAuthToken(newToken);
      return true;
    }
    setAuthToken(null);
    return false;
  }

  Uri _uri(String endpoint) {
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    // Some callers pass a leading '/' (e.g. "/api/messages"). With a base
    // address that's authority-relative (matches C# HttpClient), so trim it to
    // avoid a doubled slash.
    final ep = endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;
    return Uri.parse('$base$ep');
  }

  Map<String, String> _headers({bool json = false}) {
    final h = <String, String>{
      'Accept': 'application/json',
      'X-Client-Platform': clientPlatform,
      'X-Client-Version': clientVersion,
      'X-Request-ID': _newRequestId(),
    };
    if (json) h['Content-Type'] = 'application/json; charset=utf-8';
    final token = _authToken;
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  static int _idCounter = 0;
  String _newRequestId() {
    // Lightweight unique id per request (GUID analogue).
    final now = DateTime.now().microsecondsSinceEpoch;
    return '${now.toRadixString(16)}-${(_idCounter++).toRadixString(16)}';
  }

  bool _isSubscriptionRequired(http.Response r) => r.statusCode == 402;

  // 402 debounce: only the first concurrent payment-required should redirect.
  static bool _subscriptionRedirectInFlight = false;

  void _handleSubscriptionRequired() {
    if (_subscriptionRedirectInFlight) return;
    _subscriptionRedirectInFlight = true;

    // During onboarding the paywall is a router step — don't kick the user out.
    if (isOnboardingCompleted != null && !isOnboardingCompleted!()) {
      _subscriptionRedirectInFlight = false;
      return;
    }
    // Child accounts are intentionally unsubscribed.
    if (accountType != null &&
        accountType!().toLowerCase() == 'child') {
      _subscriptionRedirectInFlight = false;
      return;
    }

    try {
      onSubscriptionRequired?.call();
    } finally {
      // Release the latch after a beat so future 402s can still redirect.
      Timer(const Duration(seconds: 2), () => _subscriptionRedirectInFlight = false);
    }
  }

  dynamic _decode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  // ---- Verb methods -------------------------------------------------------

  Future<dynamic> getJson(String endpoint) async {
    try {
      await _ensureAuthToken();
      var response =
          await _http.get(_uri(endpoint), headers: _headers()).timeout(timeout);

      if (_isSubscriptionRequired(response)) {
        _handleSubscriptionRequired();
        return null;
      }
      if (response.statusCode == 401 && await _handleAuthFailure()) {
        response =
            await _http.get(_uri(endpoint), headers: _headers()).timeout(timeout);
        if (_isSubscriptionRequired(response)) {
          _handleSubscriptionRequired();
          return null;
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return _decode(response.body);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> getBytes(String endpoint) async {
    try {
      await _ensureAuthToken();
      var response =
          await _http.get(_uri(endpoint), headers: _headers()).timeout(timeout);

      if (_isSubscriptionRequired(response)) {
        _handleSubscriptionRequired();
        return null;
      }
      if (response.statusCode == 401 && await _handleAuthFailure()) {
        response =
            await _http.get(_uri(endpoint), headers: _headers()).timeout(timeout);
        if (_isSubscriptionRequired(response)) {
          _handleSubscriptionRequired();
          return null;
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return response.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> postJson(String endpoint, Object? body) async {
    return _sendWithBody('POST', endpoint, body);
  }

  Future<dynamic> putJson(String endpoint, Object? body) async {
    return _sendWithBody('PUT', endpoint, body);
  }

  /// DELETE, optionally with a body (matches the two C# `DeleteAsync` overloads).
  Future<dynamic> deleteJson(String endpoint, [Object? body]) async {
    return _sendWithBody('DELETE', endpoint, body, allowNullBody: true);
  }

  /// POST that returns the raw string response (matches `PostForStringAsync`).
  Future<String> postForString(String endpoint, Object? body) async {
    try {
      await _ensureAuthToken();
      if (body == null) return 'Error: Request data is null';
      final jsonContent = jsonEncode(body);

      var response = await _http
          .post(_uri(endpoint), headers: _headers(json: true), body: jsonContent)
          .timeout(timeout);

      if (_isSubscriptionRequired(response)) {
        _handleSubscriptionRequired();
        return 'Subscription required';
      }
      if (response.statusCode == 401 && await _handleAuthFailure()) {
        response = await _http
            .post(_uri(endpoint), headers: _headers(json: true), body: jsonContent)
            .timeout(timeout);
        if (_isSubscriptionRequired(response)) {
          _handleSubscriptionRequired();
          return 'Subscription required';
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return 'Error: ${response.statusCode}';
      }
      return response.body;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// PUT that returns the raw string response (string-returning analogue of
  /// [postForString]). Used by `user/update`, which the server exposes as PUT.
  Future<String> putForString(String endpoint, Object? body) async {
    try {
      await _ensureAuthToken();
      if (body == null) return 'Error: Request data is null';
      final jsonContent = jsonEncode(body);

      Future<http.Response> send() {
        final request = http.Request('PUT', _uri(endpoint))
          ..headers.addAll(_headers(json: true))
          ..body = jsonContent;
        return _http.send(request).then(http.Response.fromStream).timeout(timeout);
      }

      var response = await send();
      if (_isSubscriptionRequired(response)) {
        _handleSubscriptionRequired();
        return 'Subscription required';
      }
      if (response.statusCode == 401 && await _handleAuthFailure()) {
        response = await send();
        if (_isSubscriptionRequired(response)) {
          _handleSubscriptionRequired();
          return 'Subscription required';
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return 'Error: ${response.statusCode}';
      }
      return response.body;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// POST WITHOUT 401-retry — used only for the refresh-token call so we never
  /// recurse into a retry storm.
  Future<dynamic> postWithoutRetry(String endpoint, Object? body) async {
    try {
      if (body == null) return null;
      final jsonContent = jsonEncode(body);
      final response = await _http
          .post(_uri(endpoint), headers: _headers(json: true), body: jsonContent)
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return _decode(response.body);
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> _sendWithBody(String method, String endpoint, Object? body,
      {bool allowNullBody = false}) async {
    try {
      await _ensureAuthToken();
      if (body == null && !allowNullBody) return null;
      final jsonContent = body == null ? null : jsonEncode(body);

      Future<http.Response> send() {
        final request = http.Request(method, _uri(endpoint))
          ..headers.addAll(_headers(json: jsonContent != null));
        if (jsonContent != null) request.body = jsonContent;
        return _http.send(request).then(http.Response.fromStream).timeout(timeout);
      }

      var response = await send();
      if (_isSubscriptionRequired(response)) {
        _handleSubscriptionRequired();
        return null;
      }
      if (response.statusCode == 401 && await _handleAuthFailure()) {
        response = await send();
        if (_isSubscriptionRequired(response)) {
          _handleSubscriptionRequired();
          return null;
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return _decode(response.body);
    } catch (_) {
      return null;
    }
  }

  /// Like the JSON helpers, but surfaces the HTTP status alongside the decoded body so
  /// callers can act on it. The live-schedule editor needs this: 409 = version conflict,
  /// 423 = locked, 200 = applied — the status IS the signal. Honors 401-refresh; the live
  /// endpoints are paywall-exempt so the subscription redirect isn't triggered here.
  Future<({int status, dynamic body})> sendForResult(
      String method, String endpoint, Object? body) async {
    try {
      await _ensureAuthToken();
      final jsonContent = body == null ? null : jsonEncode(body);
      Future<http.Response> send() {
        final request = http.Request(method, _uri(endpoint))
          ..headers.addAll(_headers(json: jsonContent != null));
        if (jsonContent != null) request.body = jsonContent;
        return _http.send(request).then(http.Response.fromStream).timeout(timeout);
      }

      var response = await send();
      if (response.statusCode == 401 && await _handleAuthFailure()) {
        response = await send();
      }
      final decoded = response.body.isEmpty ? null : _decode(response.body);
      return (status: response.statusCode, body: decoded);
    } catch (_) {
      return (status: 0, body: null);
    }
  }
}
