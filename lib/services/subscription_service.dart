import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import '../models/subscription_models.dart';
import 'api_client.dart';
import 'preferences.dart';

/// Port of `Services/SubscriptionService.cs`.
///
/// The PORTABLE core is here: status fetch + 5-minute cache, server-side
/// activation/validation (Apple transaction, Google purchase, login validation),
/// and the status-changed broadcast.
///
/// The NATIVE store purchase flows (StoreKit `HandleAppleSubscriptionAsync`,
/// Play Billing `HandleGoogleSubscriptionAsync`, `RestorePurchasesAsync`) are
/// phase 3 — they map onto the `in_app_purchase` plugin. Once the plugin obtains
/// a transaction id / purchase token, it calls [validateAppleTransaction] /
/// [validateGooglePurchase] / [restoreAppleTransactions] here.
class SubscriptionService {
  SubscriptionService(this._api);
  final ApiClient _api;

  static const _subscriptionStatusKey = 'subscription_status';
  static const _lastCheckKey = 'last_subscription_check';

  final _statusChanged = StreamController<SubscriptionStatus>.broadcast();
  Stream<SubscriptionStatus> get onStatusChanged => _statusChanged.stream;

  // ---- Status -------------------------------------------------------------

  Future<SubscriptionInfo> getSubscriptionStatus() async {
    try {
      final json = await _api.getJson('/api/subscription/status');
      if (json is Map<String, dynamic>) {
        final response = SubscriptionStatusApiResponse.fromJson(json);
        final info = SubscriptionInfo(
          status: subscriptionStatusFromApi(response.status),
          hasActiveSubscription: response.hasActiveSubscription,
          subscription: response.subscription == null
              ? null
              : SubscriptionDetails(
                  type: response.subscription!.type,
                  platform: response.subscription!.platform,
                  nextBillingDate: response.subscription!.nextBillingDate,
                  monthlyPrice: response.subscription!.monthlyPrice,
                  currency: response.subscription!.currency,
                  isShared: response.subscription!.isShared,
                  originalSubscriberEmail: response.subscription!.originalSubscriberEmail,
                  sharedWithPartnerEmail: response.subscription!.sharedWithPartnerEmail,
                ),
        );
        await _cacheStatus(info);
        return info;
      }
    } catch (_) {/* fall back to cache */}
    return (await _cachedStatus()) ?? SubscriptionInfo();
  }

  Future<(bool success, String message)> activateSubscription(
      String platformSubscriptionId, {String? transactionId}) async {
    try {
      final json = await _api.postJson(
        '/api/subscription/activate',
        SubscriptionActivateRequest(
          platform: _normalizedPlatform(),
          platformSubscriptionId: platformSubscriptionId,
          transactionId: transactionId,
        ).toJson(),
      );
      final resp = json is Map<String, dynamic> ? SubscriptionResponse.fromJson(json) : null;
      if (resp?.success == true) {
        await getSubscriptionStatus();
        _statusChanged.add(SubscriptionStatus.active);
        return (true, resp?.message ?? 'Subscription activated successfully');
      }
      return (false, resp?.message ?? 'Failed to activate subscription');
    } catch (_) {
      return (false, 'An error occurred while activating your subscription');
    }
  }

  Future<(bool success, String message)> validateAppleTransaction(
      String transactionId) async {
    try {
      if (transactionId.trim().isEmpty) return (false, 'Invalid transaction ID');
      final json = await _api.postJson(
        '/api/subscription/validate/apple/transaction',
        AppleTransactionValidationRequest(transactionId: transactionId.trim()).toJson(),
      );
      final resp = json is Map<String, dynamic> ? SubscriptionResponse.fromJson(json) : null;
      if (resp?.success == true) {
        await getSubscriptionStatus();
        _statusChanged.add(SubscriptionStatus.active);
        return (true, resp?.message ?? 'Apple subscription validated successfully');
      }
      return (false, resp?.message ?? 'Failed to validate Apple transaction');
    } catch (_) {
      return (false, 'An error occurred while validating your Apple purchase');
    }
  }

  Future<(bool success, String message)> validateGooglePurchase(
      String purchaseToken) async {
    try {
      final json = await _api.postJson(
        '/api/subscription/validate/google',
        GooglePurchaseTokenRequest(purchaseToken: purchaseToken).toJson(),
      );
      final resp = json is Map<String, dynamic> ? SubscriptionResponse.fromJson(json) : null;
      if (resp?.success == true) {
        await getSubscriptionStatus();
        _statusChanged.add(SubscriptionStatus.active);
        return (true, resp?.message ?? 'Google subscription validated successfully');
      }
      return (false, resp?.message ?? 'Failed to validate Google purchase');
    } catch (_) {
      return (false, 'An error occurred while validating your Google purchase');
    }
  }

