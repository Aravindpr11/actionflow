import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/notification_service.dart';
import '../../../services/sound_service.dart';
import '../models/app_notification.dart';

/// Interactive Notification Centre view for both Manager and Staff Portals.
///
/// Features:
/// - Filter by "All" or "Unread"
/// - Shows real-time in-app alerts (Action Assigned, Due Date Approaching, Overdue, Updates, etc.)
/// - Tapping an item with an action link navigates to the Action Details screen
/// - Individual read/unread toggle and "Mark all as read"
/// - Delete individual notification
/// - Strict user isolation: only displays notifications for [userId]
class NotificationCentreView extends StatefulWidget {
  final String userId;
  final String? organizationId;
  final bool isManager;
  final String title;
  final String? subtitle;
  final void Function(String actionId)? onActionTap;
  final void Function(AppNotification notification)? onNotificationTap;
  final VoidCallback? onUnreadCountChanged;
  final NotificationService? notificationService;

  const NotificationCentreView({
    super.key,
    required this.userId,
    this.organizationId,
    this.isManager = false,
    this.title = 'Notifications & Alerts',
    this.subtitle,
    this.onActionTap,
    this.onNotificationTap,
    this.onUnreadCountChanged,
    this.notificationService,
  });

  @override
  State<NotificationCentreView> createState() => _NotificationCentreViewState();
}

class _NotificationCentreViewState extends State<NotificationCentreView> {
  late final NotificationService _service;
  bool _isLoading = true;
  String? _errorMessage;
  List<AppNotification> _notifications = [];
  bool _filterOnlyUnread = false;

  @override
  void initState() {
    super.initState();
    _service = widget.notificationService ?? NotificationService.instance;
    _loadNotifications();
  }

