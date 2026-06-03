import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Custody assignment used by the schedule editor (4-way, including Both/None).
enum CustodyParent { dad, mom, both, none }

extension CustodyParentX on CustodyParent {
  String get label => switch (this) {
        CustodyParent.dad => 'Dad',
        CustodyParent.mom => 'Mom',
        CustodyParent.both => 'Both',
        CustodyParent.none => 'None',
      };

  /// Cell/chip fill when this parent is assigned. `none` is transparent (outlined).
  Color get fill => switch (this) {
        CustodyParent.dad => AppColors.parentDad, // LightBlue
        CustodyParent.mom => AppColors.parentMom, // LightPink
        CustodyParent.both => AppColors.parentBoth, // MediumPurple
        CustodyParent.none => Colors.transparent,
      };

  /// Text color on top of [fill].
  Color get onFill => switch (this) {
        CustodyParent.dad => const Color(0xFF1E40AF),
        CustodyParent.mom => const Color(0xFFBE185D),
        CustodyParent.both => Colors.white,
        CustodyParent.none => const Color(0xFF9CA3AF),
      };
}
