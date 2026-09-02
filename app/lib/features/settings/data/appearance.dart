import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which palette the student has asked for.
///
/// Stored on the device rather than in their Supabase profile: it is a
/// property of the phone in their hand, not of their account. A student on a
/// bright bus and the same student in bed at night want different answers, and
/// syncing it across devices would fight that.
enum Appearance {
  system,
  light,
  dark;

  static Appearance fromWire(String? value) => Appearance.values.firstWhere(
    (a) => a.name == value,
    orElse: () => Appearance.system,
  );

  String get label => switch (this) {
    Appearance.system => 'Match my phone',
    Appearance.light => 'Light',
    Appearance.dark => 'Dark',
  };

  String get blurb => switch (this) {
    Appearance.system => 'Follows your phone, including its night schedule',
    Appearance.light => 'Always light, whatever your phone is set to',
    Appearance.dark => 'Always dark, whatever your phone is set to',
  };

  ThemeMode get mode => switch (this) {
    Appearance.system => ThemeMode.system,
    Appearance.light => ThemeMode.light,
    Appearance.dark => ThemeMode.dark,
  };
}

const _key = 'tack.appearance';

/// Reads and writes the choice, and tells the app which palette to paint.
class AppearanceController extends AsyncNotifier<Appearance> {
  @override
  Future<Appearance> build() async {
    final prefs = await SharedPreferences.getInstance();
    return Appearance.fromWire(prefs.getString(_key));
  }

  Future<void> choose(Appearance appearance) async {
    // Set optimistically: the whole tree rebuilds on this value, and waiting
    // for a disk write before repainting shows a visible stutter on the tap.
    state = AsyncData(appearance);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, appearance.name);
  }
}

final appearanceProvider =
    AsyncNotifierProvider<AppearanceController, Appearance>(
      AppearanceController.new,
    );
