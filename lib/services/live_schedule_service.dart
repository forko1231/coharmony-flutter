import 'dart:async';

import 'api_client.dart';
import 'websocket_service.dart';

/// Client for the live custody-schedule API (`/api/schedule/live`). Separate from
/// CustodyProposalService — talks to the unified live editor backend.
///
/// Concurrency contract mirrors the server: every content edit carries the
/// [LiveScheduleData.version] it was based on; [LiveOp.conflict] means reload, while
/// [LiveOp.locked] / [LiveOp.lockedDay] mean the other parent is mid bulk-edit or
/// editing that day. Live updates arrive via [onChanged] (the WS `live_schedule` ping).
class LiveScheduleService {
  final ApiClient _api;
  final WebSocketService _ws;

  LiveScheduleService(this._api, this._ws);

  /// Fires (with the new version) when the co-parent changes the schedule. The editor
  /// refetches on this for live updates + lock visuals.
  Stream<int> get onChanged => _ws.onLiveScheduleChanged;

  Future<LiveResult> get() => _send('GET', '', null);

  Future<LiveResult> upsertDay(int baseVersion, LiveDay day) =>
      _send('POST', 'day', {'baseVersion': baseVersion, ...day.fields()});

  Future<LiveResult> upsertOverride(int baseVersion, LiveOverride ov) =>
      _send('POST', 'override', {'baseVersion': baseVersion, ...ov.fields()});

  Future<LiveResult> deleteOverride(int baseVersion, String dateKey) =>
      _send('POST', 'override/delete', {'baseVersion': baseVersion, 'dateKey': dateKey});

  Future<LiveResult> setPatternLength(int baseVersion, int patternLength) =>
      _send('POST', 'pattern-length', {'baseVersion': baseVersion, 'patternLength': patternLength});

  Future<LiveResult> applyBulk(String kind, int patternLength, List<LiveDay> days, List<LiveOverride> overrides) =>
      _send('POST', 'apply', {
        'kind': kind,
        'patternLength': patternLength,
        'days': days.map((d) => d.fields()).toList(),
        'overrides': overrides.map((o) => o.fields()).toList(),
      });

  // Schedule-wide exclusive lock (bulk ops: template / ai / pattern).
  Future<LiveResult> acquireLock(String kind) => _send('POST', 'lock', {'kind': kind});
  Future<bool> heartbeatLock() async => (await _api.sendForResult('POST', _u('lock/heartbeat'), const {})).status == 200;
  Future<LiveResult> releaseLock() => _send('POST', 'lock/release', const {});

  // Advisory per-day lock (presence).
  Future<bool> acquireDayLock(int weekIndex, int dayIndex) async =>
      (await _api.sendForResult('POST', _u('day-lock'), {'weekIndex': weekIndex, 'dayIndex': dayIndex})).status == 200;
  Future<void> releaseDayLock(int weekIndex, int dayIndex) async =>
      _api.sendForResult('POST', _u('day-lock/release'), {'weekIndex': weekIndex, 'dayIndex': dayIndex});

  Future<LiveResult> agree() => _send('POST', 'agree', const {});

  // ── internals ──────────────────────────────────────────────────────────────
  static String _u(String path) => path.isEmpty ? 'api/schedule/live' : 'api/schedule/live/$path';

  Future<LiveResult> _send(String method, String path, Object? body) async {
    final r = await _api.sendForResult(method, _u(path), body);
    final status = r.status;
    final data = r.body;
    if (status == 200) {
      return data is Map<String, dynamic>
          ? LiveResult(LiveOp.ok, LiveScheduleData.fromJson(data))
          : const LiveResult(LiveOp.error);
    }
    if (status == 409) return const LiveResult(LiveOp.conflict);
    if (status == 423) {
      LiveScheduleData? sched;
      var op = LiveOp.locked;
      if (data is Map<String, dynamic>) {
        if (data['error'] == 'locked_day') op = LiveOp.lockedDay;
        final s = data['schedule'];
        if (s is Map<String, dynamic>) sched = LiveScheduleData.fromJson(s);
      }
      return LiveResult(op, sched);
    }
    if (status == 400 && data is Map<String, dynamic> && data['error'] == 'no_partner') {
      return const LiveResult(LiveOp.noPartner);
    }
    return const LiveResult(LiveOp.error);
  }
}

enum LiveOp { ok, conflict, locked, lockedDay, noPartner, error }

class LiveResult {
  final LiveOp op;
  final LiveScheduleData? data;
  const LiveResult(this.op, [this.data]);
  bool get ok => op == LiveOp.ok;
}

DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

class LiveScheduleData {
  final int liveScheduleId;
  final String emailA;
  final String emailB;
  final int patternLength;
  final int version;
  final String status; // "building" | "agreed"
  final String? agreedByA;
  final String? agreedByB;
  final DateTime? agreedAtUtc;
  final LockInfo? locked; // schedule-wide lock held by someone
  final List<LiveDay> days;
  final List<LiveOverride> overrides;
  final List<DayLockInfo> dayLocks;

  LiveScheduleData({
    required this.liveScheduleId,
    required this.emailA,
    required this.emailB,
    required this.patternLength,
    required this.version,
    required this.status,
    this.agreedByA,
    this.agreedByB,
    this.agreedAtUtc,
    this.locked,
    this.days = const [],
    this.overrides = const [],
    this.dayLocks = const [],
  });

