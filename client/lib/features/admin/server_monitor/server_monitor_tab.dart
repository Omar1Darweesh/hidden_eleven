import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/theme.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart';
import 'package:hidden_eleven/features/admin/widgets/admin_widgets.dart';
import 'package:hidden_eleven/features/tournament/widgets/tournament_admin_section.dart';

class ServerMonitorTab extends StatefulWidget {
  const ServerMonitorTab({super.key});

  @override
  State<ServerMonitorTab> createState() => _ServerMonitorTabState();
}

class _ServerMonitorTabState extends State<ServerMonitorTab> {
  String? _health;
  Map<String, dynamic>? _metrics;
  String? _error;
  bool _loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        AdminApi.getHealth(),
        AdminApi.getMetrics(),
      ]);
      if (mounted) {
        setState(() {
          _health = results[0] as String;
          _metrics = results[1] as Map<String, dynamic>;
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(onRefresh: _load),
        const SizedBox(height: 16),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AdminErrorState(error: _error!, onRetry: _load);
    // Single scroll owns the metrics grid + the (usually empty) tournament
    // status section. The section collapses to nothing when no tournament is
    // active, so non-tournament sessions look exactly as before.
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MetricsGrid(health: _health!, metrics: _metrics!),
          const TournamentAdminSection(),
        ],
      ),
    );
  }
}

// ── Toolbar ────────────────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'Server Monitor',
          style: TextStyle(
            color: HEColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.refresh_rounded, size: 20),
          color: HEColors.textSecondary,
          tooltip: 'Refresh',
          onPressed: onRefresh,
        ),
      ],
    );
  }
}

// ── Metrics grid ───────────────────────────────────────────────────────────────

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.health, required this.metrics});

  final String health;
  final Map<String, dynamic> metrics;

  String _formatUptime(dynamic rawSeconds) {
    final secs = (rawSeconds as num?)?.toInt() ?? 0;
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    return '${h}h ${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final isOk = health == 'ok';
    final cards = <_CardSpec>[
      _CardSpec(
        icon: Icons.circle,
        iconColor: isOk ? Colors.green : HEColors.error,
        value: isOk ? 'OK' : health.toUpperCase(),
        label: 'Server Status',
      ),
      _CardSpec(
        icon: Icons.meeting_room_outlined,
        value: '${metrics['activeRooms'] ?? 0}',
        label: 'Active Rooms',
      ),
      _CardSpec(
        icon: Icons.sports_soccer_rounded,
        value: '${metrics['activeSessions'] ?? 0}',
        label: 'Active Games',
      ),
      _CardSpec(
        icon: Icons.people_outline_rounded,
        value: '${metrics['connectedSockets'] ?? 0}',
        label: 'Connected Players',
      ),
      _CardSpec(
        icon: Icons.emoji_events_outlined,
        value: '${metrics['matchesRecorded'] ?? 0}',
        label: 'Total Matches',
      ),
      _CardSpec(
        icon: Icons.timer_outlined,
        value: _formatUptime(metrics['uptimeSeconds']),
        label: 'Uptime',
      ),
      _CardSpec(
        icon: Icons.memory_rounded,
        value: '${(metrics['memoryMb'] as num?)?.toStringAsFixed(1) ?? '—'}',
        label: 'Memory (MB)',
      ),
      _CardSpec(
        icon: Icons.info_outline_rounded,
        value: '${metrics['nodeVersion'] ?? '—'}',
        label: 'Node Version',
      ),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: cards.map((c) => _MetricCard(spec: c)).toList(),
    );
  }
}

// ── Metric card ────────────────────────────────────────────────────────────────

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.spec});
  final _CardSpec spec;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: HEColors.surface,
        borderRadius: BorderRadius.circular(HERadius.md),
        border: Border.all(color: HEColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(spec.icon, color: spec.iconColor ?? HEColors.accent, size: 22),
          const SizedBox(height: 12),
          Text(
            spec.value,
            style: const TextStyle(
              color: HEColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            spec.label,
            style: const TextStyle(color: HEColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ── Data ───────────────────────────────────────────────────────────────────────

class _CardSpec {
  const _CardSpec({
    required this.icon,
    required this.value,
    required this.label,
    this.iconColor,
  });

  final IconData icon;
  final Color? iconColor;
  final String value;
  final String label;
}
