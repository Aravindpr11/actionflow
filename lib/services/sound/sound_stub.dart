import 'sound_platform.dart';

class SoundPlatformImpl implements SoundPlatform {
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
    // No-op on stub
  }

  @override
  void unlockAudio() {
    // No-op on stub
  }
}

SoundPlatform getSoundPlatform() => SoundPlatformImpl();
