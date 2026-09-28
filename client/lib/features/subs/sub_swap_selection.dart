import 'package:flutter/foundation.dart';

/// Ephemeral, local-only state for the explicit 3-step substitution swap flow.
///
/// The flow is: select a SOURCE (a bench sub card OR a pitch starter) → the UI
/// highlights all valid TARGETS (the opposite side only — bench ↔ pitch, never
/// pitch ↔ pitch) → the user taps one target → presses the [Swap] button to
/// commit the swap to the server.
///
/// Exactly one of [sourceGroup] / [sourceSlotIndex] is set (the source), and at
/// most one of [pendingGroup] / [pendingSlotIndex] is set (the chosen target).
/// The target highlight sets ([targetGroups] / [targetSlots]) are recomputed by
/// the game screen from the server state every time the source changes.
@immutable
class SubSwapView {
  const SubSwapView({
    this.sourceGroup,
    this.sourceSlotIndex,
    this.targetGroups = const {},
    this.targetSlots = const {},
    this.pendingGroup,
    this.pendingSlotIndex,
    this.sourceLabel,
    this.targetLabel,
  });

  /// Empty selection — nothing picked yet.
  static const SubSwapView none = SubSwapView();

  /// Set when the source is a bench sub card ('att' | 'mid' | 'def').
  final String? sourceGroup;

  /// Set when the source is a pitch starter (slot index).
  final int? sourceSlotIndex;

  /// Bench groups eligible to receive the source (only when source is a pitch
  /// starter).
  final Set<String> targetGroups;

  /// Pitch slot indices eligible to receive the source (only when source is a
  /// bench sub).
  final Set<int> targetSlots;

  /// The chosen target bench group, awaiting [Swap].
  final String? pendingGroup;

  /// The chosen target pitch slot index, awaiting [Swap].
  final int? pendingSlotIndex;

  /// Human-readable label for the source, e.g. "E. Martínez (GK)".
  final String? sourceLabel;

  /// Human-readable label for the chosen target, e.g. "K. Navas (GK)".
  final String? targetLabel;

  bool get hasSource => sourceGroup != null || sourceSlotIndex != null;
  bool get hasTarget => pendingGroup != null || pendingSlotIndex != null;

  /// True once a valid source + target pair is selected and the swap may fire.
  bool get canSwap => hasSource && hasTarget;

  /// True while a source is selected (used to dim non-target cards).
  bool get active => hasSource;
}
