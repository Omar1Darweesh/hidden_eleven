import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/theme.dart';
import 'package:hidden_eleven/features/admin/models/admin_models.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart';
import 'package:hidden_eleven/features/admin/widgets/admin_widgets.dart';
import 'package:hidden_eleven/features/game/models/chemistry_vars.dart';

/// Non-blocking save-time hint: warns (never blocks) if any of [texts]
/// contains a `{token}` that isn't a real ChemistryVars placeholder — a typo
/// like `{yellowPenaltyy}` would otherwise silently render as the "—" marker
/// to players with no indication why. Called AFTER the save has already
/// succeeded, so this can never prevent or roll back a save; it's purely
/// informational. Deduplicates across every text checked in one call.
void _warnUnknownPlaceholders(BuildContext context, List<String> texts) {
  final unknown = <String>{};
  for (final t in texts) {
    unknown.addAll(ChemistryVars.findUnknownPlaceholders(t));
  }
  if (unknown.isEmpty) return;
  final names = unknown.map((n) => '{$n}').join(', ');
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: HEColors.gold,
      content: Text(
        'Saved — but ${unknown.length > 1 ? 'these aren\'t' : 'this isn\'t'} '
        'a recognized chemistry placeholder: $names',
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

/// Instructions / Game Guide — admin-editable help content. Shown to players
/// as How to Play / Help pages, and as contextual in-game quick tips filtered
/// by the current draft phase (see AdminQuickTip.phase).
class GuideTab extends StatefulWidget {
  const GuideTab({super.key});

  @override
  State<GuideTab> createState() => _GuideTabState();
}

class _GuideTabState extends State<GuideTab> {
  int _subTab = 0;
  static const _subTabs = ['Pages', 'FAQ', 'Quick Tips', 'Contextual Help'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Instructions / Game Guide',
          style: TextStyle(
            color: HEColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Edit every piece of help content shown to players in-app: How to '
          'Play pages, FAQ, contextual quick tips, and the (?) dialogs on the '
          'game/tournament/result screens.',
          style: TextStyle(color: HEColors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 16),
        _SubTabBar(
          labels: _subTabs,
          selected: _subTab,
          onSelect: (i) => setState(() => _subTab = i),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: switch (_subTab) {
            0 => const _GuideSectionsView(),
            1 => const _FaqView(),
            2 => const _QuickTipsView(),
            _ => const _ContextHelpView(),
          },
        ),
      ],
    );
  }
}

// ── Sub-tab bar ────────────────────────────────────────────────────────────────

class _SubTabBar extends StatelessWidget {
  const _SubTabBar({
    required this.labels,
    required this.selected,
    required this.onSelect,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          _SubTabChip(
            label: labels[i],
            isSelected: selected == i,
            onTap: () => onSelect(i),
          ),
        ],
      ],
    );
  }
}

class _SubTabChip extends StatelessWidget {
  const _SubTabChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? HEColors.accent.withValues(alpha: 0.12)
              : HEColors.surface,
          borderRadius: BorderRadius.circular(HERadius.sm),
          border: Border.all(
            color: isSelected
                ? HEColors.accent.withValues(alpha: 0.55)
                : HEColors.inputBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? HEColors.accent : HEColors.textPrimary,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ── Reorder arrows (shared by all three sub-views) ────────────────────────────

class _ReorderArrows extends StatelessWidget {
  const _ReorderArrows({
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
  });
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
          color: HEColors.textSecondary,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 24),
          onPressed: canMoveUp ? onMoveUp : null,
        ),
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          color: HEColors.textSecondary,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 24),
          onPressed: canMoveDown ? onMoveDown : null,
        ),
      ],
    );
  }
}

// ── Pages (fixed guide sections) ──────────────────────────────────────────────

class _GuideSectionsView extends StatefulWidget {
  const _GuideSectionsView();

  @override
  State<_GuideSectionsView> createState() => _GuideSectionsViewState();
}

