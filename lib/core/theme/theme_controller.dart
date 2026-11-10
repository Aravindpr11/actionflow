import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Central controller for application theme state and offline local persistence.
class ThemeController extends ChangeNotifier {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  ThemeMode _themeMode = ThemeMode.light;

  /// Current theme mode (defaults to [ThemeMode.light]).
  ThemeMode get themeMode => _themeMode;

  /// Whether dark theme is currently active.
  bool get isDark => _themeMode == ThemeMode.dark;

  /// File path used for offline local persistence.
  static const String _storageFileName = '.actionflow_theme.json';

  /// Initializes and loads the saved theme preference from local storage.
  Future<void> loadSavedTheme() async {
    try {
      if (kIsWeb) return;
      final file = File(_storageFileName);
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        final savedMode = data['themeMode'] as String?;
        if (savedMode == 'dark') {
          _themeMode = ThemeMode.dark;
          notifyListeners();
        } else if (savedMode == 'light') {
          _themeMode = ThemeMode.light;
          notifyListeners();
        } else if (savedMode == 'system') {
          _themeMode = ThemeMode.system;
          notifyListeners();
        }
      }
    } catch (_) {
      // In-memory fallback if file I/O is unavailable (e.g. sandbox/restricted environments)
    }
  }

  /// Sets the active [ThemeMode] and persists the choice locally.
  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    _persistThemeLocally(mode);
  }

  /// Toggles between [ThemeMode.light] and [ThemeMode.dark].
  void toggleTheme() {
    if (_themeMode == ThemeMode.dark) {
      setThemeMode(ThemeMode.light);
    } else {
      setThemeMode(ThemeMode.dark);
    }
  }

  Future<void> _persistThemeLocally(ThemeMode mode) async {
    try {
      if (kIsWeb) return;
      final file = File(_storageFileName);
      final modeStr = mode == ThemeMode.dark
          ? 'dark'
          : (mode == ThemeMode.light ? 'light' : 'system');
      await file.writeAsString(jsonEncode({'themeMode': modeStr}));
    } catch (_) {
      // Fail silently for read-only / test environments
    }
  }
}
