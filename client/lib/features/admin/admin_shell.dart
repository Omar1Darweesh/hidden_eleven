import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/theme.dart';
import 'package:hidden_eleven/features/admin/abilities/abilities_tab.dart';
import 'package:hidden_eleven/features/admin/backup/backup_tab.dart';
import 'package:hidden_eleven/features/admin/card_tiers/card_tiers_tab.dart';
import 'package:hidden_eleven/features/admin/clubs/clubs_tab.dart';
import 'package:hidden_eleven/features/admin/formations/formations_tab.dart';
import 'package:hidden_eleven/features/admin/guide/guide_tab.dart';
import 'package:hidden_eleven/features/admin/leagues/leagues_tab.dart';
import 'package:hidden_eleven/features/admin/league_bundles/league_bundles_tab.dart';
import 'package:hidden_eleven/features/admin/media/media_tab.dart';
import 'package:hidden_eleven/features/admin/nations/nations_tab.dart';
import 'package:hidden_eleven/features/admin/players/players_tab.dart';
import 'package:hidden_eleven/features/admin/scoring/scoring_tab.dart';
import 'package:hidden_eleven/features/admin/server_monitor/server_monitor_tab.dart';
import 'package:hidden_eleven/features/admin/tournament_awards/tournament_awards_tab.dart';
import 'package:hidden_eleven/features/admin/widgets/admin_auth_gate.dart';
import 'package:hidden_eleven/features/admin/services/admin_auth_service.dart';

// Desktop sidebar breakpoint
const _kSidebarBreakpoint = 720.0;

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _authSession = 0;

  void _onSignOut() {
    setState(() => _authSession++);
  }

  @override
  Widget build(BuildContext context) {
    return AdminAuthGate(
      key: ValueKey(_authSession),
      child: _AdminShellBody(onSignOut: _onSignOut),
    );
  }
}

class _AdminShellBody extends StatefulWidget {
  const _AdminShellBody({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  State<_AdminShellBody> createState() => _AdminShellBodyState();
}

class _AdminShellBodyState extends State<_AdminShellBody> {
  int _selectedIndex = 0;

  static const _tabs = [
    _TabSpec(icon: Icons.people_outline_rounded, label: 'Players'),
    _TabSpec(icon: Icons.shield_outlined, label: 'Clubs'),
    _TabSpec(icon: Icons.flag_outlined, label: 'Nations'),
    _TabSpec(icon: Icons.sports_soccer_rounded, label: 'Leagues'),
    _TabSpec(icon: Icons.inventory_2_outlined, label: 'League Bundles'),
    _TabSpec(icon: Icons.grid_view_rounded, label: 'Formations'),
    _TabSpec(icon: Icons.auto_awesome_outlined, label: 'Abilities'),
    _TabSpec(icon: Icons.palette_outlined, label: 'Card Colours'),
    _TabSpec(icon: Icons.calculate_outlined, label: 'Scoring'),
    _TabSpec(icon: Icons.emoji_events_outlined, label: 'Tournament Awards'),
    _TabSpec(icon: Icons.menu_book_outlined, label: 'Instructions'),
    _TabSpec(icon: Icons.folder_outlined, label: 'Media'),
    _TabSpec(icon: Icons.monitor_heart, label: 'Server'),
    _TabSpec(icon: Icons.backup_outlined, label: 'Backups'),
  ];

  Widget get _activeTab => switch (_selectedIndex) {
    0 => const PlayersTab(),
    1 => const ClubsTab(),
    2 => const NationsTab(),
    3 => const LeaguesTab(),
    4 => const LeagueBundlesTab(),
    5 => const FormationsTab(),
    6 => const AbilitiesTab(),
    7 => const CardTiersTab(),
    8 => const ScoringTab(),
    9 => const TournamentAwardsTab(),
    10 => const GuideTab(),
    11 => const MediaTab(),
    12 => const ServerMonitorTab(),
    13 => const BackupTab(),
    _ => const SizedBox.shrink(),
  };

  Future<void> _signOut() async {
    await AdminAuthService.clearToken();
    widget.onSignOut();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= _kSidebarBreakpoint;
    return Scaffold(
      backgroundColor: HEColors.background,
      body: wide ? _wideLayout() : _narrowLayout(),
    );
  }

  Widget _wideLayout() {
    return Row(
      children: [
        _Sidebar(
          tabs: _tabs,
          selectedIndex: _selectedIndex,
          onSelect: (i) => setState(() => _selectedIndex = i),
          onSignOut: _signOut,
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(child: _ContentArea(child: _activeTab)),
      ],
    );
  }

  Widget _narrowLayout() {
    return Column(
      children: [
        Expanded(child: _ContentArea(child: _activeTab)),
        const Divider(height: 1),
        NavigationBar(
          backgroundColor: HEColors.surface,
          selectedIndex: _selectedIndex,
          onDestinationSelected: (i) => setState(() => _selectedIndex = i),
          destinations: _tabs
              .map(
                (t) =>
                    NavigationDestination(icon: Icon(t.icon), label: t.label),
              )
              .toList(),
        ),
      ],
    );
  }
}

// ── Sidebar ────────────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelect,
    required this.onSignOut,
  });

  final List<_TabSpec> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      color: HEColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: HEColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(HERadius.sm),
                      ),
                      child: const Icon(
                        Icons.admin_panel_settings_outlined,
                        color: HEColors.accent,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Admin',
                      style: TextStyle(
                        color: HEColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Hidden Eleven',
                  style: TextStyle(color: HEColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 8),
          // Nav items
          ...tabs.asMap().entries.map(
            (e) => _SidebarItem(
              spec: e.value,
              selected: selectedIndex == e.key,
              onTap: () => onSelect(e.key),
            ),
          ),
          const Spacer(),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextButton.icon(
              onPressed: onSignOut,
              icon: const Icon(
                Icons.logout,
                size: 16,
                color: HEColors.textMuted,
              ),
              label: const Text(
                'Sign out',
                style: TextStyle(color: HEColors.textMuted, fontSize: 12),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text(
              'v1.0 · internal',
              style: TextStyle(
                color: HEColors.textMuted.withValues(alpha: 0.6),
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.spec,
    required this.selected,
    required this.onTap,
  });
  final _TabSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected
            ? HEColors.accent.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(HERadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(HERadius.sm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(
                  spec.icon,
                  size: 18,
                  color: selected ? HEColors.accent : HEColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Text(
                  spec.label,
                  style: TextStyle(
                    color: selected ? HEColors.accent : HEColors.textSecondary,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Content area ───────────────────────────────────────────────────────────────

class _ContentArea extends StatelessWidget {
  const _ContentArea({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.all(24), child: child);
  }
}

// ── Data ───────────────────────────────────────────────────────────────────────

class _TabSpec {
  const _TabSpec({required this.icon, required this.label});
  final IconData icon;
  final String label;
}
