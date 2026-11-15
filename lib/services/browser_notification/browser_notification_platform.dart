import 'package:flutter/foundation.dart';

/// Represents the current browser notification permission status.
enum NotificationPermissionStatus {
  /// User has granted notification permission.
  granted,

  /// User or browser settings have denied / blocked notification permission.
  denied,

  /// User has not yet been prompted for permission (default).
  defaultStatus,

  /// Notification API is not supported in this browser or platform.
  unsupported;

  bool get isGranted => this == NotificationPermissionStatus.granted;
  bool get isDenied => this == NotificationPermissionStatus.denied;
  bool get isDefault => this == NotificationPermissionStatus.defaultStatus;
  bool get isUnsupported => this == NotificationPermissionStatus.unsupported;

  /// User-facing status label.
  String get label => switch (this) {
        NotificationPermissionStatus.granted => 'Granted',
        NotificationPermissionStatus.denied => 'Denied (Blocked)',
        NotificationPermissionStatus.defaultStatus => 'Not Requested',
        NotificationPermissionStatus.unsupported => 'Unsupported',
      };
}

/// Abstract platform interface for Browser Desktop Notifications.
abstract class BrowserNotificationPlatform {
  /// Whether browser Notification API is supported on this platform.
  bool get isSupported;

  /// Current permission status (granted, denied, defaultStatus, unsupported).
  NotificationPermissionStatus get permissionStatus;

  /// Whether browser desktop notifications are enabled by user in ActionFlow preferences.
  bool get isNotificationEnabled;

  /// Updates user preference for browser desktop notifications.
  void setNotificationEnabled(bool enabled);

  /// Requests permission from the browser upon an explicit user interaction.
  Future<NotificationPermissionStatus> requestPermission();

  /// Displays an operating-system desktop notification if permitted and enabled.
  Future<bool> showNotification({
    required String title,
    required String body,
    String? tag,
    String? actionId,
    String? requestId,
    VoidCallback? onClick,
  });

  /// Resets in-memory session deduplication cache (e.g. on logout or in tests).
  void resetSessionCache();

  /// Test hook to simulate permission status.
  void setMockPermission(NotificationPermissionStatus? status);

  /// Test hook to simulate browser support.
  void setMockSupported(bool? supported);

  /// Test hook retrieving notifications shown in memory.
  List<Map<String, dynamic>> get shownNotifications;
}
