import 'package:flutter/foundation.dart';
import 'browser_notification_platform.dart';

/// In-memory stub implementation for testing and non-web platforms.
class BrowserNotificationStub implements BrowserNotificationPlatform {
  bool _supported = true;
  NotificationPermissionStatus _permission = NotificationPermissionStatus.defaultStatus;
  bool _enabled = true;
  final List<Map<String, dynamic>> _shownNotifications = [];

  @override
  List<Map<String, dynamic>> get shownNotifications => List.unmodifiable(_shownNotifications);

  @override
  void setMockSupported(bool? supported) {
    _supported = supported ?? true;
  }

  @override
  void setMockPermission(NotificationPermissionStatus? status) {
    _permission = status ?? NotificationPermissionStatus.defaultStatus;
  }

  @override
  bool get isSupported => _supported;

  @override
  NotificationPermissionStatus get permissionStatus =>
      _supported ? _permission : NotificationPermissionStatus.unsupported;

  @override
  bool get isNotificationEnabled => _enabled;

  @override
  void setNotificationEnabled(bool enabled) {
    _enabled = enabled;
  }

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    if (!_supported) return NotificationPermissionStatus.unsupported;
    if (_permission == NotificationPermissionStatus.denied) {
      return NotificationPermissionStatus.denied;
    }
    // Simulate user granting permission on prompt
    _permission = NotificationPermissionStatus.granted;
    _enabled = true;
    return NotificationPermissionStatus.granted;
  }

  @override
  Future<bool> showNotification({
    required String title,
    required String body,
    String? tag,
    String? actionId,
    String? requestId,
    VoidCallback? onClick,
  }) async {
    if (!isSupported) return false;
    if (permissionStatus != NotificationPermissionStatus.granted) return false;
    if (!isNotificationEnabled) return false;

    _shownNotifications.add({
      'title': title,
      'body': body,
      'tag': tag,
      'actionId': actionId,
      'requestId': requestId,
      'timestamp': DateTime.now(),
    });

    return true;
  }

  @override
  void resetSessionCache() {
    _shownNotifications.clear();
  }
}

BrowserNotificationPlatform getBrowserNotificationPlatform() => BrowserNotificationStub();
