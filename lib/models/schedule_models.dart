// DTOs for the (classic) schedule domain. 1:1 with `Services/ScheduleService.cs`.
//
// IMPORTANT casing note: `ScheduleItem` declares explicit PascalCase
// [JsonPropertyName] keys, but the C# client deserializes case-insensitively
// (AppJsonContext.PropertyNameCaseInsensitive = true), so the server may emit
// either case. ScheduleItem.fromJson therefore reads keys case-insensitively.
// The request DTOs use camelCase keys (matching their [JsonPropertyName]).

double? _dbl(dynamic v) => v == null ? null : (v as num).toDouble();
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

Map<String, dynamic> _stripNulls(Map<String, dynamic> m) {
  m.removeWhere((_, v) => v == null);
  return m;
}

/// Case-insensitive view over a decoded JSON map (mirrors C#
/// PropertyNameCaseInsensitive). Keys are lowercased once on construction.
class _Ci {
  _Ci(Map<String, dynamic> src)
      : _m = {for (final e in src.entries) e.key.toLowerCase(): e.value};
  final Map<String, dynamic> _m;
  dynamic operator [](String key) => _m[key.toLowerCase()];
}

class ScheduleItem {
  ScheduleItem({
    this.scheduleId = 0,
    this.email = '',
    this.month = 0,
    this.day = 0,
    this.year = 0,
    this.tag = '',
    this.startTime = '',
    this.endTime = '',
    this.repeatType = '',
    this.endDate,
    this.status = 'approved',
    this.isCustodial = false,
    this.isOverride = false,
    this.overrideType = '',
    this.isProtected = false,
    this.recurrenceCount = 0,
    this.parentAssignment = '',
    this.notes = '',
    this.proposerEmail = '',
    this.transferLatitude,
    this.transferLongitude,
    this.transferLocationName,
    this.transferAddress,
    this.visibleToKids = true,
    this.needsApproval = false,
    this.isUserCustodyDay = false,
  });

  final int scheduleId;
  final String email;
  final int month;
  final int day;
  final int year;
  final String tag;
  final String startTime;
  final String endTime;
  final String repeatType;
  final DateTime? endDate;
  final String status;
  final bool isCustodial;
  final bool isOverride;
  final String overrideType;
  final bool isProtected;
  final int recurrenceCount;
  final String parentAssignment;
  final String notes;
  final String proposerEmail;
  final double? transferLatitude;
  final double? transferLongitude;
  final String? transferLocationName;
  final String? transferAddress;
  final bool visibleToKids;

  // Client-side only (JsonIgnore in C#).
  bool needsApproval;
  bool isUserCustodyDay;

  bool get hasTransferLocation =>
      transferLatitude != null && transferLongitude != null;

  factory ScheduleItem.fromJson(Map<String, dynamic> json) {
    final j = _Ci(json);
    return ScheduleItem(
      scheduleId: (j['scheduleId'] as num?)?.toInt() ?? 0,
      email: j['email'] as String? ?? '',
      month: (j['month'] as num?)?.toInt() ?? 0,
      day: (j['day'] as num?)?.toInt() ?? 0,
      year: (j['year'] as num?)?.toInt() ?? 0,
      tag: j['tag'] as String? ?? '',
      startTime: j['startTime'] as String? ?? '',
      endTime: j['endTime'] as String? ?? '',
      repeatType: j['repeatType'] as String? ?? '',
      endDate: _date(j['endDate']),
      status: j['status'] as String? ?? 'approved',
      isCustodial: j['isCustodial'] as bool? ?? false,
      isOverride: j['isOverride'] as bool? ?? false,
      overrideType: j['overrideType'] as String? ?? '',
      isProtected: j['isProtected'] as bool? ?? false,
      recurrenceCount: (j['recurrenceCount'] as num?)?.toInt() ?? 0,
      parentAssignment: j['parentAssignment'] as String? ?? '',
      notes: j['notes'] as String? ?? '',
      proposerEmail: j['proposerEmail'] as String? ?? '',
      transferLatitude: _dbl(j['transferLatitude']),
      transferLongitude: _dbl(j['transferLongitude']),
      transferLocationName: j['transferLocationName'] as String?,
      transferAddress: j['transferAddress'] as String?,
      visibleToKids: j['visibleToKids'] as bool? ?? true,
    );
  }
}

