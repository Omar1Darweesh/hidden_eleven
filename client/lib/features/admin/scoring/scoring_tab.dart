import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hidden_eleven/app/theme.dart';
import 'package:hidden_eleven/features/admin/models/admin_models.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart';
import 'package:hidden_eleven/features/admin/widgets/admin_widgets.dart';

/// Admin-configurable chemistry/scoring values (Phase A/B/C — see the
/// "Chemistry Scoring — Admin-Configurable" design spec). Numeric-only: every
/// field here is a reward, penalty, multiplier, or fallback threshold that
/// already flows into GameService.createSession()'s scoring snapshot — no
/// rule TYPE (which bonuses exist, position groupings) is editable here.
///
/// A preview/simulate feature (see the design spec) is deliberately NOT part
/// of this tab — it would need its own dry-run endpoint and fixture data,
/// which is a materially bigger piece of work than the rest of this screen.
/// Rather than half-build it, it's simply absent; Publish's validation
/// errors are the only feedback loop this phase ships with.
class ScoringTab extends StatefulWidget {
  const ScoringTab({super.key});

  @override
  State<ScoringTab> createState() => _ScoringTabState();
}

class _ScoringTabState extends State<ScoringTab> {
  AdminScoringConfigFile? _file;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _publishing = false;
  bool _controllersReady = false;

  late TextEditingController _rewardPerChallenge;
  late TextEditingController _tierEasy;
  late TextEditingController _tierMedium;
  late TextEditingController _tierHard;
  late TextEditingController _sameClub;
  late TextEditingController _sameNation;
  late TextEditingController _sameLeague;
  late TextEditingController _positionGroup;
  late TextEditingController _clubAndPosClub;
  late TextEditingController _clubAndPosGroup;
  late TextEditingController _nationAndPosNation;
  late TextEditingController _nationAndPosGroup;
  late TextEditingController _bonusPerLine;
  late TextEditingController _yellowPenalty;
  late TextEditingController _captainMultiplier;
  final _noteController = TextEditingController();

  List<TextEditingController> get _allControllers => [
    _rewardPerChallenge,
    _tierEasy,
    _tierMedium,
    _tierHard,
    _sameClub,
    _sameNation,
    _sameLeague,
    _positionGroup,
    _clubAndPosClub,
    _clubAndPosGroup,
    _nationAndPosNation,
    _nationAndPosGroup,
    _bonusPerLine,
    _yellowPenalty,
    _captainMultiplier,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (_controllersReady) {
      for (final c in _allControllers) {
        c.dispose();
      }
    }
    _noteController.dispose();
    super.dispose();
  }

