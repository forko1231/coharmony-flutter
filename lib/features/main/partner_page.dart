import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/auth_models.dart';
import '../../services/analytics_service.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';

/// Connections (Partner & Lawyers) — faithful port of `Views/Main/PartnerPage.xaml(.cs)`.
///
/// MAUI builds the body imperatively into an empty `ContentLayout`; here it's
/// rendered declaratively from loaded service state ([AuthService.checkForInvite],
/// `getChildren`, `getApprovedLawyers`, `getPendingLawyerRequests`) and refreshed
/// on a 30-second poll. The co-parent card is state-driven (none / pending-received
/// / pending-sent / synced); children + child invites show once a partner is synced;
/// lawyers are request-based (accept/decline incoming, remove approved) — there is no
/// "add lawyer" action. Includes the 4-step "adding children" help modal.
class PartnerPage extends StatefulWidget {
  const PartnerPage({super.key});

  @override
  State<PartnerPage> createState() => _PartnerPageState();
}

class _PartnerPageState extends State<PartnerPage> {
  final _partnerInvite = TextEditingController();
  final _childInvite = TextEditingController();

  PartnerInviteInfo? _partner;
  List<ChildInfo> _children = const [];
  List<LawyerInfo> _lawyers = const [];
  List<LawyerRequestInfo> _lawyerRequests = const [];

