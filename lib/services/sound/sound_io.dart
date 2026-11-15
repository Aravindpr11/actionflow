import 'sound_platform.dart';

class SoundPlatformIO implements SoundPlatform {
  bool _enabled = true;
  double _volume = 0.8;

  @override
  bool get isSoundEnabled => _enabled;

  @override
  void setSoundEnabled(bool enabled) {
    _enabled = enabled;
  }

  @override
  double get soundVolume => _volume;

  @override
  void setSoundVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
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
