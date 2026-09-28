import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hidden_eleven/app/theme.dart';
import 'package:hidden_eleven/features/admin/models/admin_models.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart';
import 'package:hidden_eleven/features/game/models/chemistry_vars.dart';

/// Player-facing Help / How to Play page — reads the exact same
/// admin-editable content the Instructions tab manages (GuideTab), so
/// there's a single source of truth: an admin edits one place, players see
/// it here immediately, no client rebuild/deploy needed.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  List<AdminGuideSection>? _sections;
  List<AdminFaqItem>? _faq;
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
      // Both admin-authored, unauthenticated GETs — same pattern
      // host_room_screen.dart already uses for Formations/Leagues.
      final results = await Future.wait([
        AdminApi.getGuideSections(),
        AdminApi.getFaqItems(),
      ]);
      if (!mounted) return;
      setState(() {
        _sections =
            (results[0] as List<AdminGuideSection>)
                .where((s) => s.visible)
                .toList()
              ..sort((a, b) => a.order.compareTo(b.order));
        _faq =
            (results[1] as List<AdminFaqItem>).where((f) => f.visible).toList()
              ..sort((a, b) => a.order.compareTo(b.order));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HEColors.background,
      appBar: AppBar(
        backgroundColor: HEColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text('How to Play'),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: HEColors.accent),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: HEColors.error,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(
                color: HEColors.textSecondary,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final sections = _sections ?? [];
    final faq = _faq ?? [];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final section in sections) ...[
          _SectionBlock(section: section),
          const SizedBox(height: 20),
        ],
        if (faq.isNotEmpty) ...[
          const Text(
            'FAQ',
            style: TextStyle(
              color: HEColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          for (final item in faq) _FaqTile(item: item),
        ],
      ],
    );
  }
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({required this.section});
  final AdminGuideSection section;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(HESpacing.lg),
      decoration: BoxDecoration(
        color: HEColors.surfaceElevated,
        borderRadius: BorderRadius.circular(HERadius.lg),
        border: Border.all(color: HEColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: const TextStyle(
              color: HEColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          // Blank-line-separated paragraphs — admin content is plain text,
          // no markdown parser needed on the client.
          for (final para in section.body.split('\n\n'))
            if (para.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  ChemistryVars.resolve(para.trim()),
                  style: const TextStyle(
                    color: HEColors.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _FaqTile extends StatefulWidget {
  const _FaqTile({required this.item});
  final AdminFaqItem item;

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: HEColors.surface,
        borderRadius: BorderRadius.circular(HERadius.md),
        border: Border.all(color: HEColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(HERadius.md),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.item.question,
                      style: const TextStyle(
                        color: HEColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: HEColors.textSecondary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(
                ChemistryVars.resolve(widget.item.answer),
                style: const TextStyle(
                  color: HEColors.textSecondary,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