  Future<(bool isValid, String message)> validateSubscription() async {
    try {
      final json = await _api.postJson(
          '/api/subscription/validate-subscription', <String, dynamic>{});
      if (json is Map<String, dynamic>) {
        final resp = SubscriptionLoginValidationResponse.fromJson(json);
        if (resp.isValid) {
          await getSubscriptionStatus();
        } else {
          clearCache();
        }
        return (resp.isValid, resp.message ?? 'Subscription validation completed');
      }
    } catch (_) {/* fall through */}
    return (false, 'Unable to validate subscription status with server');
  }

  Future<bool> validateAppleSubscriptionInBackground() async {
    try {
      if (Platform.isIOS) {
        final (isValid, _) = await validateSubscription();
        return isValid;
      }
      final info = await getSubscriptionStatus();
      return info.hasActiveSubscription;
    } catch (_) {
      return false;
    }
  }

  /// Server-side restore for Apple transaction ids gathered by the native
  /// restore flow (the HTTP half of `RestorePurchasesAsync`).
  Future<(bool success, String message)> restoreAppleTransactions(
      List<String> transactionIds) async {
    try {
      final json = await _api.postJson(
          '/api/subscription/restore/apple', AppleRestoreRequest(transactionIds: transactionIds).toJson());
      final resp = json is Map<String, dynamic> ? SubscriptionResponse.fromJson(json) : null;
      if (resp?.success == true) {
        await getSubscriptionStatus();
        _statusChanged.add(SubscriptionStatus.active);
        return (true, resp?.message ?? 'Subscription successfully restored.');
      }
      return (false, resp?.message ?? 'Found previous purchases but validation failed.');
    } catch (_) {
      return (false, 'An error occurred while restoring purchases.');
    }
  }

  // ---- Native store flows (phase 3) --------------------------------------

  /// TODO(phase 3): StoreKit purchase via `in_app_purchase`, then
  /// [validateAppleTransaction]. iOS only.
  Future<(bool success, String message)> handleAppleSubscription(
          {SubscriptionPlan plan = SubscriptionPlan.monthly}) async =>
      (false, 'Apple subscriptions are only available on iOS devices.');

  /// TODO(phase 3): Play Billing purchase via `in_app_purchase`, then
  /// [validateGooglePurchase]. Android only.
  Future<(bool success, String message)> handleGoogleSubscription(
          {SubscriptionPlan plan = SubscriptionPlan.monthly}) async =>
      (false, 'Google subscriptions are only available on Android devices.');

  /// TODO(phase 3): StoreKit restore via `in_app_purchase`, then
  /// [restoreAppleTransactions]. iOS only.
  Future<(bool success, String message)> restorePurchases() async =>
      (false, 'Restore Purchases is only available on iOS devices.');

  // ---- Cache --------------------------------------------------------------

  Future<void> _cacheStatus(SubscriptionInfo info) async {
    try {
      await Preferences.setString(_subscriptionStatusKey, jsonEncode(info.toJson()));
      await Preferences.setString(
          _lastCheckKey, DateTime.now().toUtc().toIso8601String());
    } catch (_) {/* ignore */}
  }

  Future<SubscriptionInfo?> _cachedStatus() async {
    try {
      final json = Preferences.getString(_subscriptionStatusKey, '');
      final lastCheckStr = Preferences.getString(_lastCheckKey, '');
      if (json.isEmpty || lastCheckStr.isEmpty) return null;
      final lastCheck = DateTime.tryParse(lastCheckStr);
      if (lastCheck == null) return null;
      if (DateTime.now().toUtc().difference(lastCheck) < const Duration(minutes: 5)) {
        final decoded = jsonDecode(json);
        if (decoded is Map<String, dynamic>) {
          return SubscriptionInfo.fromCache(decoded);
        }
      }
    } catch (_) {/* ignore */}
    return null;
  }

  void clearCache() {
    Preferences.remove(_subscriptionStatusKey);
    Preferences.remove(_lastCheckKey);
  }

  String _normalizedPlatform() {
    if (Platform.isIOS) return 'Apple';
    if (Platform.isAndroid) return 'Google';
    return 'Unknown';
  }

  void dispose() => _statusChanged.close();
}
