/// Abstract platform interface for notification sound playback and preferences.
abstract class SoundPlatform {
  /// Whether notification sound is enabled by user preference.
  bool get isSoundEnabled;

  /// Update user preference for notification sound.
  void setSoundEnabled(bool enabled);

  /// Sound volume between 0.0 (silent) and 1.0 (full). Defaults to 0.8.
  double get soundVolume;

  /// Update user preference for sound volume.
  void setSoundVolume(double volume);

  /// Play the notification sound tone.
  Future<void> playNotificationSound();

  /// Attempt unlocking audio playback on user gesture if restricted by browser autoplay.
  void unlockAudio();
}
