import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/shared/widgets/he_visual_style.dart';

class HETextField extends StatelessWidget {
  const HETextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.errorText,
    this.onChanged,
    this.textInputAction = TextInputAction.done,
    this.autofocus = false,
    this.style = HEVisualStyle.standard,
  });

  final TextEditingController controller;
  final String hintText;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final TextInputAction textInputAction;
  final bool autofocus;

  /// Migration bridge only — both values now render identically, entirely
  /// from the app-wide `InputDecorationTheme` (`theme.dart`), which already
  /// carries the Night Tactics fill/border/focus-ring/error colours that
  /// used to be duplicated here per-value. See [HEVisualStyle]'s doc
  /// comment; do not branch on this in new code.
  final HEVisualStyle style;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: textInputAction,
      autofocus: autofocus,
      style: Theme.of(context).textTheme.bodyLarge,
      cursorColor: HETheme.pfAccentViolet,
      decoration: InputDecoration(hintText: hintText, errorText: errorText),
    );
  }
}
