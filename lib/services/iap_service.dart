import 'dart:async';
import 'dart:io' show Platform;

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../models/subscription_models.dart';
import 'subscription_service.dart';

/// Native store purchase/restore via `in_app_purchase` — the phase-3 half of MAUI's
/// `SubscriptionService.HandleAppleSubscriptionAsync` / `HandleGoogleSubscriptionAsync`
/// / `RestorePurchasesAsync`. Purchases complete asynchronously on [InAppPurchase.purchaseStream];
/// on a purchased/restored item we hand the transaction id (iOS) or purchase token
/// (Android) to [SubscriptionService] for server validation, then complete the purchase.
///
/// Product ids match the MAUI app's store config:
///   Apple monthly `ERSplitPremium24356`, Apple annual `CoHarmonyPremiumAnnual`,
///   Google subscription `ezsplit_premium_monthly` (monthly/annual are base plans).
class IapService {
  IapService(this._subscription);
  final SubscriptionService _subscription;
  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _sub;
  final _results = StreamController<({bool success, String message})>.broadcast();

  /// Emits the outcome of each purchase/restore so the UI can react.
  Stream<({bool success, String message})> get results => _results.stream;

  static const appleMonthly = 'ERSplitPremium24356';
  static const appleAnnual = 'CoHarmonyPremiumAnnual';
  static const googleProduct = 'ezsplit_premium_monthly';

  /// Google Play base-plan id for the annual plan (any other base plan = monthly).
  /// Matches the Play Console config used by MAUI (note the intentional spelling).
  static const googleAnnualBasePlanId = 'coharmonypremiunannual';

  bool get _supported => Platform.isIOS || Platform.isAndroid;

  /// Begins listening to the purchase stream. Safe to call repeatedly.
  void init() {
    if (!_supported) return;
    _sub ??= _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) => _results.add((success: false, message: 'Purchase error: $e')),
    );
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          continue;
        case PurchaseStatus.error:
          _results.add((success: false, message: p.error?.message ?? 'Purchase failed.'));
        case PurchaseStatus.canceled:
          _results.add((success: false, message: 'Purchase cancelled.'));
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final r = await _validate(p);
          _results.add(r);
      }
      // Always acknowledge so the store doesn't refund / re-deliver.
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
  }

  Future<({bool success, String message})> _validate(PurchaseDetails p) async {
    if (Platform.isIOS) {
      // On StoreKit, purchaseID is the transaction identifier the server re-verifies.
      final (ok, msg) = await _subscription.validateAppleTransaction(p.purchaseID ?? '');
      return (success: ok, message: msg);
    }
    // On Play Billing, serverVerificationData carries the purchase token.
    final (ok, msg) = await _subscription.validateGooglePurchase(p.verificationData.serverVerificationData);
    return (success: ok, message: msg);
  }

  /// Query + start the purchase for [plan]. The result arrives on [results].
  Future<void> buy(SubscriptionPlan plan) async {
    if (!_supported) {
      _results.add((success: false, message: 'Purchases are only available on iOS and Android.'));
      return;
    }
    init();
    if (!await _iap.isAvailable()) {
      _results.add((success: false, message: 'The app store is not available right now.'));
      return;
    }
    final id = Platform.isIOS
        ? (plan == SubscriptionPlan.annual ? appleAnnual : appleMonthly)
        : googleProduct;
    final resp = await _iap.queryProductDetails({id});
    if (resp.productDetails.isEmpty) {
      _results.add((success: false, message: 'That subscription is not available in the store yet.'));
      return;
    }
    final param = _purchaseParamFor(resp, plan);
    if (param == null) {
      _results.add((success: false, message: 'No subscription offers available for this plan yet.'));
      return;
    }
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  /// Builds the purchase param for [plan]. On iOS each plan is a distinct product,
  /// so the single result is used directly. On Android the one subscription product
  /// flattens to one [GooglePlayProductDetails] per base-plan/offer — pick the offer
  /// on the annual base plan (or any non-annual base plan for monthly), preferring a
  /// `free-trial` offer, then any named offer, then the default. Mirrors MAUI's
  /// `HandleGoogleSubscriptionAsync` offer-token selection.
  PurchaseParam? _purchaseParamFor(ProductDetailsResponse resp, SubscriptionPlan plan) {
    if (!Platform.isAndroid) {
      return PurchaseParam(productDetails: resp.productDetails.first);
    }
    final offers = resp.productDetails.whereType<GooglePlayProductDetails>().toList();
    if (offers.isEmpty) return PurchaseParam(productDetails: resp.productDetails.first);

    String? basePlanOf(GooglePlayProductDetails g) {
      final list = g.productDetails.subscriptionOfferDetails;
      final i = g.subscriptionIndex;
      if (list == null || i == null || i >= list.length) return null;
      return list[i].basePlanId;
    }

    String? offerIdOf(GooglePlayProductDetails g) {
      final list = g.productDetails.subscriptionOfferDetails;
      final i = g.subscriptionIndex;
      if (list == null || i == null || i >= list.length) return null;
      return list[i].offerId;
    }

    final wantAnnual = plan == SubscriptionPlan.annual;
    final matches = offers.where((g) {
      final bp = basePlanOf(g);
      if (bp == null) return false;
      return wantAnnual ? bp == googleAnnualBasePlanId : bp != googleAnnualBasePlanId;
    }).toList();

    GooglePlayProductDetails? pick;
    for (final g in matches) {
      if (offerIdOf(g) == 'free-trial') {
        pick = g;
        break;
      }
    }
    if (pick == null) {
      for (final g in matches) {
        if ((offerIdOf(g) ?? '').isNotEmpty) {
          pick = g;
          break;
        }
      }
    }
    pick ??= matches.isNotEmpty ? matches.first : null;
    pick ??= offers.first; // last-resort fallback so a purchase can still proceed
    return GooglePlayPurchaseParam(productDetails: pick, offerToken: pick.offerToken);
  }

  /// Restore previous purchases. Restored items flow through [results].
  Future<void> restore() async {
    if (!_supported) {
      _results.add((success: false, message: 'Restore is only available on iOS and Android.'));
      return;
    }
    init();
    await _iap.restorePurchases();
  }

  void dispose() {
    _sub?.cancel();
    _results.close();
  }
}
