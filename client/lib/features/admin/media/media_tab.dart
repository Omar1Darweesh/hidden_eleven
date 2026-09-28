import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/theme.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart';
import 'package:hidden_eleven/features/admin/widgets/admin_widgets.dart';

class MediaTab extends StatefulWidget {
  const MediaTab({super.key});

  @override
  State<MediaTab> createState() => _MediaTabState();
}

class _MediaTabState extends State<MediaTab> {
  Map<String, List<String>>? _tree;
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
      final tree = await AdminApi.getAssets();
      if (mounted)
        setState(() {
          _tree = tree;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ConventionCard(),
        const SizedBox(height: 20),
        const AdminSectionHeader('Asset Files on Server'),
        const SizedBox(height: 12),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AdminErrorState(error: _error!, onRetry: _load);
    final tree = _tree ?? {};
    if (tree.isEmpty) {
      return const AdminEmptyState(label: 'No asset folders found');
    }
    return ListView(
      children: tree.entries
          .map((e) => _FolderTile(folder: e.key, files: e.value))
          .toList(),
    );
  }
}

// ── Naming convention card ─────────────────────────────────────────────────────

class _ConventionCard extends StatelessWidget {
  static const _rows = [
    ('players/photos/', 'player-name.png', 'erling-haaland.png'),
    ('clubs/logos/', 'club-name.png', 'manchester-city.png'),
    ('nations/flags/', 'nation-name.png', 'brazil.png'),
    ('leagues/logos/', 'league-name.png', 'premier-league.png'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HEColors.surfaceElevated,
        borderRadius: BorderRadius.circular(HERadius.md),
        border: Border.all(color: HEColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.folder_outlined, color: HEColors.accent, size: 18),
              SizedBox(width: 8),
              Text(
                'Asset Naming Convention',
                style: TextStyle(
                  color: HEColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Lowercase only · hyphen-separated · no spaces · no special characters',
            style: TextStyle(color: HEColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(2),
              2: FlexColumnWidth(2),
            },
            children: [_headerRow(), ..._rows.map(_dataRow)],
          ),
        ],
      ),
    );
  }

  TableRow _headerRow() => TableRow(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: HEColors.divider)),
    ),
    children: [
      _cell('Folder', header: true),
      _cell('Pattern', header: true),
      _cell('Example', header: true),
    ],
  );

  TableRow _dataRow((String, String, String) row) => TableRow(
    children: [
      _cell(row.$1, mono: true),
      _cell(row.$2, mono: true),
      _cell(row.$3, mono: true, accent: true),
    ],
  );

  Widget _cell(
    String text, {
    bool header = false,
    bool mono = false,
    bool accent = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Text(
        text,
        style: TextStyle(
          color: accent
              ? HEColors.accent
              : header
              ? HEColors.textSecondary
              : HEColors.textPrimary,
          fontSize: 11,
          fontWeight: header ? FontWeight.w700 : FontWeight.w400,
          fontFamily: mono ? 'monospace' : null,
          letterSpacing: header ? 0.8 : 0,
        ),
      ),
    );
  }
}

// ── Folder tile with file list ─────────────────────────────────────────────────

class _FolderTile extends StatefulWidget {
  const _FolderTile({required this.folder, required this.files});
  final String folder;
  final List<String> files;

  @override
  State<_FolderTile> createState() => _FolderTileState();
}

class _FolderTileState extends State<_FolderTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: HEColors.surfaceElevated,
        borderRadius: BorderRadius.circular(HERadius.sm),
        border: Border.all(color: HEColors.divider),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(HERadius.sm),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? Icons.folder_open_outlined
                        : Icons.folder_outlined,
                    color: HEColors.accent,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.folder,
                    style: const TextStyle(
                      color: HEColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: HEColors.accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(HERadius.xs),
                    ),
                    child: Text(
                      '${widget.files.length}',
                      style: const TextStyle(
                        color: HEColors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: HEColors.textSecondary,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            if (widget.files.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No files',
                  style: TextStyle(color: HEColors.textMuted, fontSize: 12),
                ),
              )
            else
              ...widget.files.map(
                (f) => _FileRow(folder: widget.folder, filename: f),
              ),
          ],
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.folder, required this.filename});
  final String folder;
  final String filename;

  @override
  Widget build(BuildContext context) {
    final url = AdminApi.assetUrl('$folder$filename');
    final isImage =
        filename.endsWith('.png') ||
        filename.endsWith('.jpg') ||
        filename.endsWith('.jpeg') ||
        filename.endsWith('.webp') ||
        filename.endsWith('.svg');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          if (isImage)
            AdminImagePreview(url: url, size: 28)
          else
            const Icon(
              Icons.insert_drive_file_outlined,
              color: HEColors.textMuted,
              size: 28,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              filename,
              style: const TextStyle(
                color: HEColors.textSecondary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
