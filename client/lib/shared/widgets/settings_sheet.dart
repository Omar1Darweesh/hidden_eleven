import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/app/routes.dart';
import 'package:hidden_eleven/features/game/game_provider.dart';
import 'package:hidden_eleven/features/lobby/room_provider.dart';
import 'package:hidden_eleven/shared/audio/audio_service.dart';
import 'package:hidden_eleven/shared/providers/app_preferences_provider.dart';

/// Opens the in-game Settings sheet. Bottom sheet on narrow (mobile/tablet)
/// widths, a centered constrained dialog on wide (desktop) widths — the
/// same width-based adaptivity used nowhere else in this codebase yet (every
/// existing "sheet-like" surface — `card_details_modal.dart`,
/// `help_dialog.dart` — is a fixed `showDialog` regardless of width), so
/// this establishes the pattern rather than deviating from one.
///
/// Deliberately just a widget shown over the current route: it does not
/// pause, cancel, or otherwise touch any Riverpod provider, Timer, or
/// WebSocket subscription. Every one of those already lives independently
/// of the widget tree (the turn timer, the socket listener, etc. are
/// provider-owned), so opening/closing this sheet cannot interrupt a live
/// draft, a running timer, or an in-flight reveal — verified by inspection
/// of `room_provider.dart`/`game_provider.dart` rather than assumed.
void showSettingsSheet(BuildContext context) {
  final isWide = MediaQuery.sizeOf(context).width >= HETheme.breakpointMobile;

  if (isWide) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: const _SettingsSheetContent(isDialog: true),
        ),
      ),
    );
    return;
  }

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _SettingsSheetContent(isDialog: false),
  );
}

class _SettingsSheetContent extends ConsumerWidget {
  const _SettingsSheetContent({required this.isDialog});

  final bool isDialog;

