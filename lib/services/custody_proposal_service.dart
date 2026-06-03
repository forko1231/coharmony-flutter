import '../models/custody_models.dart';
import 'api_client.dart';

/// Port of `Services/CustodyProposalService.cs`. Custody proposal operations with
/// versioning and negotiation. Routes/payloads are 1:1 with the C# service and the
/// `SplitServer/Controllers/CustodyProposalController.cs` contract.
class CustodyProposalService {
  CustodyProposalService(this._api);
  final ApiClient _api;

  // ---- Get proposals ------------------------------------------------------

  Future<ActiveProposalResponse?> getActiveProposal() async {
    final json = await _api.getJson('api/custody/proposal/active');
    return json is Map<String, dynamic> ? ActiveProposalResponse.fromJson(json) : null;
  }

  Future<CustodyProposalDto?> getProposalById(int proposalId) async {
    final json = await _api.getJson('api/custody/proposal/$proposalId');
    return json is Map<String, dynamic> ? CustodyProposalDto.fromJson(json) : null;
  }

  Future<ApprovedScheduleResponse?> getApprovedSchedule() async {
    final json = await _api.getJson('api/custody/proposal/approved');
    return json is Map<String, dynamic>
        ? ApprovedScheduleResponse.fromJson(json)
        : null;
  }

  Future<ProposalComparisonResponse?> getProposalComparison(int proposalId) async {
    final json = await _api.getJson('api/custody/proposal/$proposalId/comparison');
    return json is Map<String, dynamic>
        ? ProposalComparisonResponse.fromJson(json)
        : null;
  }

  Future<List<ProposalSummaryDto>?> getProposalHistory({int? limit = 20}) async {
    final json = await _api.getJson('api/custody/proposal/history?limit=$limit');
    if (json is List) {
      return json
          .map((e) => ProposalSummaryDto.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return null;
  }

  // ---- Create proposals ---------------------------------------------------

  Future<CustodyProposalDto?> createProposalFromCurrent() async {
    final json = await _api.postJson(
        'api/custody/proposal/create-from-current', <String, dynamic>{});
    return json is Map<String, dynamic> ? CustodyProposalDto.fromJson(json) : null;
  }

  Future<CustodyProposalDto?> createNewProposal(int patternLength) async {
    final json = await _api.postJson(
        'api/custody/proposal/create', CreateProposalRequest(patternLength: patternLength).toJson());
    return json is Map<String, dynamic> ? CustodyProposalDto.fromJson(json) : null;
  }

  Future<CustodyProposalDto?> createCounterProposal(int parentProposalId) async {
    final json = await _api.postJson(
        'api/custody/proposal/$parentProposalId/counter', <String, dynamic>{});
    return json is Map<String, dynamic> ? CustodyProposalDto.fromJson(json) : null;
  }

  // ---- Day operations -----------------------------------------------------

  Future<bool> updateDay(int proposalId, UpdateDayRequest request) async {
    final json =
        await _api.putJson('api/custody/proposal/$proposalId/day', request.toJson());
    return json is Map<String, dynamic> && SuccessResponse.fromJson(json).success;
  }

  Future<bool> updateDays(int proposalId, List<UpdateDayRequest> requests) async {
    final json = await _api.putJson(
        'api/custody/proposal/$proposalId/days', requests.map((r) => r.toJson()).toList());
    return json is Map<String, dynamic> && SuccessResponse.fromJson(json).success;
  }

  Future<bool> markDayConflict(int proposalId, int weekIndex, int dayIndex,
      {String? reason}) async {
    final json = await _api.postJson(
      'api/custody/proposal/$proposalId/day/conflict',
      MarkConflictRequest(weekIndex: weekIndex, dayIndex: dayIndex, reason: reason).toJson(),
    );
    return json is Map<String, dynamic> && SuccessResponse.fromJson(json).success;
  }

  Future<bool> clearDayConflict(int proposalId, int weekIndex, int dayIndex) async {
    final json = await _api.deleteJson(
        'api/custody/proposal/$proposalId/day/conflict?weekIndex=$weekIndex&dayIndex=$dayIndex');
    return json is Map<String, dynamic> && SuccessResponse.fromJson(json).success;
  }

  // ---- Override operations ------------------------------------------------

  Future<bool> addOrUpdateOverride(int proposalId, UpdateOverrideRequest request) async {
    final json = await _api.putJson(
        'api/custody/proposal/$proposalId/override', request.toJson());
    return json is Map<String, dynamic> && SuccessResponse.fromJson(json).success;
  }

  Future<bool> deleteOverride(int proposalId, String dateKey) async {
    final json = await _api.deleteJson(
        'api/custody/proposal/$proposalId/override?dateKey=${Uri.encodeQueryComponent(dateKey)}');
    return json is Map<String, dynamic> && SuccessResponse.fromJson(json).success;
  }

  Future<bool> markOverrideConflict(int proposalId, String dateKey,
      {String? reason}) async {
    final json = await _api.postJson(
      'api/custody/proposal/$proposalId/override/conflict',
      MarkOverrideConflictRequest(dateKey: dateKey, reason: reason).toJson(),
    );
    return json is Map<String, dynamic> && SuccessResponse.fromJson(json).success;
  }

  Future<bool> clearOverrideConflict(int proposalId, String dateKey) async {
    final json = await _api.deleteJson(
        'api/custody/proposal/$proposalId/override/conflict?dateKey=${Uri.encodeQueryComponent(dateKey)}');
    return json is Map<String, dynamic> && SuccessResponse.fromJson(json).success;
  }

  // ---- Proposal actions ---------------------------------------------------

  Future<SuccessResponse?> submitProposal(int proposalId) =>
      _action('api/custody/proposal/$proposalId/submit');

  Future<SuccessResponse?> withdrawProposal(int proposalId) =>
      _action('api/custody/proposal/$proposalId/withdraw');

  Future<SuccessResponse?> approveProposal(int proposalId) =>
      _action('api/custody/proposal/$proposalId/approve');

  Future<SuccessResponse?> rejectProposal(int proposalId) =>
      _action('api/custody/proposal/$proposalId/reject');

  Future<SuccessResponse?> _action(String endpoint) async {
    final json = await _api.postJson(endpoint, <String, dynamic>{});
    return json is Map<String, dynamic> ? SuccessResponse.fromJson(json) : null;
  }
}
