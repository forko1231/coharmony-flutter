import 'package:flutter/material.dart';
import '../../navigation/app_navigator.dart';
import '../../services/analytics_service.dart';
import '../../services/onboarding_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';

class _TourItem {
  final String emoji;
  final String title;
  final String description;
  final String locationHint;
  const _TourItem(this.emoji, this.title, this.description, this.locationHint);
}

/// Post-subscription feature tour — port of `OnboardingTourPage.xaml(.cs)`.
/// Five swipeable cards (emoji + title + description + location chip), dots, and
/// a Next/Get-Started button.
class TourPage extends StatefulWidget {
  const TourPage({super.key});

  @override
  State<TourPage> createState() => _TourPageState();
}

class _TourPageState extends State<TourPage> {
  final _controller = PageController();
  int _index = 0;

  static const _items = <_TourItem>[
    _TourItem('📅', 'Your schedule, your way',
        'Tap any day to assign a parent or set a handoff time. Add override days for holidays. Your co-parent sees changes as proposals they can accept or counter.',
        'Schedule tab'),
    _TourItem('💬', 'Talk it out',
        'Message your co-parent and kids in one place. Stuck on what to say? The AI assistant can help you draft a calm, professional message before you send.',
        'Messages tab'),
    _TourItem('💳', 'Split the costs',
        'Log expenses, request reimbursements, and verify payments together. Everything is timestamped and visible to both parents — no more disputes.',
        'Dashboard → Payments'),
    _TourItem('✨', 'Ask the AI anything',
        'Describe a custody pattern in plain English, ask about your finances, or get help with a tough message. The AI uses your real data to give real answers.',
        'Dashboard → AI Assistant'),
    _TourItem('⚙️', 'Tweak anything later',
        'Invite more kids, change your schedule, swap your role, manage your subscription — everything you set up here can be changed anytime.',
        'Settings'),
  ];

  bool get _isLast => _index >= _items.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (!_isLast) {
      _controller.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    } else {
      _finish();
    }
  }

  void _skip() {
    AnalyticsService.trackCustom('onboarding_tour_skipped',
        extraTags: {'at_position': _index.toString()});
    _finish();
  }

  Future<void> _finish() async {
    OnboardingState.tourSeen = true;
    AnalyticsService.trackCustom('onboarding_tour_completed');
    // tourSeen is now set, so the router falls through to completeOnboarding →
    // main app (which also marks onboarding complete).
    await advanceOnboarding(context);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          // Top bar: dots + skip
          Padding(
            padding: EdgeInsets.fromLTRB(20, MediaQuery.viewPaddingOf(context).top + 12, 20, 12),
            child: Row(
              children: [
                const Expanded(child: SizedBox()),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(_items.length, (i) {
                    final active = i == _index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.primaryBlue
                            : (context.isDark ? const Color(0xFF374151) : const Color(0xFFD1D5DB)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: _skip,
                    child: Text('Skip',
                        textAlign: TextAlign.end,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: palette.textSecondary)),
                  ),
                ),
              ],
            ),
          ),

          // Cards
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: _items.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => _TourCard(item: _items[i]),
            ),
          ),

          // Footer
          Container(
            width: double.infinity,
            color: palette.background,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
            child: GestureDetector(
              onTap: _next,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(color: AppColors.primaryBlue.withValues(alpha: 0.35), offset: const Offset(0, 6), blurRadius: 12),
                  ],
                ),
                child: Center(
                  child: Text(_isLast ? 'Get Started' : 'Next',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TourCard extends StatelessWidget {
  final _TourItem item;
  const _TourCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: palette.surfaceElevated,
                  borderRadius: BorderRadius.circular(60),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: context.isDark ? 0.5 : 0.10),
                        offset: const Offset(0, 6),
                        blurRadius: 18),
                  ],
                ),
                child: Center(child: Text(item.emoji, style: const TextStyle(fontSize: 64))),
              ),
              const SizedBox(height: 28),
              Text(item.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: palette.textPrimary)),
              const SizedBox(height: 12),
              Text(item.description,
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: palette.textSecondary)),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: context.isDark ? const Color(0xFF1E3A5F) : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('📍', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Text(item.locationHint,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
