import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hidden_eleven/app/theme.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart';

/// Lifecycle of an image upload within a form.
enum UploadStatus { idle, uploading, success, error }

// ── Image preview with fallback ───────────────────────────────────────────────

class AdminImagePreview extends StatelessWidget {
  const AdminImagePreview({
    super.key,
    required this.url,
    this.size = 44,
    this.placeholder = Icons.image_outlined,
  });

  final String? url;
  final double size;
  final IconData placeholder;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return _Placeholder(size: size, icon: placeholder);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(HERadius.sm),
      child: Image.network(
        AdminApi.proxyImageUrl(url!),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (ctx, err, stack) =>
            _Placeholder(size: size, icon: placeholder),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.size, required this.icon});
  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: HEColors.surfaceElevated,
        borderRadius: BorderRadius.circular(HERadius.sm),
        border: Border.all(color: HEColors.divider),
      ),
      child: Icon(icon, color: HEColors.textMuted, size: size * 0.45),
    );
  }
}

// ── Image uploader ────────────────────────────────────────────────────────────
//
// Usage in a form:
//   1. Keep Uint8List? _pendingBytes / String? _pendingFilename in form state.
//   2. Pass status: _uploadStatus and errorMessage: _uploadError.
//   3. After entity save, set status=uploading, call AdminApi.upload*, then
//      set status=success (with savedPath) or status=error on failure.
//
// The widget shows the existing server image until a local file is picked,
// then previews the local file. On success it shows a green "Saved" badge
// with the stored relative path.

class AdminImageUploader extends StatefulWidget {
  const AdminImageUploader({
    super.key,
    this.currentUrl,
    this.savedPath,
    this.placeholder = Icons.image_outlined,
    required this.onFilePicked,
    this.status = UploadStatus.idle,
    this.errorMessage,
    this.size = 110,
    this.urlController,
  });

  /// Fully-resolved HTTP URL of the currently saved image (may be null/empty).
  final String? currentUrl;

  /// Relative stored path shown on success (e.g. /assets/players/photos/x.png).
  final String? savedPath;

  final IconData placeholder;

  /// Called with raw bytes + original filename when the user picks a file.
  final void Function(Uint8List bytes, String filename) onFilePicked;

  final UploadStatus status;
  final String? errorMessage;
  final double size;

  /// When provided, shows an editable URL field (method 1).
  /// The text is used for live preview; overrides currentUrl when non-empty.
  final TextEditingController? urlController;

  @override
  State<AdminImageUploader> createState() => _AdminImageUploaderState();
}

class _AdminImageUploaderState extends State<AdminImageUploader> {
  Uint8List? _localBytes;

  @override
  void initState() {
    super.initState();
    widget.urlController?.addListener(_onUrlChanged);
  }

  @override
  void didUpdateWidget(AdminImageUploader old) {
    super.didUpdateWidget(old);
    if (old.urlController != widget.urlController) {
      old.urlController?.removeListener(_onUrlChanged);
      widget.urlController?.addListener(_onUrlChanged);
    }
    if (old.status != UploadStatus.success &&
        widget.status == UploadStatus.success) {
      setState(() => _localBytes = null);
    }
  }

  @override
  void dispose() {
    widget.urlController?.removeListener(_onUrlChanged);
    super.dispose();
  }

