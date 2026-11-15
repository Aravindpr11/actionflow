import 'package:flutter/foundation.dart';
import 'browser_notification/browser_notification_platform.dart';
import 'browser_notification/browser_notification_stub.dart'
    if (dart.library.js_interop) 'browser_notification/browser_notification_web.dart'
    if (dart.library.io) 'browser_notification/browser_notification_io.dart' as bn_impl;

export 'browser_notification/browser_notification_platform.dart'
    show NotificationPermissionStatus;

/// Singleton service managing browser desktop notifications and permission states.
class BrowserNotificationService {
  static final BrowserNotificationService instance =
      BrowserNotificationService._internal();

  BrowserNotificationService._internal() {
    _platform = bn_impl.getBrowserNotificationPlatform();
  }

  late final BrowserNotificationPlatform _platform;

  /// Whether browser Notification API is supported on the current platform/browser.
  bool get isSupported => _platform.isSupported;

  /// Current browser notification permission status.
  NotificationPermissionStatus get permissionStatus => _platform.permissionStatus;

  /// Whether browser desktop notifications are enabled in user settings.
  bool get isNotificationEnabled => _platform.isNotificationEnabled;

  /// Updates user preference for browser desktop notifications.
  void setNotificationEnabled(bool enabled) {
    _platform.setNotificationEnabled(enabled);
  }

  /// Toggles desktop notification preference between ON and OFF. Returns next state.
  bool toggleNotificationEnabled() {
    final next = !isNotificationEnabled;
    setNotificationEnabled(next);
    return next;
  }

  /// Requests permission from the browser upon an explicit user interaction.
  Future<NotificationPermissionStatus> requestPermission() async {
    return _platform.requestPermission();
  }

  /// Displays an operating-system desktop notification if permitted and enabled.
  Future<bool> showNotification({
    required String title,
    required String body,
    String? tag,
    String? actionId,
    String? requestId,
    VoidCallback? onClick,
  }) async {
    return _platform.showNotification(
      title: title,
      body: body,
      tag: tag,
      actionId: actionId,
      requestId: requestId,
      onClick: onClick,
    );
  }

  /// Resets in-memory session deduplication cache (e.g. on logout or in tests).
  void resetSessionCache() {
    _platform.resetSessionCache();
  }

  // --- Testing & Mocking Hooks ---

  @visibleForTesting
  void setMockPermission(NotificationPermissionStatus? status) {
    _platform.setMockPermission(status);
  }

  @visibleForTesting
  void setMockSupported(bool? supported) {
    _platform.setMockSupported(supported);
  }

  @visibleForTesting
  List<Map<String, dynamic>> get shownNotificationsForTesting =>
      _platform.shownNotifications;
}
