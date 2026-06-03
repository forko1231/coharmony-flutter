// DTOs for the subscription domain. 1:1 with `Services/SubscriptionService.cs`
// + the subscription response types in AppJsonContext.cs.
//
// The API status/detail responses use lowercase-first property names that are
// already camelCase (status, hasActiveSubscription, nextBillingDate, ...).

double _dbl(dynamic v) => v == null ? 0 : (v as num).toDouble();
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

enum SubscriptionStatus {
  none,
  active,
  pastDue,
  cancelled,
  expired,
  sharedActive,
  trialActive,
  trialExpired,
  gracePeriod,
  billingRetry,
  onHold,
}

/// Parse the API status string (matches the C# lowercased switch).
SubscriptionStatus subscriptionStatusFromApi(String? s) {
  switch (s?.toLowerCase()) {
    case 'active':
      return SubscriptionStatus.active;
    case 'pastdue':
      return SubscriptionStatus.pastDue;
    case 'cancelled':
      return SubscriptionStatus.cancelled;
    case 'expired':
      return SubscriptionStatus.expired;
    case 'sharedactive':
      return SubscriptionStatus.sharedActive;
    case 'trialactive':
      return SubscriptionStatus.trialActive;
    case 'trialexpired':
      return SubscriptionStatus.trialExpired;
    case 'graceperiod':
      return SubscriptionStatus.gracePeriod;
    case 'billingretry':
      return SubscriptionStatus.billingRetry;
    case 'onhold':
      return SubscriptionStatus.onHold;
    default:
      return SubscriptionStatus.none;
  }
}

/// Which billing plan the user chose on the paywall.
enum SubscriptionPlan { monthly, annual }

class SubscriptionDetails {
  SubscriptionDetails({
    this.type,
    this.platform,
    this.nextBillingDate,
    this.monthlyPrice = 0,
    this.currency,
    this.isShared = false,
    this.originalSubscriberEmail,
    this.sharedWithPartnerEmail,
  });
  final String? type;
  final String? platform;
  final DateTime? nextBillingDate;
  final double monthlyPrice;
  final String? currency;
  final bool isShared;
  final String? originalSubscriberEmail;
  final String? sharedWithPartnerEmail;

  Map<String, dynamic> toJson() => {
        'type': type,
        'platform': platform,
        'nextBillingDate': nextBillingDate?.toIso8601String(),
        'monthlyPrice': monthlyPrice,
        'currency': currency,
        'isShared': isShared,
        'originalSubscriberEmail': originalSubscriberEmail,
        'sharedWithPartnerEmail': sharedWithPartnerEmail,
      };

  factory SubscriptionDetails.fromJson(Map<String, dynamic> j) => SubscriptionDetails(
        type: j['type'] as String?,
        platform: j['platform'] as String?,
        nextBillingDate: _date(j['nextBillingDate']),
        monthlyPrice: _dbl(j['monthlyPrice']),
        currency: j['currency'] as String?,
        isShared: j['isShared'] as bool? ?? false,
        originalSubscriberEmail: j['originalSubscriberEmail'] as String?,
        sharedWithPartnerEmail: j['sharedWithPartnerEmail'] as String?,
      );
}

class SubscriptionInfo {
  SubscriptionInfo({
    this.status = SubscriptionStatus.none,
    this.hasActiveSubscription = false,
    this.subscription,
  });
  final SubscriptionStatus status;
  final bool hasActiveSubscription;
  final SubscriptionDetails? subscription;

  /// Local cache form (stores status by index for a robust round-trip).
  Map<String, dynamic> toJson() => {
        'status': status.index,
        'hasActiveSubscription': hasActiveSubscription,
        'subscription': subscription?.toJson(),
      };

  factory SubscriptionInfo.fromCache(Map<String, dynamic> j) {
    final idx = (j['status'] as num?)?.toInt() ?? 0;
    return SubscriptionInfo(
      status: idx >= 0 && idx < SubscriptionStatus.values.length
          ? SubscriptionStatus.values[idx]
          : SubscriptionStatus.none,
      hasActiveSubscription: j['hasActiveSubscription'] as bool? ?? false,
      subscription: j['subscription'] is Map<String, dynamic>
          ? SubscriptionDetails.fromJson(j['subscription'] as Map<String, dynamic>)
          : null,
    );
  }
}

