import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/theme.dart';
import 'package:hidden_eleven/features/admin/models/admin_models.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart';
import 'package:hidden_eleven/features/admin/widgets/admin_widgets.dart';
import 'package:hidden_eleven/shared/data/asset_fallbacks.dart';

class NationsTab extends StatefulWidget {
  const NationsTab({super.key});

  @override
  State<NationsTab> createState() => _NationsTabState();
}

class _NationsTabState extends State<NationsTab> {
  List<AdminNation>? _nations;
  String? _error;
  bool _loading = true;
  String _query = '';

  List<AdminNation> get _filtered {
    var list = _nations ?? [];
    final q = _query.toLowerCase().trim();
    if (q.isNotEmpty) {
      list = list.where((n) => n.name.toLowerCase().contains(q)).toList();
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
      final nations = await AdminApi.getNations();
      if (mounted)
        setState(() {
          _nations = nations;
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

  Future<void> _openForm([AdminNation? nation]) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _NationFormDialog(nation: nation),
    );
    if (result == true) _load();
  }

  Future<void> _delete(AdminNation nation) async {
    final confirmed = await showDeleteConfirm(context, nation.name);
    if (confirmed != true) return;
    try {
      await AdminApi.deleteNation(nation.slug);
      _load();
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
    final total = (_nations ?? []).length;
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
                  hintText: 'Search nations…',
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
            if (_nations != null)
              Text(
                '${filtered.length} of $total',
                style: const TextStyle(color: HEColors.textMuted, fontSize: 12),
              ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: () => _openForm(),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Nation'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(child: _body(filtered)),
      ],
    );
  }

  Widget _body(List<AdminNation> nations) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AdminErrorState(error: _error!, onRetry: _load);
    if (nations.isEmpty) {
      return AdminEmptyState(
        label: _query.isNotEmpty
            ? 'No nations match "$_query"'
            : 'No nations yet',
      );
    }
    return ListView.separated(
      itemCount: nations.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, i) => _NationRow(
        nation: nations[i],
        onEdit: () => _openForm(nations[i]),
        onDelete: () => _delete(nations[i]),
      ),
    );
  }
}

class _NationRow extends StatelessWidget {
  const _NationRow({
    required this.nation,
    required this.onEdit,
    required this.onDelete,
  });
  final AdminNation nation;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  // Stored flag if any, otherwise the same name-based CDN fallback the game uses.
  String _effectiveFlagUrl() {
    final stored = AdminApi.resolveAssetUrl(nation.flagUrl);
    return stored.isNotEmpty
        ? stored
        : (nationFlagFallbackUrl(nation.name) ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            AdminImagePreview(
              url: _effectiveFlagUrl(),
              size: 36,
              placeholder: Icons.flag_outlined,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                nation.name,
                style: const TextStyle(
                  color: HEColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              nation.slug,
              style: const TextStyle(
                color: HEColors.textMuted,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 8),
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
    );
  }
}

class _NationFormDialog extends StatefulWidget {
  const _NationFormDialog({this.nation});
  final AdminNation? nation;

  @override
  State<_NationFormDialog> createState() => _NationFormDialogState();
}

class _NationFormDialogState extends State<_NationFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;

  late final TextEditingController _flagUrlCtrl;
  Uint8List? _pendingFlagBytes;
  String? _pendingFlagFilename;
  UploadStatus _flagUploadStatus = UploadStatus.idle;
  String? _flagUploadError;
  String? _savedFlagPath;

  bool _saving = false;
  bool get _isEdit => widget.nation != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.nation?.name ?? '');
    _savedFlagPath = widget.nation?.flagUrl;
    // Show the stored flag if any; otherwise pre-fill the same name-based
    // fallback the game card uses (flagcdn), so the admin sees the real URL.
    final resolved = AdminApi.resolveAssetUrl(widget.nation?.flagUrl);
    final effective = resolved.isNotEmpty
        ? resolved
        : (nationFlagFallbackUrl(widget.nation?.name) ?? '');
    _flagUrlCtrl = TextEditingController(text: effective);
  }

  @override
  void dispose() {
    _name.dispose();
    _flagUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final manualFlagUrl = _flagUrlCtrl.text.trim();
      final originalFlagUrl = AdminApi.resolveAssetUrl(
        widget.nation?.flagUrl ?? '',
      );

      final dto = {
        'name': _name.text.trim(),
        if (manualFlagUrl.isNotEmpty &&
            manualFlagUrl != originalFlagUrl &&
            _pendingFlagBytes == null)
          'flagUrl': manualFlagUrl,
      };

      final AdminNation saved;
      if (_isEdit) {
        saved = await AdminApi.updateNation(widget.nation!.slug, dto);
      } else {
        saved = await AdminApi.createNation(dto);
      }
      if (_pendingFlagBytes != null) {
        setState(() => _flagUploadStatus = UploadStatus.uploading);
        try {
          final updated = await AdminApi.uploadNationFlag(
            saved.slug,
            _pendingFlagBytes!,
            _pendingFlagFilename!,
          );
          if (mounted) {
            setState(() {
              _flagUploadStatus = UploadStatus.success;
              _savedFlagPath = updated.flagUrl;
              _flagUrlCtrl.text = AdminApi.resolveAssetUrl(updated.flagUrl);
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _saving = false;
              _flagUploadStatus = UploadStatus.error;
              _flagUploadError = e.toString();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Nation saved, but flag upload failed: $e'),
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
      title: _isEdit ? 'Edit Nation' : 'Add Nation',
      saving: _saving,
      isEdit: _isEdit,
      onSave: _save,
      children: [
        AdminTextField(
          controller: _name,
          label: 'Name',
          hint: 'e.g. Brazil',
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: 20),
        const AdminSectionHeader('Flag'),
        const SizedBox(height: 10),
        AdminImageUploader(
          currentUrl: AdminApi.resolveAssetUrl(widget.nation?.flagUrl),
          placeholder: Icons.flag_outlined,
          status: _flagUploadStatus,
          errorMessage: _flagUploadError,
          savedPath: _savedFlagPath,
          urlController: _flagUrlCtrl,
          onFilePicked: (bytes, name) {
            setState(() {
              _pendingFlagBytes = bytes;
              _pendingFlagFilename = name;
              _flagUploadStatus = UploadStatus.idle;
              _flagUploadError = null;
            });
          },
        ),
      ],
    );
  }
}
