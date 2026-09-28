import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/theme.dart';
import 'package:hidden_eleven/features/admin/backup/file_downloader.dart';
import 'package:hidden_eleven/features/admin/models/admin_models.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart';
import 'package:hidden_eleven/features/admin/widgets/admin_widgets.dart';

/// Shows the state of the single rotating backup archive (created daily by
/// the server's cron job, or on demand here), lets an admin trigger one
/// manually, and lets them save the current archive to their own machine.
class BackupTab extends StatefulWidget {
  const BackupTab({super.key});

  @override
  State<BackupTab> createState() => _BackupTabState();
}

class _BackupTabState extends State<BackupTab> {
  AdminBackupStatus? _status;
  String? _error;
  bool _loading = true;
  bool _running = false;
  bool _downloading = false;

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
      final status = await AdminApi.getBackupStatus();
      if (mounted) {
        setState(() {
          _status = status;
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

  Future<void> _runNow() async {
    setState(() => _running = true);
    try {
      final status = await AdminApi.runBackupNow();
      if (mounted) {
        setState(() {
          _status = status;
          _running = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Backup created.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _running = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _download() async {
    setState(() => _downloading = true);
    try {
      final bytes = await AdminApi.downloadBackup();
      final filename = _status?.filename ?? 'hidden-eleven-backup.tar.gz';
      if (mounted) {
        saveBytesAsFile(bytes, filename);
        setState(() => _downloading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloading = false);
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
        const Text(
          'Backups',
          style: TextStyle(
            color: HEColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'A daily backup runs automatically at 3 AM and replaces the '
          'previous one — there is no accumulating history. Use "Backup '
          'Now" to refresh it on demand before a risky change.',
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
    final status = _status;
    if (status == null) {
      return const AdminEmptyState(label: 'No status loaded');
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AdminSectionHeader('Latest Backup'),
          const SizedBox(height: 10),
          _StatusCard(status: status),
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RunNowButton(running: _running, onPressed: _runNow),
              if (status.exists) ...[
                const SizedBox(width: 12),
                _DownloadButton(
                  downloading: _downloading,
                  onPressed: _download,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});
  final AdminBackupStatus status;

  String _formatSize(int? bytes) {
    if (bytes == null) return '—';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HEColors.surface,
        borderRadius: BorderRadius.circular(HERadius.md),
        border: Border.all(color: HEColors.divider),
      ),
      child: Row(
        children: [
          Icon(
            status.exists
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            color: status.exists ? Colors.green : HEColors.textMuted,
            size: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.exists ? (status.filename ?? '—') : 'No backup yet',
                  style: const TextStyle(
                    color: HEColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (status.exists) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${_formatSize(status.sizeBytes)} · ${status.createdAt ?? '—'}',
                    style: const TextStyle(
                      color: HEColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RunNowButton extends StatelessWidget {
  const _RunNowButton({required this.running, required this.onPressed});
  final bool running;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: running ? null : onPressed,
      style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
      icon: running
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.black54,
              ),
            )
          : const Icon(Icons.backup_outlined, size: 16),
      label: Text(running ? 'Running…' : 'Backup Now'),
    );
  }
}

class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.downloading, required this.onPressed});
  final bool downloading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: downloading ? null : onPressed,
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
      icon: downloading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.download_outlined, size: 16),
      label: Text(downloading ? 'Downloading…' : 'Download to PC'),
    );
  }
}