// ---- API responses -------------------------------------------------------

class SubscriptionStatusApiResponse {
  SubscriptionStatusApiResponse({this.status, this.hasActiveSubscription = false, this.subscription});
  final String? status;
  final bool hasActiveSubscription;
  final SubscriptionDetailsApiResponse? subscription;
  factory SubscriptionStatusApiResponse.fromJson(Map<String, dynamic> j) =>
      SubscriptionStatusApiResponse(
        status: j['status'] as String?,
        hasActiveSubscription: j['hasActiveSubscription'] as bool? ?? false,
        subscription: j['subscription'] is Map<String, dynamic>
            ? SubscriptionDetailsApiResponse.fromJson(
                j['subscription'] as Map<String, dynamic>)
            : null,
      );
}

class SubscriptionDetailsApiResponse {
  SubscriptionDetailsApiResponse({
    this.type,
    this.platform,
    this.nextBillingDate,
    this.monthlyPrice = 0,
    this.currency,
    this.isShared = false,
    this.originalSubscriberEmail,
    this.sharedWithPartnerEmail,
  });
  final String? type;
  final String? platform;
  final DateTime? nextBillingDate;
  final double monthlyPrice;
  final String? currency;
  final bool isShared;
  final String? originalSubscriberEmail;
  final String? sharedWithPartnerEmail;
  factory SubscriptionDetailsApiResponse.fromJson(Map<String, dynamic> j) =>
      SubscriptionDetailsApiResponse(
        type: j['type'] as String?,
        platform: j['platform'] as String?,
        nextBillingDate: _date(j['nextBillingDate']),
        monthlyPrice: _dbl(j['monthlyPrice']),
        currency: j['currency'] as String?,
        isShared: j['isShared'] as bool? ?? false,
        originalSubscriberEmail: j['originalSubscriberEmail'] as String?,
        sharedWithPartnerEmail: j['sharedWithPartnerEmail'] as String?,
      );
}

class SubscriptionResponse {
  SubscriptionResponse({this.success = false, this.message});
  final bool success;
  final String? message;
  factory SubscriptionResponse.fromJson(Map<String, dynamic> j) => SubscriptionResponse(
        success: j['success'] as bool? ?? false,
        message: j['message'] as String?,
      );
}

class SubscriptionLoginValidationResponse {
  SubscriptionLoginValidationResponse({
    this.isValid = false,
    this.hasAccess = false,
    this.message,
    this.requiresSubscription = false,
  });
  final bool isValid;
  final bool hasAccess;
  final String? message;
  final bool requiresSubscription;
  factory SubscriptionLoginValidationResponse.fromJson(Map<String, dynamic> j) =>
      SubscriptionLoginValidationResponse(
        isValid: j['isValid'] as bool? ?? false,
        hasAccess: j['hasAccess'] as bool? ?? false,
        message: j['message'] as String?,
        requiresSubscription: j['requiresSubscription'] as bool? ?? false,
      );
}

// ---- Requests ------------------------------------------------------------

class SubscriptionActivateRequest {
  SubscriptionActivateRequest({
    required this.platform,
    required this.platformSubscriptionId,
    this.transactionId,
  });
  final String platform;
  final String platformSubscriptionId;
  final String? transactionId;
  Map<String, dynamic> toJson() {
    final m = {
      'platform': platform,
      'platformSubscriptionId': platformSubscriptionId,
      'transactionId': transactionId,
    };
    m.removeWhere((_, v) => v == null);
    return m;
  }
}

class AppleTransactionValidationRequest {
  AppleTransactionValidationRequest({required this.transactionId});
  final String transactionId;
  Map<String, dynamic> toJson() => {'transactionId': transactionId};
}

class GooglePurchaseTokenRequest {
  GooglePurchaseTokenRequest({required this.purchaseToken});
  final String purchaseToken;
  Map<String, dynamic> toJson() => {'purchaseToken': purchaseToken};
}

class AppleRestoreRequest {
  AppleRestoreRequest({required this.transactionIds});
  final List<String> transactionIds;
  Map<String, dynamic> toJson() => {'transactionIds': transactionIds};
}
