import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/admin/models/admin_models.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart';
import 'package:hidden_eleven/features/game/models/chemistry_vars.dart';
import 'package:hidden_eleven/shared/widgets/help_dialog.dart';

/// Module-level cache — the 5 context-help entries rarely change mid-session,
/// and every screen showing a (?) button would otherwise re-fetch the same
/// small payload on every visit. Cleared only by a fresh app process/reload.
Future<List<AdminContextHelp>>? _cachedContextHelp;

Future<List<AdminContextHelp>> _loadContextHelp() {
  return _cachedContextHelp ??= AdminApi.getContextHelp().catchError(
    (_) => <AdminContextHelp>[],
  );
}

/// Converts admin-edited context-help content into the HelpSection list the
/// existing dialog chrome already renders. Entry bodies are resolved through
/// ChemistryVars here — the single conversion point both callers below share
/// — so `help_dialog.dart`'s dialog chrome itself stays generic/content-
/// agnostic, with no knowledge of chemistry placeholders.
List<HelpSection> contextHelpToSections(AdminContextHelp help) => help.sections
    .map(
      (s) => HelpSection(
        s.heading,
        s.entries
            .map((e) => HelpEntry(e.label, ChemistryVars.resolve(e.body)))
            .toList(),
      ),
    )
    .toList();

/// Opens the same admin-editable-with-fallback help dialog [ContextHelpButton]
/// shows, without needing to mount that widget — for callers (e.g. an
/// overflow menu item) that just need the resulting action, not the icon.
/// Reuses the same module-level cache, so this never double-fetches.
Future<void> showContextHelp(
  BuildContext context, {
  required String contextKey,
  required String title,
  required List<HelpSection> fallbackSections,
  IconData icon = Icons.help_outline_rounded,
  Color accent = HETheme.pfAccentViolet,
}) async {
  final all = await _loadContextHelp();
  final match = all.where((c) => c.key == contextKey).firstOrNull;
  final sections = (match != null && match.visible && match.sections.isNotEmpty)
      ? contextHelpToSections(match)
      : fallbackSections;
  if (!context.mounted) return;
  showHelpDialog(
    context,
    title: title,
    icon: icon,
    accent: accent,
    sections: sections,
  );
}

/// Drop-in replacement for [HelpButton] that fetches its content from the
/// admin-editable Instructions dashboard (Admin → Instructions → Contextual
/// Help — see admin.service.ts's CONTEXT_HELP_KEYS), falling back to
/// [fallbackSections] — the exact hardcoded content this replaces —
/// immediately on first render and permanently if the fetch fails, the key
/// isn't found, or the admin has hidden it. Never shows a loading state: the
/// fallback IS the initial content, swapped only if a better answer arrives.
class ContextHelpButton extends StatefulWidget {
  const ContextHelpButton({
    super.key,
    required this.contextKey,
    required this.title,
    required this.fallbackSections,
    this.icon = Icons.help_outline_rounded,
    this.accent = HETheme.pfAccentViolet,
    this.size = 20,
    this.color,
    this.compact = false,
  });

  /// Matches AdminContextHelp.key exactly — 'draft_scoring' | 'abilities' |
  /// 'match_details' | 'result_page' | 'tournament'.
  final String contextKey;
  final String title;
  final List<HelpSection> fallbackSections;
  final IconData icon;
  final Color accent;
  final double size;
  final Color? color;
  final bool compact;

  @override
  State<ContextHelpButton> createState() => _ContextHelpButtonState();
}

class _ContextHelpButtonState extends State<ContextHelpButton> {
  List<HelpSection>? _fetched;

  @override
  void initState() {
    super.initState();
    _loadContextHelp().then((all) {
      if (!mounted) return;
      final match = all.where((c) => c.key == widget.contextKey).firstOrNull;
      if (match == null || !match.visible || match.sections.isEmpty) return;
      setState(() => _fetched = contextHelpToSections(match));
    });
  }

  @override
  Widget build(BuildContext context) {
    return HelpButton(
      title: widget.title,
      sections: _fetched ?? widget.fallbackSections,
      icon: widget.icon,
      accent: widget.accent,
      size: widget.size,
      color: widget.color,
      compact: widget.compact,
    );
  }
}
