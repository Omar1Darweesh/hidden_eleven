import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/app/he_theme.dart';

/// Phase 5: the subs panel's att/mid/def/extra position tags used to reuse
/// pfDanger/pfGold-equivalent (HEColors.error/gold) plus a raw cyan for
/// unrelated category meanings. HETheme.pfPosition* replaces them —
/// this locks in that they stay a distinct identity set, never colliding
/// with a real semantic state color.
void main() {
  test('position tags are distinct from each other', () {
    final tags = {
      HETheme.pfPositionAttack,
      HETheme.pfPositionMid,
      HETheme.pfPositionDef,
      HETheme.pfPositionExtra,
    };
    expect(tags, hasLength(4));
  });

  test('position tags never collide with a semantic state color', () {
    final semanticStates = {
      HETheme.pfGold,
      HETheme.pfDanger,
      HETheme.pfSuccess,
      HETheme.pfWarning,
      HETheme.pfBronze,
    };
    final positionTags = {
      HETheme.pfPositionAttack,
      HETheme.pfPositionMid,
      HETheme.pfPositionDef,
      HETheme.pfPositionExtra,
    };

    expect(positionTags.intersection(semanticStates), isEmpty);
  });
}