// ---- Request DTOs (camelCase) ------------------------------------------

class ScheduleUpdateApiRequest {
  ScheduleUpdateApiRequest({
    required this.month,
    required this.day,
    required this.year,
    this.tag = '',
    this.startTime = '',
    this.endTime = '',
    this.repeatType = '',
    this.endDate = '',
    this.isCustodial = false,
    this.isOverride = false,
    this.overrideType = '',
    this.isProtected = false,
    this.notes = '',
    this.status = 'approved',
    this.proposerEmail = '',
    this.parentAssignment = '',
    this.visibleToKids = true,
  });
  final int month;
  final int day;
  final int year;
  final String tag;
  final String startTime;
  final String endTime;
  final String repeatType;
  final String endDate;
  final bool isCustodial;
  final bool isOverride;
  final String overrideType;
  final bool isProtected;
  final String notes;
  final String status;
  final String proposerEmail;
  final String? parentAssignment;
  final bool visibleToKids;

  Map<String, dynamic> toJson() => _stripNulls({
        'month': month,
        'day': day,
        'year': year,
        'tag': tag,
        'startTime': startTime,
        'endTime': endTime,
        'repeatType': repeatType,
        'endDate': endDate,
        'isCustodial': isCustodial,
        'isOverride': isOverride,
        'overrideType': overrideType,
        'isProtected': isProtected,
        'notes': notes,
        'status': status,
        'proposerEmail': proposerEmail,
        'parentAssignment': parentAssignment,
        'visibleToKids': visibleToKids,
      });
}

class ScheduleUpdateRequest {
  ScheduleUpdateRequest({
    required this.month,
    required this.day,
    required this.year,
    this.tag = '',
    this.startTime = '',
    this.endTime = '',
    this.repeatType = '',
    this.endDate = '',
    this.isCustodial = false,
    this.isOverride = false,
    this.overrideType = '',
    this.isProtected = false,
    this.notes = '',
    this.status = 'approved',
    this.proposerEmail = '',
    this.parentAssignment = '',
    this.transferLatitude,
    this.transferLongitude,
    this.transferLocationName,
    this.transferAddress,
    this.visibleToKids = true,
  });
  final int month;
  final int day;
  final int year;
  final String tag;
  final String startTime;
  final String endTime;
  final String repeatType;
  final String endDate;
  final bool isCustodial;
  final bool isOverride;
  final String overrideType;
  final bool isProtected;
  final String notes;
  final String status;
  final String proposerEmail;
  final String? parentAssignment;
  final double? transferLatitude;
  final double? transferLongitude;
  final String? transferLocationName;
  final String? transferAddress;
  final bool visibleToKids;

  Map<String, dynamic> toJson() => _stripNulls({
        'month': month,
        'day': day,
        'year': year,
        'tag': tag,
        'startTime': startTime,
        'endTime': endTime,
        'repeatType': repeatType,
        'endDate': endDate,
        'isCustodial': isCustodial,
        'isOverride': isOverride,
        'overrideType': overrideType,
        'isProtected': isProtected,
        'notes': notes,
        'status': status,
        'proposerEmail': proposerEmail,
        'parentAssignment': parentAssignment,
        'transferLatitude': transferLatitude,
        'transferLongitude': transferLongitude,
        'transferLocationName': transferLocationName,
        'transferAddress': transferAddress,
        'visibleToKids': visibleToKids,
      });
}

class ScheduleDeleteRequest {
  ScheduleDeleteRequest({
    required this.month,
    required this.day,
    required this.year,
    this.tag = '',
    this.scheduleId,
  });
  final int month;
  final int day;
  final int year;
  final String tag;
  // When set, the server deletes by id with couple authorization (so a co-parent can delete
  // a shared event they don't own). Falls back to the (date,tag) match when null.
  final int? scheduleId;
  Map<String, dynamic> toJson() => {
        'month': month,
        'day': day,
        'year': year,
        'tag': tag,
        if (scheduleId != null && scheduleId! > 0) 'scheduleId': scheduleId,
      };
}

