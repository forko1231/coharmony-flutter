import 'package:flutter/material.dart';
import '../theme/app_palette.dart';

/// The bordered input container used throughout the forms — equivalent to the
/// MAUI `<Border SurfaceInput + 1.5 stroke + RoundRectangle 14>` wrapping an `<Entry>`.
/// Wrap a [TextField] (with a collapsed/borderless decoration) as its [child].
class AppInputBox extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double strokeThickness;
  final Color? strokeColor;

  const AppInputBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 14),
    this.strokeThickness = 1.5,
    this.strokeColor,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: palette.surfaceInput,
        border: Border.all(color: strokeColor ?? palette.border, width: strokeThickness),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

/// A borderless [TextField] styled to sit inside [AppInputBox] (mirrors MAUI `<Entry>`).
class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final Widget? trailing;
  final int maxLines;

  const AppTextField({
    super.key,
    this.controller,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.trailing,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final field = TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      maxLines: obscure ? 1 : maxLines,
      style: TextStyle(fontSize: 16, color: palette.textPrimary),
      cursorColor: palette.textPrimary,
      decoration: InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        hintText: hint,
        hintStyle: TextStyle(fontSize: 16, color: palette.textPlaceholder),
      ),
    );
    if (trailing == null) return field;
    return Row(
      children: [
        Expanded(child: field),
        const SizedBox(width: 8),
        trailing!,
      ],
    );
  }
}
