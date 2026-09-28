import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/theme.dart';
import 'package:hidden_eleven/features/admin/models/admin_models.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart';
import 'package:hidden_eleven/features/game/models/chemistry_vars.dart';

/// Shows one admin-authored quick tip contextual to the current draft phase
/// (matches GameTurn.phase exactly — 'selecting_position', 'selecting_card',
/// 'hidden_pick', 'subs', etc. — see AdminQuickTip.phase). Not wired into any
/// screen by default; drop it into game_screen.dart's build() wherever a
/// small contextual hint makes sense, passing the current `game.turn.phase`
/// (or `game.status` for the subs phase).
///
/// Example:
///   QuickTipBanner(phase: game.turn.phase)
class QuickTipBanner extends StatefulWidget {
  const QuickTipBanner({super.key, required this.phase});

  /// Current phase to show a tip for — pass null for a general (non-phase)
  /// tip. Tips tagged for a DIFFERENT phase are never shown.
  final String? phase;

  @override
  State<QuickTipBanner> createState() => _QuickTipBannerState();
}

class _QuickTipBannerState extends State<QuickTipBanner> {
  List<AdminQuickTip>? _tips;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant QuickTipBanner old) {
    super.didUpdateWidget(old);
    // A phase change means a stale dismiss shouldn't carry over — the next
    // phase's tip is new information, not the same one re-appearing.
    if (old.phase != widget.phase) {
      setState(() => _dismissed = false);
    }
  }

  Future<void> _load() async {
    try {
      final tips = await AdminApi.getQuickTips();
      if (mounted) setState(() => _tips = tips);
    } catch (_) {
      // Best-effort only — a failed tip fetch should never block gameplay.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed || _tips == null) return const SizedBox.shrink();
    final candidates =
        _tips!.where((t) => t.visible && t.phase == widget.phase).toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    if (candidates.isEmpty) return const SizedBox.shrink();
    final tip = candidates.first;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: HEColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(HERadius.sm),
        border: Border.all(color: HEColors.accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lightbulb_outline_rounded,
            color: HEColors.accent,
            size: 14,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ChemistryVars.resolve(tip.text),
              style: const TextStyle(
                color: HEColors.textSecondary,
                fontSize: 11.5,
                height: 1.3,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _dismissed = true),
            child: const Icon(
              Icons.close_rounded,
              color: HEColors.textMuted,
              size: 14,
            ),
          ),
        ],
      ),
    );
  }
}
