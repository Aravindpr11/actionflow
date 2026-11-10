import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/notification_service.dart';
import '../models/app_notification.dart';

/// Automatic on-screen quick alert toast displayed near the top-right
/// when a new notification arrives during an active session.
class QuickAlertToast extends StatefulWidget {
  final AppNotification notification;
  final void Function(String actionId)? onActionTap;
  final void Function(AppNotification notification)? onNotificationTap;
  final VoidCallback? onView;
  final VoidCallback onDismiss;
  final Duration duration;

  const QuickAlertToast({
    super.key,
    required this.notification,
    this.onActionTap,
    this.onNotificationTap,
    this.onView,
    required this.onDismiss,
    this.duration = const Duration(seconds: 6),
  });

  /// Displays a floating quick alert toast using the [Overlay].
  static OverlayEntry show(
    BuildContext context, {
    required AppNotification notification,
    void Function(String actionId)? onActionTap,
    void Function(AppNotification notification)? onNotificationTap,
    VoidCallback? onView,
    Duration duration = const Duration(seconds: 6),
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (ctx) {
        return Positioned(
          bottom: 24,
          right: 24,
          child: QuickAlertToast(
            notification: notification,
            onActionTap: onActionTap,
            onNotificationTap: onNotificationTap,
            onView: onView,
            duration: duration,
            onDismiss: () {
              entry.remove();
            },
          ),
        );
      },
    );

    overlay.insert(entry);
    return entry;
  }

  @override
  State<QuickAlertToast> createState() => _QuickAlertToastState();
}

