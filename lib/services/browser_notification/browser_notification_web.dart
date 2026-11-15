import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'browser_notification_platform.dart';

class BrowserNotificationWeb implements BrowserNotificationPlatform {
  static const String _prefKey = 'actionflow_browser_notifications_enabled';
  final Set<String> _sessionShownTags = {};

  // Testing overrides
  NotificationPermissionStatus? _mockPermissionOverride;
  bool? _mockSupportedOverride;

  @override
  List<Map<String, dynamic>> get shownNotifications => const [];

  @override
  @visibleForTesting
  void setMockPermission(NotificationPermissionStatus? status) {
    _mockPermissionOverride = status;
  }

  @override
  @visibleForTesting
  void setMockSupported(bool? supported) {
    _mockSupportedOverride = supported;
  }

  @override
  bool get isSupported {
    if (_mockSupportedOverride != null) return _mockSupportedOverride!;
    try {
      // Accessing web.Notification.permission will throw if Notification API is not defined
      final _ = web.Notification.permission;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  NotificationPermissionStatus get permissionStatus {
    if (_mockPermissionOverride != null) return _mockPermissionOverride!;
    if (!isSupported) return NotificationPermissionStatus.unsupported;
    try {
      final p = web.Notification.permission;
      return switch (p) {
        'granted' => NotificationPermissionStatus.granted,
        'denied' => NotificationPermissionStatus.denied,
        'default' => NotificationPermissionStatus.defaultStatus,
        _ => NotificationPermissionStatus.defaultStatus,
      };
    } catch (_) {
      return NotificationPermissionStatus.unsupported;
    }
  }

  @override
  bool get isNotificationEnabled {
    if (!isSupported) return false;
    try {
      final val = web.window.localStorage.getItem(_prefKey);
      if (val == null) {
        // Defaults to true when permission has been granted
        return permissionStatus.isGranted;
      }
      return val == 'true';
    } catch (_) {
      return true;
    }
  }

  @override
  void setNotificationEnabled(bool enabled) {
    try {
      web.window.localStorage.setItem(_prefKey, enabled ? 'true' : 'false');
    } catch (_) {}
  }

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    if (!isSupported) return NotificationPermissionStatus.unsupported;

    final current = permissionStatus;
    if (current.isGranted) {
      setNotificationEnabled(true);
      return NotificationPermissionStatus.granted;
    }
    if (current.isDenied) {
      return NotificationPermissionStatus.denied;
    }

    try {
      final res = await web.Notification.requestPermission().toDart;
      final str = res.toDart;
      final status = switch (str) {
        'granted' => NotificationPermissionStatus.granted,
        'denied' => NotificationPermissionStatus.denied,
        _ => NotificationPermissionStatus.defaultStatus,
      };

      if (status.isGranted) {
        setNotificationEnabled(true);
      }
      return status;
    } catch (e) {
      debugPrint('[BrowserNotificationWeb] requestPermission error: $e');
      return permissionStatus;
    }
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

    // Deduplicate within session if tag provided
    if (tag != null && tag.isNotEmpty) {
      if (_sessionShownTags.contains(tag)) {
        return false;
      }
      _sessionShownTags.add(tag);
    }

    try {
      final options = web.NotificationOptions(
        body: body,
        icon: 'favicon.png',
        tag: tag ?? '',
      );

      final notif = web.Notification(title, options);
      if (onClick != null) {
        notif.onclick = ((web.Event e) {
          try {
            web.window.focus();
          } catch (_) {}
          onClick();
        }).toJS;
      }
      return true;
    } catch (e) {
      debugPrint('[BrowserNotificationWeb] showNotification error: $e');
      return false;
    }
  }

  @override
  void resetSessionCache() {
    _sessionShownTags.clear();
  }
}

BrowserNotificationPlatform getBrowserNotificationPlatform() =>
    BrowserNotificationWeb();