  void _initControllers(AdminScoringConfigValues v) {
    if (_controllersReady) {
      for (final c in _allControllers) {
        c.dispose();
      }
    }
    _rewardPerChallenge = TextEditingController(
      text: '${v.rewardPerChallenge}',
    );
    _tierEasy = TextEditingController(text: '${v.tierRewards.easy}');
    _tierMedium = TextEditingController(text: '${v.tierRewards.medium}');
    _tierHard = TextEditingController(text: '${v.tierRewards.hard}');
    _sameClub = TextEditingController(text: '${v.thresholds.sameClubCount}');
    _sameNation = TextEditingController(
      text: '${v.thresholds.sameNationCount}',
    );
    _sameLeague = TextEditingController(
      text: '${v.thresholds.sameLeagueCount}',
    );
    _positionGroup = TextEditingController(
      text: '${v.thresholds.positionGroupCount}',
    );
    _clubAndPosClub = TextEditingController(
      text: '${v.thresholds.clubAndPositionClubCount}',
    );
    _clubAndPosGroup = TextEditingController(
      text: '${v.thresholds.clubAndPositionGroupCount}',
    );
    _nationAndPosNation = TextEditingController(
      text: '${v.thresholds.nationAndPositionNationCount}',
    );
    _nationAndPosGroup = TextEditingController(
      text: '${v.thresholds.nationAndPositionGroupCount}',
    );
    _bonusPerLine = TextEditingController(text: '${v.bonusPerLine}');
    _yellowPenalty = TextEditingController(text: '${v.yellowPenalty}');
    _captainMultiplier = TextEditingController(text: '${v.captainMultiplier}');
    _controllersReady = true;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final file = await AdminApi.getScoringConfig();
      _initControllers(file.draft.values);
      if (mounted) {
        setState(() {
          _file = file;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Map<String, dynamic> _buildValuesJson() => {
    'userChallenges': {
      'rewardPerChallenge': int.tryParse(_rewardPerChallenge.text.trim()) ?? 0,
    },
    'cardChemistry': {
      'tierRewards': {
        'easy': int.tryParse(_tierEasy.text.trim()) ?? 0,
        'medium': int.tryParse(_tierMedium.text.trim()) ?? 0,
        'hard': int.tryParse(_tierHard.text.trim()) ?? 0,
      },
      'thresholds': {
        'sameClubCount': int.tryParse(_sameClub.text.trim()) ?? 0,
        'sameNationCount': int.tryParse(_sameNation.text.trim()) ?? 0,
        'sameLeagueCount': int.tryParse(_sameLeague.text.trim()) ?? 0,
        'positionGroupCount': int.tryParse(_positionGroup.text.trim()) ?? 0,
        'clubAndPositionClubCount':
            int.tryParse(_clubAndPosClub.text.trim()) ?? 0,
        'clubAndPositionGroupCount':
            int.tryParse(_clubAndPosGroup.text.trim()) ?? 0,
        'nationAndPositionNationCount':
            int.tryParse(_nationAndPosNation.text.trim()) ?? 0,
        'nationAndPositionGroupCount':
            int.tryParse(_nationAndPosGroup.text.trim()) ?? 0,
      },
    },
    'lineLeader': {
      'bonusPerLine': int.tryParse(_bonusPerLine.text.trim()) ?? 0,
    },
    'abilityEffects': {
      'yellowPenalty': int.tryParse(_yellowPenalty.text.trim()) ?? 0,
      'captainMultiplier': int.tryParse(_captainMultiplier.text.trim()) ?? 0,
    },
  };

  Future<void> _saveDraft() async {
    setState(() => _saving = true);
    try {
      await AdminApi.saveScoringConfigDraft(_buildValuesJson());
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Draft saved.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      return;
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _publish() async {
    setState(() => _publishing = true);
    try {
      // Publish always acts on exactly what's on screen — save first so a
      // click on Publish can never accidentally ship stale field values.
      await AdminApi.saveScoringConfigDraft(_buildValuesJson());
      final note = _noteController.text.trim();
      await AdminApi.publishScoringConfig(note: note.isEmpty ? null : note);
      _noteController.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Published.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _publishing = false);
        _showValidationErrors(_extractErrorMessages(e));
      }
      return;
    }
    if (mounted) setState(() => _publishing = false);
  }

  void _showValidationErrors(List<String> messages) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HEColors.surfaceElevated,
        title: const Text('Cannot publish'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: messages
              .map(
                (m) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '•  $m',
                    style: const TextStyle(
                      color: HEColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Scoring Configuration',
          style: TextStyle(
            color: HEColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Numeric chemistry/scoring values only — reward amounts, '
          'penalties, and multipliers. Rule types and how challenges are '
          'assigned are not editable here. A live-in-progress game keeps '
          'using whatever was published when it started, never a later edit.',
          style: TextStyle(color: HEColors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 16),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AdminErrorState(error: _error!, onRetry: _load);
    final file = _file;
    if (file == null) return const AdminEmptyState(label: 'No config loaded');

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusBanner(file: file),
          const SizedBox(height: 20),

          const AdminSectionHeader('User Challenges'),
          const SizedBox(height: 10),
          _numField(
            _rewardPerChallenge,
            'Reward per satisfied challenge',
            'Awarded once per completed challenge (each player has 5).',
          ),

          const SizedBox(height: 20),
          const AdminSectionHeader('Card Chemistry — Tier Rewards'),
          const SizedBox(height: 4),
          const Text(
            'Every drafted card carries 3 tiered challenges; all three can '
            'be satisfied independently.',
            style: TextStyle(color: HEColors.textMuted, fontSize: 11.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _numField(_tierEasy, 'Easy')),
              const SizedBox(width: 12),
              Expanded(child: _numField(_tierMedium, 'Medium')),
              const SizedBox(width: 12),
              Expanded(child: _numField(_tierHard, 'Hard')),
            ],
          ),

          const SizedBox(height: 20),
          const AdminSectionHeader('Card Chemistry — Fallback Thresholds'),
          const SizedBox(height: 4),
          const Text(
            'Only used when a bonus is missing its own count (every card '
            'generated today always has one) — a safety net, not an active '
            'tuning knob in practice.',
            style: TextStyle(color: HEColors.textMuted, fontSize: 11.5),
          ),
          const SizedBox(height: 10),
          _thresholdGrid(),

          const SizedBox(height: 20),
          const AdminSectionHeader('Line Leader'),
          const SizedBox(height: 10),
          _numField(
            _bonusPerLine,
            'Bonus per line won',
            'Awarded once per line (Defence / Midfield / Attack) to whoever '
                'has the highest-rated in-position card there.',
          ),

          const SizedBox(height: 20),
          const AdminSectionHeader('Ability Effects'),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _numField(_yellowPenalty, 'Yellow card penalty')),
              const SizedBox(width: 12),
              Expanded(
                child: _numField(
                  _captainMultiplier,
                  'Captain multiplier',
                  'How many times the captained card\'s chemistry counts '
                      '(2 = doubled). Minimum 1.',
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          _SaveBar(
            saving: _saving,
            publishing: _publishing,
            noteController: _noteController,
            onSaveDraft: _saveDraft,
            onPublish: _publish,
          ),

          const SizedBox(height: 28),
          AdminSectionHeader('Version History (${1 + file.history.length})'),
          const SizedBox(height: 10),
          _HistoryList(published: file.published, history: file.history),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _numField(
    TextEditingController controller,
    String label, [
    String? helper,
  ]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminTextField(
          controller: controller,
          label: label,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          validator: (v) {
            final n = int.tryParse(v ?? '');
            if (n == null || n < 0) return 'Enter a whole number ≥ 0';
            return null;
          },
        ),
        if (helper != null) ...[
          const SizedBox(height: 3),
          Text(
            helper,
            style: const TextStyle(color: HEColors.textMuted, fontSize: 10.5),
          ),
        ],
      ],
    );
  }

  Widget _thresholdGrid() {
    final fields = <(TextEditingController, String)>[
      (_sameClub, 'Same club'),
      (_sameNation, 'Same nation'),
      (_sameLeague, 'Same league'),
      (_positionGroup, 'Position group'),
      (_clubAndPosClub, 'Club+position — club'),
      (_clubAndPosGroup, 'Club+position — group'),
      (_nationAndPosNation, 'Nation+position — nation'),
      (_nationAndPosGroup, 'Nation+position — group'),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: fields
          .map((f) => SizedBox(width: 190, child: _numField(f.$1, f.$2)))
          .toList(),
    );
  }
}

/// Parses a `_check()`-thrown `Exception('HTTP 400: <raw json body>')`
/// string back into the individual validation messages. The server's
/// HttpExceptionFilter (shared/http-exception.filter.ts) reshapes every
/// admin API error into `{ error: <string | string[]> }` — never NestJS's
/// default `{ message, statusCode, error }` shape — so this reads `error`,
/// not `message`. Falls back to the raw exception text if the body isn't
/// that expected shape, so a genuinely unexpected error is never hidden.
List<String> _extractErrorMessages(Object error) {
  final text = error.toString();
  const marker = 'HTTP 400: ';
  final idx = text.indexOf(marker);
  if (idx == -1) return [text];
  try {
    final decoded = jsonDecode(text.substring(idx + marker.length));
    final message = decoded is Map ? decoded['error'] : null;
    if (message is List) return message.map((e) => e.toString()).toList();
    if (message is String) return [message];
  } catch (_) {
    // fall through
  }
  return [text];
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.file});
  final AdminScoringConfigFile file;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: HEColors.gold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(HERadius.sm),
        border: Border.all(color: HEColors.gold.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: HEColors.gold,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Published: v${file.published.version}'
              '${file.published.publishedAt != null ? ' · ${file.published.publishedAt}' : ''}'
              '  ·  editing will become v${file.draft.version} when published.',
              style: const TextStyle(
                color: HEColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.saving,
    required this.publishing,
    required this.noteController,
    required this.onSaveDraft,
    required this.onPublish,
  });

  final bool saving;
  final bool publishing;
  final TextEditingController noteController;
  final VoidCallback onSaveDraft;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    final busy = saving || publishing;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HEColors.surfaceElevated,
        borderRadius: BorderRadius.circular(HERadius.md),
        border: Border.all(color: HEColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminTextField(
            controller: noteController,
            label: 'Publish note (optional)',
            hint: 'What changed and why',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : onSaveDraft,
                icon: saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 16),
                label: Text(saving ? 'Saving…' : 'Save Draft'),
              ),
              FilledButton.icon(
                onPressed: busy ? null : onPublish,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                icon: publishing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black54,
                        ),
                      )
                    : const Icon(Icons.publish_rounded, size: 16),
                label: Text(publishing ? 'Publishing…' : 'Publish'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.published, required this.history});
  final AdminScoringConfigVersion published;
  final List<AdminScoringConfigVersion> history;

  @override
  Widget build(BuildContext context) {
    final rows = [published, ...history.reversed];
    return Column(
      children: [
        for (int i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _HistoryRow(version: rows[i], isCurrent: i == 0),
        ],
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.version, required this.isCurrent});
  final AdminScoringConfigVersion version;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: HEColors.surface,
        borderRadius: BorderRadius.circular(HERadius.md),
        border: Border.all(
          color: isCurrent
              ? HEColors.gold.withValues(alpha: 0.5)
              : HEColors.divider,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isCurrent
                  ? HEColors.gold.withValues(alpha: 0.15)
                  : HEColors.surfaceElevated,
              borderRadius: BorderRadius.circular(HERadius.xs),
            ),
            child: Text(
              'v${version.version}',
              style: TextStyle(
                color: isCurrent ? HEColors.gold : HEColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  version.publishedAt ?? version.createdAt,
                  style: const TextStyle(
                    color: HEColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (version.note != null && version.note!.isNotEmpty)
                  Text(
                    version.note!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: HEColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          if (isCurrent)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Text(
                'CURRENT',
                style: TextStyle(
                  color: HEColors.gold,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
