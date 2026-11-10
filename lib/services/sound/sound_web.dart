import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'sound_platform.dart';

class SoundPlatformWeb implements SoundPlatform {
  static const String _prefKey = 'actionflow_notification_sound_enabled';
  web.AudioContext? _audioContext;
  bool _unlocked = false;

  SoundPlatformWeb() {
    _initAutoplayUnlock();
  }

  @override
  bool get isSoundEnabled {
    try {
      final val = web.window.localStorage.getItem(_prefKey);
      if (val == null) return true; // Default ON
      return val == 'true';
    } catch (_) {
      return true;
    }
  }

  @override
  void setSoundEnabled(bool enabled) {
    try {
      web.window.localStorage.setItem(_prefKey, enabled ? 'true' : 'false');
    } catch (_) {}
  }

  void _initAutoplayUnlock() {
    try {
      final doc = web.document;
      final callback = ((web.Event e) {
        unlockAudio();
      }).toJS;

      doc.addEventListener(
        'pointerdown',
        callback,
        web.AddEventListenerOptions(once: true),
      );
      doc.addEventListener(
        'touchstart',
        callback,
        web.AddEventListenerOptions(once: true),
      );
      doc.addEventListener(
        'click',
        callback,
        web.AddEventListenerOptions(once: true),
      );
      doc.addEventListener(
        'keydown',
        callback,
        web.AddEventListenerOptions(once: true),
      );
    } catch (_) {}
  }

  @override
  void unlockAudio() {
    if (_unlocked && _audioContext != null && _audioContext!.state == 'running') {
      return;
    }
    try {
      _audioContext ??= web.AudioContext();
      if (_audioContext!.state == 'suspended') {
        _audioContext!.resume();
      }
      _unlocked = true;
    } catch (_) {}
  }

  @override
  Future<void> playNotificationSound() async {
    if (!isSoundEnabled) return;

    try {
      _audioContext ??= web.AudioContext();
      if (_audioContext!.state == 'suspended') {
        await _audioContext!.resume().toDart;
      }

      final ctx = _audioContext!;
      final now = ctx.currentTime;

      // Note 1: 880 Hz (A5), soft chime
      final osc1 = ctx.createOscillator();
      final gain1 = ctx.createGain();
      osc1.type = 'sine';
      osc1.frequency.setValueAtTime(880, now);
      gain1.gain.setValueAtTime(0.12, now);
      gain1.gain.exponentialRampToValueAtTime(0.001, now + 0.18);
      osc1.connect(gain1);
      gain1.connect(ctx.destination);
      osc1.start(now);
      osc1.stop(now + 0.18);

      // Note 2: 1320 Hz (E6), harmonic bell resolution
      final osc2 = ctx.createOscillator();
      final gain2 = ctx.createGain();
      osc2.type = 'sine';
      osc2.frequency.setValueAtTime(1320, now + 0.10);
      gain2.gain.setValueAtTime(0.15, now + 0.10);
      gain2.gain.exponentialRampToValueAtTime(0.001, now + 0.38);
      osc2.connect(gain2);
      gain2.connect(ctx.destination);
      osc2.start(now + 0.10);
      osc2.stop(now + 0.38);
    } catch (_) {
      // Gracefully handle browser audio restrictions
    }
  }
}

SoundPlatform getSoundPlatform() => SoundPlatformWeb();
