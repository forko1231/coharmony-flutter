import 'package:flutter/material.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';

/// The simple rounded input used by the older password-reset/verify screens —
/// a `surface` box (radius 10, padding 10) wrapping a borderless field, with an
/// optional password eye toggle. Mirrors those screens' `<Border>` + `<Entry>`.
class AuthSimpleInput extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final bool isPassword;
  final TextInputType? keyboardType;
  final int? maxLength;
  final TextAlign textAlign;
  final double fontSize;
  final bool bold;

  const AuthSimpleInput({
    super.key,
    required this.controller,
    required this.hint,
    this.isPassword = false,
    this.keyboardType,
    this.maxLength,
    this.textAlign = TextAlign.start,
    this.fontSize = 16,
    this.bold = false,
  });

  @override
  State<AuthSimpleInput> createState() => _AuthSimpleInputState();
}

class _AuthSimpleInputState extends State<AuthSimpleInput> {
  late bool _obscure = widget.isPassword;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              obscureText: _obscure,
              keyboardType: widget.keyboardType,
              maxLength: widget.maxLength,
              textAlign: widget.textAlign,
              style: TextStyle(
                  fontSize: widget.fontSize,
                  fontWeight: widget.bold ? FontWeight.bold : FontWeight.normal,
                  color: palette.textPrimary),
              cursorColor: palette.textPrimary,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                counterText: '',
                hintText: widget.hint,
                hintStyle: TextStyle(fontSize: widget.fontSize, color: palette.textPlaceholder),
              ),
            ),
          ),
          if (widget.isPassword)
            GestureDetector(
              onTap: () => setState(() => _obscure = !_obscure),
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: AppIcon(_obscure ? 'icon_eye_off' : 'icon_eye', size: 22, color: palette.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}
