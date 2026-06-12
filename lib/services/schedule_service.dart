import 'dart:convert';

import '../models/schedule_models.dart';
import 'api_client.dart';

/// Port of `Services/ScheduleService.cs`. The classic schedule + weekly-pattern
/// system (distinct from the live custody editor in [LiveScheduleService]).
/// Routes/payloads are 1:1 with the C# service and `ScheduleController.cs`.
class ScheduleService {
  ScheduleService(this._api);
  final ApiClient _api;

  Future<List<ScheduleItem>> getSchedule({int? month, int? year}) async {
    var endpoint = 'api/schedule';
    final params = <String>[];
    if (month != null) params.add('month=$month');
    if (year != null) params.add('year=$year');
    if (params.isNotEmpty) endpoint = 'api/schedule?${params.join('&')}';

    final json = await _api.getJson(endpoint);
    if (json is List) {
      return json
          .map((e) => ScheduleItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  Future<bool> updateSchedule(
    int month,
    int day,
    int year,
    String tag,
    String startTime,
    String endTime, {
    String repeatType = 'none',
    String? endDate,
    bool isCustodial = false,
    bool visibleToKids = true,
  }) async {
    String formattedEndDate = '';
    if (endDate != null && endDate.isNotEmpty) {
      final dt = DateTime.tryParse(endDate);
      // Wall-clock contract: the backend DateTime.TryParses EndDate with no
      // timezone handling (an offset/Z suffix would be shifted to server-local
      // time and could move the date), so send an explicit date-only string
      // built from the calendar components as written.
      if (dt != null) {
        formattedEndDate = '${dt.year.toString().padLeft(4, '0')}-'
            '${dt.month.toString().padLeft(2, '0')}-'
            '${dt.day.toString().padLeft(2, '0')}';
      }
    }

    // The endpoint binds a JSON ARRAY (List<ScheduleUpdateRequest>) — a single
    // object is a guaranteed 400 — so delegate to the batch method with one item.
    return updateSchedules([
      ScheduleUpdateRequest(
        month: month,
        day: day,
        year: year,
        tag: tag,
        startTime: startTime,
        endTime: endTime,
        repeatType: repeatType,
        endDate: formattedEndDate,
        isCustodial: isCustodial,
        visibleToKids: visibleToKids,
      ),
    ]);
  }

  Future<bool> respondToCustodyProposal(
      int month, int day, int year, bool accept) async {
    final response = await _api.postForString(
      'api/schedule/custody/respond',
      CustodyProposalResponseRequest(
              month: month, day: day, year: year, accept: accept)
          .toJson(),
    );
    return response.contains('accepted') || response.contains('rejected');
  }

  /// Returns the weekly custody pattern as a JSON string (mirrors the C#
  /// `GetAsync<string>`); falls back to "{}" on error.
  Future<String> getWeeklyCustodyPattern() async {
    final json = await _api.getJson('api/schedule/custody/pattern');
    if (json == null) return '{}';
    return json is String ? json : jsonEncode(json);
  }

  Future<bool> setWeeklyCustodyPattern(
    int dayOfWeek,
    String parent,
    String repeatPattern,
    bool hasTransferTime,
    Duration? transferTime, {
    String? patternStartDate,
    int patternLength = 1,
  }) async {
    final r = await _api.postJson(
      'api/schedule/custody/pattern',
      CustodyPatternSetRequest(
        dayOfWeek: dayOfWeek,
        parent: parent,
        repeatPattern: repeatPattern,
        hasTransferTime: hasTransferTime,
        transferTime: hasTransferTime && transferTime != null
            ? _formatHhmm(transferTime)
            : null,
        patternStartDate: patternStartDate,
        patternLength: patternLength,
      ).toJson(),
    );
    return r is bool ? r : false;
  }

  Future<bool> deleteWeeklyCustodyPattern(int dayOfWeek) async {
    final r = await _api.deleteJson('api/schedule/custody/pattern?dayOfWeek=$dayOfWeek');
    return r is bool ? r : false;
  }

  Future<Map<String, double>> getCustodyMetrics(int month, int year) async {
    final json =
        await _api.getJson('api/schedule/custody/metrics?month=$month&year=$year');
    if (json is Map<String, dynamic>) {
      return json.map((k, v) => MapEntry(k, (v as num).toDouble()));
    }
    return {};
  }

  Future<bool> updateSchedules(List<ScheduleUpdateRequest> requests) async {
    final json = await _api.postJson(
        'api/schedule', requests.map((r) => r.toJson()).toList());
    return json is Map<String, dynamic> &&
        ScheduleOperationResponse.fromJson(json).success;
  }

  Future<bool> deleteSchedules(List<ScheduleDeleteRequest> requests) async {
    final json = await _api.deleteJson(
        'api/schedule', requests.map((r) => r.toJson()).toList());
    return json is Map<String, dynamic> &&
        ScheduleOperationResponse.fromJson(json).success;
  }

  Future<bool> respondToCustodyProposals(
      List<CustodyProposalResponseItem> responses) async {
    final json = await _api.postJson(
        'api/schedule/custody/respond', responses.map((r) => r.toJson()).toList());
    return json is Map<String, dynamic> && ResponseResult.fromJson(json).success;
  }

  Future<bool> setWeeklyCustodyPatterns(List<CustodyPatternRequest> patterns) async {
    final json = await _api.postJson(
        'api/schedule/custody/pattern', patterns.map((r) => r.toJson()).toList());
    return json is Map<String, dynamic> && ResponseResult.fromJson(json).success;
  }

  Future<bool> deleteWeeklyCustodyPatterns(
      List<CustodyPatternDeleteRequest> requests) async {
    final json = await _api.deleteJson(
        'api/schedule/custody/pattern', requests.map((r) => r.toJson()).toList());
    return json is Map<String, dynamic> &&
        ScheduleOperationResponse.fromJson(json).success;
  }

  Future<List<ScheduleItem>> getScheduleOptimized(
    int month,
    int year, {
    bool includeHistoricalOverrides = true,
    int historicalYears = 5,
  }) async {
    final json = await _api.getJson(
        'api/schedule/optimized?month=$month&year=$year&includeHistoricalOverrides=$includeHistoricalOverrides&historicalYears=$historicalYears');
    if (json is List) {
      return json
          .map((e) => ScheduleItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  static String _formatHhmm(Duration d) {
    final h = d.inHours.remainder(24).toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}
