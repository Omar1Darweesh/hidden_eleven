import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/theme.dart';
import 'package:hidden_eleven/features/admin/models/admin_models.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart';
import 'package:hidden_eleven/features/admin/widgets/admin_widgets.dart';

class LeaguesTab extends StatefulWidget {
  const LeaguesTab({super.key});

  @override
  State<LeaguesTab> createState() => _LeaguesTabState();
}

class _LeaguesTabState extends State<LeaguesTab> {
  List<AdminLeague>? _leagues;
  String? _error;
  bool _loading = true;
  String _query = '';

  List<AdminLeague> get _filtered {
    var list = _leagues ?? [];
    final q = _query.toLowerCase().trim();
    if (q.isNotEmpty) {
      list = list.where((l) => l.name.toLowerCase().contains(q)).toList();
    }
    return list;
  }

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
      final leagues = await AdminApi.getLeagues();
      if (mounted)
        setState(() {
          _leagues = leagues;
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

  Future<void> _openForm([AdminLeague? league]) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _LeagueFormDialog(league: league),
    );
    if (result == true) _load();
  }

  Future<void> _delete(AdminLeague league) async {
    final confirmed = await showDeleteConfirm(context, league.name);
    if (confirmed != true) return;
    try {
      await AdminApi.deleteLeague(league.slug);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _toggleActive(AdminLeague league) async {
    try {
      final updated = await AdminApi.updateLeague(league.slug, {
        'active': !league.active,
      });
      if (mounted) {
        setState(() {
          final i = _leagues!.indexWhere((l) => l.slug == league.slug);
          if (i != -1) _leagues![i] = updated;
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
    final filtered = _filtered;
    final total = (_leagues ?? []).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: (q) => setState(() => _query = q),
                style: const TextStyle(
                  color: HEColors.textPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Search leagues…',
                  hintStyle: const TextStyle(
                    color: HEColors.textMuted,
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: HEColors.textSecondary,
                    size: 18,
                  ),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: HEColors.textSecondary,
                            size: 16,
                          ),
                          onPressed: () => setState(() => _query = ''),
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (_leagues != null)
              Text(
                '${filtered.length} of $total',
                style: const TextStyle(color: HEColors.textMuted, fontSize: 12),
              ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: () => _openForm(),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add League'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(child: _body(filtered)),
      ],
    );
  }

  Widget _body(List<AdminLeague> leagues) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AdminErrorState(error: _error!, onRetry: _load);
    if (leagues.isEmpty) {
      return AdminEmptyState(
        label: _query.isNotEmpty
            ? 'No leagues match "$_query"'
            : 'No leagues yet',
      );
    }
    return ListView.separated(
      itemCount: leagues.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, i) => _LeagueRow(
        league: leagues[i],
        onEdit: () => _openForm(leagues[i]),
        onDelete: () => _delete(leagues[i]),
        onToggleActive: () => _toggleActive(leagues[i]),
      ),
    );
  }
}

class _LeagueRow extends StatelessWidget {
  const _LeagueRow({
    required this.league,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
  });
  final AdminLeague league;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final active = league.active;
    return InkWell(
      onTap: onEdit,
      child: Opacity(
        opacity: active ? 1 : 0.5,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              AdminImagePreview(
                url: AdminApi.resolveAssetUrl(league.logoUrl),
                size: 36,
                placeholder: Icons.sports_soccer_rounded,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  league.name,
                  style: const TextStyle(
                    color: HEColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Allowed-in-rooms toggle.
              Text(
                active ? 'Allowed' : 'Off',
                style: TextStyle(
                  color: active ? HEColors.accent : HEColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Switch(
                value: active,
                onChanged: (_) => onToggleActive(),
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

class _LeagueFormDialog extends StatefulWidget {
  const _LeagueFormDialog({this.league});
  final AdminLeague? league;

  @override
  State<_LeagueFormDialog> createState() => _LeagueFormDialogState();
}

class _LeagueFormDialogState extends State<_LeagueFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;

  late final TextEditingController _logoUrlCtrl;
  Uint8List? _pendingLogoBytes;
  String? _pendingLogoFilename;
  UploadStatus _logoUploadStatus = UploadStatus.idle;
  String? _logoUploadError;
  String? _savedLogoPath;

  bool _saving = false;
  bool get _isEdit => widget.league != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.league?.name ?? '');
    _savedLogoPath = widget.league?.logoUrl;
    _logoUrlCtrl = TextEditingController(
      text: AdminApi.resolveAssetUrl(widget.league?.logoUrl),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _logoUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final manualLogoUrl = _logoUrlCtrl.text.trim();
      final originalLogoUrl = AdminApi.resolveAssetUrl(
        widget.league?.logoUrl ?? '',
      );

      final dto = {
        'name': _name.text.trim(),
        if (manualLogoUrl.isNotEmpty &&
            manualLogoUrl != originalLogoUrl &&
            _pendingLogoBytes == null)
          'logoUrl': manualLogoUrl,
      };

      final AdminLeague saved;
      if (_isEdit) {
        saved = await AdminApi.updateLeague(widget.league!.slug, dto);
      } else {
        saved = await AdminApi.createLeague(dto);
      }
      if (_pendingLogoBytes != null) {
        setState(() => _logoUploadStatus = UploadStatus.uploading);
        try {
          final updated = await AdminApi.uploadLeagueLogo(
            saved.slug,
            _pendingLogoBytes!,
            _pendingLogoFilename!,
          );
          if (mounted) {
            setState(() {
              _logoUploadStatus = UploadStatus.success;
              _savedLogoPath = updated.logoUrl;
              _logoUrlCtrl.text = AdminApi.resolveAssetUrl(updated.logoUrl);
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _saving = false;
              _logoUploadStatus = UploadStatus.error;
              _logoUploadError = e.toString();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('League saved, but logo upload failed: $e'),
              ),
            );
          }
          return;
        }
      }
      if (mounted) Navigator.of(context).pop(true);
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
      title: _isEdit ? 'Edit League' : 'Add League',
      saving: _saving,
      isEdit: _isEdit,
      onSave: _save,
      children: [
        AdminTextField(
          controller: _name,
          label: 'Name',
          hint: 'e.g. Premier League',
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: 20),
        const AdminSectionHeader('League Logo'),
        const SizedBox(height: 10),
        AdminImageUploader(
          currentUrl: AdminApi.resolveAssetUrl(widget.league?.logoUrl),
          placeholder: Icons.sports_soccer_rounded,
          status: _logoUploadStatus,
          errorMessage: _logoUploadError,
          savedPath: _savedLogoPath,
          urlController: _logoUrlCtrl,
          onFilePicked: (bytes, name) {
            setState(() {
              _pendingLogoBytes = bytes;
              _pendingLogoFilename = name;
              _logoUploadStatus = UploadStatus.idle;
              _logoUploadError = null;
            });
          },
        ),
      ],
    );
  }
}
