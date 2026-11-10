import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/notification_service.dart';
import '../../../services/sound_service.dart';
import '../models/app_notification.dart';

/// Interactive compact notification dropdown card displayed directly beneath the bell icon.
class NotificationDropdownOverlay extends StatefulWidget {
  final String userId;
  final String? organizationId;
  final bool isManager;
  final void Function(String actionId)? onActionTap;
  final void Function(AppNotification notification)? onNotificationTap;
  final VoidCallback? onViewAllNotifications;
  final VoidCallback? onClose;
  final VoidCallback? onUnreadCountChanged;
  final NotificationService? notificationService;
  final double? width;
  final double? maxHeight;

  const NotificationDropdownOverlay({
    super.key,
    required this.userId,
    this.organizationId,
    this.isManager = false,
    this.onActionTap,
    this.onNotificationTap,
    this.onViewAllNotifications,
    this.onClose,
    this.onUnreadCountChanged,
    this.notificationService,
    this.width,
    this.maxHeight,
  });

  @override
  State<NotificationDropdownOverlay> createState() =>
      _NotificationDropdownOverlayState();
}

class _NotificationDropdownOverlayState
    extends State<NotificationDropdownOverlay> {
  late final NotificationService _service;
  NotificationCategory _selectedCategory = NotificationCategory.all;
  bool _isLoading = true;
  String? _errorMessage;
  List<AppNotification> _notifications = [];
  bool _isMarkingAllRead = false;

  @override
  void initState() {
    super.initState();
    _service = widget.notificationService ?? NotificationService.instance;
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = await _service.getNotifications(userId: widget.userId);
      if (!mounted) return;
      setState(() {
        _notifications = items;
        _isLoading = false;
      });
      widget.onUnreadCountChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not load notifications: $e';
        _isLoading = false;
      });
    }
  }

  int get _unreadCount => _notifications.where((n) => !n.isRead).length;

  int _countForCategory(NotificationCategory cat) {
    if (cat == NotificationCategory.all) {
      return _notifications.length;
    }
    return _notifications.where((n) => n.category == cat).length;
  }

  List<AppNotification> get _filteredNotifications {
    if (_selectedCategory == NotificationCategory.all) {
      return _notifications;
    }
    return _notifications
        .where((n) => n.category == _selectedCategory)
        .toList();
  }

  Future<void> _handleMarkAllAsRead() async {
    if (_isMarkingAllRead || _unreadCount == 0) return;
    setState(() => _isMarkingAllRead = true);

    try {
      await _service.markAllAsRead(userId: widget.userId);
      if (!mounted) return;
      setState(() {
        _notifications = _notifications
            .map((n) => n.copyWith(isRead: true, readAt: DateTime.now()))
            .toList();
        _isMarkingAllRead = false;
      });
      widget.onUnreadCountChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isMarkingAllRead = false);
    }
  }

  Future<void> _handleNotificationTap(AppNotification notif) async {
    if (!notif.isRead) {
      // Optimistic read
      setState(() {
        final index = _notifications.indexWhere((n) => n.id == notif.id);
        if (index != -1) {
          _notifications[index] = notif.copyWith(
            isRead: true,
            readAt: DateTime.now(),
          );
        }
      });
      try {
        await _service.markAsRead(
          notificationId: notif.id,
          userId: widget.userId,
        );
        widget.onUnreadCountChanged?.call();
      } catch (_) {}
    }

    widget.onClose?.call();

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
      widget.onViewAllNotifications?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = AppTheme.cardBg(context);
    final borderColor = AppTheme.cardBorder(context);
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final keyboardHeight = mediaQuery.viewInsets.bottom;
    final bottomPadding = mediaQuery.padding.bottom;
    final topPadding = mediaQuery.padding.top;
    final safeAvailableHeight = math.max(180.0, screenHeight - keyboardHeight - bottomPadding - topPadding - 16.0);

    final double effectiveWidth = widget.width ??
        (screenWidth < 440 ? (screenWidth - 24.0).clamp(260.0, 390.0) : 390.0);
    final double effectiveMaxHeight = widget.maxHeight != null
        ? math.min(widget.maxHeight!, safeAvailableHeight)
        : math.min(520.0, math.max(180.0, safeAvailableHeight - 80.0));

    return Material(
      color: Colors.transparent,
      child: Container(
        width: effectiveWidth,
        constraints: BoxConstraints(maxHeight: effectiveMaxHeight),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withOpacity(0.5)
                  : Colors.black.withOpacity(0.12),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header
            _buildHeader(context, effectiveWidth),

            // 2. Filter Tabs
            _buildFilterTabs(context),

            const Divider(height: 1, thickness: 1),

            // 3. Scrollable List Body
            Flexible(
              child: _buildBody(context),
            ),

            // 4. Footer
            _buildFooter(context, effectiveWidth),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, double currentWidth) {
    final textPrimary = AppTheme.textPrimary(context);
    final unread = _unreadCount;
    final isCompact = currentWidth < 340;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.cardBorder(context), width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.notifications_active_outlined,
            size: 18,
            color: AppTheme.primaryColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    'Notifications',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (unread > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$unread New',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Mark all read button
          if (unread > 0)
            Tooltip(
              message: 'Mark all as read',
              child: InkWell(
                onTap: _isMarkingAllRead ? null : _handleMarkAllAsRead,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isMarkingAllRead)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        const Icon(
                          Icons.done_all_rounded,
                          size: 14,
                          color: AppTheme.primaryColor,
                        ),
                      if (!isCompact) ...[
                        const SizedBox(width: 4),
                        Text(
                          'Mark read',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          // Sound Toggle Button
          Tooltip(
            message: SoundService.instance.isSoundEnabled
                ? 'Sound Alert: ON (Click to mute)'
                : 'Sound Alert: MUTED (Click to enable)',
            child: InkWell(
              onTap: () {
                setState(() {
                  SoundService.instance.toggleSound();
                });
              },
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  SoundService.instance.isSoundEnabled
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  size: 16,
                  color: SoundService.instance.isSoundEnabled
                      ? AppTheme.primaryColor
                      : AppTheme.textSecondary(context),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Close button
          Tooltip(
            message: 'Close',
            child: InkWell(
              onTap: widget.onClose,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AppTheme.inputFill(context).withOpacity(0.4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: NotificationCategory.values.map((cat) {
            final isSelected = _selectedCategory == cat;
            final count = _countForCategory(cat);

            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                onTap: () => setState(() => _selectedCategory = cat),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryColor
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primaryColor
                          : AppTheme.cardBorder(context),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        cat.label,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected
                              ? Colors.white
                              : AppTheme.textPrimary(context),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white.withOpacity(0.25)
                              : AppTheme.cardBorder(context),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? Colors.white
                                : AppTheme.textSecondary(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 180,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }

    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 32, color: AppTheme.errorColor),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary(context),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _fetchNotifications,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final list = _filteredNotifications;
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.inputFill(context),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                size: 28,
                color: AppTheme.textMuted(context),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'No notifications in this tab',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "You're completely caught up!",
              style: TextStyle(
                fontSize: 11.5,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      shrinkWrap: true,
      itemCount: list.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        thickness: 0.8,
        color: AppTheme.cardBorder(context).withOpacity(0.6),
      ),
      itemBuilder: (context, index) {
        final notif = list[index];
        return _NotificationTile(
          notification: notif,
          onTap: () => _handleNotificationTap(notif),
        );
      },
    );
  }

  Widget _buildFooter(BuildContext context, double currentWidth) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.inputFill(context).withOpacity(0.5),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
        border: Border(
          top: BorderSide(color: AppTheme.cardBorder(context), width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${_notifications.length} Alerts',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary(context),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () {
              widget.onClose?.call();
              widget.onViewAllNotifications?.call();
            },
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currentWidth < 420 ? 'View All' : 'View All Notifications',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: AppTheme.primaryColor,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final themeColor = notification.themeColor;
    final isUnread = !notification.isRead;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        color: isUnread
            ? AppTheme.primaryColor.withOpacity(0.04)
            : Colors.transparent,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Event Icon
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: themeColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                notification.iconData,
                size: 17,
                color: themeColor,
              ),
            ),
            const SizedBox(width: 10),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: isUnread
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: AppTheme.textPrimary(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        notification.timeAgo,
                        style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.textMuted(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notification.message,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isUnread
                          ? AppTheme.textPrimary(context).withOpacity(0.85)
                          : AppTheme.textSecondary(context),
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (notification.actionId != null &&
                      notification.actionId!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: themeColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Action: ${notification.actionId}',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: themeColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Unread Blue Dot
            if (isUnread)
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppTheme.primaryColor,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A comprehensive bell trigger button with overlay management.
///
/// Anchors the [NotificationDropdownOverlay] directly beneath the bell icon.
/// Supports clicking to toggle, outside click dismissal, and Escape key dismissal.
class NotificationBellButton extends StatefulWidget {
  final String userId;
  final String? organizationId;
  final bool isManager;
  final int? unreadCount;
  final void Function(String actionId)? onActionTap;
  final void Function(AppNotification notification)? onNotificationTap;
  final VoidCallback? onViewAllNotifications;
  final VoidCallback? onUnreadCountChanged;
  final NotificationService? notificationService;
  final Widget Function(
    BuildContext context,
    VoidCallback toggleDropdown,
    int unreadCount,
    bool isOpen,
  )? customBuilder;

  const NotificationBellButton({
    super.key,
    required this.userId,
    this.organizationId,
    this.isManager = false,
    this.unreadCount,
    this.onActionTap,
    this.onNotificationTap,
    this.onViewAllNotifications,
    this.onUnreadCountChanged,
    this.notificationService,
    this.customBuilder,
  });

  @override
  State<NotificationBellButton> createState() => _NotificationBellButtonState();
}

class _NotificationBellButtonState extends State<NotificationBellButton> {
  OverlayEntry? _overlayEntry;
  late final NotificationService _service;
  int _unreadCount = 0;
  StreamSubscription<AppNotification>? _notifSub;

  @override
  void initState() {
    super.initState();
    _service = widget.notificationService ?? NotificationService.instance;
    _unreadCount = widget.unreadCount ?? 0;
    _fetchUnreadCount();

    // Listen for new in-app alerts in real-time
    _notifSub = _service.onNotificationReceived.listen((notif) {
      if (notif.userId == widget.userId && !notif.isRead) {
        if (mounted) {
          setState(() => _unreadCount++);
          widget.onUnreadCountChanged?.call();
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant NotificationBellButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.unreadCount != null && widget.unreadCount != oldWidget.unreadCount) {
      _unreadCount = widget.unreadCount!;
    }
    if (widget.userId != oldWidget.userId) {
      _fetchUnreadCount();
    }
  }

  @override
  void dispose() {
    _closeDropdown(updateState: false);
    _notifSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchUnreadCount() async {
    try {
      final count = await _service.getUnreadCount(userId: widget.userId);
      if (mounted) {
        setState(() => _unreadCount = count);
        widget.onUnreadCountChanged?.call();
      }
    } catch (_) {}
  }

  bool get isOpen => _overlayEntry != null;

  void _toggleDropdown() {
    if (isOpen) {
      _closeDropdown();
    } else {
      _openDropdown();
    }
  }

  void _openDropdown() {
    if (_overlayEntry != null) return;

    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (ctx) {
        final buttonMediaQuery = MediaQuery.maybeOf(context);
        final overlayMediaQuery = MediaQuery.maybeOf(ctx);
        final mediaQuery = buttonMediaQuery ?? overlayMediaQuery ?? const MediaQueryData();
        final double screenWidth = [
          if (buttonMediaQuery != null) buttonMediaQuery.size.width,
          if (overlayMediaQuery != null) overlayMediaQuery.size.width,
        ].fold<double>(mediaQuery.size.width, math.min);
        final double screenHeight = [
          if (buttonMediaQuery != null) buttonMediaQuery.size.height,
          if (overlayMediaQuery != null) overlayMediaQuery.size.height,
        ].fold<double>(mediaQuery.size.height, math.min);

        // Obtain button's global coordinates
        final renderBox = context.findRenderObject() as RenderBox?;
        final buttonOffset =
            (renderBox != null && renderBox.hasSize && renderBox.attached)
                ? renderBox.localToGlobal(Offset.zero)
                : Offset(screenWidth - 48.0, 60.0);
        final buttonSize =
            (renderBox != null && renderBox.hasSize && renderBox.attached)
                ? renderBox.size
                : const Size(38.0, 38.0);

        // Safe horizontal padding from screen edges
        const double safeMargin = 12.0;
        final double maxAllowedWidth = screenWidth - (safeMargin * 2);

        // Responsive width calculation:
        // On mobile / narrow viewports (< 440px), occupy the available width minus margins.
        // On wider viewports (desktop/tablet), standard width of 390px.
        final double panelWidth = screenWidth < 440
            ? maxAllowedWidth.clamp(260.0, 390.0)
            : math.min(390.0, maxAllowedWidth);

        // Anchor horizontally relative to the bell button:
        // Try aligning the right edge of the panel with the right edge of the button.
        final double buttonRight = buttonOffset.dx + buttonSize.width;
        final double desiredLeft = buttonRight - panelWidth;

        // Clamp left coordinate so it NEVER extends beyond the left (safeMargin) or right screen boundaries!
        final double maxLeft = screenWidth - panelWidth - safeMargin;
        final double safeLeft = desiredLeft.clamp(
          safeMargin,
          maxLeft < safeMargin ? safeMargin : maxLeft,
        );

        // Safe-area and keyboard insets handling
        final double keyboardHeight = math.max(
          buttonMediaQuery?.viewInsets.bottom ?? 0.0,
          overlayMediaQuery?.viewInsets.bottom ?? 0.0,
        );
        final double bottomPadding = math.max(
          buttonMediaQuery?.padding.bottom ?? 0.0,
          overlayMediaQuery?.padding.bottom ?? 0.0,
        );
        final double topPadding = math.max(
          buttonMediaQuery?.padding.top ?? 0.0,
          overlayMediaQuery?.padding.top ?? 0.0,
        );

        // Vertical positioning:
        final double topUnderButton = buttonOffset.dy + buttonSize.height + 8.0;
        final double availableHeightBelow =
            screenHeight - topUnderButton - bottomPadding - keyboardHeight - 16.0;

        double top = topUnderButton;
        double maxPanelHeight;
        if (availableHeightBelow < 220 &&
            (buttonOffset.dy - topPadding) > availableHeightBelow) {
          final double availableHeightAbove =
              buttonOffset.dy - topPadding - 16.0;
          maxPanelHeight =
              math.min(520.0, math.max(180.0, availableHeightAbove));
          top = (buttonOffset.dy - maxPanelHeight - 8.0)
              .clamp(topPadding + 8.0, screenHeight - 60.0);
        } else {
          maxPanelHeight =
              math.min(520.0, math.max(180.0, availableHeightBelow));
        }

        return Stack(
          children: [
            // 1. Transparent full-screen modal barrier to catch clicks outside
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _closeDropdown,
                child: const SizedBox.expand(),
              ),
            ),

            // 2. Escape key listener
            Positioned.fill(
              child: FocusScope(
                autofocus: true,
                child: KeyboardListener(
                  focusNode: FocusNode()..requestFocus(),
                  onKeyEvent: (event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.escape) {
                      _closeDropdown();
                    }
                  },
                  child: const SizedBox.shrink(),
                ),
              ),
            ),

            // 3. Dropdown safely positioned completely inside the viewport
            Positioned(
              left: safeLeft,
              top: top,
              child: SizedBox(
                width: panelWidth,
                child: NotificationDropdownOverlay(
                  width: panelWidth,
                  maxHeight: maxPanelHeight,
                  userId: widget.userId,
                  organizationId: widget.organizationId,
                  isManager: widget.isManager,
                  notificationService: _service,
                  onActionTap: (actionId) {
                    _closeDropdown();
                    widget.onActionTap?.call(actionId);
                  },
                  onNotificationTap: (notif) {
                    _closeDropdown();
                    widget.onNotificationTap?.call(notif);
                  },
                  onViewAllNotifications: () {
                    _closeDropdown();
                    widget.onViewAllNotifications?.call();
                  },
                  onClose: _closeDropdown,
                  onUnreadCountChanged: () {
                    _fetchUnreadCount();
                    widget.onUnreadCountChanged?.call();
                  },
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(entry);
    setState(() => _overlayEntry = entry);
  }

  void _closeDropdown({bool updateState = true}) {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (updateState && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.customBuilder != null
        ? widget.customBuilder!(context, _toggleDropdown, _unreadCount, isOpen)
        : _defaultBellButton(context);
  }

  Widget _defaultBellButton(BuildContext context) {
    return InkWell(
      onTap: _toggleDropdown,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 38,
        width: 38,
        decoration: BoxDecoration(
          color: isOpen
              ? AppTheme.primaryColor.withOpacity(0.1)
              : AppTheme.cardBg(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isOpen
                ? AppTheme.primaryColor
                : AppTheme.cardBorder(context),
            width: isOpen ? 1.5 : 1,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              isOpen
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              size: 20,
              color: isOpen
                  ? AppTheme.primaryColor
                  : AppTheme.textSecondary(context),
            ),
            if (_unreadCount > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$_unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

