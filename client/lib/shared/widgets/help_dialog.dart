import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';

/// A reusable contextual-help pattern: a small (?) button that opens a
/// page-specific dialog explaining the page's own terms and flow. Generalized
/// from the ability-cards guide (`abilities_help.dart`) so every major page
/// (draft, tournament, match details, result) shares one presentation
/// mechanism — only the content differs, kept next to the feature it
/// describes rather than in one giant shared file.

/// One "label: explanation" line inside a [HelpSection].
class HelpEntry {
  final String label;
  final String body;
  const HelpEntry(this.label, this.body);
}

/// A titled group of [HelpEntry] lines inside a help dialog.
class HelpSection {
  final String title;
  final List<HelpEntry> entries;
  const HelpSection(this.title, this.entries);
}

/// Small circular (?) button — drop into an AppBar/section header. Opens the
/// page-specific help dialog built from [sections].
class HelpButton extends StatelessWidget {
  final String title;
  final List<HelpSection> sections;
  final IconData icon;
  final Color accent;
  final double size;
  final Color? color;

  /// True for tight inline slots (e.g. inside a compact row) — shrinks the
  /// tap-target padding instead of the default 48x48 AppBar-action sizing.
  final bool compact;

  const HelpButton({
    super.key,
    required this.title,
    required this.sections,
    this.icon = Icons.help_outline_rounded,
    this.accent = HETheme.pfAccentViolet,
    this.size = 20,
    this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.help_outline_rounded, size: size),
      color: color ?? HETheme.pfTextSecondary,
      tooltip: 'Help — $title',
      padding: compact ? EdgeInsets.zero : null,
      constraints: compact ? const BoxConstraints() : null,
      visualDensity: compact ? VisualDensity.compact : null,
      onPressed: () => showHelpDialog(
        context,
        title: title,
        icon: icon,
        accent: accent,
        sections: sections,
      ),
    );
  }
}

void showHelpDialog(
  BuildContext context, {
  required String title,
  required List<HelpSection> sections,
  IconData icon = Icons.help_outline_rounded,
  Color accent = HETheme.pfAccentViolet,
}) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => _HelpDialog(
      title: title,
      icon: icon,
      accent: accent,
      sections: sections,
    ),
  );
}

class _HelpDialog extends StatelessWidget {
  const _HelpDialog({
    required this.title,
    required this.icon,
    required this.accent,
    required this.sections,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final List<HelpSection> sections;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 620),
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: HETheme.pfSurfaceDeep,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
                color: accent.withValues(alpha: 0.10),
                child: Row(
                  children: [
                    Icon(icon, color: accent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: HETheme.pfTextPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: HETheme.pfTextMuted,
                        size: 20,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int i = 0; i < sections.length; i++) ...[
                        if (i > 0) const SizedBox(height: 18),
                        _sectionHeader(sections[i].title),
                        const SizedBox(height: 8),
                        for (final e in sections[i].entries) _entryRow(e),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String text) => Text(
    text,
    style: const TextStyle(
      color: HETheme.pfTextSecondary,
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.4,
    ),
  );

  Widget _entryRow(HelpEntry e) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          e.label,
          style: const TextStyle(
            color: HETheme.pfTextPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          e.body,
          style: const TextStyle(
            color: HETheme.pfTextSecondary,
            fontSize: 11.5,
            height: 1.35,
          ),
        ),
      ],
    ),
  );
}

/// A tiny inline "i" icon for a single potentially-confusing label — tap (or
/// hover on desktop) to reveal one short line, without opening a full dialog
/// or permanently occupying screen space with visible paragraph text.
class InlineHelp extends StatelessWidget {
  final String text;
  final double size;

  const InlineHelp(this.text, {super.key, this.size = 13});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: text,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 5),
      textStyle: const TextStyle(
        color: HETheme.pfTextPrimary,
        fontSize: 11.5,
        height: 1.3,
      ),
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: HETheme.pfBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          Icons.info_outline_rounded,
          size: size,
          color: HETheme.pfTextMuted,
        ),
      ),
    );
  }
}