  bool _loading = true;
  bool _busy = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    // MAUI polls every 30s while the page is open.
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _partnerInvite.dispose();
    _childInvite.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final partner = await ServiceLocator.auth.checkForInvite();
      final requests = await ServiceLocator.auth.getPendingLawyerRequests();
      final lawyers = await ServiceLocator.auth.getApprovedLawyers();
      final children = partner.synced ? await ServiceLocator.auth.getChildren() : const <ChildInfo>[];
      if (!mounted) return;
      setState(() {
        _partner = partner;
        _lawyerRequests = requests;
        _lawyers = lawyers;
        _children = children;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (!silent) await _alert('Error', 'Failed to load connections: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final synced = _partner?.synced ?? false;
    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          Column(
            children: [
              _header(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _coParentCard(context),
                          if (synced) ...[
                            const SizedBox(height: 20),
                            _childrenCard(context),
                          ],
                          if (_lawyerRequests.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            _lawyerRequestsCard(context),
                          ],
                          if (_lawyers.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            _approvedLawyersCard(context),
                          ],
                          const SizedBox(height: 20),
                          _dataProtectedCard(context),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_loading || _busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black26,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────────
  Widget _header(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: EdgeInsets.fromLTRB(24, MediaQuery.viewPaddingOf(context).top + 20, 24, 20),
      decoration: BoxDecoration(
        color: palette.surface,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.08),
              offset: const Offset(0, 4),
              blurRadius: 16),
        ],
      ),
      child: Row(
        children: [
          _squareButton(
            context,
            bg: context.isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
            child: AppIcon('icon_chevron_left', size: 24, color: palette.textSecondary),
            onTap: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Column(
              children: [
                Text('Connections',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                const SizedBox(height: 2),
                Text('Co-Parent & Legal Representatives',
                    style: TextStyle(fontSize: 13, color: palette.textSecondary)),
              ],
            ),
          ),
          _squareButton(
            context,
            bg: AppColors.primaryBlue,
            child: const AppIcon('icon_refresh', size: 22, color: Colors.white),
            onTap: () => _load(),
          ),
        ],
      ),
    );
  }

  // ── Co-parent card (state-driven) ──────────────────────────────────────────────
  Widget _coParentCard(BuildContext context) {
    final p = _partner;
    final synced = p?.synced ?? false;
    final status = p?.status;
    final pendingReceived = (p?.valid ?? false) && status == 'pending_received';
    final pendingSent = (p?.valid ?? false) && status == 'pending_sent';
    final name = (p?.inviterName?.isNotEmpty ?? false) ? p!.inviterName! : (p?.inviterEmail ?? 'Co-Parent');
    final email = p?.inviterEmail ?? '';

    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(context,
              icon: 'icon_users',
              iconBg: AppColors.iconBgBlue,
              iconTint: AppColors.primaryBlue,
              title: 'Co-Parent',
              subtitle: 'The other parent on this account'),
          const SizedBox(height: 16),
          if (synced) ...[
            _personRow(context, name, email, AppColors.primaryBlue,
                badge: 'Connected', badgeColor: AppColors.successGreen),
            const SizedBox(height: 12),
            _pillButton(context, 'Disconnect Partner', AppColors.dangerRed, _disconnectPartner),
          ] else if (pendingReceived) ...[
            _personRow(context, name, email, AppColors.warningAmber,
                badge: 'Invited you', badgeColor: AppColors.warningAmber),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _pillButton(context, 'Decline', AppColors.dangerRed, _declinePartner)),
                const SizedBox(width: 12),
                Expanded(child: _pillButton(context, 'Accept', AppColors.successGreen, _acceptPartner)),
              ],
            ),
          ] else if (pendingSent) ...[
            _emptyRow(context, 'Invitation pending',
                "You've invited $email to connect. They'll need to accept your invitation."),
          ] else ...[
            _inviteRow(context,
                controller: _partnerInvite,
                hint: "Enter partner's email address",
                buttonLabel: 'Send Invitation',
                buttonColor: AppColors.primaryBlue,
                onInvite: _sendPartnerInvite),
          ],
        ],
      ),
    );
  }

  // ── Children card (synced only) ─────────────────────────────────────────────────
  Widget _childrenCard(BuildContext context) {
    final palette = context.palette;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _sectionHeader(context,
                    icon: 'icon_user_plus',
                    iconBg: AppColors.iconBgPurple,
                    iconTint: AppColors.accentPurple,
                    title: 'Children',
                    subtitle: 'Free accounts for your kids'),
              ),
              GestureDetector(
                onTap: () => _showChildrenHelp(context),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.iconBgPurple,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Text('?',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.accentPurple)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final c in _children) ...[
            _personRow(context, _childName(c), c.email ?? '', AppColors.accentPurple,
                badge: c.isAccepted ? 'Active' : 'Pending',
                badgeColor: c.isAccepted ? AppColors.successGreen : AppColors.warningAmber),
            const SizedBox(height: 12),
          ],
          // Invite a child
          _inviteRow(context,
              controller: _childInvite,
              hint: "Enter child's email address",
              buttonLabel: 'Invite Child',
              buttonColor: AppColors.accentPurple,
              onInvite: _inviteChild),
          const SizedBox(height: 8),
          Text('Make sure your child has created their CoHarmony account before you send the invite.',
              style: TextStyle(fontSize: 12, color: palette.textSecondary)),
        ],
      ),
    );
  }

  // ── Pending lawyer requests ─────────────────────────────────────────────────────
  Widget _lawyerRequestsCard(BuildContext context) {
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(context,
              icon: 'icon_scale',
              iconBg: AppColors.iconBgYellow,
              iconTint: AppColors.warningAmber,
              title: 'Pending Lawyer Requests',
              subtitle: 'Review carefully before accepting'),
          const SizedBox(height: 16),
          for (var i = 0; i < _lawyerRequests.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _personRow(context, _lawyerRequests[i].lawyerName ?? 'Unknown',
                _lawyerRequests[i].lawyerEmail ?? '', AppColors.warningAmber,
                badge: 'Request', badgeColor: AppColors.warningAmber),
            const SizedBox(height: 8),
            if (_lawyerRequests[i].lawyerFirm?.isNotEmpty ?? false)
              _detailRow(context, 'icon_home', 'Firm:', _lawyerRequests[i].lawyerFirm!),
            if (_lawyerRequests[i].lawyerBarNumber?.isNotEmpty ?? false)
              _detailRow(context, 'icon_document', 'Bar #:', _lawyerRequests[i].lawyerBarNumber!),
            if (_lawyerRequests[i].requestedAt != null)
              _detailRow(context, 'icon_calendar', 'Requested:', _fmtDate(_lawyerRequests[i].requestedAt!.toLocal())),
            const SizedBox(height: 8),
            // Prominent red consent box — granting a lawyer access to all the
            // user's data is sensitive (mirrors MAUI's warning styling).
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.isDark ? const Color(0xFF3F1D1D) : const Color(0xFFFEF2F2),
                border: Border.all(color: AppColors.dangerRed),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: AppIcon('icon_alert', size: 14, color: AppColors.dangerRed),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        'Accepting grants this lawyer read access to your schedules, payment records, messages, and location data. Only accept someone you know and trust.',
                        style: TextStyle(
                            fontSize: 12,
                            color: context.isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C))),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                    child: _pillButton(context, 'Decline', AppColors.dangerRed,
                        () => _rejectLawyer(_lawyerRequests[i].lawyerEmail))),
                const SizedBox(width: 12),
                Expanded(
                    child: _pillButton(context, 'Accept', AppColors.successGreen,
                        () => _acceptLawyer(_lawyerRequests[i].lawyerEmail))),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Approved lawyers ──────────────────────────────────────────────────────────
  Widget _approvedLawyersCard(BuildContext context) {
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(context,
              icon: 'icon_scale',
              iconBg: AppColors.iconBgGreen,
              iconTint: AppColors.successGreen,
              title: 'Your Legal Representatives',
              subtitle: 'Lawyers with read access to your records'),
          const SizedBox(height: 16),
          for (var i = 0; i < _lawyers.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _personRow(context, _lawyers[i].lawyerName ?? 'Unknown', _lawyers[i].lawyerEmail ?? '',
                AppColors.successGreen,
                badge: 'Approved', badgeColor: AppColors.successGreen),
            const SizedBox(height: 8),
            if (_lawyers[i].lawyerFirm?.isNotEmpty ?? false)
              _detailRow(context, 'icon_home', 'Firm:', _lawyers[i].lawyerFirm!, valueColor: const Color(0xFF166534)),
            if (_lawyers[i].lawyerBarNumber?.isNotEmpty ?? false)
              _detailRow(context, 'icon_document', 'Bar #:', _lawyers[i].lawyerBarNumber!,
                  valueColor: const Color(0xFF166534)),
            if (_lawyers[i].approvedAt != null)
              _detailRow(context, 'icon_check_circle', 'Approved:', _fmtDate(_lawyers[i].approvedAt!.toLocal()),
                  valueColor: const Color(0xFF166534)),
            const SizedBox(height: 8),
            _pillButton(context, 'Remove Access', AppColors.dangerRed,
                () => _removeLawyer(_lawyers[i].lawyerEmail)),
          ],
        ],
      ),
    );
  }

  // Detail row (icon + label + value) used by the lawyer cards — mirrors MAUI's CreateDetailRow.
  Widget _detailRow(BuildContext context, String icon, String label, String value, {Color? valueColor}) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 24, child: AppIcon(icon, size: 18, color: palette.textSecondary)),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 14, color: palette.textSecondary)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: valueColor ?? palette.textPrimary)),
          ),
        ],
      ),
    );
  }

  // "Your Data is Protected" gradient shield card — always shown at the bottom (MAUI parity).
  Widget _dataProtectedCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0EA5E9), Color(0xFF0284C7)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: const Color(0xFF0EA5E9).withValues(alpha: 0.3), offset: const Offset(0, 6), blurRadius: 16),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
            child: const AppIcon('icon_shield', size: 24, color: Colors.white),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your Data is Protected',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                SizedBox(height: 2),
                Text('Only approved connections can access your information',
                    style: TextStyle(fontSize: 13, color: Color(0xFFE0F2FE))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _childName(ChildInfo c) {
    final full = '${c.firstName ?? ''} ${c.lastName ?? ''}'.trim();
    return full.isNotEmpty ? full : (c.email ?? 'Child');
  }

  static const _shortMonths = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String _fmtDate(DateTime d) => '${_shortMonths[d.month]} ${d.day.toString().padLeft(2, '0')}, ${d.year}';

  // ── Actions ─────────────────────────────────────────────────────────────────────
  Future<void> _sendPartnerInvite() async {
    final email = _partnerInvite.text.trim();
    if (email.isEmpty) {
      await _alert('Error', 'Please enter a valid email address');
      return;
    }
    await _run(() async {
      final result = await ServiceLocator.auth.invitePartner(email);
      final ok = result.toLowerCase().contains('success') || result.toLowerCase().contains('sent');
      if (ok) {
        AnalyticsService.trackCustom('coparent_invited');
        _partnerInvite.clear();
        await _load(silent: true);
        await _alert('Success', 'Partnership invitation sent!');
      } else {
        await _alert('Error', result);
      }
    });
  }

  Future<void> _acceptPartner() async {
    if (await _confirm('Confirm Partnership',
            'Accept this partnership? This lets you sync schedules and messages with this person.',
            'Yes, Accept') !=
        true) {
      return;
    }
    await _run(() async {
      final ok = await ServiceLocator.auth.acceptInvite();
      if (ok) {
        AnalyticsService.trackCustom('coparent_joined');
        await _load(silent: true);
        await _alert('Success', 'Partnership accepted!');
      } else {
        await _alert('Error', 'Failed to accept partnership');
      }
    });
  }

  Future<void> _declinePartner() async {
    if (await _confirm('Decline Partnership', 'Decline this partnership invitation?', 'Yes, Decline') != true) {
      return;
    }
    await _run(() async {
      final ok = await ServiceLocator.auth.rejectInvite();
      await _load(silent: true);
      await _alert(ok ? 'Info' : 'Error', ok ? 'Partnership invitation declined' : 'Failed to decline partnership');
    });
  }

  Future<void> _disconnectPartner() async {
    if (await _confirm('Disconnect Partner',
            'Disconnect from your partner? This stops all data synchronization.', 'Yes, Disconnect') !=
        true) {
      return;
    }
    await _run(() async {
      final ok = await ServiceLocator.auth.rejectInvite();
      await _load(silent: true);
      await _alert(ok ? 'Info' : 'Error', ok ? 'Partnership disconnected' : 'Failed to disconnect partnership');
    });
  }

  Future<void> _inviteChild() async {
    final email = _childInvite.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      await _alert('Invalid Email', 'Please enter a valid email address.');
      return;
    }
    if (await _confirm('Confirm Child Invite',
            'Invite $email? This sends a family invite; the child must tap "I\'m a Child" on the subscription page to accept. Please double-check the email.',
            'Send Invite') !=
        true) {
      return;
    }
    await _run(() async {
      final result = await ServiceLocator.auth.inviteChild(email);
      final ok = result.toLowerCase().contains('success') || result.toLowerCase().contains('invited');
      if (ok) {
        AnalyticsService.trackCustom('child_invited');
        _childInvite.clear();
        await _load(silent: true);
        await _alert('Invite Sent',
            'Family invitation sent to $email! Remind them to open CoHarmony and tap "I\'m a Child" to accept.');
      } else {
        var msg = result;
        final low = result.toLowerCase();
        if (low.contains('pending invite') || low.contains('another family')) {
          msg = 'This user already has a pending invite from another family. They must decline that invite first.';
        } else if (low.contains('not found')) {
          msg = 'No account was found with that email. Make sure your child has created a CoHarmony account first.';
        } else if (low.contains('already a child')) {
          msg = 'This user is already part of a family as a child account.';
        }
        await _alert('Could Not Invite', msg);
      }
    });
  }

  Future<void> _acceptLawyer(String? email) async {
    if (email == null || email.isEmpty) return;
    if (await _confirm('Accept Lawyer Request',
            'Accept this lawyer? They will be able to view your custody schedules, payment records, messages, and location data.',
            'Continue') !=
        true) {
      return;
    }
    if (await _confirm('Final Confirmation',
            'Please confirm you know and trust this lawyer.\n\n$email\n\nThis grants significant access to your personal data.',
            'Yes, I Confirm') !=
        true) {
      return;
    }
    await _run(() async {
      final ok = await ServiceLocator.auth.acceptLawyerRequest(email);
      await _load(silent: true);
      await _alert(ok ? 'Success' : 'Error',
          ok ? 'Lawyer request accepted. They can now view your data.' : 'Failed to accept lawyer request');
    });
  }

  Future<void> _rejectLawyer(String? email) async {
    if (email == null || email.isEmpty) return;
    if (await _confirm('Decline Lawyer Request', "Decline this lawyer's request?", 'Yes, Decline') != true) {
      return;
    }
    await _run(() async {
      final ok = await ServiceLocator.auth.rejectLawyerRequest(email);
      await _load(silent: true);
      await _alert(ok ? 'Info' : 'Error', ok ? 'Lawyer request declined' : 'Failed to decline lawyer request');
    });
  }

  Future<void> _removeLawyer(String? email) async {
    if (email == null || email.isEmpty) return;
    if (await _confirm('Remove Lawyer Access',
            "Remove this lawyer's access? They will no longer be able to view your data.", 'Yes, Remove') !=
        true) {
      return;
    }
    await _run(() async {
      final ok = await ServiceLocator.auth.removeLawyer(email);
      await _load(silent: true);
      await _alert(ok ? 'Success' : 'Error', ok ? 'Lawyer access removed' : 'Failed to remove lawyer access');
    });
  }

  /// Runs an action behind the busy overlay.
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) await _alert('Error', '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm(String title, String message, String confirmLabel) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(confirmLabel)),
        ],
      ),
    );
  }

  Future<void> _alert(String title, String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  Widget _pillButton(BuildContext context, String label, Color color, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 48,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
          child: Center(
            child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ),
      );

  // ── Children help modal ─────────────────────────────────────────────────────
  void _showChildrenHelp(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: const Color(0xCC000000),
      builder: (_) => const _ChildrenHelpDialog(),
    );
  }

  // ── Shared building blocks ───────────────────────────────────────────────────
  Widget _card(BuildContext context, {required Widget child}) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.08),
              offset: const Offset(0, 8),
              blurRadius: 24),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionHeader(BuildContext context,
      {required String icon,
      required Color iconBg,
      required Color iconTint,
      required String title,
      required String subtitle}) {
    final palette = context.palette;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
          child: Center(child: AppIcon(icon, size: 22, color: iconTint)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: palette.textPrimary)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 13, color: palette.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _personRow(BuildContext context, String name, String email, Color avatarColor,
      {required String badge, required Color badgeColor}) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceInput,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: avatarColor, borderRadius: BorderRadius.circular(14)),
            child: Center(
              child: Text(_initials(name),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                const SizedBox(height: 2),
                Text(email, style: TextStyle(fontSize: 13, color: palette.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: Text(badge, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeColor)),
          ),
        ],
      ),
    );
  }

  Widget _emptyRow(BuildContext context, String title, String subtitle) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceInput,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: palette.textPrimary)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 13, color: palette.textSecondary)),
        ],
      ),
    );
  }

  Widget _inviteRow(BuildContext context,
      {required TextEditingController controller,
      required String hint,
      required String buttonLabel,
      required Color buttonColor,
      required VoidCallback onInvite}) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: context.isDark ? const Color(0xFF111827) : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(fontSize: 14, color: palette.textPrimary),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              hintText: hint,
              hintStyle: TextStyle(fontSize: 14, color: palette.textSecondary),
            ),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: onInvite,
          child: Container(
            height: 44,
            decoration: BoxDecoration(color: buttonColor, borderRadius: BorderRadius.circular(12)),
            child: Center(
              child: Text(buttonLabel,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _squareButton(BuildContext context, {required Color bg, required Widget child, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Center(child: child),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }
}

// ── Children help modal (4-step walkthrough) ─────────────────────────────────────
class _ChildrenHelpDialog extends StatefulWidget {
  const _ChildrenHelpDialog();

  @override
  State<_ChildrenHelpDialog> createState() => _ChildrenHelpDialogState();
}

class _ChildrenHelpDialogState extends State<_ChildrenHelpDialog> {
  int _step = 0;
  static const _total = 4;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Dialog(
      backgroundColor: palette.surfaceElevated,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Step dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < _total; i++)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i == _step ? AppColors.accentPurple : const Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(child: _stepContent(context, _step)),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.textSecondary,
                      side: BorderSide(color: palette.border, width: 2),
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentPurple,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    onPressed: () {
                      if (_step < _total - 1) {
                        setState(() => _step++);
                      } else {
                        Navigator.of(context).pop();
                      }
                    },
                    child: Text(_step < _total - 1 ? 'Next' : 'Done',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepContent(BuildContext context, int step) {
    switch (step) {
      case 0:
        return _step0(context);
      case 1:
        return _numberStep(context,
            number: '1',
            numberColor: AppColors.primaryBlue,
            numberBg: AppColors.iconBgBlue,
            title: 'Your Child Creates an Account',
            body: 'Your child downloads CoHarmony and creates a free account using their own email address.',
            rows: const [
              _MiniRow('icon_download', AppColors.primaryBlue, 'Download CoHarmony', 'Available on iOS and Android'),
              _MiniRow('icon_user_plus', AppColors.primaryBlue, 'Create an account', 'Use their own email address'),
            ]);
      case 2:
        return _step2(context);
      default:
        return _numberStep(context,
            number: '3',
            numberColor: AppColors.successGreen,
            numberBg: AppColors.iconBgGreen,
            title: 'Child Accepts the Invite',
            body:
                'Your child logs in to CoHarmony and taps the "I\'m a Child" button on the subscription page to see and accept the invite.',
            rows: const [
              _MiniRow('icon_user', AppColors.successGreen, 'Child logs in to CoHarmony', null),
              _MiniRow('icon_handshake', AppColors.successGreen, 'Taps "I\'m a Child" on subscription page', null),
              _MiniRow('icon_check_circle', AppColors.successGreen, 'Sees your invite and taps Accept',
                  "They're now connected to the family!"),
            ]);
    }
  }

  // Step 0 — overview
  Widget _step0(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: AppColors.iconBgPurple, borderRadius: BorderRadius.circular(16)),
          child: const Center(child: AppIcon('icon_user_plus', size: 32, color: AppColors.accentPurple)),
        ),
        const SizedBox(height: 16),
        Text('Adding Children to Your Family',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: palette.textPrimary)),
        const SizedBox(height: 8),
        Text('Your children can join for free and get access to the custody schedule and messaging.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: palette.textSecondary)),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.isDark ? const Color(0xFF1F2937) : const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _benefitRow(context, 'icon_check_circle', AppColors.iconBgGreen, AppColors.successGreen,
                  'Completely free for children'),
              const SizedBox(height: 10),
              _benefitRow(context, 'icon_calendar', AppColors.iconBgBlue, AppColors.primaryBlue, 'View custody schedule'),
              const SizedBox(height: 10),
              _benefitRow(context, 'icon_chat', AppColors.iconBgPurple, AppColors.accentPurple, 'Message either parent'),
            ],
          ),
        ),
      ],
    );
  }

  // Step 2 — send invite (mock entry + warning)
  Widget _step2(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: AppColors.iconBgPurple, borderRadius: BorderRadius.circular(16)),
          child: const Center(
              child: Text('2', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.accentPurple))),
        ),
        const SizedBox(height: 16),
        Text('Send the Invite',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: palette.textPrimary)),
        const SizedBox(height: 8),
        Text('On this page, enter your child\'s email and tap "Invite Child". Double-check the email is correct!',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: palette.textSecondary)),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.isDark ? const Color(0xFF1F2937) : const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: context.isDark ? const Color(0xFF111827) : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('child@email.com', style: TextStyle(fontSize: 14, color: palette.textSecondary)),
              ),
              const SizedBox(height: 10),
              Container(
                height: 40,
                decoration: BoxDecoration(color: AppColors.accentPurple, borderRadius: BorderRadius.circular(12)),
                child: const Center(
                    child: Text('Invite Child',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                    '⚠️  Make sure your child has already created their CoHarmony account before you send the invite.',
                    style: TextStyle(fontSize: 12, height: 1.3, color: Color(0xFF92400E))),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _numberStep(BuildContext context,
      {required String number,
      required Color numberColor,
      required Color numberBg,
      required String title,
      required String body,
      required List<_MiniRow> rows}) {
    final palette = context.palette;
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: numberBg, borderRadius: BorderRadius.circular(16)),
          child: Center(
              child: Text(number, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: numberColor))),
        ),
        const SizedBox(height: 16),
        Text(title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: palette.textPrimary)),
        const SizedBox(height: 8),
        Text(body, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: palette.textSecondary)),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.isDark ? const Color(0xFF1F2937) : const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (int i = 0; i < rows.length; i++) ...[
                _detailRow(context, rows[i]),
                if (i < rows.length - 1) const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _benefitRow(BuildContext context, String icon, Color bg, Color tint, String label) {
    final palette = context.palette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          child: Center(child: AppIcon(icon, size: 18, color: tint)),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(label,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: palette.textPrimary)),
        ),
      ],
    );
  }

  Widget _detailRow(BuildContext context, _MiniRow row) {
    final palette = context.palette;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: row.color, borderRadius: BorderRadius.circular(12)),
          child: Center(child: AppIcon(row.icon, size: 18, color: Colors.white)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(row.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: palette.textPrimary)),
              if (row.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(row.subtitle!, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniRow {
  final String icon;
  final Color color;
  final String title;
  final String? subtitle;
  const _MiniRow(this.icon, this.color, this.title, this.subtitle);
}
