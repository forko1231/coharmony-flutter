import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';

/// The shared onboarding step header: "STEP n OF 3" + a 3-segment progress bar,
/// on a surface bar with the dynamic-island-clearing top padding. Used by the
/// partner-invite, schedule-review/apply and subscription onboarding steps.
class OnboardingStepHeader extends StatelessWidget {
  final int step; // 1-based
  final int total;
  final String? labelOverride;

  const OnboardingStepHeader({super.key, required this.step, this.total = 3, this.labelOverride});

  // Per-segment colors (blue → green → purple), matching the MAUI onboarding
  // steps and the subscription paywall's indicator.
  static const _seg = [AppColors.primaryBlue, AppColors.successGreen, AppColors.accentPurple];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final labelColor = _seg[(step - 1).clamp(0, _seg.length - 1)];
    final topInset = MediaQuery.viewPaddingOf(context).top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, topInset + 16, 24, 20),
      color: palette.surface,
      child: Column(
        children: [
          Text(labelOverride ?? 'STEP $step OF $total',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 2, color: labelColor)),
          const SizedBox(height: 14),
          Row(
            children: List.generate(total, (i) {
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: i < total - 1 ? 8 : 0),
                  decoration: BoxDecoration(
                    color: i < step ? _seg[i % _seg.length] : palette.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
