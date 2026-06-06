import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/ai_models.dart';
import '../../models/custody_models.dart';
import '../../services/analytics_service.dart';
import '../../services/custody_templates/template_registry.dart';
import '../../services/live_schedule_service.dart';
import '../../services/preferences.dart';
import '../../services/service_locator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';
import '../messaging/chat_interface_page.dart';
import '../onboarding/proposal_preview_grid.dart';
import '../schedule/live_schedule_page.dart';
import '../schedule/templates/template_config_page.dart';

/// Port of `Views/AI/AiChatPage.xaml(.cs)` — the CoHarmony AI assistant chat. Welcome
/// state with suggestion chips, then a bubble thread. Wired to [AiChatService.sendMessage]
/// with history, typing indicator, monthly-usage display, limit/error handling, and the
/// AI's inline **tool-call preview cards** (set_custody_pattern / add_override_day /
/// create_event / draft_message / select_template) with their apply/open/send actions.
class AiChatPage extends StatefulWidget {
  /// MAUI passes "onboarding-schedule" / "schedule" / "general".
  final String chatContext;
  const AiChatPage({super.key, this.chatContext = 'general'});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final _controller = TextEditingController();
  final List<_ChatItem> _items = [];
  final List<AiChatMessageDto> _history = [];
  bool _sending = false;
  double _usageFraction = 0;

  static const _suggestions = [
    ('icon_calendar', AppColors.primaryBlue, 'Set up a 2-week alternating schedule'),
    ('icon_info', AppColors.primaryBlue, 'How do custody proposals work?'),
    ('icon_gift', AppColors.dangerRed, 'Help me add holiday override days'),
  ];

  // Parent fills/text for preview cards (mirror the editor legend).
  static const _parentFill = {
    'Husband': Color(0xFFBFDBFE),
    'Wife': Color(0xFFFCE7F3),
    'Both': Color(0xFFE9D5FF),
    'None': Color(0xFFF3F4F6),
  };
  static const _parentText = {
    'Husband': Color(0xFF1E40AF),
    'Wife': Color(0xFFBE185D),
    'Both': Color(0xFF6B21A8),
    'None': Color(0xFF9CA3AF),
  };
  static const _monthAbbr = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadUsage() async {
    try {
      final usage = await ServiceLocator.aiChat.getUsage();
      if (usage != null && usage.monthlyBudget > 0 && mounted) {
        setState(() => _usageFraction = (usage.monthlySpend / usage.monthlyBudget).clamp(0, 1));
      }
    } catch (_) {/* non-critical */}
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) return;

    setState(() {
      _items.add(_TextItem(trimmed, true));
      _history.add(AiChatMessageDto(role: 'user', content: trimmed));
      _controller.clear();
      _sending = true;
    });

