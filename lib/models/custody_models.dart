// DTOs for the custody-proposal domain. 1:1 with `Services/CustodyProposalService.cs`
// (which uses explicit camelCase [JsonPropertyName] attributes). Response types have
// fromJson; request types have toJson (nulls omitted to match the client's
// DefaultIgnoreCondition = WhenWritingNull).

DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
// Date-only parse: keep the parsed calendar components as-is (no toLocal) so a timezone
// suffix on the wire value can never shift the date.
DateTime? _dateOnly(dynamic v) {
  final d = _date(v);
  return d == null ? null : DateTime(d.year, d.month, d.day);
}
double? _dbl(dynamic v) => v == null ? null : (v as num).toDouble();

Map<String, dynamic> _stripNulls(Map<String, dynamic> m) {
  m.removeWhere((_, v) => v == null);
  return m;
}

// ---- Shared --------------------------------------------------------------

class SuccessResponse {
  SuccessResponse({this.success = false, this.message});
  final bool success;
  final String? message;
  factory SuccessResponse.fromJson(Map<String, dynamic> j) => SuccessResponse(
        success: j['success'] as bool? ?? false,
        message: j['message'] as String?,
      );
}

// ---- Responses -----------------------------------------------------------

class ActiveProposalResponse {
  ActiveProposalResponse({this.hasActiveProposal = false, this.proposal});
  final bool hasActiveProposal;
  final CustodyProposalDto? proposal;
  factory ActiveProposalResponse.fromJson(Map<String, dynamic> j) =>
      ActiveProposalResponse(
        hasActiveProposal: j['hasActiveProposal'] as bool? ?? false,
        proposal: j['proposal'] == null
            ? null
            : CustodyProposalDto.fromJson(j['proposal'] as Map<String, dynamic>),
      );
}

class CustodyProposalDto {
  CustodyProposalDto({
    this.proposalId = 0,
    this.chainId = '',
    this.version = 0,
    this.status = '',
    this.patternLength = 0,
    this.proposerEmail = '',
    this.isCurrentUserProposer = false,
    this.canEdit = false,
    this.canRespond = false,
    this.canWithdraw = false,
    this.createdAt,
    this.submittedAt,
    this.notes,
    this.days = const [],
    this.overrides = const [],
  });
  final int proposalId;
  final String chainId;
  final int version;
  final String status;
  final int patternLength;
  final String proposerEmail;
  final bool isCurrentUserProposer;
  final bool canEdit;
  final bool canRespond;
  final bool canWithdraw;
  final DateTime? createdAt;
  final DateTime? submittedAt;
  final String? notes;
  final List<ProposalDayDto> days;
  final List<ProposalOverrideDto> overrides;

