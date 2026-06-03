import '../../models/custody_models.dart';
import '../custody_proposal_service.dart';
import 'custody_template.dart';

/// Turns a (template, answers) pair into an actual submitted proposal on the server —
/// port of `Services/CustodyTemplates/TemplateApplyHelper.cs`. Used by the onboarding
/// flow so the user doesn't have to manually save after picking a template. The editor
/// uses its own flow (loads into local edits, user reviews + saves).
class TemplateApplyHelper {
  TemplateApplyHelper._();

  /// Create a fresh proposal, push all the template's days into it, and submit it to
  /// the partner. Returns success/failure and a user-facing message.
  static Future<TemplateApplyResult> createAndSubmitProposal(
    CustodyProposalService proposalService,
    CustodyTemplate template,
    TemplateAnswers answers,
  ) async {
    List<GeneratedDay> days;
    try {
      days = template.buildPattern(answers);
    } catch (ex) {
      return TemplateApplyResult(false, "Couldn't build template: $ex", null);
    }

    // 1. Create proposal
    final proposal = await proposalService.createNewProposal(template.patternLengthWeeks);
    if (proposal == null) {
      return const TemplateApplyResult(
          false, "Couldn't create a proposal. Please check your connection.", null);
    }

    // 2. Push days
    final dayUpdates = <UpdateDayRequest>[
      for (final d in days)
        UpdateDayRequest(
          weekIndex: d.weekIndex,
          dayIndex: d.dayIndex,
          parentAssignment: d.parentAssignment,
          transferTime: d.transferTime,
          transferEndTime: d.transferEndTime,
        ),
    ];

    final daysOk = await proposalService.updateDays(proposal.proposalId, dayUpdates);
    if (!daysOk) {
      return TemplateApplyResult(
          false, "Couldn't save the day pattern. Please try again.", proposal.proposalId);
    }

    // 3. Submit to partner
    final submit = await proposalService.submitProposal(proposal.proposalId);
    if (submit?.success != true) {
      return TemplateApplyResult(false,
          "Couldn't submit the proposal to your partner. Please try again.", proposal.proposalId);
    }

    return TemplateApplyResult(
        true, 'Schedule sent to your partner for review.', proposal.proposalId);
  }
}

class TemplateApplyResult {
  const TemplateApplyResult(this.success, this.message, this.proposalId);
  final bool success;
  final String message;
  final int? proposalId;
}
