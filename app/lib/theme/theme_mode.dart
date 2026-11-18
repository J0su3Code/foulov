import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Jour, nuit ou automatique (selon le téléphone). Propre à ce téléphone, jamais envoyé.
class ThemeModeSetting extends ValueNotifier<ThemeMode> {
  ThemeModeSetting._() : super(ThemeMode.system);
  static final instance = ThemeModeSetting._();

  static const _store = FlutterSecureStorage();
  static const _key = 'foulov.theme_mode';

  Future<void> load() async {
    value = switch (await _store.read(key: _key)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> set(ThemeMode m) async {
    value = m;
    await _store.write(key: _key, value: m.name);
  }
}