class _GuideSectionsViewState extends State<_GuideSectionsView> {
  List<AdminGuideSection>? _sections;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sections = await AdminApi.getGuideSections();
      if (mounted) {
        setState(() {
          _sections = sections;
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

  Future<void> _openForm(AdminGuideSection section) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _GuideSectionFormDialog(section: section),
    );
    if (result == true) _load();
  }

  // Swaps `order` with the neighbor rather than reassigning every row's
  // order — keeps every other row's order value untouched, so a failed
  // request only ever risks these two rows, never the whole list.
  Future<void> _move(AdminGuideSection section, int delta) async {
    final sections = _sections!;
    final idx = sections.indexWhere((s) => s.key == section.key);
    final swapIdx = idx + delta;
    if (swapIdx < 0 || swapIdx >= sections.length) return;
    final a = sections[idx];
    final b = sections[swapIdx];
    try {
      await AdminApi.updateGuideSection(a.key, {'order': b.order});
      await AdminApi.updateGuideSection(b.key, {'order': a.order});
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _toggleVisible(AdminGuideSection section) async {
    try {
      final updated = await AdminApi.updateGuideSection(section.key, {
        'visible': !section.visible,
      });
      if (mounted) {
        setState(() {
          final i = _sections!.indexWhere((s) => s.key == section.key);
          if (i != -1) _sections![i] = updated;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AdminErrorState(error: _error!, onRetry: _load);
    final sections = _sections ?? [];
    if (sections.isEmpty) {
      return const AdminEmptyState(label: 'No guide sections');
    }
    return ListView.separated(
      itemCount: sections.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _GuideSectionRow(
        section: sections[i],
        canMoveUp: i > 0,
        canMoveDown: i < sections.length - 1,
        onEdit: () => _openForm(sections[i]),
        onMoveUp: () => _move(sections[i], -1),
        onMoveDown: () => _move(sections[i], 1),
        onToggleVisible: () => _toggleVisible(sections[i]),
      ),
    );
  }
}

class _GuideSectionRow extends StatelessWidget {
  const _GuideSectionRow({
    required this.section,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onEdit,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onToggleVisible,
  });
  final AdminGuideSection section;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onEdit;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onToggleVisible;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: section.visible ? 1 : 0.55,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(HERadius.md),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 8, 8, 8),
          decoration: BoxDecoration(
            color: HEColors.surface,
            borderRadius: BorderRadius.circular(HERadius.md),
            border: Border.all(color: HEColors.divider),
          ),
          child: Row(
            children: [
              _ReorderArrows(
                canMoveUp: canMoveUp,
                canMoveDown: canMoveDown,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.title,
                      style: const TextStyle(
                        color: HEColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      section.body.isEmpty ? 'No content yet' : section.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: HEColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: section.visible,
                onChanged: (_) => onToggleVisible(),
                activeColor: HEColors.accent,
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: HEColors.textSecondary,
                tooltip: 'Edit',
                onPressed: onEdit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideSectionFormDialog extends StatefulWidget {
  const _GuideSectionFormDialog({required this.section});
  final AdminGuideSection section;

  @override
  State<_GuideSectionFormDialog> createState() =>
      _GuideSectionFormDialogState();
}

class _GuideSectionFormDialogState extends State<_GuideSectionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _body;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.section.title);
    _body = TextEditingController(text: widget.section.body);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await AdminApi.updateGuideSection(widget.section.key, {
        'title': _title.text.trim(),
        'body': _body.text.trim(),
      });
      if (mounted) {
        _warnUnknownPlaceholders(context, [_body.text]);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminFormScaffold(
      formKey: _formKey,
      title: 'Edit Page',
      saving: _saving,
      isEdit: true,
      onSave: _save,
      children: [
        AdminTextField(
          controller: _title,
          label: 'Title',
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: 14),
        AdminTextField(
          controller: _body,
          label: 'Body',
          hint:
              'Shown to players on the Help / How to Play page. Blank '
              'line = new paragraph.',
          maxLines: 10,
        ),
      ],
    );
  }
}

// ── FAQ ────────────────────────────────────────────────────────────────────────

class _FaqView extends StatefulWidget {
  const _FaqView();

  @override
  State<_FaqView> createState() => _FaqViewState();
}

class _FaqViewState extends State<_FaqView> {
  List<AdminFaqItem>? _items;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await AdminApi.getFaqItems();
      if (mounted) {
        setState(() {
          _items = items;
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

  Future<void> _openForm([AdminFaqItem? item]) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _FaqFormDialog(item: item, nextOrder: _items?.length ?? 0),
    );
    if (result == true) _load();
  }

  Future<void> _delete(AdminFaqItem item) async {
    final confirmed = await showDeleteConfirm(context, item.question);
    if (confirmed != true) return;
    try {
      await AdminApi.deleteFaqItem(item.id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _move(AdminFaqItem item, int delta) async {
    final items = _items!;
    final idx = items.indexWhere((i) => i.id == item.id);
    final swapIdx = idx + delta;
    if (swapIdx < 0 || swapIdx >= items.length) return;
    final a = items[idx];
    final b = items[swapIdx];
    try {
      await AdminApi.updateFaqItem(a.id, {'order': b.order});
      await AdminApi.updateFaqItem(b.id, {'order': a.order});
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _toggleVisible(AdminFaqItem item) async {
    try {
      final updated = await AdminApi.updateFaqItem(item.id, {
        'visible': !item.visible,
      });
      if (mounted) {
        setState(() {
          final i = _items!.indexWhere((x) => x.id == item.id);
          if (i != -1) _items![i] = updated;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () => _openForm(),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Add FAQ'),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AdminErrorState(error: _error!, onRetry: _load);
    final items = _items ?? [];
    if (items.isEmpty) return const AdminEmptyState(label: 'No FAQ items yet');
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _FaqRow(
        item: items[i],
        canMoveUp: i > 0,
        canMoveDown: i < items.length - 1,
        onEdit: () => _openForm(items[i]),
        onDelete: () => _delete(items[i]),
        onMoveUp: () => _move(items[i], -1),
        onMoveDown: () => _move(items[i], 1),
        onToggleVisible: () => _toggleVisible(items[i]),
      ),
    );
  }
}

class _FaqRow extends StatelessWidget {
  const _FaqRow({
    required this.item,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onEdit,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onToggleVisible,
  });
  final AdminFaqItem item;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onToggleVisible;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: item.visible ? 1 : 0.55,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(HERadius.md),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 8, 4, 8),
          decoration: BoxDecoration(
            color: HEColors.surface,
            borderRadius: BorderRadius.circular(HERadius.md),
            border: Border.all(color: HEColors.divider),
          ),
          child: Row(
            children: [
              _ReorderArrows(
                canMoveUp: canMoveUp,
                canMoveDown: canMoveDown,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.question,
                      style: const TextStyle(
                        color: HEColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      item.answer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: HEColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: item.visible,
                onChanged: (_) => onToggleVisible(),
                activeColor: HEColors.accent,
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: HEColors.textSecondary,
                tooltip: 'Edit',
                onPressed: onEdit,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                color: HEColors.error,
                tooltip: 'Delete',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FaqFormDialog extends StatefulWidget {
  const _FaqFormDialog({this.item, required this.nextOrder});
  final AdminFaqItem? item;
  final int nextOrder;

  @override
  State<_FaqFormDialog> createState() => _FaqFormDialogState();
}

class _FaqFormDialogState extends State<_FaqFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _question;
  late final TextEditingController _answer;
  bool _saving = false;
  bool get _isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    _question = TextEditingController(text: widget.item?.question ?? '');
    _answer = TextEditingController(text: widget.item?.answer ?? '');
  }

  @override
  void dispose() {
    _question.dispose();
    _answer.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final dto = {
        'question': _question.text.trim(),
        'answer': _answer.text.trim(),
      };
      if (_isEdit) {
        await AdminApi.updateFaqItem(widget.item!.id, dto);
      } else {
        await AdminApi.createFaqItem({
          ...dto,
          'order': widget.nextOrder,
          'visible': true,
        });
      }
      if (mounted) {
        _warnUnknownPlaceholders(context, [_question.text, _answer.text]);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminFormScaffold(
      formKey: _formKey,
      title: _isEdit ? 'Edit FAQ' : 'Add FAQ',
      saving: _saving,
      isEdit: _isEdit,
      onSave: _save,
      children: [
        AdminTextField(
          controller: _question,
          label: 'Question',
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: 14),
        AdminTextField(
          controller: _answer,
          label: 'Answer',
          maxLines: 5,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
      ],
    );
  }
}

// ── Quick tips ───────────────────────────────────────────────────────────────

/// Phase keys reuse GameTurn.phase (game_state.dart) exactly, so the player
/// app can filter tips by the phase currently on screen. Null = general tip.
const _phaseOptions = <(String?, String)>[
  (null, 'General'),
  ('selecting_position', 'Selecting Position'),
  ('selecting_card', 'Selecting Card'),
  ('hidden_pick', 'Hidden Pick'),
  ('subs', 'Subs'),
];

String _phaseLabel(String? phase) => _phaseOptions
    .firstWhere((p) => p.$1 == phase, orElse: () => _phaseOptions.first)
    .$2;

class _QuickTipsView extends StatefulWidget {
  const _QuickTipsView();

  @override
  State<_QuickTipsView> createState() => _QuickTipsViewState();
}

class _QuickTipsViewState extends State<_QuickTipsView> {
  List<AdminQuickTip>? _tips;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tips = await AdminApi.getQuickTips();
      if (mounted) {
        setState(() {
          _tips = tips;
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

  Future<void> _openForm([AdminQuickTip? tip]) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _QuickTipFormDialog(tip: tip, nextOrder: _tips?.length ?? 0),
    );
    if (result == true) _load();
  }

  Future<void> _delete(AdminQuickTip tip) async {
    final confirmed = await showDeleteConfirm(context, tip.text);
    if (confirmed != true) return;
    try {
      await AdminApi.deleteQuickTip(tip.id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _move(AdminQuickTip tip, int delta) async {
    final tips = _tips!;
    final idx = tips.indexWhere((t) => t.id == tip.id);
    final swapIdx = idx + delta;
    if (swapIdx < 0 || swapIdx >= tips.length) return;
    final a = tips[idx];
    final b = tips[swapIdx];
    try {
      await AdminApi.updateQuickTip(a.id, {'order': b.order});
      await AdminApi.updateQuickTip(b.id, {'order': a.order});
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _toggleVisible(AdminQuickTip tip) async {
    try {
      final updated = await AdminApi.updateQuickTip(tip.id, {
        'visible': !tip.visible,
      });
      if (mounted) {
        setState(() {
          final i = _tips!.indexWhere((t) => t.id == tip.id);
          if (i != -1) _tips![i] = updated;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () => _openForm(),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Add Tip'),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AdminErrorState(error: _error!, onRetry: _load);
    final tips = _tips ?? [];
    if (tips.isEmpty) return const AdminEmptyState(label: 'No quick tips yet');
    return ListView.separated(
      itemCount: tips.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _QuickTipRow(
        tip: tips[i],
        canMoveUp: i > 0,
        canMoveDown: i < tips.length - 1,
        onEdit: () => _openForm(tips[i]),
        onDelete: () => _delete(tips[i]),
        onMoveUp: () => _move(tips[i], -1),
        onMoveDown: () => _move(tips[i], 1),
        onToggleVisible: () => _toggleVisible(tips[i]),
      ),
    );
  }
}

class _QuickTipRow extends StatelessWidget {
  const _QuickTipRow({
    required this.tip,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onEdit,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onToggleVisible,
  });
  final AdminQuickTip tip;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onToggleVisible;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: tip.visible ? 1 : 0.55,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(HERadius.md),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 8, 4, 8),
          decoration: BoxDecoration(
            color: HEColors.surface,
            borderRadius: BorderRadius.circular(HERadius.md),
            border: Border.all(color: HEColors.divider),
          ),
          child: Row(
            children: [
              _ReorderArrows(
                canMoveUp: canMoveUp,
                canMoveDown: canMoveDown,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tip.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: HEColors.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: HEColors.accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _phaseLabel(tip.phase),
                        style: const TextStyle(
                          color: HEColors.accent,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: tip.visible,
                onChanged: (_) => onToggleVisible(),
                activeColor: HEColors.accent,
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: HEColors.textSecondary,
                tooltip: 'Edit',
                onPressed: onEdit,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                color: HEColors.error,
                tooltip: 'Delete',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickTipFormDialog extends StatefulWidget {
  const _QuickTipFormDialog({this.tip, required this.nextOrder});
  final AdminQuickTip? tip;
  final int nextOrder;

  @override
  State<_QuickTipFormDialog> createState() => _QuickTipFormDialogState();
}

class _QuickTipFormDialogState extends State<_QuickTipFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _text;
  String? _phase;
  bool _saving = false;
  bool get _isEdit => widget.tip != null;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.tip?.text ?? '');
    _phase = widget.tip?.phase;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final dto = {'text': _text.text.trim(), 'phase': _phase};
      if (_isEdit) {
        await AdminApi.updateQuickTip(widget.tip!.id, dto);
      } else {
        await AdminApi.createQuickTip({
          ...dto,
          'order': widget.nextOrder,
          'visible': true,
        });
      }
      if (mounted) {
        _warnUnknownPlaceholders(context, [_text.text]);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminFormScaffold(
      formKey: _formKey,
      title: _isEdit ? 'Edit Tip' : 'Add Tip',
      saving: _saving,
      isEdit: _isEdit,
      onSave: _save,
      children: [
        AdminTextField(
          controller: _text,
          label: 'Tip text',
          hint: 'A short, single-sentence tip.',
          maxLines: 3,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: 16),
        const AdminSectionHeader('Show during phase'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _phaseOptions.map((opt) {
            final (phase, label) = opt;
            final isSelected = _phase == phase;
            return GestureDetector(
              onTap: () => setState(() => _phase = phase),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? HEColors.accent.withValues(alpha: 0.12)
                      : HEColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(HERadius.sm),
                  border: Border.all(
                    color: isSelected
                        ? HEColors.accent.withValues(alpha: 0.55)
                        : HEColors.inputBorder,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? HEColors.accent : HEColors.textPrimary,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Contextual Help (the in-app "?" dialogs) ──────────────────────────────────
// One entry per real, live "?" button already in the app (Draft & Scoring on
// the game screen, Abilities, Live Match Details, Result Page, Tournament).
// Fixed keys, PUT-only — no create/delete, same shape as Pages — but each
// holds a nested list of sections/entries matching what those dialogs
// actually render (HelpSection/HelpEntry client-side).

class _ContextHelpView extends StatefulWidget {
  const _ContextHelpView();

  @override
  State<_ContextHelpView> createState() => _ContextHelpViewState();
}

class _ContextHelpViewState extends State<_ContextHelpView> {
  List<AdminContextHelp>? _items;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await AdminApi.getContextHelp();
      if (mounted) {
        setState(() {
          _items = items;
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

  Future<void> _openForm(AdminContextHelp item) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _ContextHelpFormDialog(item: item),
    );
    if (result == true) _load();
  }

  Future<void> _toggleVisible(AdminContextHelp item) async {
    try {
      final updated = await AdminApi.updateContextHelp(item.key, {
        'visible': !item.visible,
      });
      if (mounted) {
        setState(() {
          final i = _items!.indexWhere((c) => c.key == item.key);
          if (i != -1) _items![i] = updated;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AdminErrorState(error: _error!, onRetry: _load);
    final items = _items ?? [];
    if (items.isEmpty) {
      return const AdminEmptyState(label: 'No contextual help entries');
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _ContextHelpRow(
        item: items[i],
        onEdit: () => _openForm(items[i]),
        onToggleVisible: () => _toggleVisible(items[i]),
      ),
    );
  }
}

class _ContextHelpRow extends StatelessWidget {
  const _ContextHelpRow({
    required this.item,
    required this.onEdit,
    required this.onToggleVisible,
  });
  final AdminContextHelp item;
  final VoidCallback onEdit;
  final VoidCallback onToggleVisible;

  @override
  Widget build(BuildContext context) {
    final entryCount = item.sections.fold<int>(
      0,
      (sum, s) => sum + s.entries.length,
    );
    return Opacity(
      opacity: item.visible ? 1 : 0.55,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(HERadius.md),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          decoration: BoxDecoration(
            color: HEColors.surface,
            borderRadius: BorderRadius.circular(HERadius.md),
            border: Border.all(color: HEColors.divider),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        color: HEColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${item.sections.length} section'
                      '${item.sections.length == 1 ? '' : 's'} · '
                      '$entryCount entr${entryCount == 1 ? 'y' : 'ies'}',
                      style: const TextStyle(
                        color: HEColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: item.visible,
                onChanged: (_) => onToggleVisible(),
                activeColor: HEColors.accent,
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: HEColors.textSecondary,
                tooltip: 'Edit',
                onPressed: onEdit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Mutable local editing model — built from AdminContextHelpSection/Entry on
// open, edited freely, serialized back to JSON on save. Keeping this
// separate from the immutable admin model avoids fighting Flutter's
// TextEditingController lifecycle against @immutable copyWith churn.
class _EditableEntry {
  _EditableEntry({String label = '', String body = ''})
    : labelCtrl = TextEditingController(text: label),
      bodyCtrl = TextEditingController(text: body);
  final TextEditingController labelCtrl;
  final TextEditingController bodyCtrl;
}

class _EditableSection {
  _EditableSection({String heading = '', List<_EditableEntry>? entries})
    : headingCtrl = TextEditingController(text: heading),
      entries = entries ?? [];
  final TextEditingController headingCtrl;
  final List<_EditableEntry> entries;
}

class _ContextHelpFormDialog extends StatefulWidget {
  const _ContextHelpFormDialog({required this.item});
  final AdminContextHelp item;

  @override
  State<_ContextHelpFormDialog> createState() => _ContextHelpFormDialogState();
}

class _ContextHelpFormDialogState extends State<_ContextHelpFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late List<_EditableSection> _sections;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.item.title);
    _sections = widget.item.sections
        .map(
          (s) => _EditableSection(
            heading: s.heading,
            entries: s.entries
                .map((e) => _EditableEntry(label: e.label, body: e.body))
                .toList(),
          ),
        )
        .toList();
  }

  @override
  void dispose() {
    _title.dispose();
    for (final s in _sections) {
      s.headingCtrl.dispose();
      for (final e in s.entries) {
        e.labelCtrl.dispose();
        e.bodyCtrl.dispose();
      }
    }
    super.dispose();
  }

  void _addSection() => setState(() => _sections.add(_EditableSection()));

  void _removeSection(int i) => setState(() {
    final s = _sections.removeAt(i);
    s.headingCtrl.dispose();
    for (final e in s.entries) {
      e.labelCtrl.dispose();
      e.bodyCtrl.dispose();
    }
  });

  void _addEntry(_EditableSection s) =>
      setState(() => s.entries.add(_EditableEntry()));

  void _removeEntry(_EditableSection s, int i) => setState(() {
    final e = s.entries.removeAt(i);
    e.labelCtrl.dispose();
    e.bodyCtrl.dispose();
  });

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final dto = {
        'title': _title.text.trim(),
        'sections': _sections
            .map(
              (s) => {
                'heading': s.headingCtrl.text.trim(),
                'entries': s.entries
                    .map(
                      (e) => {
                        'label': e.labelCtrl.text.trim(),
                        'body': e.bodyCtrl.text.trim(),
                      },
                    )
                    .toList(),
              },
            )
            .toList(),
      };
      await AdminApi.updateContextHelp(widget.item.key, dto);
      if (mounted) {
        _warnUnknownPlaceholders(context, [
          for (final s in _sections) ...[
            s.headingCtrl.text,
            for (final e in s.entries) ...[e.labelCtrl.text, e.bodyCtrl.text],
          ],
        ]);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminFormScaffold(
      formKey: _formKey,
      title: 'Edit "${widget.item.title}"',
      saving: _saving,
      isEdit: true,
      onSave: _save,
      maxWidth: 560,
      children: [
        AdminTextField(
          controller: _title,
          label: 'Dialog title',
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: 18),
        for (var si = 0; si < _sections.length; si++) ...[
          _SectionEditor(
            section: _sections[si],
            onRemoveSection: () => _removeSection(si),
            onAddEntry: () => _addEntry(_sections[si]),
            onRemoveEntry: (ei) => _removeEntry(_sections[si], ei),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: _addSection,
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('Add Section'),
        ),
      ],
    );
  }
}

class _SectionEditor extends StatelessWidget {
  const _SectionEditor({
    required this.section,
    required this.onRemoveSection,
    required this.onAddEntry,
    required this.onRemoveEntry,
  });
  final _EditableSection section;
  final VoidCallback onRemoveSection;
  final VoidCallback onAddEntry;
  final ValueChanged<int> onRemoveEntry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HEColors.surfaceElevated,
        borderRadius: BorderRadius.circular(HERadius.sm),
        border: Border.all(color: HEColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: AdminTextField(
                  controller: section.headingCtrl,
                  label: 'Section heading',
                  hint: 'e.g. HOW IT WORKS',
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                color: HEColors.error,
                tooltip: 'Remove section',
                onPressed: onRemoveSection,
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var ei = 0; ei < section.entries.length; ei++) ...[
            _EntryEditor(
              entry: section.entries[ei],
              onRemove: () => onRemoveEntry(ei),
            ),
            const SizedBox(height: 8),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onAddEntry,
              icon: const Icon(Icons.add_rounded, size: 14),
              label: const Text('Add Entry'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryEditor extends StatelessWidget {
  const _EntryEditor({required this.entry, required this.onRemove});
  final _EditableEntry entry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: HEColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: HEColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                AdminTextField(controller: entry.labelCtrl, label: 'Label'),
                const SizedBox(height: 8),
                AdminTextField(
                  controller: entry.bodyCtrl,
                  label: 'Body',
                  maxLines: 3,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 16),
            color: HEColors.textMuted,
            tooltip: 'Remove entry',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
