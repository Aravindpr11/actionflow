/// Abstract platform interface for notification sound playback and preferences.
abstract class SoundPlatform {
  /// Whether notification sound is enabled by user preference.
  bool get isSoundEnabled;

  /// Update user preference for notification sound.
  void setSoundEnabled(bool enabled);

  /// Play the notification sound tone.
  Future<void> playNotificationSound();

  /// Attempt unlocking audio playback on user gesture if restricted by browser autoplay.
  void unlockAudio();
}