  void _onUrlChanged() => setState(() {});

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    setState(() => _localBytes = bytes);
    widget.onFilePicked(bytes, file.name);
  }

  @override
  Widget build(BuildContext context) {
    final isUploading = widget.status == UploadStatus.uploading;
    final hasPending = _localBytes != null;
    final urlText = widget.urlController?.text.trim() ?? '';
    final displayUrl = urlText.isNotEmpty ? urlText : (widget.currentUrl ?? '');
    final hasImage = hasPending || displayUrl.isNotEmpty;

    // ── Preview image ──────────────────────────────────────────────────────────

    final Color borderColor = switch (widget.status) {
      UploadStatus.success => const Color(0xFF4CAF50),
      UploadStatus.error => HEColors.error,
      _ when hasPending => HEColors.accent,
      _ => HEColors.divider,
    };

    Widget imgContent;
    if (hasPending) {
      imgContent = Image.memory(
        _localBytes!,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
      );
    } else if (displayUrl.isNotEmpty) {
      imgContent = Image.network(
        AdminApi.proxyImageUrl(displayUrl),
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        loadingBuilder: (ctx, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            width: widget.size,
            height: widget.size,
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
        errorBuilder: (ctx, err, stack) =>
            _Placeholder(size: widget.size, icon: widget.placeholder),
      );
    } else {
      imgContent = _Placeholder(size: widget.size, icon: widget.placeholder);
    }

    final statusLine = _buildStatusLine(hasPending);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HEColors.surfaceElevated,
        borderRadius: BorderRadius.circular(HERadius.sm),
        border: Border.all(color: HEColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row: preview + status ──────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(HERadius.sm),
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    border: Border.all(color: borderColor, width: 1.5),
                    borderRadius: BorderRadius.circular(HERadius.sm),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(HERadius.sm - 1.5),
                    child: imgContent,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!hasImage)
                      const Text(
                        'No image set',
                        style: TextStyle(
                          color: HEColors.textMuted,
                          fontSize: 12,
                        ),
                      )
                    else
                      const Text(
                        'Current image',
                        style: TextStyle(
                          color: HEColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (statusLine != null) ...[
                      const SizedBox(height: 6),
                      statusLine,
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ── Method 1: paste URL ────────────────────────────────────────────
          if (widget.urlController != null) ...[
            const Text(
              'METHOD 1 — PASTE URL',
              style: TextStyle(
                color: HEColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: widget.urlController,
              style: const TextStyle(
                color: HEColors.textPrimary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                hintText: 'https://… or /assets/…',
                hintStyle: const TextStyle(
                  color: HEColors.textMuted,
                  fontSize: 12,
                ),
                suffixIcon: urlText.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 14),
                        color: HEColors.textSecondary,
                        onPressed: () => widget.urlController?.clear(),
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(child: Divider(color: HEColors.divider)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'or',
                    style: TextStyle(
                      color: HEColors.textMuted.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                ),
                const Expanded(child: Divider(color: HEColors.divider)),
              ],
            ),
            const SizedBox(height: 14),
          ],

          // ── Method 2: upload file ──────────────────────────────────────────
          if (widget.urlController != null)
            const Text(
              'METHOD 2 — UPLOAD FILE',
              style: TextStyle(
                color: HEColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            )
          else
            const Text(
              'UPLOAD FILE',
              style: TextStyle(
                color: HEColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: isUploading ? null : _pick,
            icon: isUploading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_rounded, size: 16),
            label: Text(
              isUploading
                  ? 'Uploading…'
                  : (hasPending
                        ? 'Change File (pending)'
                        : 'Choose Image File'),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: hasPending
                  ? HEColors.accent
                  : HEColors.textSecondary,
              side: BorderSide(
                color: hasPending ? HEColors.accent : HEColors.inputBorder,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              textStyle: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildStatusLine(bool hasPending) {
    switch (widget.status) {
      case UploadStatus.uploading:
        return const Text(
          'Uploading…',
          style: TextStyle(color: HEColors.textSecondary, fontSize: 11),
        );

      case UploadStatus.success:
        return Row(
          children: [
            const Icon(
              Icons.check_circle_outline_rounded,
              size: 13,
              color: Color(0xFF4CAF50),
            ),
            const SizedBox(width: 4),
            const Text(
              'Saved',
              style: TextStyle(color: Color(0xFF4CAF50), fontSize: 11),
            ),
            if (widget.savedPath != null && widget.savedPath!.isNotEmpty) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.savedPath!,
                  style: const TextStyle(
                    color: HEColors.textMuted,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        );

      case UploadStatus.error:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 13,
              color: HEColors.error,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                widget.errorMessage ?? 'Upload failed',
                style: const TextStyle(color: HEColors.error, fontSize: 11),
                maxLines: 2,
              ),
            ),
          ],
        );

      case UploadStatus.idle:
        if (hasPending) {
          return const Row(
            children: [
              Icon(Icons.circle, size: 6, color: HEColors.accent),
              SizedBox(width: 5),
              Text(
                'Pending upload',
                style: TextStyle(color: HEColors.accent, fontSize: 11),
              ),
            ],
          );
        }
        return null;
    }
  }
}

// ── Stat bars strip ───────────────────────────────────────────────────────────
//
// Compact PAC/SHO/PAS/DRI/DEF/PHY readout used in player rows and the form.

class StatBarsStrip extends StatelessWidget {
  const StatBarsStrip({super.key, required this.stats, this.compact = false});

  /// (label, value) pairs — see AdminPlayer.statBars.
  final List<({String label, int value})> stats;
  final bool compact;

  static Color colorFor(int v) {
    if (v >= 85) return HEColors.gold;
    if (v >= 75) return const Color(0xFF7FD17F);
    if (v >= 65) return const Color(0xFFBCC2CC);
    return HEColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: compact ? 8 : 12,
      runSpacing: 4,
      children: stats
          .map(
            (s) => _StatPill(label: s.label, value: s.value, compact: compact),
          )
          .toList(),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    required this.compact,
  });
  final String label;
  final int value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = StatBarsStrip.colorFor(value);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: TextStyle(
            color: HEColors.textMuted,
            fontSize: compact ? 9 : 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        Text(
          '$value',
          style: TextStyle(
            color: color,
            fontSize: compact ? 11 : 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

// ── Searchable dropdown ───────────────────────────────────────────────────────
//
// Generic modal-search select field. Validation is manual: pass errorText
// when the field is required and not yet filled.

class AdminSearchableDropdown<T> extends StatelessWidget {
  const AdminSearchableDropdown({
    super.key,
    required this.label,
    required this.items,
    required this.labelOf,
    this.value,
    required this.onChanged,
    this.hint,
    this.errorText,
    this.loading = false,
    this.leadingOf,
  });

  final String label;
  final List<T> items;
  final String Function(T) labelOf;
  final T? value;
  final ValueChanged<T?> onChanged;
  final String? hint;
  final String? errorText;
  final bool loading;

  /// Optional leading widget factory for each list item (e.g. an image).
  final Widget? Function(T)? leadingOf;

  Future<void> _openPicker(BuildContext context) async {
    final selected = await showDialog<T>(
      context: context,
      builder: (ctx) => _SearchPickerDialog<T>(
        title: 'Select $label',
        items: items,
        labelOf: labelOf,
        leadingOf: leadingOf,
        current: value,
      ),
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    final borderColor = hasError ? HEColors.error : HEColors.divider;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: hasError ? HEColors.error : HEColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: loading ? null : () => _openPicker(context),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: borderColor,
                  width: hasError ? 1.5 : 1,
                ),
              ),
            ),
            child: Row(
              children: [
                if (loading) ...[
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Loading…',
                    style: TextStyle(color: HEColors.textMuted, fontSize: 14),
                  ),
                ] else if (value != null) ...[
                  Expanded(
                    child: Text(
                      labelOf(value as T),
                      style: const TextStyle(
                        color: HEColors.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.expand_more_rounded,
                    color: HEColors.textSecondary,
                    size: 18,
                  ),
                ] else ...[
                  Expanded(
                    child: Text(
                      hint ?? 'Select $label',
                      style: const TextStyle(
                        color: HEColors.textMuted,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.expand_more_rounded,
                    color: HEColors.textSecondary,
                    size: 18,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 4),
          Text(
            errorText!,
            style: const TextStyle(color: HEColors.error, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _SearchPickerDialog<T> extends StatefulWidget {
  const _SearchPickerDialog({
    required this.title,
    required this.items,
    required this.labelOf,
    this.leadingOf,
    this.current,
  });

  final String title;
  final List<T> items;
  final String Function(T) labelOf;
  final Widget? Function(T)? leadingOf;
  final T? current;

  @override
  State<_SearchPickerDialog<T>> createState() => _SearchPickerDialogState<T>();
}

class _SearchPickerDialogState<T> extends State<_SearchPickerDialog<T>> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<T> get _filtered {
    if (_query.isEmpty) return widget.items;
    final q = _query.toLowerCase();
    return widget.items
        .where((item) => widget.labelOf(item).toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Dialog(
      backgroundColor: HEColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
              color: HEColors.surfaceElevated,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: HEColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: HEColors.textSecondary,
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ctrl,
                    autofocus: true,
                    onChanged: (q) => setState(() => _query = q),
                    style: const TextStyle(
                      color: HEColors.textPrimary,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search…',
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
                              icon: const Icon(Icons.close_rounded, size: 16),
                              color: HEColors.textSecondary,
                              onPressed: () {
                                _ctrl.clear();
                                setState(() => _query = '');
                              },
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // List
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'No results',
                        style: TextStyle(
                          color: HEColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final item = filtered[i];
                        final isCurrent =
                            widget.current != null &&
                            widget.labelOf(item) ==
                                widget.labelOf(widget.current as T);
                        final leading = widget.leadingOf?.call(item);
                        return InkWell(
                          onTap: () => Navigator.of(context).pop(item),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                if (leading != null) ...[
                                  leading,
                                  const SizedBox(width: 10),
                                ],
                                Expanded(
                                  child: Text(
                                    widget.labelOf(item),
                                    style: TextStyle(
                                      color: isCurrent
                                          ? HEColors.accent
                                          : HEColors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: isCurrent
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                                if (isCurrent)
                                  const Icon(
                                    Icons.check_rounded,
                                    color: HEColors.accent,
                                    size: 16,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Consistent form text field ─────────────────────────────────────────────────

class AdminTextField extends StatelessWidget {
  const AdminTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.inputFormatters,
    this.maxLines = 1,
    this.onChanged,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      onChanged: onChanged,
      validator: validator,
      style: const TextStyle(color: HEColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(
          color: HEColors.textSecondary,
          fontSize: 13,
        ),
        hintStyle: const TextStyle(color: HEColors.textMuted, fontSize: 13),
      ),
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────────

class AdminSectionHeader extends StatelessWidget {
  const AdminSectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: HEColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class AdminEmptyState extends StatelessWidget {
  const AdminEmptyState({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inbox_outlined,
              color: HEColors.textMuted,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(
                color: HEColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error state ────────────────────────────────────────────────────────────────

class AdminErrorState extends StatelessWidget {
  const AdminErrorState({
    super.key,
    required this.error,
    required this.onRetry,
  });
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: HEColors.error,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            error,
            style: const TextStyle(color: HEColors.textSecondary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

// ── Confirm delete dialog ──────────────────────────────────────────────────────

Future<bool?> showDeleteConfirm(BuildContext context, String label) {
  return showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: HEColors.surfaceElevated,
      title: const Text('Delete'),
      content: Text('Delete "$label"? This cannot be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: HEColors.error),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}

// ── Inline rating badge ────────────────────────────────────────────────────────

class RatingBadge extends StatelessWidget {
  const RatingBadge(this.rating, {super.key});
  final int rating;

  Color get _color {
    if (rating >= 85) return HEColors.gold;
    if (rating >= 75) return const Color(0xFFBCC2CC);
    if (rating >= 65) return const Color(0xFFCD7F32);
    return HEColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(HERadius.xs),
        border: Border.all(color: _color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$rating',
        style: TextStyle(
          color: _color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ── Shared dialog chrome ───────────────────────────────────────────────────────

class AdminDialogHeader extends StatelessWidget {
  const AdminDialogHeader({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
      decoration: const BoxDecoration(
        color: HEColors.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: HEColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            color: HEColors.textSecondary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}

class AdminDialogFooter extends StatelessWidget {
  const AdminDialogFooter({
    super.key,
    required this.saving,
    required this.isEdit,
    required this.onSave,
  });
  final bool saving;
  final bool isEdit;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: saving ? null : onSave,
            // Override the theme's full-width (Size.fromHeight) minimum, which
            // forces infinite width and makes the button overflow/clip when
            // placed in a Row. A finite min keeps it visible & natural-width.
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black54,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 16),
            label: Text(isEdit ? 'Save' : 'Create'),
          ),
        ],
      ),
    );
  }
}

// ── Form dialog scaffold ──────────────────────────────────────────────────────
//
// Scrollable body with a PINNED header and footer. The previous form dialogs
// used a fixed Column, so on short viewports the Save button was pushed off the
// bottom and became unreachable. This caps the height to the viewport, scrolls
// the middle, and always keeps the Save/Cancel buttons visible.

class AdminFormScaffold extends StatelessWidget {
  const AdminFormScaffold({
    super.key,
    required this.formKey,
    required this.title,
    required this.children,
    required this.saving,
    required this.isEdit,
    required this.onSave,
    this.maxWidth = 460,
  });

  final GlobalKey<FormState> formKey;
  final String title;
  final List<Widget> children;
  final bool saving;
  final bool isEdit;
  final VoidCallback onSave;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.9;
    return Dialog(
      backgroundColor: HEColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminDialogHeader(title: title),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
              const Divider(height: 1),
              AdminDialogFooter(saving: saving, isEdit: isEdit, onSave: onSave),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Position chip ──────────────────────────────────────────────────────────────

class PositionChip extends StatelessWidget {
  const PositionChip(this.position, {super.key, this.primary = false});
  final String position;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: primary
            ? HEColors.accent.withValues(alpha: 0.15)
            : HEColors.surfaceElevated,
        borderRadius: BorderRadius.circular(HERadius.xs),
        border: Border.all(
          color: primary ? HEColors.accentMuted : HEColors.divider,
        ),
      ),
      child: Text(
        position,
        style: TextStyle(
          color: primary ? HEColors.accent : HEColors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

// ── Shared hex-colour editing ─────────────────────────────────────────────────
//
// Extracted from card_tiers_tab.dart (its original, sole owner) so a second
// admin-editable colour field — abilities_tab.dart's per-ability colour —
// doesn't duplicate the parsing helper, the 39-swatch preset palette, or the
// tap-to-select grid rendering. Both tabs still own their own colour
// PREVIEW shape (a mini gradient card swatch for tiers, a plain filled
// circle for abilities) — only the parts that were byte-for-byte identical
// are shared here.

/// Parses a `#RRGGBB`/`#RRGGBBAA` hex string into a [Color]. Falls back to a
/// neutral grey-blue if the string doesn't parse — never throws, since this
/// is called on every keystroke of a free-text hex field.
Color hexToColor(String hex) {
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  return Color(int.tryParse(h, radix: 16) ?? 0xFFB0BDD8);
}

/// Curated hex presets organised by colour family, so the palette reads like
/// a colour-picker grid rather than a random list.
const kAdminColorPresets = <(String, String)>[
  // ── Darks / Neutrals ──
  ('Onyx', '#111318'),
  ('Black', '#222831'),
  ('Carbon', '#2D3142'),
  ('Graphite', '#4A4E69'),
  ('Slate', '#64748B'),
  ('Silver', '#9AA5B1'),
  ('Stone', '#CBD5E1'),
  ('White', '#F0F4F8'),
  // ── Reds ──
  ('Crimson', '#C0392B'),
  ('Red', '#E74C3C'),
  ('Rose', '#FB7185'),
  ('Pink', '#F472B6'),
  // ── Oranges ──
  ('Rust', '#C0531A'),
  ('Orange', '#E67E22'),
  ('Amber', '#F39C12'),
  ('Peach', '#FDBA74'),
  // ── Yellows ──
  ('Yellow', '#F2C037'),
  ('Gold', '#FFD700'),
  ('Cream', '#FFF3A3'),
  // ── Greens ──
  ('Forest', '#1A6B3C'),
  ('Green', '#2ECC71'),
  ('Mint', '#6EE7B7'),
  ('Lime', '#A3E635'),
  // ── Teals / Cyans ──
  ('Teal', '#14B8A6'),
  ('Cyan', '#22D3EE'),
  ('Sky', '#38BDF8'),
  // ── Blues ──
  ('Navy', '#1E3A5F'),
  ('Royal', '#2563EB'),
  ('Blue', '#3A8DDE'),
  ('Ice', '#93C5FD'),
  // ── Purples / Violets ──
  ('Indigo', '#4338CA'),
  ('Purple', '#A55CFF'),
  ('Violet', '#7C3AED'),
  ('Lavender', '#C4B5FD'),
  ('Magenta', '#E879F9'),
  // ── Special FUT-style ──
  ('TOTY', '#C9A84C'),
  ('Icons', '#E6C96A'),
  ('FUTTIES', '#FF5F6D'),
  ('RTTK', '#00C9A7'),
  ('OTW', '#F7971E'),
];

/// Tap-to-select grid of [kAdminColorPresets], highlighting whichever one
/// (if any) matches [selectedHex]. Purely a picker — the caller owns the
/// actual hex text field/state and receives taps via [onSelect].
class AdminColorPresetGrid extends StatelessWidget {
  const AdminColorPresetGrid({
    super.key,
    required this.selectedHex,
    required this.onSelect,
  });

  final String selectedHex;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 10,
      children: kAdminColorPresets.map((p) {
        final c = hexToColor(p.$2);
        final selected = selectedHex.trim().toLowerCase() == p.$2.toLowerCase();
        return GestureDetector(
          onTap: () => onSelect(p.$2),
          child: SizedBox(
            width: 40,
            child: Column(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: selected
                        ? Border.all(color: Colors.white, width: 2.5)
                        : Border.all(color: HEColors.divider, width: 1),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: c.withValues(alpha: 0.7),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  p.$1,
                  style: TextStyle(
                    color: selected ? HEColors.textPrimary : HEColors.textMuted,
                    fontSize: 8,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Validator for a hex-colour [AdminTextField] — shared so every admin
/// colour field enforces the same `#RRGGBB`/`#RRGGBBAA` shape.
String? adminHexColorValidator(String? v) {
  final h = (v ?? '').replaceAll('#', '').trim();
  if (h.length != 6 && h.length != 8) return 'Use #RRGGBB';
  return null;
}