    try {
      final response = await ServiceLocator.aiChat
          .sendMessage(trimmed, context: widget.chatContext, conversationHistory: _history);
      if (!mounted) return;

      if (response == null) {
        _addAi("Sorry, I couldn't connect to the server. Please check your connection and try again.");
        return;
      }
      if (response.limitReached) {
        _addAi(response.message);
        _applyUsage(response);
        return;
      }
      if (response.message.trim().isNotEmpty) {
        _addAi(response.message);
        _history.add(AiChatMessageDto(role: 'assistant', content: response.message));
      }
      for (final call in response.toolCalls ?? const <AiToolCallDto>[]) {
        _handleToolCall(call);
      }
      _applyUsage(response);
    } catch (_) {
      if (mounted) _addAi('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _handleToolCall(AiToolCallDto call) {
    try {
      switch (call.functionName) {
        case 'set_custody_pattern':
          _items.add(_PatternItem(SetCustodyPatternArgs.fromJson(_decode(call.arguments))));
        case 'add_override_day':
          _items.add(_OverrideItem(AddOverrideDayArgs.fromJson(_decode(call.arguments))));
        case 'create_event':
          _items.add(_EventItem(CreateEventArgs.fromJson(_decode(call.arguments))));
        case 'draft_message':
          _items.add(_DraftItem(DraftMessageArgs.fromJson(_decode(call.arguments))));
        case 'select_template':
          final args = SelectTemplateArgs.fromJson(_decode(call.arguments));
          final template = TemplateRegistry.findById(args.templateId);
          if (template == null) {
            AnalyticsService.trackCustom('ai_unknown_template_id');
            _addAi("I couldn't find that template. Try describing the schedule in different words.");
          } else {
            _items.add(_TemplateItem(args));
          }
      }
      if (mounted) setState(() {});
    } catch (_) {/* malformed args — ignore the card */}
  }

  static Map<String, dynamic> _decode(String arguments) {
    try {
      if (arguments.isEmpty) return <String, dynamic>{};
      return jsonDecode(arguments) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  void _addAi(String text) => setState(() => _items.add(_TextItem(text, false)));
  void _remove(_ChatItem item) => setState(() => _items.remove(item));

  String get _welcomeSubtitle => switch (widget.chatContext) {
        'onboarding-schedule' =>
          "Describe your custody pattern in plain English and I'll build it for you. Once you accept it, setup continues automatically.",
        'schedule' =>
          'I can help you set up custody schedules, create patterns, add override days, and answer schedule questions.',
        _ => 'I can help you set up custody schedules, answer questions about the app, and more.',
      };

  void _applyUsage(AiChatResponse r) {
    if (r.monthlyBudget > 0 && mounted) {
      setState(() => _usageFraction = (r.monthlySpend / r.monthlyBudget).clamp(0, 1));
    }
  }

  // ── Tool-call actions ─────────────────────────────────────────────────────────
  // Apply an AI-generated weekly pattern to the LIVE schedule (replaces the recurring
  // pattern). Takes the schedule-wide lock so the co-parent can't edit mid-apply, then
  // bulk-applies + releases. No proposals — one shared live schedule.
  Future<void> _applyPattern(_PatternItem item) async {
    setState(() => item.busy = true);
    try {
      final live = ServiceLocator.liveSchedule;
      final days = [
        for (final d in item.args.days)
          LiveDay(
            weekIndex: d.weekIndex,
            dayIndex: d.dayIndex,
            parentAssignment: d.parentAssignment,
            transferTime: d.transferTime,
            transferEndTime: d.transferEndTime,
            transferLocationName: d.locationName,
            transferAddress: d.locationAddress,
            transferLatitude: d.latitude,
            transferLongitude: d.longitude,
          ),
      ];
      final lock = await live.acquireLock('ai');
      if (lock.op != LiveOp.ok) {
        _addAi(_liveMsg(lock.op));
        if (mounted) setState(() => item.busy = false);
        return;
      }
      // Hold the lock across the apply; ALWAYS release it, even if the apply throws.
      try {
        final res = await live.applyBulk('ai', item.args.patternLengthWeeks, days, const []);
        if (!mounted) return;
        if (res.ok) {
          _remove(item);
          AnalyticsService.trackCustom('ai_pattern_applied_live');
          _addAi("✅ Added to your live schedule. Open the Schedule editor to review it — when you're happy, tap Agree.");
        } else {
          _addAi(_liveMsg(res.op));
          setState(() => item.busy = false);
        }
      } finally {
        await live.releaseLock();
      }
    } catch (_) {
      _addAi('Something went wrong while applying the pattern. Please try again, or use the Schedule editor.');
      if (mounted) setState(() => item.busy = false);
    }
  }

  // One place mapping every live-schedule outcome to a clear, user-facing line.
  String _liveMsg(LiveOp op) => switch (op) {
        LiveOp.locked =>
          "Your co-parent is editing the whole schedule right now — give it a moment and try again.",
        LiveOp.lockedDay =>
          "Your co-parent is editing one of the days right now — give it a moment and try again.",
        LiveOp.conflict =>
          "Your co-parent just changed the schedule. Tap to apply again and I'll build on the latest version.",
        LiveOp.noPartner =>
          "Link your co-parent first, then I can set up your shared schedule.",
        LiveOp.error || LiveOp.ok =>
          "I couldn't apply that just now. Please try again, or use the Schedule editor.",
      };

  // Add an AI-suggested override (holiday / special day) to the LIVE schedule.
  Future<void> _applyOverride(_OverrideItem item) async {
    final o = item.args;
    setState(() => item.busy = true);
    try {
      final live = ServiceLocator.liveSchedule;
      final cur = await live.get();
      if (!cur.ok || cur.data == null) {
        _addAi("I couldn't load your schedule to add that. Open the Schedule editor and try there.");
        setState(() => item.busy = false);
        return;
      }
      final res = await live.upsertOverride(
        cur.data!.version,
        LiveOverride(
          dateKey: (o.holidayRule?.isNotEmpty ?? false) ? '01-01' : '${_pad(o.month)}-${_pad(o.day)}',
          month: o.month,
          day: o.day,
          parentAssignment: o.parentAssignment,
          description: o.label,
          transferTime: o.transferTime,
          transferEndTime: o.transferEndTime,
          isAnnual: o.isAnnual,
          holidayRule: o.holidayRule,
          alternationMode: o.alternationMode ?? 'fixed',
          alternationStartParent: o.alternationStartParent,
          transferLocationName: o.locationName,
          transferAddress: o.locationAddress,
          transferLatitude: o.latitude,
          transferLongitude: o.longitude,
        ),
      );
      if (res.ok) {
        _remove(item);
        _addAi('✅ Added ${o.label} to your live schedule.');
      } else {
        _addAi(_liveMsg(res.op));
        setState(() => item.busy = false);
      }
    } catch (_) {
      _addAi('Something went wrong. Please try again, or use the Schedule editor.');
      if (mounted) setState(() => item.busy = false);
    }
  }

  Future<void> _applyEvent(_EventItem item) async {
    final e = item.args;
    setState(() => item.busy = true);
    try {
      final ok = await ServiceLocator.schedule.updateSchedule(
        e.month, e.day, e.year, e.title, e.startTime, e.endTime,
        repeatType: e.repeatType, endDate: e.endDate, isCustodial: false,
      );
      if (ok) {
        _remove(item);
        final note = e.repeatType != 'none' ? ' It will repeat ${e.repeatType}.' : '';
        _addAi('✅ "${e.title}" added to your calendar!$note');
      } else {
        _addAi('Failed to add the event. Please try from the Schedule tab.');
        setState(() => item.busy = false);
      }
    } catch (_) {
      _addAi('Something went wrong. Please try from the Schedule tab.');
      if (mounted) setState(() => item.busy = false);
    }
  }

  Future<void> _sendDraft(_DraftItem item) async {
    final partnerEmail = Preferences.getString('partnerEmail');
    if (partnerEmail.isEmpty) {
      _addAi("I couldn't find your co-parent's contact. Connect with them first from the Partner page.");
      return;
    }
    _remove(item);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatInterfacePage(
        contactEmail: 'partner',
        contactName: 'Co-Parent',
        draftMessage: item.args.messageText,
      ),
    ));
  }

  Future<void> _openTemplate(_TemplateItem item) async {
    final template = TemplateRegistry.findById(item.args.templateId);
    if (template == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TemplateConfigPage(template: template, presetAnswers: item.args.answers),
    ));
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.surface,
      body: Column(
        children: [
          _header(context),
          if (_usageFraction > 0)
            Container(
              color: palette.surface,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: _usageFraction,
                        minHeight: 4,
                        backgroundColor: palette.border,
                        color: _usageFraction > 0.8
                            ? AppColors.dangerRed
                            : _usageFraction > 0.6
                                ? AppColors.warningAmber
                                : AppColors.primaryBlue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${(_usageFraction * 100).round()}% used',
                      style: TextStyle(fontSize: 11, color: palette.textSecondary)),
                ],
              ),
            ),
          Expanded(
            child: Container(
              color: palette.background,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => FocusScope.of(context).unfocus(),
                child: _items.isEmpty ? _welcome(context) : _messageList(context),
              ),
            ),
          ),
          _inputBar(context),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: EdgeInsets.fromLTRB(4, MediaQuery.viewPaddingOf(context).top + 8, 16, 8),
      color: palette.surface,
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: const SizedBox(
              width: 36,
              height: 36,
              child: Center(child: Text('‹', style: TextStyle(fontSize: 32, color: AppColors.primaryBlue))),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text('CoHarmony™ AI',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const AppIcon('icon_sparkle', size: 12, color: AppColors.primaryBlue),
                    const SizedBox(width: 4),
                    Text('Your personal assistant', style: TextStyle(fontSize: 11, color: palette.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.primaryBlue, borderRadius: BorderRadius.circular(14)),
            child: const Center(child: AppIcon('icon_sparkle', size: 22, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _welcome(BuildContext context) {
    final palette = context.palette;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(color: AppColors.iconBgBlue, borderRadius: BorderRadius.circular(20)),
            child: const Center(child: AppIcon('icon_sparkle', size: 40, color: AppColors.primaryBlue)),
          ),
          const SizedBox(height: 20),
          Text("Hi! I'm your CoHarmony™ AI assistant.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: palette.textPrimary)),
          const SizedBox(height: 8),
          Text(_welcomeSubtitle,
              textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: palette.textSecondary)),
          const SizedBox(height: 20),
          for (final s in _suggestions) ...[
            _chip(context, s.$1, s.$2, s.$3),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String icon, Color tint, String label) {
    final palette = context.palette;
    return GestureDetector(
      onTap: () => _send(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: palette.surfaceElevated,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, size: 16, color: tint),
            const SizedBox(width: 8),
            Flexible(child: Text(label, style: TextStyle(fontSize: 14, color: palette.textPrimary))),
          ],
        ),
      ),
    );
  }

  Widget _messageList(BuildContext context) {
    final palette = context.palette;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _items.length + (_sending ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        if (_sending && i == _items.length) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: palette.surfaceElevated, borderRadius: BorderRadius.circular(16)),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: palette.textSecondary),
              ),
            ),
          );
        }
        return _buildItem(context, _items[i]);
      },
    );
  }

  Widget _buildItem(BuildContext context, _ChatItem item) {
    return switch (item) {
      _TextItem t => _bubble(context, t),
      _PatternItem p => _patternCard(context, p),
      _OverrideItem o => _overrideCard(context, o),
      _EventItem e => _eventCard(context, e),
      _DraftItem d => _draftCard(context, d),
      _TemplateItem t => _templateCard(context, t),
      _ViewScheduleItem _ => _viewScheduleButton(context),
    };
  }

  Widget _bubble(BuildContext context, _TextItem t) {
    final palette = context.palette;
    return Row(
      mainAxisAlignment: t.outgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: t.outgoing ? AppColors.primaryBlue : palette.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(t.text, style: TextStyle(fontSize: 15, color: t.outgoing ? Colors.white : palette.textPrimary)),
          ),
        ),
      ],
    );
  }

  // ── Cards ─────────────────────────────────────────────────────────────────────
  Widget _cardShell(BuildContext context, Color accent, List<Widget> children, {double maxWidth = 320, double opacity = 1}) {
    final palette = context.palette;
    return Align(
      alignment: Alignment.centerLeft,
      child: Opacity(
        opacity: opacity,
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: palette.surfaceElevated,
            border: Border.all(color: accent),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }

  Widget _cardHeader(BuildContext context, String icon, Color accent, String title) => Row(
        children: [
          AppIcon(icon, size: 16, color: accent),
          const SizedBox(width: 8),
          Flexible(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: accent)),
          ),
        ],
      );

  Widget _cardButtons(BuildContext context, String declineLabel, VoidCallback onDecline, String acceptLabel,
      Color acceptColor, VoidCallback onAccept) {
    final palette = context.palette;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.textSecondary,
              side: BorderSide(color: palette.border),
              minimumSize: const Size(0, 40),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: onDecline,
            child: Text(declineLabel, style: const TextStyle(fontSize: 13)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: acceptColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 40),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: onAccept,
            child: Text(acceptLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _patternCard(BuildContext context, _PatternItem item) {
    final palette = context.palette;
    final p = item.args;
    return _cardShell(context, AppColors.primaryBlue, opacity: item.busy ? 0.6 : 1, [
      _cardHeader(context, 'icon_calendar', AppColors.primaryBlue, 'Schedule Preview'),
      const SizedBox(height: 4),
      Text('${p.patternLengthWeeks}-week pattern', style: TextStyle(fontSize: 12, color: palette.textSecondary)),
      const SizedBox(height: 10),
      ProposalPreviewGrid(
        patternLength: p.patternLengthWeeks,
        days: [
          for (final d in p.days)
            ProposalDayDto(
              weekIndex: d.weekIndex,
              dayIndex: d.dayIndex,
              parentAssignment: d.parentAssignment,
              transferTime: d.transferTime,
              transferEndTime: d.transferEndTime,
            ),
        ],
      ),
      const SizedBox(height: 12),
      _cardButtons(
        context,
        'Decline',
        () {
          _remove(item);
          _addAi("No problem! Let me know if you'd like a different pattern.");
        },
        'Add to schedule',
        AppColors.successGreen,
        item.busy ? () {} : () => _applyPattern(item),
      ),
    ]);
  }

  Widget _overrideCard(BuildContext context, _OverrideItem item) {
    final palette = context.palette;
    final o = item.args;
    final monthName = o.month >= 1 && o.month <= 12 ? _monthAbbr[o.month] : '???';
    final subtitle = <String>[
      if (o.holidayRule?.isNotEmpty ?? false) 'Variable date (auto-resolved)' else '$monthName ${o.day}',
      if (o.isAnnual) (o.alternationMode == 'alternating' ? 'Alternates yearly' : 'Repeats every year'),
    ].join(' • ');
    return _cardShell(context, AppColors.dangerRed, opacity: item.busy ? 0.6 : 1, [
      _cardHeader(context, 'icon_gift', AppColors.dangerRed, 'Override Day Preview'),
      const SizedBox(height: 10),
      Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(color: _parentFill[o.parentAssignment] ?? _parentFill['None'], borderRadius: BorderRadius.circular(10)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(monthName, style: TextStyle(fontSize: 10, color: _parentText[o.parentAssignment] ?? _parentText['None'])),
                Text('${o.day}',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _parentText[o.parentAssignment] ?? _parentText['None'])),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${o.label} → ${o.parentAssignment}',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                Text(subtitle, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                if (o.transferTime?.isNotEmpty ?? false)
                  Text(
                      (o.transferEndTime?.isNotEmpty ?? false)
                          ? 'Handoff ${o.transferTime} – ${o.transferEndTime}'
                          : 'Handoff at ${o.transferTime}',
                      style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                if (o.locationName?.isNotEmpty ?? false)
                  Text('📍 ${o.locationName}', style: TextStyle(fontSize: 12, color: palette.textSecondary)),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _cardButtons(context, 'Dismiss', () {
        _remove(item);
        _addAi("No problem! Let me know if you'd like to set up a different override day.");
      }, 'Accept', AppColors.successGreen, item.busy ? () {} : () => _applyOverride(item)),
    ]);
  }

  Widget _eventCard(BuildContext context, _EventItem item) {
    final palette = context.palette;
    final e = item.args;
    final monthName = e.month >= 1 && e.month <= 12 ? _monthAbbr[e.month] : '???';
    return _cardShell(context, AppColors.successGreen, opacity: item.busy ? 0.6 : 1, [
      _cardHeader(context, 'icon_calendar', AppColors.successGreen, 'Event Preview'),
      const SizedBox(height: 10),
      Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(10)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(monthName, style: const TextStyle(fontSize: 10, color: Color(0xFF065F46))),
                Text('${e.day}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF065F46))),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                Text('$monthName ${e.day}, ${e.year} • ${e.startTime} – ${e.endTime}',
                    style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                if (e.repeatType != 'none')
                  Text('🔁 Repeats ${e.repeatType}', style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                if (e.notes?.isNotEmpty ?? false)
                  Text(e.notes!, style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: palette.textSecondary)),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _cardButtons(context, 'Decline', () {
        _remove(item);
        _addAi("No problem! Let me know if you'd like to add a different event.");
      }, 'Add Event', AppColors.successGreen, item.busy ? () {} : () => _applyEvent(item)),
    ]);
  }

  Widget _draftCard(BuildContext context, _DraftItem item) {
    final palette = context.palette;
    final d = item.args;
    return _cardShell(context, AppColors.accentPurple, [
      _cardHeader(context, 'icon_chat', AppColors.accentPurple, 'Draft: ${d.subject}'),
      const SizedBox(height: 10),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: palette.surfaceInput, borderRadius: BorderRadius.circular(12)),
        child: Text(d.messageText, style: TextStyle(fontSize: 14, color: palette.textPrimary)),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.textSecondary,
                side: BorderSide(color: palette.border),
                minimumSize: const Size(0, 40),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: () {
                _remove(item);
                _addAi("No problem! Let me know if you'd like me to try a different draft.");
              },
              child: const Text('Dismiss', style: TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.textPrimary,
                side: BorderSide(color: palette.border),
                minimumSize: const Size(0, 40),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(text: d.messageText));
                messenger.showSnackBar(
                    const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)));
              },
              child: const Text('Copy', style: TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentPurple,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 40),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: () => _sendDraft(item),
              child: const Text('Send', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    ]);
  }

  Widget _templateCard(BuildContext context, _TemplateItem item) {
    final palette = context.palette;
    final template = TemplateRegistry.findById(item.args.templateId);
    if (template == null) return const SizedBox.shrink();
    return _cardShell(context, AppColors.primaryBlue, [
      _cardHeader(context, 'icon_calendar', AppColors.primaryBlue, template.name),
      const SizedBox(height: 6),
      Text(template.shortDescription, style: TextStyle(fontSize: 13, color: palette.textSecondary)),
      const SizedBox(height: 12),
      _cardButtons(context, 'Dismiss', () => _remove(item), 'Open', AppColors.primaryBlue, () => _openTemplate(item)),
    ]);
  }

  Widget _viewScheduleButton(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LiveSchedulePage())),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: context.isDark ? const Color(0xFF1E3A5F) : const Color(0xFFEFF6FF),
            border: Border.all(color: AppColors.primaryBlue),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon('icon_calendar', size: 18, color: AppColors.primaryBlue),
              SizedBox(width: 10),
              Text('View in Schedule Editor',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
              SizedBox(width: 8),
              Text('→', style: TextStyle(fontSize: 16, color: AppColors.primaryBlue)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputBar(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: palette.surface,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.08),
              offset: const Offset(0, -4),
              blurRadius: 16),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: context.isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
                border: Border.all(color: palette.border),
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 5,
                style: TextStyle(fontSize: 16, color: palette.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Ask me anything...',
                  hintStyle: TextStyle(color: palette.textSecondary),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _send(_controller.text),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.primaryBlue, borderRadius: BorderRadius.circular(22)),
              child: const Center(child: AppIcon('icon_send', size: 20, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chat item model ──────────────────────────────────────────────────────────────
sealed class _ChatItem {}

class _TextItem extends _ChatItem {
  _TextItem(this.text, this.outgoing);
  final String text;
  final bool outgoing;
}

class _PatternItem extends _ChatItem {
  _PatternItem(this.args);
  final SetCustodyPatternArgs args;
  bool busy = false;
}

class _OverrideItem extends _ChatItem {
  _OverrideItem(this.args);
  final AddOverrideDayArgs args;
  bool busy = false;
}

class _EventItem extends _ChatItem {
  _EventItem(this.args);
  final CreateEventArgs args;
  bool busy = false;
}

class _DraftItem extends _ChatItem {
  _DraftItem(this.args);
  final DraftMessageArgs args;
}

class _TemplateItem extends _ChatItem {
  _TemplateItem(this.args);
  final SelectTemplateArgs args;
}

class _ViewScheduleItem extends _ChatItem {}
