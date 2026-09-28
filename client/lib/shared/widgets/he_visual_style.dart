/// **Migration bridge only — both values now render identically.**
///
/// Hidden Eleven has moved to one app-wide design system (Night Tactics /
/// `pf*` tokens — see `he_theme.dart`), sourced centrally via
/// `theme.dart`'s `ThemeData`. [HEButton] and [HETextField] both collapsed
/// their formerly-separate `standard`/`purpleFloodlights` rendering paths
/// onto that one system; this enum's two values no longer produce different
/// output.
///
/// It stays defined, and those widgets keep accepting it as a parameter,
/// purely so the ~40 existing call sites that pass either value (explicitly
/// or via the default) keep compiling unchanged while they're migrated off
/// it screen by screen. Once no call site passes [purpleFloodlights]
/// explicitly, delete this enum and the now-vestigial `style` parameter —
/// do not add new logic that branches on it.
enum HEVisualStyle { standard, purpleFloodlights }