  @override
  void didUpdateWidget(covariant NotificationCentreView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _loadNotifications();
    }
  }

  Future<void> _loadNotifications() async {
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
        _errorMessage = 'Failed to load notifications: $e';
        _isLoading = false;
      });
    }
  }

  int get _unreadCount => _notifications.where((n) => !n.isRead).length;

  Future<void> _handleToggleRead(AppNotification item) async {
    final nextState = !item.isRead;
    // Optimistic update
    setState(() {
      final index = _notifications.indexWhere((n) => n.id == item.id);
      if (index != -1) {
        _notifications[index] = item.copyWith(
          isRead: nextState,
          readAt: nextState ? DateTime.now() : null,
        );
      }
    });
    widget.onUnreadCountChanged?.call();

    try {
      await _service.toggleRead(
        notificationId: item.id,
        userId: widget.userId,
        isRead: nextState,
      );
    } catch (e) {
      // Revert on error
      _loadNotifications();
    }
  }

  Future<void> _handleMarkAllAsRead() async {
    if (_unreadCount == 0) return;

    final now = DateTime.now();
    setState(() {
      _notifications = _notifications
          .map((n) => n.isRead ? n : n.copyWith(isRead: true, readAt: now))
          .toList();
    });
    widget.onUnreadCountChanged?.call();

    try {
      await _service.markAllAsRead(userId: widget.userId);
    } catch (e) {
      _loadNotifications();
    }
  }

  Future<void> _handleDelete(AppNotification item) async {
    setState(() {
      _notifications.removeWhere((n) => n.id == item.id);
    });
    widget.onUnreadCountChanged?.call();

    try {
      await _service.deleteNotification(
        notificationId: item.id,
        userId: widget.userId,
      );
    } catch (e) {
      _loadNotifications();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = AppTheme.cardBg(context);
    final cardBorder = AppTheme.cardBorder(context);

    final displayedList = _filterOnlyUnread
        ? _notifications.where((n) => !n.isRead).toList()
        : _notifications;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : const Color(0x060F172A),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.notifications_rounded,
                  color: Color(0xFF1565C0),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                        if (_unreadCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFDC2626).withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              '$_unreadCount Unread',
                              style: const TextStyle(
                                color: Color(0xFFDC2626),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.subtitle ??
                          'Real-time alerts, safety escalations, and action reminders.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              // Sound Toggle Button
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    SoundService.instance.toggleSound();
                  });
                },
                icon: Icon(
                  SoundService.instance.isSoundEnabled
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  size: 15,
                  color: SoundService.instance.isSoundEnabled
                      ? const Color(0xFF1565C0)
                      : AppTheme.textSecondary(context),
                ),
                label: Text(
                  SoundService.instance.isSoundEnabled ? 'Sound ON' : 'Muted',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: SoundService.instance.isSoundEnabled
                        ? const Color(0xFF1565C0)
                        : AppTheme.textSecondary(context),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  side: BorderSide(
                    color: SoundService.instance.isSoundEnabled
                        ? const Color(0xFF1565C0).withOpacity(0.4)
                        : AppTheme.cardBorder(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Mark all as read button
              if (_unreadCount > 0)
                TextButton.icon(
                  onPressed: _handleMarkAllAsRead,
                  icon: const Icon(Icons.done_all_rounded, size: 16),
                  label: const Text(
                    'Mark all read',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF1565C0),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Filters (All vs Unread)
          Row(
            children: [
              _buildFilterChip(
                label: 'All (${_notifications.length})',
                isSelected: !_filterOnlyUnread,
                onTap: () => setState(() => _filterOnlyUnread = false),
                context: context,
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                label: 'Unread ($_unreadCount)',
                isSelected: _filterOnlyUnread,
                onTap: () => setState(() => _filterOnlyUnread = true),
                context: context,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                tooltip: 'Refresh Notifications',
                color: AppTheme.textSecondary(context),
                onPressed: _loadNotifications,
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Content Area
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Column(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFDC2626),
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFFDC2626),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _loadNotifications,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else if (displayedList.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              decoration: BoxDecoration(
                color: AppTheme.containerBg(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_off_outlined,
                    size: 38,
                    color: AppTheme.textMuted(context),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _filterOnlyUnread
                        ? 'No unread notifications'
                        : 'No notifications yet',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _filterOnlyUnread
                        ? 'All caught up! Check the All tab for older alerts.'
                        : 'You are completely up to date with your HSSE actions.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: displayedList.length,
              separatorBuilder: (ctx, i) => const SizedBox(height: 10),
              itemBuilder: (ctx, index) {
                final item = displayedList[index];
                return _buildNotificationCard(item, context, isDark);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required BuildContext context,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF1565C0)
              : (isDark
                  ? const Color(0xFF1E293B)
                  : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF1565C0)
                : AppTheme.cardBorder(context),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : AppTheme.textSecondary(context),
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationCard(
    AppNotification item,
    BuildContext context,
    bool isDark,
  ) {
    final themeColor = item.themeColor;
    final isUnread = !item.isRead;

    return Container(
      decoration: BoxDecoration(
        color: isUnread
            ? (isDark
                ? const Color(0xFF1E3A8A).withValues(alpha: 0.22)
                : const Color(0xFFEFF6FF))
            : AppTheme.containerBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUnread
              ? (isDark
                  ? const Color(0xFF1D4ED8).withValues(alpha: 0.45)
                  : const Color(0xFFBFDBFE))
              : AppTheme.cardBorder(context),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (widget.onNotificationTap != null) {
              widget.onNotificationTap!(item);
              return;
            }
            final targetId = item.effectiveActionIdentifier ?? item.actionId;
            if (targetId != null && targetId.isNotEmpty) {
              widget.onActionTap?.call(targetId);
            } else if (item.isActionRelated) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Action reference is missing from this notification.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(item.message.isNotEmpty ? item.message : item.title),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Event icon container
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.iconData, color: themeColor, size: 18),
                ),
                const SizedBox(width: 12),

                // Main details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: TextStyle(
                                fontWeight:
                                    isUnread ? FontWeight.bold : FontWeight.w600,
                                fontSize: 13,
                                color: AppTheme.textPrimary(context),
                              ),
                            ),
                          ),
                          if (isUnread) ...[
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: Color(0xFF2563EB),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            item.timeAgo,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textMuted(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.message,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                      if (item.actionId != null &&
                          item.actionId!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFF1565C0).withValues(alpha: 0.25),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.link_rounded,
                                    size: 12,
                                    color: Color(0xFF1565C0),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    item.actionId!,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1565C0),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (widget.onActionTap != null)
                              Text(
                                '• Click to view action',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: AppTheme.textMuted(context),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Trailing actions (Toggle read, delete)
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert_rounded,
                    size: 17,
                    color: AppTheme.textMuted(context),
                  ),
                  tooltip: 'Options',
                  onSelected: (val) {
                    if (val == 'toggle_read') {
                      _handleToggleRead(item);
                    } else if (val == 'delete') {
                      _handleDelete(item);
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'toggle_read',
                      child: Row(
                        children: [
                          Icon(
                            item.isRead
                                ? Icons.mark_email_unread_outlined
                                : Icons.mark_email_read_outlined,
                            size: 16,
                            color: AppTheme.textPrimary(context),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            item.isRead ? 'Mark as unread' : 'Mark as read',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: const [
                          Icon(
                            Icons.delete_outline_rounded,
                            size: 16,
                            color: Color(0xFFDC2626),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Delete',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