  bool get isAgreed => status == 'agreed';

  factory LiveScheduleData.fromJson(Map<String, dynamic> j) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) f) =>
        (j[key] as List?)?.whereType<Map<String, dynamic>>().map(f).toList() ?? <T>[];
    return LiveScheduleData(
      liveScheduleId: (j['liveScheduleId'] as num?)?.toInt() ?? 0,
      emailA: j['emailA'] as String? ?? '',
      emailB: j['emailB'] as String? ?? '',
      patternLength: (j['patternLength'] as num?)?.toInt() ?? 1,
      version: (j['version'] as num?)?.toInt() ?? 0,
      status: j['status'] as String? ?? 'building',
      agreedByA: j['agreedByA'] as String?,
      agreedByB: j['agreedByB'] as String?,
      agreedAtUtc: _dt(j['agreedAtUtc']),
      locked: LockInfo.fromJson(j['locked'] as Map<String, dynamic>?),
      days: list('days', LiveDay.fromJson),
      overrides: list('overrides', LiveOverride.fromJson),
      dayLocks: list('dayLocks', DayLockInfo.fromJson),
    );
  }

  LiveDay? dayAt(int weekIndex, int dayIndex) {
    for (final d in days) {
      if (d.weekIndex == weekIndex && d.dayIndex == dayIndex) return d;
    }
    return null;
  }

  /// The email (lowercased) currently holding a lock on this day, or null.
  String? dayLockedBy(int weekIndex, int dayIndex) {
    for (final l in dayLocks) {
      if (l.weekIndex == weekIndex && l.dayIndex == dayIndex) return l.by;
    }
    return null;
  }
}

class LockInfo {
  final String by;
  final String? kind; // "template" | "ai" | "pattern"
  final DateTime? expiresUtc;
  LockInfo({required this.by, this.kind, this.expiresUtc});
  static LockInfo? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final by = j['by'] as String?;
    if (by == null || by.isEmpty) return null;
    return LockInfo(by: by, kind: j['kind'] as String?, expiresUtc: _dt(j['expiresUtc']));
  }
}

class DayLockInfo {
  final int weekIndex;
  final int dayIndex;
  final String by;
  final DateTime? expiresUtc;
  DayLockInfo({required this.weekIndex, required this.dayIndex, required this.by, this.expiresUtc});
  factory DayLockInfo.fromJson(Map<String, dynamic> j) => DayLockInfo(
        weekIndex: (j['weekIndex'] as num?)?.toInt() ?? 0,
        dayIndex: (j['dayIndex'] as num?)?.toInt() ?? 0,
        by: j['by'] as String? ?? '',
        expiresUtc: _dt(j['expiresUtc']),
      );
}

class LiveDay {
  final int weekIndex;
  final int dayIndex;
  final String parentAssignment; // Husband | Wife | Both | None
  final String? transferTime; // "HH:mm:ss"
  final String? transferEndTime;
  final double? transferLatitude;
  final double? transferLongitude;
  final String? transferLocationName;
  final String? transferAddress;

  LiveDay({
    required this.weekIndex,
    required this.dayIndex,
    this.parentAssignment = 'None',
    this.transferTime,
    this.transferEndTime,
    this.transferLatitude,
    this.transferLongitude,
    this.transferLocationName,
    this.transferAddress,
  });

  factory LiveDay.fromJson(Map<String, dynamic> j) => LiveDay(
        weekIndex: (j['weekIndex'] as num?)?.toInt() ?? 0,
        dayIndex: (j['dayIndex'] as num?)?.toInt() ?? 0,
        parentAssignment: j['parentAssignment'] as String? ?? 'None',
        transferTime: j['transferTime'] as String?,
        transferEndTime: j['transferEndTime'] as String?,
        transferLatitude: (j['transferLatitude'] as num?)?.toDouble(),
        transferLongitude: (j['transferLongitude'] as num?)?.toDouble(),
        transferLocationName: j['transferLocationName'] as String?,
        transferAddress: j['transferAddress'] as String?,
      );

  Map<String, dynamic> fields() => {
        'weekIndex': weekIndex,
        'dayIndex': dayIndex,
        'parentAssignment': parentAssignment,
        'transferTime': transferTime,
        'transferEndTime': transferEndTime,
        'transferLatitude': transferLatitude,
        'transferLongitude': transferLongitude,
        'transferLocationName': transferLocationName,
        'transferAddress': transferAddress,
      };
}

class LiveOverride {
  final String dateKey; // "MM-DD"
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

  LiveOverride({
    required this.dateKey,
    required this.month,
    required this.day,
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

  factory LiveOverride.fromJson(Map<String, dynamic> j) => LiveOverride(
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
        transferLatitude: (j['transferLatitude'] as num?)?.toDouble(),
        transferLongitude: (j['transferLongitude'] as num?)?.toDouble(),
        transferLocationName: j['transferLocationName'] as String?,
        transferAddress: j['transferAddress'] as String?,
      );

  Map<String, dynamic> fields() => {
        'dateKey': dateKey,
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
        'transferLatitude': transferLatitude,
        'transferLongitude': transferLongitude,
        'transferLocationName': transferLocationName,
        'transferAddress': transferAddress,
      };
}
