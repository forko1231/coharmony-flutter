import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Renders a CoHarmony icon from `assets/images/<name>.svg`, optionally tinted —
/// the Flutter equivalent of MAUI's `<Image Source="icon_x.png">` +
/// `IconTintColorBehavior`. Pass the logical name without extension, e.g.
/// `AppIcon('icon_calendar', size: 28, color: AppColors.primaryBlue)`.
class AppIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;

  const AppIcon(this.name, {super.key, this.size = 24, this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/images/$name.svg',
      width: size,
      height: size,
      colorFilter:
          color != null ? ColorFilter.mode(color!, BlendMode.srcIn) : null,
    );
  }
}
