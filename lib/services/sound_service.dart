import 'package:flutter/foundation.dart';
import 'sound/sound_platform.dart';
import 'sound/sound_stub.dart'
    if (dart.library.js_interop) 'sound/sound_web.dart'
    if (dart.library.io) 'sound/sound_io.dart' as sound_impl;

/// Singleton service managing audio alert sounds and user sound preferences.
class SoundService {
  static final SoundService instance = SoundService._internal();
  SoundService._internal() {
    _platform = sound_impl.getSoundPlatform();
  }

  late final SoundPlatform _platform;

  /// Whether notification sound is enabled in user preferences.
  bool get isSoundEnabled => _platform.isSoundEnabled;

  /// Sets user preference for notification sound.
  void setSoundEnabled(bool enabled) {
    _platform.setSoundEnabled(enabled);
  }

  /// Toggles sound preference between ON and OFF. Returns new state.
  bool toggleSound() {
    final next = !isSoundEnabled;
    setSoundEnabled(next);
    return next;
  }

  /// Unlocks audio context on user gesture (click/touch).
  void unlockAudio() {
    _platform.unlockAudio();
  }

  /// Plays the notification sound if enabled by user and supported by browser.
  Future<void> playNotificationSound() async {
    try {
      await _platform.playNotificationSound();
    } catch (e) {
      debugPrint('[SoundService] playNotificationSound error: $e');
    }
  }
}