class _QuickAlertToastState extends State<QuickAlertToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.3, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );

    _animController.forward();

    // Auto-dismiss timer
    _dismissTimer = Timer(widget.duration, () {
      _handleDismiss();
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleDismiss() async {
    if (!mounted) return;
    _dismissTimer?.cancel();
    await _animController.reverse();
    widget.onDismiss();
  }

  Future<void> _handleView() async {
    _dismissTimer?.cancel();
    final notif = widget.notification;

    try {
      if (!notif.isRead) {
        await NotificationService.instance.markAsRead(
          notificationId: notif.id,
          userId: notif.userId,
        );
      }
    } catch (_) {}

    await _handleDismiss();

    if (widget.onNotificationTap != null) {
      widget.onNotificationTap!(notif);
      return;
    }

    final targetId = notif.effectiveActionIdentifier ?? notif.actionId;
    if (targetId != null &&
        targetId.isNotEmpty &&
        widget.onActionTap != null) {
      widget.onActionTap!(targetId);
    } else {
      widget.onView?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = widget.notification.themeColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = AppTheme.cardBg(context);
    final borderColor = AppTheme.cardBorder(context);

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 380,
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.55)
                      : Colors.black.withValues(alpha: 0.14),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left: Icon Circle
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: themeColor.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            widget.notification.iconData,
                            size: 19,
                            color: themeColor,
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Center: Title + Message + Time
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      widget.notification.title,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary(context),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Just now',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppTheme.textMuted(context),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                widget.notification.message,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: AppTheme.textSecondary(context),
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (widget.notification.actionId != null &&
                                  widget.notification.actionId!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Action: ${widget.notification.actionId}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: themeColor,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(width: 6),

                        // Right: Close button
                        InkWell(
                          onTap: _handleDismiss,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Action Strip
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    color: AppTheme.inputFill(context).withValues(alpha: 0.5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _handleDismiss,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'Dismiss',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        ElevatedButton.icon(
                          onPressed: _handleView,
                          icon: const Icon(Icons.arrow_forward_rounded, size: 12),
                          label: const Text('View'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// In-app listener widget that listens for newly received notifications
/// and displays a [QuickAlertToast] overlay automatically.
///
/// Also performs an initial unread check upon login / session start,
/// showing a compact alert for the latest unread notification if any exist,
/// while preventing duplicate popups across navigation and widget rebuilds.
class QuickAlertListener extends StatefulWidget {
  final String userId;
  final Widget child;
  final void Function(String actionId)? onActionTap;
  final void Function(AppNotification notification)? onNotificationTap;
  final VoidCallback? onViewNotifications;
  final bool enabled;
  final NotificationService? notificationService;

  const QuickAlertListener({
    super.key,
    required this.userId,
    required this.child,
    this.onActionTap,
    this.onNotificationTap,
    this.onViewNotifications,
    this.enabled = true,
    this.notificationService,
  });

  /// Set of user IDs that have already been checked for unread notifications in the current session.
  static final Set<String> _checkedSessions = {};

  /// Set of user IDs currently performing a fetch in-flight to prevent duplicate concurrent calls.
  static final Set<String> _inFlightFetches = {};

  /// Resets the login notification check for a specific user, or all users if [userId] is null.
  /// Call upon user logout so subsequent logins trigger the alert.
  static void resetSession([String? userId]) {
    if (userId != null) {
      _checkedSessions.remove(userId);
      _inFlightFetches.remove(userId);
    } else {
      _checkedSessions.clear();
      _inFlightFetches.clear();
    }
  }

  /// Clears all checked sessions.
  static void clearSessions() {
    _checkedSessions.clear();
    _inFlightFetches.clear();
  }

  /// Whether the session has already been checked for [userId].
  static bool hasCheckedSession(String userId) => _checkedSessions.contains(userId);

  /// Allows retrying the unread notification check for [userId] if an earlier attempt failed.
  static void retryCheck([String? userId]) {
    if (userId != null) {
      _checkedSessions.remove(userId);
      _inFlightFetches.remove(userId);
    } else {
      _checkedSessions.clear();
      _inFlightFetches.clear();
    }
  }

  @override
  State<QuickAlertListener> createState() => _QuickAlertListenerState();
}

class _QuickAlertListenerState extends State<QuickAlertListener> {
  StreamSubscription<AppNotification>? _subscription;
  NotificationService get _notifService =>
      widget.notificationService ?? NotificationService.instance;

  @override
  void initState() {
    super.initState();
    _subscribe();
    _scheduleLoginUnreadCheck();
  }

  @override
  void didUpdateWidget(covariant QuickAlertListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.enabled != widget.enabled) {
      _subscription?.cancel();
      _subscribe();
      _scheduleLoginUnreadCheck();
    } else if (!QuickAlertListener.hasCheckedSession(widget.userId)) {
      _scheduleLoginUnreadCheck();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _subscribe() {
    if (!widget.enabled || widget.userId.isEmpty) return;

    _subscription = _notifService.onNotificationReceived.listen(
      (notif) {
        if (!mounted || !widget.enabled) return;
        if (notif.userId == widget.userId && !notif.isRead) {
          QuickAlertToast.show(
            context,
            notification: notif,
            onActionTap: widget.onActionTap,
            onNotificationTap: widget.onNotificationTap,
            onView: widget.onViewNotifications,
          );
        }
      },
    );
  }

  void _scheduleLoginUnreadCheck() {
    if (!widget.enabled || widget.userId.isEmpty) return;
    if (QuickAlertListener.hasCheckedSession(widget.userId)) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUnreadOnLogin();
    });
  }

  Future<void> _checkUnreadOnLogin() async {
    if (!mounted || !widget.enabled || widget.userId.isEmpty) return;
    if (QuickAlertListener.hasCheckedSession(widget.userId)) return;
    if (QuickAlertListener._inFlightFetches.contains(widget.userId)) return;

    QuickAlertListener._inFlightFetches.add(widget.userId);

    try {
      final notifs = await _notifService.getNotifications(
        userId: widget.userId,
      );
      if (!mounted) return;

      // Mark session as successfully checked ONLY after the fetch succeeds
      QuickAlertListener._checkedSessions.add(widget.userId);

      final unread = notifs.where((n) => !n.isRead).toList();
      if (unread.isEmpty) return;

      final latest = unread.first;
      final displayNotification = unread.length > 1
          ? latest.copyWith(
              message: '${latest.message} (+${unread.length - 1} more unread)',
            )
          : latest;

      QuickAlertToast.show(
        context,
        notification: displayNotification,
        onActionTap: widget.onActionTap,
        onNotificationTap: widget.onNotificationTap,
        onView: widget.onViewNotifications,
      );
    } catch (e) {
      debugPrint('[QuickAlertListener] checkUnreadOnLogin error: $e');
      // Ensure the session is NOT marked as checked on failure so retries can occur
      QuickAlertListener._checkedSessions.remove(widget.userId);
    } finally {
      QuickAlertListener._inFlightFetches.remove(widget.userId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