  factory CustodyProposalDto.fromJson(Map<String, dynamic> j) => CustodyProposalDto(
        proposalId: (j['proposalId'] as num?)?.toInt() ?? 0,
        chainId: j['chainId']?.toString() ?? '',
        version: (j['version'] as num?)?.toInt() ?? 0,
        status: j['status'] as String? ?? '',
        patternLength: (j['patternLength'] as num?)?.toInt() ?? 0,
        proposerEmail: j['proposerEmail'] as String? ?? '',
        isCurrentUserProposer: j['isCurrentUserProposer'] as bool? ?? false,
        canEdit: j['canEdit'] as bool? ?? false,
        canRespond: j['canRespond'] as bool? ?? false,
        canWithdraw: j['canWithdraw'] as bool? ?? false,
        createdAt: _date(j['createdAt']),
        submittedAt: _date(j['submittedAt']),
        notes: j['notes'] as String?,
        days: (j['days'] as List<dynamic>? ?? [])
            .map((e) => ProposalDayDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        overrides: (j['overrides'] as List<dynamic>? ?? [])
            .map((e) => ProposalOverrideDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ProposalDayDto {
  ProposalDayDto({
    this.weekIndex = 0,
    this.dayIndex = 0,
    this.parentAssignment = 'None',
    this.transferTime,
    this.transferEndTime,
    this.dayStatus = 'normal',
    this.hasConflict = false,
    this.conflictReason,
    this.conflictMarkedBy,
    this.isChangedFromPrevious = false,
    this.previousAssignment,
    this.transferLatitude,
    this.transferLongitude,
    this.transferLocationName,
    this.transferAddress,
  });
  final int weekIndex;
  final int dayIndex;
  final String parentAssignment;
  final String? transferTime;
  final String? transferEndTime;
  final String dayStatus;
  final bool hasConflict;
  final String? conflictReason;
  final String? conflictMarkedBy;
  final bool isChangedFromPrevious;
  final String? previousAssignment;
  final double? transferLatitude;
  final double? transferLongitude;
  final String? transferLocationName;
  final String? transferAddress;

  factory ProposalDayDto.fromJson(Map<String, dynamic> j) => ProposalDayDto(
        weekIndex: (j['weekIndex'] as num?)?.toInt() ?? 0,
        dayIndex: (j['dayIndex'] as num?)?.toInt() ?? 0,
        parentAssignment: j['parentAssignment'] as String? ?? 'None',
        transferTime: j['transferTime'] as String?,
        transferEndTime: j['transferEndTime'] as String?,
        dayStatus: j['dayStatus'] as String? ?? 'normal',
        hasConflict: j['hasConflict'] as bool? ?? false,
        conflictReason: j['conflictReason'] as String?,
        conflictMarkedBy: j['conflictMarkedBy'] as String?,
        isChangedFromPrevious: j['isChangedFromPrevious'] as bool? ?? false,
        previousAssignment: j['previousAssignment'] as String?,
        transferLatitude: _dbl(j['transferLatitude']),
        transferLongitude: _dbl(j['transferLongitude']),
        transferLocationName: j['transferLocationName'] as String?,
        transferAddress: j['transferAddress'] as String?,
      );
}

class ProposalOverrideDto {
  ProposalOverrideDto({
    this.dateKey = '',
    this.originalDateKey,
    this.month = 0,
    this.day = 0,
    this.parentAssignment = 'None',
    this.transferTime,
    this.transferEndTime,
    this.description,
    this.isAnnual = false,
    this.holidayRule,
    this.alternationMode = 'fixed',
    this.alternationStartParent,
    this.overrideStatus = 'normal',
    this.hasConflict = false,
    this.conflictReason,
    this.conflictMarkedBy,
    this.isNewInThisVersion = false,
    this.isChangedFromPrevious = false,
    this.isMarkedForDeletion = false,
    this.transferLatitude,
    this.transferLongitude,
    this.transferLocationName,
    this.transferAddress,
  });
  final String dateKey;

  /// Local-only (JsonIgnore in C#): tracks the original date when the date is changed.
  final String? originalDateKey;
  final int month;
  final int day;
  final String parentAssignment;
  final String? transferTime;
  final String? transferEndTime;
  final String? description;
  final bool isAnnual;
  final String? holidayRule;
  final String alternationMode;
  final String? alternationStartParent;
  final String overrideStatus;
  final bool hasConflict;
  final String? conflictReason;
  final String? conflictMarkedBy;
  final bool isNewInThisVersion;
  final bool isChangedFromPrevious;
  final bool isMarkedForDeletion;
  final double? transferLatitude;
  final double? transferLongitude;
  final String? transferLocationName;
  final String? transferAddress;

  factory ProposalOverrideDto.fromJson(Map<String, dynamic> j) => ProposalOverrideDto(
        dateKey: j['dateKey'] as String? ?? '',
        month: (j['month'] as num?)?.toInt() ?? 0,
        day: (j['day'] as num?)?.toInt() ?? 0,
        parentAssignment: j['parentAssignment'] as String? ?? 'None',
        transferTime: j['transferTime'] as String?,
        transferEndTime: j['transferEndTime'] as String?,
        description: j['description'] as String?,
        isAnnual: j['isAnnual'] as bool? ?? false,
        holidayRule: j['holidayRule'] as String?,
        alternationMode: j['alternationMode'] as String? ?? 'fixed',
        alternationStartParent: j['alternationStartParent'] as String?,
        overrideStatus: j['overrideStatus'] as String? ?? 'normal',
        hasConflict: j['hasConflict'] as bool? ?? false,
        conflictReason: j['conflictReason'] as String?,
        conflictMarkedBy: j['conflictMarkedBy'] as String?,
        isNewInThisVersion: j['isNewInThisVersion'] as bool? ?? false,
        isChangedFromPrevious: j['isChangedFromPrevious'] as bool? ?? false,
        isMarkedForDeletion: j['isMarkedForDeletion'] as bool? ?? false,
        transferLatitude: _dbl(j['transferLatitude']),
        transferLongitude: _dbl(j['transferLongitude']),
        transferLocationName: j['transferLocationName'] as String?,
        transferAddress: j['transferAddress'] as String?,
      );
}

class ProposalSummaryDto {
  ProposalSummaryDto({
    this.proposalId = 0,
    this.chainId = '',
    this.version = 0,
    this.status = '',
    this.patternLength = 0,
    this.proposerEmail = '',
    this.isCurrentUserProposer = false,
    this.createdAt,
    this.submittedAt,
    this.resolvedAt,
    this.dayCount = 0,
    this.overrideCount = 0,
    this.conflictCount = 0,
  });
  final int proposalId;
  final String chainId;
  final int version;
  final String status;
  final int patternLength;
  final String proposerEmail;
  final bool isCurrentUserProposer;
  final DateTime? createdAt;
  final DateTime? submittedAt;
  final DateTime? resolvedAt;
  final int dayCount;
  final int overrideCount;
  final int conflictCount;

  factory ProposalSummaryDto.fromJson(Map<String, dynamic> j) => ProposalSummaryDto(
        proposalId: (j['proposalId'] as num?)?.toInt() ?? 0,
        chainId: j['chainId']?.toString() ?? '',
        version: (j['version'] as num?)?.toInt() ?? 0,
        status: j['status'] as String? ?? '',
        patternLength: (j['patternLength'] as num?)?.toInt() ?? 0,
        proposerEmail: j['proposerEmail'] as String? ?? '',
        isCurrentUserProposer: j['isCurrentUserProposer'] as bool? ?? false,
        createdAt: _date(j['createdAt']),
        submittedAt: _date(j['submittedAt']),
        resolvedAt: _date(j['resolvedAt']),
        dayCount: (j['dayCount'] as num?)?.toInt() ?? 0,
        overrideCount: (j['overrideCount'] as num?)?.toInt() ?? 0,
        conflictCount: (j['conflictCount'] as num?)?.toInt() ?? 0,
      );
}

class ApprovedScheduleResponse {
  ApprovedScheduleResponse({
    this.patternLength = 0,
    this.patternAnchorDate,
    this.days = const [],
    this.overrides = const [],
  });
  final int patternLength;

  /// Persistent week-0 Sunday for the repeating pattern (date-only). Null for rows the
  /// server backfill hasn't reached yet — callers fall back to the legacy month anchor.
  final DateTime? patternAnchorDate;
  final List<ApprovedDayDto> days;
  final List<ApprovedOverrideDto> overrides;

  /// True when an actual approved schedule exists (has days configured).
  bool get hasSchedule => days.isNotEmpty;

  factory ApprovedScheduleResponse.fromJson(Map<String, dynamic> j) =>
      ApprovedScheduleResponse(
        patternLength: (j['patternLength'] as num?)?.toInt() ?? 0,
        patternAnchorDate: _dateOnly(j['patternAnchorDate']),
        days: (j['days'] as List<dynamic>? ?? [])
            .map((e) => ApprovedDayDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        overrides: (j['overrides'] as List<dynamic>? ?? [])
            .map((e) => ApprovedOverrideDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ApprovedDayDto {
  ApprovedDayDto({
    this.weekIndex = 0,
    this.dayIndex = 0,
    this.parentAssignment = 'None',
    this.transferTime,
    this.transferEndTime,
    this.transferLatitude,
    this.transferLongitude,
    this.transferLocationName,
    this.transferAddress,
  });
  final int weekIndex;
  final int dayIndex;
  final String parentAssignment;
  final String? transferTime;
  final String? transferEndTime;
  final double? transferLatitude;
  final double? transferLongitude;
  final String? transferLocationName;
  final String? transferAddress;

  factory ApprovedDayDto.fromJson(Map<String, dynamic> j) => ApprovedDayDto(
        weekIndex: (j['weekIndex'] as num?)?.toInt() ?? 0,
        dayIndex: (j['dayIndex'] as num?)?.toInt() ?? 0,
        parentAssignment: j['parentAssignment'] as String? ?? 'None',
        transferTime: j['transferTime'] as String?,
        transferEndTime: j['transferEndTime'] as String?,
        transferLatitude: _dbl(j['transferLatitude']),
        transferLongitude: _dbl(j['transferLongitude']),
        transferLocationName: j['transferLocationName'] as String?,
        transferAddress: j['transferAddress'] as String?,
      );
}

class ApprovedOverrideDto {
  ApprovedOverrideDto({
    this.dateKey = '',
    this.month = 0,
    this.day = 0,
    this.parentAssignment = 'None',
    this.transferTime,
    this.transferEndTime,
    this.description,
    this.isAnnual = false,
    this.holidayRule,
    this.alternationMode = 'fixed',
    this.alternationStartParent,
    this.transferLatitude,
    this.transferLongitude,
    this.transferLocationName,
    this.transferAddress,
  });
  final String dateKey;
  final int month;
  final int day;
  final String parentAssignment;
  final String? transferTime;
  final String? transferEndTime;
  final String? description;
  final bool isAnnual;
  final String? holidayRule;
  final String alternationMode;
  final String? alternationStartParent;
  final double? transferLatitude;
  final double? transferLongitude;
  final String? transferLocationName;
  final String? transferAddress;

  factory ApprovedOverrideDto.fromJson(Map<String, dynamic> j) => ApprovedOverrideDto(
        dateKey: j['dateKey'] as String? ?? '',
        month: (j['month'] as num?)?.toInt() ?? 0,
        day: (j['day'] as num?)?.toInt() ?? 0,
        parentAssignment: j['parentAssignment'] as String? ?? 'None',
        transferTime: j['transferTime'] as String?,
        transferEndTime: j['transferEndTime'] as String?,
        description: j['description'] as String?,
        isAnnual: j['isAnnual'] as bool? ?? false,
        holidayRule: j['holidayRule'] as String?,
        alternationMode: j['alternationMode'] as String? ?? 'fixed',
        alternationStartParent: j['alternationStartParent'] as String?,
        transferLatitude: _dbl(j['transferLatitude']),
        transferLongitude: _dbl(j['transferLongitude']),
        transferLocationName: j['transferLocationName'] as String?,
        transferAddress: j['transferAddress'] as String?,
      );
}

class ProposalComparisonResponse {
  ProposalComparisonResponse({
    this.proposalId = 0,
    this.version = 0,
    this.status = '',
    this.proposerEmail = '',
    this.createdAt,
    this.submittedAt,
    this.changedDays = const [],
    this.changedOverrides = const [],
    this.conflictDays = const [],
    this.conflictOverrides = const [],
    this.hasChanges = false,
    this.hasConflicts = false,
  });
  final int proposalId;
  final int version;
  final String status;
  final String proposerEmail;
  final DateTime? createdAt;
  final DateTime? submittedAt;
  final List<DayComparisonDto> changedDays;
  final List<OverrideComparisonDto> changedOverrides;
  final List<DayComparisonDto> conflictDays;
  final List<OverrideComparisonDto> conflictOverrides;
  final bool hasChanges;
  final bool hasConflicts;

  factory ProposalComparisonResponse.fromJson(Map<String, dynamic> j) =>
      ProposalComparisonResponse(
        proposalId: (j['proposalId'] as num?)?.toInt() ?? 0,
        version: (j['version'] as num?)?.toInt() ?? 0,
        status: j['status'] as String? ?? '',
        proposerEmail: j['proposerEmail'] as String? ?? '',
        createdAt: _date(j['createdAt']),
        submittedAt: _date(j['submittedAt']),
        changedDays: (j['changedDays'] as List<dynamic>? ?? [])
            .map((e) => DayComparisonDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        changedOverrides: (j['changedOverrides'] as List<dynamic>? ?? [])
            .map((e) => OverrideComparisonDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        conflictDays: (j['conflictDays'] as List<dynamic>? ?? [])
            .map((e) => DayComparisonDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        conflictOverrides: (j['conflictOverrides'] as List<dynamic>? ?? [])
            .map((e) => OverrideComparisonDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        hasChanges: j['hasChanges'] as bool? ?? false,
        hasConflicts: j['hasConflicts'] as bool? ?? false,
      );
}

class DayComparisonDto {
  DayComparisonDto({
    this.weekIndex = 0,
    this.dayIndex = 0,
    this.currentAssignment = 'None',
    this.previousAssignment,
    this.dayStatus = 'normal',
    this.conflictReason,
    this.conflictMarkedBy,
  });
  final int weekIndex;
  final int dayIndex;
  final String currentAssignment;
  final String? previousAssignment;
  final String dayStatus;
  final String? conflictReason;
  final String? conflictMarkedBy;

  factory DayComparisonDto.fromJson(Map<String, dynamic> j) => DayComparisonDto(
        weekIndex: (j['weekIndex'] as num?)?.toInt() ?? 0,
        dayIndex: (j['dayIndex'] as num?)?.toInt() ?? 0,
        currentAssignment: j['currentAssignment'] as String? ?? 'None',
        previousAssignment: j['previousAssignment'] as String?,
        dayStatus: j['dayStatus'] as String? ?? 'normal',
        conflictReason: j['conflictReason'] as String?,
        conflictMarkedBy: j['conflictMarkedBy'] as String?,
      );
}

class OverrideComparisonDto {
  OverrideComparisonDto({
    this.dateKey = '',
    this.month = 0,
    this.day = 0,
    this.currentAssignment = 'None',
    this.description,
    this.overrideStatus = 'normal',
    this.conflictReason,
    this.conflictMarkedBy,
    this.isNew = false,
    this.isDeleted = false,
  });
  final String dateKey;
  final int month;
  final int day;
  final String currentAssignment;
  final String? description;
  final String overrideStatus;
  final String? conflictReason;
  final String? conflictMarkedBy;
  final bool isNew;
  final bool isDeleted;

  factory OverrideComparisonDto.fromJson(Map<String, dynamic> j) =>
      OverrideComparisonDto(
        dateKey: j['dateKey'] as String? ?? '',
        month: (j['month'] as num?)?.toInt() ?? 0,
        day: (j['day'] as num?)?.toInt() ?? 0,
        currentAssignment: j['currentAssignment'] as String? ?? 'None',
        description: j['description'] as String?,
        overrideStatus: j['overrideStatus'] as String? ?? 'normal',
        conflictReason: j['conflictReason'] as String?,
        conflictMarkedBy: j['conflictMarkedBy'] as String?,
        isNew: j['isNew'] as bool? ?? false,
        isDeleted: j['isDeleted'] as bool? ?? false,
      );
}

// ---- Requests ------------------------------------------------------------

class CreateProposalRequest {
  CreateProposalRequest({this.patternLength = 1});
  final int patternLength;
  Map<String, dynamic> toJson() => {'patternLength': patternLength};
}

class UpdateDayRequest {
  UpdateDayRequest({
    required this.weekIndex,
    required this.dayIndex,
    this.parentAssignment = 'None',
    this.transferTime,
    this.transferEndTime,
    this.locationName,
    this.locationAddress,
    this.latitude,
    this.longitude,
    this.dayStatus,
    this.hasConflict = false,
    this.conflictReason,
    this.conflictMarkedBy,
  });
  final int weekIndex;
  final int dayIndex;
  final String parentAssignment;
  final String? transferTime;
  final String? transferEndTime;
  final String? locationName;
  final String? locationAddress;
  final double? latitude;
  final double? longitude;
  final String? dayStatus;
  final bool hasConflict;
  final String? conflictReason;
  final String? conflictMarkedBy;

  Map<String, dynamic> toJson() => _stripNulls({
        'weekIndex': weekIndex,
        'dayIndex': dayIndex,
        'parentAssignment': parentAssignment,
        'transferTime': transferTime,
        'transferEndTime': transferEndTime,
        'locationName': locationName,
        'locationAddress': locationAddress,
        'latitude': latitude,
        'longitude': longitude,
        'dayStatus': dayStatus,
        'hasConflict': hasConflict,
        'conflictReason': conflictReason,
        'conflictMarkedBy': conflictMarkedBy,
      });
}

class MarkConflictRequest {
  MarkConflictRequest({required this.weekIndex, required this.dayIndex, this.reason});
  final int weekIndex;
  final int dayIndex;
  final String? reason;
  Map<String, dynamic> toJson() => _stripNulls({
        'weekIndex': weekIndex,
        'dayIndex': dayIndex,
        'reason': reason,
      });
}

class UpdateOverrideRequest {
  UpdateOverrideRequest({
    this.dateKey = '',
    this.originalDateKey,
    this.month = 0,
    this.day = 0,
    this.parentAssignment = 'None',
    this.transferTime,
    this.transferEndTime,
    this.description,
    this.isAnnual = false,
    this.holidayRule,
    this.alternationMode,
    this.alternationStartParent,
    this.locationName,
    this.locationAddress,
    this.latitude,
    this.longitude,
    this.isMarkedForDeletion = false,
  });
  final String dateKey;
  final String? originalDateKey;
  final int month;
  final int day;
  final String parentAssignment;
  final String? transferTime;
  final String? transferEndTime;
  final String? description;
  final bool isAnnual;
  final String? holidayRule;
  final String? alternationMode;
  final String? alternationStartParent;
  final String? locationName;
  final String? locationAddress;
  final double? latitude;
  final double? longitude;
  final bool isMarkedForDeletion;

  Map<String, dynamic> toJson() => _stripNulls({
        'dateKey': dateKey,
        'originalDateKey': originalDateKey,
        'month': month,
        'day': day,
        'parentAssignment': parentAssignment,
        'transferTime': transferTime,
        'transferEndTime': transferEndTime,
        'description': description,
        'isAnnual': isAnnual,
        'holidayRule': holidayRule,
        'alternationMode': alternationMode,
        'alternationStartParent': alternationStartParent,
        'locationName': locationName,
        'locationAddress': locationAddress,
        'latitude': latitude,
        'longitude': longitude,
        'isMarkedForDeletion': isMarkedForDeletion,
      });
}

class MarkOverrideConflictRequest {
  MarkOverrideConflictRequest({required this.dateKey, this.reason});
  final String dateKey;
  final String? reason;
  Map<String, dynamic> toJson() =>
      _stripNulls({'dateKey': dateKey, 'reason': reason});
}