  Future<void> _confirmLeaveRoom(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HETheme.pfSurfaceRaised,
        title: const Text('Leave this room?'),
        content: const Text(
          "You'll return to the home screen. If the match is still going, "
          "you can rejoin from there before it's forfeited.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Leave Room',
              style: TextStyle(color: HETheme.pfDanger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // Exact same sequence the existing "leave game" AppBar action and the
    // connection-lost dialog both already use (game_screen.dart) — reusing
    // the established flow rather than inventing a new one.
    ref.read(roomProvider.notifier).exitGameToHome();
    ref.read(gameProvider.notifier).reset();
    Navigator.of(context).pop(); // close the settings sheet/dialog itself
    if (context.mounted) context.goNamed(Routes.home);
  }

  void _openHowToPlay(BuildContext context) {
    Navigator.of(context).pop();
    context.pushNamed(Routes.help);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sfxMuted = ref.watch(sfxMutedProvider);
    final musicMuted = ref.watch(musicMutedProvider);
    final prefs = ref.watch(appPreferencesProvider);

    final content = Container(
      padding: EdgeInsets.fromLTRB(
        HETheme.spaceLg,
        HETheme.spaceLg,
        HETheme.spaceLg,
        HETheme.spaceLg +
            (isDialog ? 0 : MediaQuery.viewPaddingOf(context).bottom),
      ),
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceRaised,
        borderRadius: isDialog
            ? BorderRadius.circular(HETheme.radiusLg)
            : const BorderRadius.vertical(
                top: Radius.circular(HETheme.radiusLg),
              ),
        border: Border.all(color: HETheme.pfBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isDialog) ...[
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: HETheme.spaceMd),
                decoration: BoxDecoration(
                  color: HETheme.pfBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
          Row(
            children: [
              Expanded(
                child: Text('Settings', style: HETheme.display(size: 22)),
              ),
              // 44x44 minimum touch target, keyboard-reachable close action.
              SizedBox(
                width: 44,
                height: 44,
                child: IconButton(
                  tooltip: 'Close settings',
                  icon: const Icon(
                    Icons.close_rounded,
                    color: HETheme.pfTextSecondary,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
          const SizedBox(height: HETheme.spaceSm),

          _SectionLabel('SOUND'),
          _ToggleRow(
            icon: Icons.music_note_rounded,
            label: 'Music',
            value: !musicMuted,
            semanticsLabel: 'Music, ${musicMuted ? 'off' : 'on'}',
            onChanged: (on) =>
                ref.read(musicMutedProvider.notifier).setValue(!on),
          ),
          _ToggleRow(
            icon: Icons.graphic_eq_rounded,
            label: 'Sound effects',
            value: !sfxMuted,
            semanticsLabel: 'Sound effects, ${sfxMuted ? 'off' : 'on'}',
            onChanged: (on) =>
                ref.read(sfxMutedProvider.notifier).setValue(!on),
          ),

          const SizedBox(height: HETheme.spaceLg),
          _SectionLabel('DISPLAY'),
          _ToggleRow(
            icon: Icons.motion_photos_off_outlined,
            label: 'Reduced motion',
            value: prefs.reducedMotion,
            semanticsLabel:
                'Reduced motion, ${prefs.reducedMotion ? 'on' : 'off'}',
            onChanged: (on) =>
                ref.read(appPreferencesProvider.notifier).setReducedMotion(on),
          ),
          const SizedBox(height: HETheme.spaceSm),
          _TextSizeRow(
            value: prefs.textScale,
            onChanged: (v) =>
                ref.read(appPreferencesProvider.notifier).setTextScale(v),
          ),

          const SizedBox(height: HETheme.spaceLg),
          _SectionLabel('HELP'),
          _ActionRow(
            icon: Icons.help_outline_rounded,
            label: 'How to Play',
            onTap: () => _openHowToPlay(context),
          ),

          const SizedBox(height: HETheme.spaceLg),
          _SectionLabel('ROOM'),
          _ActionRow(
            icon: Icons.exit_to_app_rounded,
            label: 'Leave Room',
            color: HETheme.pfDanger,
            onTap: () => _confirmLeaveRoom(context, ref),
          ),
        ],
      ),
    );

    return isDialog ? content : SafeArea(top: false, child: content);
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: HETheme.spaceSm,
        top: HETheme.spaceXs,
      ),
      child: Text(text, style: HETheme.displayLabel(size: 11)),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.semanticsLabel,
  });

  final IconData icon;
  final String label;
  final bool value;
  final String semanticsLabel;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      toggled: value,
      child: MergeSemantics(
        child: SizedBox(
          height: 48, // clears the 44x44 minimum with room for the label.
          child: Row(
            children: [
              Icon(icon, size: 18, color: HETheme.pfTextSecondary),
              const SizedBox(width: HETheme.spaceMd),
              Expanded(
                child: Text(
                  label,
                  style: HETheme.body(size: 14, color: HETheme.pfTextPrimary),
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: HETheme.pfAccentViolet,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextSizeRow extends StatelessWidget {
  const _TextSizeRow({required this.value, required this.onChanged});

  final TextScaleOption value;
  final ValueChanged<TextScaleOption> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.text_fields_rounded,
          size: 18,
          color: HETheme.pfTextSecondary,
        ),
        const SizedBox(width: HETheme.spaceMd),
        Expanded(
          child: Text(
            'Text size',
            style: HETheme.body(size: 14, color: HETheme.pfTextPrimary),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in TextScaleOption.values)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: _TextSizeChip(
                  option: option,
                  selected: option == value,
                  onTap: () => onChanged(option),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TextSizeChip extends StatelessWidget {
  const _TextSizeChip({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final TextScaleOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${option.label} text size',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? HETheme.pfAccentViolet.withValues(alpha: 0.14)
                  : HETheme.surfaceRaised,
              borderRadius: BorderRadius.circular(HETheme.radiusSm),
              border: Border.all(
                color: selected
                    ? HETheme.pfAccentViolet.withValues(alpha: 0.5)
                    : HETheme.pfBorder,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              // Short label so three chips fit one row at every text scale —
              // the initial letter is enough given the full name is right
              // there in the row's own "Text size" label.
              option.label[0],
              style: HETheme.mono(
                size: 12,
                weight: FontWeight.w800,
                color: selected
                    ? HETheme.pfAccentViolet
                    : HETheme.pfTextSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? HETheme.pfTextPrimary;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(HETheme.radiusSm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color ?? HETheme.pfTextSecondary),
              const SizedBox(width: HETheme.spaceMd),
              Expanded(
                child: Text(label, style: HETheme.body(size: 14, color: fg)),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: HETheme.pfTextMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
