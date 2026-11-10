import 'sound_platform.dart';

class SoundPlatformIO implements SoundPlatform {
  bool _enabled = true;

  @override
  bool get isSoundEnabled => _enabled;

  @override
  void setSoundEnabled(bool enabled) {
    _enabled = enabled;
  }

  @override
  Future<void> playNotificationSound() async {
    // Simulated in native/test environment
  }

  @override
  void unlockAudio() {
    // No-op on native/test environment
  }
}

SoundPlatform getSoundPlatform() => SoundPlatformIO();
