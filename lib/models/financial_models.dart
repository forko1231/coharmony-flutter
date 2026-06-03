// DTOs for the financial (charge tracking + receipts) domain. 1:1 with
// `Services/FinancialService.cs` + the charge request types in AppJsonContext.cs.
// Default (camelCase) JSON naming. C# `decimal` -> Dart `double`.

double? _dbl(dynamic v) => v == null ? null : (v as num).toDouble();
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

Map<String, dynamic> _stripNulls(Map<String, dynamic> m) {
  m.removeWhere((_, v) => v == null);
  return m;
}

class FCharge {
  FCharge({
    this.chargeId = 0,
    this.email,
    this.date,
    this.repeatPattern,
    this.amount = 0,
    this.type,
    this.isPaid = false,
    this.fromWho,
    this.category,
    this.paymentStatus = 'unpaid',
    this.paidDate,
    this.verificationRequestDate,
    this.verifiedDate,
    this.disputedDate,
    this.disputeReason,
    this.splitPercentage,
    this.isSplitPayment = false,
    this.linkedChargeId,
    this.receiptUrl,
  });
  final int chargeId;
  final String? email;
  final DateTime? date;
  final String? repeatPattern;
  final double amount;
  final String? type;
  final bool isPaid;
  final String? fromWho;
  final String? category;
  final String paymentStatus;
  final DateTime? paidDate;
  final DateTime? verificationRequestDate;
  final DateTime? verifiedDate;
  final DateTime? disputedDate;
  final String? disputeReason;
  final double? splitPercentage;
  final bool isSplitPayment;
  final int? linkedChargeId;
  final String? receiptUrl;

  factory FCharge.fromJson(Map<String, dynamic> j) => FCharge(
        chargeId: (j['chargeId'] as num?)?.toInt() ?? 0,
        email: j['email'] as String?,
        date: _date(j['date']),
        repeatPattern: j['repeatPattern'] as String?,
        amount: _dbl(j['amount']) ?? 0,
        type: j['type'] as String?,
        isPaid: j['isPaid'] as bool? ?? false,
        fromWho: j['fromWho'] as String?,
        category: j['category'] as String?,
        paymentStatus: j['paymentStatus'] as String? ?? 'unpaid',
        paidDate: _date(j['paidDate']),
        verificationRequestDate: _date(j['verificationRequestDate']),
        verifiedDate: _date(j['verifiedDate']),
        disputedDate: _date(j['disputedDate']),
        disputeReason: j['disputeReason'] as String?,
        splitPercentage: _dbl(j['splitPercentage']),
        isSplitPayment: j['isSplitPayment'] as bool? ?? false,
        linkedChargeId: (j['linkedChargeId'] as num?)?.toInt(),
        receiptUrl: j['receiptUrl'] as String?,
      );
}

// ---- Requests ------------------------------------------------------------

class ChargeRequest {
  ChargeRequest({
    required this.date,
    this.repeatPattern,
    required this.amount,
    required this.type,
    this.isPaid = false,
    this.splitPercentage,
    this.isSplitPayment = false,
  });
  final DateTime date;
  final String? repeatPattern;
  final double amount;
  final String type;
  final bool isPaid;
  final double? splitPercentage;
  final bool isSplitPayment;

  Map<String, dynamic> toJson() => _stripNulls({
        'date': date.toIso8601String(),
        'repeatPattern': repeatPattern,
        'amount': amount,
        'type': type,
        'isPaid': isPaid,
        'splitPercentage': splitPercentage,
        'isSplitPayment': isSplitPayment,
      });
}

class ChargeStatusUpdateRequest {
  ChargeStatusUpdateRequest({
    required this.chargeId,
    required this.paymentStatus,
    this.category,
    this.receiptUrl,
  });
  final int chargeId;
  final String paymentStatus;
  final String? category;
  final String? receiptUrl;

  Map<String, dynamic> toJson() => _stripNulls({
        'chargeId': chargeId,
        'paymentStatus': paymentStatus,
        'category': category,
        'receiptUrl': receiptUrl,
      });
}

class ChargeVerificationRequest {
  ChargeVerificationRequest({
    required this.chargeId,
    required this.isVerified,
    this.disputeReason,
  });
  final int chargeId;
  final bool isVerified;
  final String? disputeReason;

  Map<String, dynamic> toJson() => _stripNulls({
        'chargeId': chargeId,
        'isVerified': isVerified,
        'disputeReason': disputeReason,
      });
}

class ReceiptUploadRequest {
  ReceiptUploadRequest({required this.base64Data, required this.fileName});
  final String base64Data;
  final String fileName;
  Map<String, dynamic> toJson() =>
      {'base64Data': base64Data, 'fileName': fileName};
}

// ---- Responses -----------------------------------------------------------

class ReceiptUploadResponse {
  ReceiptUploadResponse({this.success = false, this.message, this.receiptUrl});
  final bool success;
  final String? message;
  final String? receiptUrl;
  factory ReceiptUploadResponse.fromJson(Map<String, dynamic> j) =>
      ReceiptUploadResponse(
        success: j['success'] as bool? ?? false,
        message: j['message'] as String?,
        receiptUrl: j['receiptUrl'] as String?,
      );
}

class ReceiptResponse {
  ReceiptResponse({this.base64Data, this.fileName, this.contentType});
  final String? base64Data;
  final String? fileName;
  final String? contentType;
  factory ReceiptResponse.fromJson(Map<String, dynamic> j) => ReceiptResponse(
        base64Data: j['base64Data'] as String?,
        fileName: j['fileName'] as String?,
        contentType: j['contentType'] as String?,
      );
}