class CustodyProposalResponseItem {
  CustodyProposalResponseItem({
    required this.month,
    required this.day,
    required this.year,
    this.accept = false,
    this.repeatType = '',
  });
  final int month;
  final int day;
  final int year;
  final bool accept;
  final String repeatType;
  Map<String, dynamic> toJson() => {
        'month': month,
        'day': day,
        'year': year,
        'accept': accept,
        'repeatType': repeatType,
      };
}

class CustodyPatternRequest {
  CustodyPatternRequest({
    required this.dayOfWeek,
    this.parent = '',
    this.repeatPattern = '',
    this.hasTransferTime = false,
    this.transferTime = '',
    this.patternStartDate = '',
    this.patternLength = 1,
    this.transferLatitude,
    this.transferLongitude,
    this.transferLocationName,
    this.transferAddress,
  });
  final int dayOfWeek;
  final String parent;
  final String repeatPattern;
  final bool hasTransferTime;
  final String transferTime;
  final String patternStartDate;
  final int patternLength;
  final double? transferLatitude;
  final double? transferLongitude;
  final String? transferLocationName;
  final String? transferAddress;

  Map<String, dynamic> toJson() => _stripNulls({
        'dayOfWeek': dayOfWeek,
        'parent': parent,
        'repeatPattern': repeatPattern,
        'hasTransferTime': hasTransferTime,
        'transferTime': transferTime,
        'patternStartDate': patternStartDate,
        'patternLength': patternLength,
        'transferLatitude': transferLatitude,
        'transferLongitude': transferLongitude,
        'transferLocationName': transferLocationName,
        'transferAddress': transferAddress,
      });
}

class CustodyPatternDeleteRequest {
  CustodyPatternDeleteRequest({required this.dayOfWeek});
  final int dayOfWeek;
  Map<String, dynamic> toJson() => {'dayOfWeek': dayOfWeek};
}

class CustodyPatternSetRequest {
  CustodyPatternSetRequest({
    required this.dayOfWeek,
    this.parent = '',
    this.repeatPattern = '',
    this.hasTransferTime = false,
    this.transferTime,
    this.patternStartDate,
    this.patternLength = 1,
  });
  final int dayOfWeek;
  final String parent;
  final String repeatPattern;
  final bool hasTransferTime;
  final String? transferTime;
  final String? patternStartDate;
  final int patternLength;

  Map<String, dynamic> toJson() => _stripNulls({
        'dayOfWeek': dayOfWeek,
        'parent': parent,
        'repeatPattern': repeatPattern,
        'hasTransferTime': hasTransferTime,
        'transferTime': transferTime,
        'patternStartDate': patternStartDate,
        'patternLength': patternLength,
      });
}

class CustodyProposalResponseRequest {
  CustodyProposalResponseRequest({
    required this.month,
    required this.day,
    required this.year,
    required this.accept,
  });
  final int month;
  final int day;
  final int year;
  final bool accept;
  Map<String, dynamic> toJson() =>
      {'month': month, 'day': day, 'year': year, 'accept': accept};
}

// ---- Response DTOs ------------------------------------------------------

class ScheduleOperationResponse {
  ScheduleOperationResponse({this.success = false, this.message = ''});
  final bool success;
  final String message;
  factory ScheduleOperationResponse.fromJson(Map<String, dynamic> j) =>
      ScheduleOperationResponse(
        success: j['success'] as bool? ?? false,
        message: j['message'] as String? ?? '',
      );
}

class ResponseResult {
  ResponseResult({this.success = false, this.responses = const []});
  final bool success;
  final List<String> responses;
  factory ResponseResult.fromJson(Map<String, dynamic> j) => ResponseResult(
        success: j['success'] as bool? ?? false,
        responses: (j['responses'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      );
}
