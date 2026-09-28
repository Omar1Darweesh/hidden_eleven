import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hidden_eleven/app/theme.dart';
import 'package:hidden_eleven/features/admin/models/admin_models.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart';
import 'package:hidden_eleven/features/admin/widgets/admin_widgets.dart';

/// Admin-configurable tournament AWARD point values (Track A — see the
/// "Tournament Awards admin configurability" implementation plan). These are
/// the points paid out for tournament placement/stats (champion, runner-up,
/// top scorer, most assists, best rating) — distinct from chemistry/draft
/// scoring, which lives in the Scoring tab. Mirrors ScoringTab's draft/
/// publish/history UX closely; no simulation-tuning controls and no new
/// award categories are editable here — only the 5 existing point values.
class TournamentAwardsTab extends StatefulWidget {
  const TournamentAwardsTab({super.key});

  @override
  State<TournamentAwardsTab> createState() => _TournamentAwardsTabState();
}

class _TournamentAwardsTabState extends State<TournamentAwardsTab> {
  AdminTournamentAwardsConfigFile? _file;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _publishing = false;
  bool _controllersReady = false;

  late TextEditingController _championPoints;
  late TextEditingController _runnerUpPoints;
  late TextEditingController _topScorerBonus;
  late TextEditingController _mostAssistsBonus;
  late TextEditingController _highestRatingBonus;
  final _noteController = TextEditingController();

  List<TextEditingController> get _allControllers => [
    _championPoints,
    _runnerUpPoints,
    _topScorerBonus,
    _mostAssistsBonus,
    _highestRatingBonus,
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

  void _initControllers(AdminTournamentAwardsConfigValues v) {
    if (_controllersReady) {
      for (final c in _allControllers) {
        c.dispose();
      }
    }
    _championPoints = TextEditingController(text: '${v.championPoints}');
    _runnerUpPoints = TextEditingController(text: '${v.runnerUpPoints}');
    _topScorerBonus = TextEditingController(text: '${v.topScorerBonus}');
    _mostAssistsBonus = TextEditingController(text: '${v.mostAssistsBonus}');
    _highestRatingBonus = TextEditingController(
      text: '${v.highestRatingBonus}',
    );
    _controllersReady = true;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final file = await AdminApi.getTournamentAwardsConfig();
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
    'championPoints': int.tryParse(_championPoints.text.trim()) ?? 0,
    'runnerUpPoints': int.tryParse(_runnerUpPoints.text.trim()) ?? 0,
    'topScorerBonus': int.tryParse(_topScorerBonus.text.trim()) ?? 0,
    'mostAssistsBonus': int.tryParse(_mostAssistsBonus.text.trim()) ?? 0,
    'highestRatingBonus': int.tryParse(_highestRatingBonus.text.trim()) ?? 0,
  };

  Future<void> _saveDraft() async {
    setState(() => _saving = true);
    try {
      await AdminApi.saveTournamentAwardsConfigDraft(_buildValuesJson());
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
      await AdminApi.saveTournamentAwardsConfigDraft(_buildValuesJson());
      final note = _noteController.text.trim();
      await AdminApi.publishTournamentAwardsConfig(
        note: note.isEmpty ? null : note,
      );
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
          'Tournament Awards',
          style: TextStyle(
            color: HEColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Points paid out for knockout-tournament placement and stats — '
          'champion, runner-up, top scorer, most assists, best rating. This '
          'is tournament AWARD points, not chemistry/draft scoring (see the '
          'Scoring tab for that).',
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
          const SizedBox(height: 12),
          _FutureTournamentsNote(),
          const SizedBox(height: 20),

          const AdminSectionHeader('Placement'),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _numField(_championPoints, 'Champion')),
              const SizedBox(width: 12),
              Expanded(child: _numField(_runnerUpPoints, 'Runner-up')),
            ],
          ),

          const SizedBox(height: 20),
          const AdminSectionHeader('Stat Awards'),
          const SizedBox(height: 4),
          const Text(
            'A tied category is SHARED: its bonus is split equally among '
            'every tied winner, rounded up.',
            style: TextStyle(color: HEColors.textMuted, fontSize: 11.5),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _numField(_topScorerBonus, 'Top scorer')),
              const SizedBox(width: 12),
              Expanded(child: _numField(_mostAssistsBonus, 'Most assists')),
              const SizedBox(width: 12),
              Expanded(child: _numField(_highestRatingBonus, 'Best rating')),
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

  Widget _numField(TextEditingController controller, String label) {
    return AdminTextField(
      controller: controller,
      label: label,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validator: (v) {
        final n = int.tryParse(v ?? '');
        if (n == null || n < 0) return 'Enter a whole number ≥ 0';
        return null;
      },
    );
  }
}

/// Parses a `_check()`-thrown `Exception('HTTP 400: <raw json body>')`
/// string back into the individual validation messages — identical parsing
/// to ScoringTab's own copy (each admin tab keeps its own small copy since
/// this is file-private, not a shared util).
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

class _FutureTournamentsNote extends StatelessWidget {
  const _FutureTournamentsNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: HEColors.surfaceElevated,
        borderRadius: BorderRadius.circular(HERadius.sm),
        border: Border.all(color: HEColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.schedule_rounded,
            color: HEColors.textMuted,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Changes apply only to tournaments started after publishing — '
              'a tournament already in progress keeps whatever was published '
              'when it began.',
              style: const TextStyle(color: HEColors.textMuted, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.file});
  final AdminTournamentAwardsConfigFile file;

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
  final AdminTournamentAwardsConfigVersion published;
  final List<AdminTournamentAwardsConfigVersion> history;

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
  final AdminTournamentAwardsConfigVersion version;
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
