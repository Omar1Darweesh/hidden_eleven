import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';

import 'package:hidden_eleven/features/admin/services/admin_api.dart';
import 'package:hidden_eleven/features/game/models/ability.dart';
import 'package:hidden_eleven/features/game/models/chemistry_vars.dart';

/// The "HOW IT WORKS" 4 steps, admin-editable (Admin → Instructions →
/// Contextual Help, key 'abilities') — this is only the offline fallback,
/// used immediately and permanently if the fetch fails, the key isn't found,
/// or the admin has hidden it. "THE CARDS" section below renders live
/// AbilityMeta — name/description are themselves admin-configured (see
/// ability.dart's AbilityMeta.ensureLoaded), with description resolved
/// through ChemistryVars for any `{yellowPenalty}`-style placeholder; icon
/// stays code-only, there's no server field for it.
const _fallbackHowItWorks = <(String, String, String)>[
  (
    '1',
    'Pick a secret card',
    'At kickoff each player draws one ability — kept hidden from everyone else.',
  ),
  ('2', 'Build your XI', 'Draft your 11 players as normal.'),
  (
    '3',
    'Play or discard',
    'Before subs, use your card on a target (or discard it). Everyone sees what’s played.',
  ),
  ('4', 'Subs', 'Spin subs to recover from anything done to your squad.'),
];

/// A friendly "how it works" guide for the ability-cards feature: the phase
/// flow plus what each of the 5 cards does. Opened from a (?) button.
void showAbilitiesHelpDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => const _AbilitiesHelpDialog(),
  );
}

/// Small circular (?) button that opens the guide. Drop it into headers/app bars.
class AbilitiesHelpButton extends StatelessWidget {
  const AbilitiesHelpButton({super.key, this.size = 20, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.help_outline_rounded, size: size),
      color: color ?? HETheme.pfTextSecondary,
      tooltip: 'How abilities work',
      onPressed: () => showAbilitiesHelpDialog(context),
    );
  }
}

class _AbilitiesHelpDialog extends StatefulWidget {
  const _AbilitiesHelpDialog();

  @override
  State<_AbilitiesHelpDialog> createState() => _AbilitiesHelpDialogState();
}

class _AbilitiesHelpDialogState extends State<_AbilitiesHelpDialog> {
  List<(String, String, String)>? _fetchedSteps;

  @override
  void initState() {
    super.initState();
    AdminApi.getContextHelp()
        .then((all) {
          if (!mounted) return;
          final match = all.where((c) => c.key == 'abilities').firstOrNull;
          final section = match?.sections.firstOrNull;
          if (match == null ||
              !match.visible ||
              section == null ||
              section.entries.isEmpty) {
            return;
          }
          setState(() {
            _fetchedSteps = [
              for (var i = 0; i < section.entries.length; i++)
                (
                  '${i + 1}',
                  section.entries[i].label,
                  ChemistryVars.resolve(section.entries[i].body),
                ),
            ];
          });
        })
        .catchError((_) {
          // Best-effort only — the hardcoded fallback above is a complete guide
          // on its own, so a failed fetch is never a broken dialog.
        });
  }

  @override
  Widget build(BuildContext context) {
    final steps = _fetchedSteps ?? _fallbackHowItWorks;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 620),
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: const Color(0xFF0F1520),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: HETheme.pfAccentViolet.withValues(alpha: 0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
                color: HETheme.pfAccentViolet.withValues(alpha: 0.10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      color: HETheme.pfAccentViolet,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Ability Cards',
                        style: TextStyle(
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
                      _section('HOW IT WORKS'),
                      const SizedBox(height: 8),
                      for (final (n, title, body) in steps)
                        _step(n, title, body),
                      const SizedBox(height: 18),
                      _section('THE CARDS'),
                      const SizedBox(height: 8),
                      for (final t in AbilityType.values) _card(t),
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

  Widget _section(String text) => Text(
    text,
    style: const TextStyle(
      color: HETheme.pfTextSecondary,
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.4,
    ),
  );

  Widget _step(String n, String title, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: HETheme.pfAccentViolet.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            n,
            style: const TextStyle(
              color: HETheme.pfAccentViolet,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: HETheme.pfTextPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                body,
                style: const TextStyle(
                  color: HETheme.pfTextSecondary,
                  fontSize: 11.5,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _card(AbilityType type) {
    final meta = AbilityMeta.of(type);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: meta.color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: meta.color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: meta.color.withValues(alpha: 0.16),
                shape: BoxShape.circle,
                border: Border.all(color: meta.color.withValues(alpha: 0.5)),
              ),
              child: Icon(meta.icon, color: meta.color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meta.name,
                    style: TextStyle(
                      color: meta.color,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    ChemistryVars.resolve(meta.description),
                    style: const TextStyle(
                      color: HETheme.pfTextSecondary,
                      fontSize: 11.5,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
