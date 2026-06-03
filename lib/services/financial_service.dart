import '../models/financial_models.dart';
import 'api_client.dart';

/// Port of `Services/FinancialService.cs`. Charge tracking (who-owes-who) and
/// receipt management. Routes/payloads are 1:1 with the C# service and
/// `FinancialController.cs`.
class FinancialService {
  FinancialService(this._api);
  final ApiClient _api;

  Future<List<FCharge>> getCharges({DateTime? date}) async {
    final dateParam = date != null ? '?date=${_ymd(date)}' : '';
    final json = await _api.getJson('api/financial/charges$dateParam');
    if (json is List) {
      return json.map((e) => FCharge.fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<String> makeCharge(
    DateTime date,
    String repeatPattern,
    double amount,
    String chargeType, {
    bool isPaid = false,
    double? splitPercentage,
  }) async {
    return _api.postForString(
      'api/financial/charge',
      ChargeRequest(
        date: date,
        repeatPattern: repeatPattern,
        amount: amount,
        type: chargeType,
        isPaid: isPaid,
        splitPercentage: splitPercentage,
        isSplitPayment: splitPercentage != null,
      ).toJson(),
    );
  }

  Future<String> updateChargePaymentStatus(int chargeId, String newStatus,
      {String? category}) async {
    return _api.postForString(
      'api/financial/charge/update-status',
      ChargeStatusUpdateRequest(
              chargeId: chargeId, paymentStatus: newStatus, category: category)
          .toJson(),
    );
  }

  Future<String> verifyOrDisputePayment(int chargeId, bool isVerified,
      {String disputeReason = 'none'}) async {
    return _api.postForString(
      'api/financial/charge/verify',
      ChargeVerificationRequest(
              chargeId: chargeId, isVerified: isVerified, disputeReason: disputeReason)
          .toJson(),
    );
  }

  Future<List<FCharge>> getChargesAwaitingVerification() async {
    final json = await _api.getJson('api/financial/charges/awaiting-verification');
    if (json is List) {
      return json.map((e) => FCharge.fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<ReceiptUploadResponse> uploadReceipt(
      int chargeId, String base64Data, String fileName) async {
    final json = await _api.postJson(
      'api/financial/charge/$chargeId/receipt',
      ReceiptUploadRequest(base64Data: base64Data, fileName: fileName).toJson(),
    );
    return json is Map<String, dynamic>
        ? ReceiptUploadResponse.fromJson(json)
        : ReceiptUploadResponse(success: false, message: 'Failed to upload receipt');
  }

  Future<ReceiptResponse?> getReceipt(int chargeId) async {
    final json = await _api.getJson('api/financial/charge/$chargeId/receipt');
    if (json is Map<String, dynamic>) {
      final r = ReceiptResponse.fromJson(json);
      if (r.base64Data != null && r.base64Data!.isNotEmpty) return r;
    }
    return null;
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
