import 'sound_platform.dart';

class SoundPlatformImpl implements SoundPlatform {
  bool _enabled = true;

  @override
  bool get isSoundEnabled => _enabled;

  @override
  void setSoundEnabled(bool enabled) {
    _enabled = enabled;
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
