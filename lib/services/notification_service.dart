import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/supabase_config.dart';
import '../features/dashboard/manager_dashboard/models/action_record.dart';
import '../features/notifications/models/app_notification.dart';
import '../models/organization.dart';
import 'auth_service.dart';
import 'sound_service.dart';

/// In-memory store for in-app notifications.
///
/// Used for tests, offline mode, and as a fallback if the remote
/// database table has not yet been migrated.
///
/// Strictly enforces user isolation: User A cannot read, update, or delete
/// notifications belonging to User B.
class MockNotificationStore {
  static final MockNotificationStore instance =
      MockNotificationStore._internal();
  MockNotificationStore._internal();

  final List<AppNotification> _notifications = [];
  final Set<String> _seededUsers = {};
  static int _idCounter = 0;
  static bool enableDefaultSeeding = true;

  List<AppNotification> get allNotificationsForTesting =>
      List.unmodifiable(_notifications);

  void clear() {
    _notifications.clear();
    _seededUsers.clear();
  }

  void seed(List<AppNotification> items) {
    for (final item in items) {
      _notifications.removeWhere((n) => n.id == item.id);
      _notifications.add(item);
    }
  }

  void _seedDefaultUserNotifications(String userId) {
    if (!enableDefaultSeeding) return;
    if (_seededUsers.contains(userId)) return;
    _seededUsers.add(userId);
    if (_notifications.any((n) => n.userId == userId)) {
      return; // Already populated
    }

    final now = DateTime.now();
    final defaultItems = [
      AppNotification(
        id: 'seed-notif-1-$userId',
        userId: userId,
        title: 'Action Update Required',
        message: 'Equipment Inspection finding needs an updated checklist.',
        eventType: 'action_updated',
        actionId: 'AC-1029',
        isRead: false,
        idempotencyKey: 'seed_1_$userId',
        createdAt: now.subtract(const Duration(minutes: 10)),
      ),
      AppNotification(
        id: 'seed-notif-2-$userId',
        userId: userId,
        title: 'Target Date Approaching',
        message: 'Scaffolding repairs target date is set for tomorrow.',
        eventType: 'due_date_approaching',
        actionId: 'AC-1014',
        isRead: false,
        idempotencyKey: 'seed_2_$userId',
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      AppNotification(
        id: 'seed-notif-3-$userId',
        userId: userId,
        title: 'Action Assigned',
        message: 'AC-1042 Fire Extinguisher Inspection assigned to you.',
        eventType: 'action_assigned',
        actionId: 'AC-1042',
        isRead: false,
        idempotencyKey: 'seed_3_$userId',
        createdAt: now.subtract(const Duration(hours: 5)),
      ),
      AppNotification(
        id: 'seed-notif-4-$userId',
        userId: userId,
        title: 'Action Closed',
        message: 'AC-1002 marked as 100% completed by Operations.',
        eventType: 'action_completed',
        actionId: 'AC-1002',
        isRead: true,
        idempotencyKey: 'seed_4_$userId',
        createdAt: now.subtract(const Duration(days: 1)),
        readAt: now.subtract(const Duration(hours: 12)),
      ),
    ];

    for (final item in defaultItems) {
      if (!_notifications.any(
        (n) => n.idempotencyKey == item.idempotencyKey,
      )) {
        _notifications.add(item);
      }
    }
  }

  List<AppNotification> getNotifications(String userId) {
    _seedDefaultUserNotifications(userId);
    return _notifications
        .where((n) => n.userId == userId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  int getUnreadCount(String userId) {
    _seedDefaultUserNotifications(userId);
    return _notifications.where((n) => n.userId == userId && !n.isRead).length;
  }

  bool hasNotificationWithIdempotencyKey(String? key, String userId) {
    if (key == null || key.isEmpty) return false;
    return _notifications.any(
      (n) => n.userId == userId && n.idempotencyKey == key,
    );
  }

  AppNotification createNotification(AppNotification notification) {
    // Idempotency check: avoid duplicate notifications
    if (notification.idempotencyKey != null &&
        notification.idempotencyKey!.isNotEmpty) {
      final existingIndex = _notifications.indexWhere(
        (n) =>
            n.userId == notification.userId &&
            n.idempotencyKey == notification.idempotencyKey,
      );
      if (existingIndex != -1) {
        return _notifications[existingIndex];
      }
    }

    final newNotification = notification.copyWith(
      id: notification.id.isEmpty
          ? 'notif-${DateTime.now().microsecondsSinceEpoch}-${++_idCounter}'
          : notification.id,
      createdAt: notification.createdAt,
    );

    _notifications.removeWhere(
      (n) => n.id == newNotification.id && n.userId == newNotification.userId,
    );
    _notifications.add(newNotification);
    return newNotification;
  }

  void markAsRead({required String notificationId, required String userId}) {
    final index = _notifications.indexWhere(
      (n) => n.id == notificationId && n.userId == userId,
    );
    if (index != -1) {
      final item = _notifications[index];
      _notifications[index] = item.copyWith(
        isRead: true,
        readAt: DateTime.now(),
      );
    }
  }

  void toggleRead({
    required String notificationId,
    required String userId,
    required bool isRead,
  }) {
    final index = _notifications.indexWhere(
      (n) => n.id == notificationId && n.userId == userId,
    );
    if (index != -1) {
      final item = _notifications[index];
      _notifications[index] = item.copyWith(
        isRead: isRead,
        readAt: isRead ? DateTime.now() : null,
      );
    }
  }

  void markAllAsRead({required String userId}) {
    final now = DateTime.now();
    for (int i = 0; i < _notifications.length; i++) {
      if (_notifications[i].userId == userId && !_notifications[i].isRead) {
        _notifications[i] = _notifications[i].copyWith(
          isRead: true,
          readAt: now,
        );
      }
    }
  }

  void deleteNotification({
    required String notificationId,
    required String userId,
  }) {
    _notifications.removeWhere(
      (n) => n.id == notificationId && n.userId == userId,
    );
  }
}

/// In-app notification service for the ActionFlow enterprise tracker.
///
/// Guaranteed properties:
/// 1. In-app only: NO emails sent, NO Resend calls.
/// 2. Strict user isolation: [userId] matches auth.uid(). Users can only read,
///    toggle, or clear their own notifications.
/// 3. Reliable idempotency: Duplicate alerts on rebuilds/retries are prevented.
/// 4. Fallback resilience: Seamlessly falls back to [MockNotificationStore] in
///    test suites, offline environments, or when remote table is unmigrated.
/// 5. Realtime updates: Streams database inserts to the active session.
/// 6. Audio alerts: Plays short professional sound for incoming notifications with deduplication.
class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal([this._clientOverride]);

  factory NotificationService([SupabaseClient? client]) {
    if (client != null) {
      return NotificationService._internal(client);
    }
    return instance;
  }

  final SupabaseClient? _clientOverride;
  static bool useMockOnly = false;
  final Set<String> _evaluatedReminderKeys = {};
  final Set<String> _playedSoundNotificationIds = {};

  RealtimeChannel? _realtimeChannel;
  String? _subscribedUserId;
  StreamSubscription<AuthState>? _authSubscription;

  final StreamController<AppNotification> _notificationStreamController =
      StreamController<AppNotification>.broadcast();

  /// Stream of newly received or created notifications in the active session.
  Stream<AppNotification> get onNotificationReceived =>
      _notificationStreamController.stream;

  /// Broadcasts a newly received or created notification to all active listeners.
  void notifyListenersOfNewAlert(AppNotification notification) {
    if (!_notificationStreamController.isClosed) {
      _notificationStreamController.add(notification);
    }
  }

  /// Clears the in-memory session cache of evaluated reminder checks.
  void clearReminderSessionCache() => _evaluatedReminderKeys.clear();

  SupabaseClient? get _client => _clientOverride ?? SupabaseConfig.clientOrNull;

  bool get isReady =>
      !useMockOnly &&
      _client != null &&
      SupabaseConfig.isInitialized &&
      _client?.auth.currentUser != null;

  MockNotificationStore get _mockStore => MockNotificationStore.instance;

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// Validates whether [id] is a well-formed 36-character UUID.
  static bool isValidUuid(String? id) {
    if (id == null) return false;
    final trimmed = id.trim();
    if (trimmed.length != 36) return false;
    return _uuidRegex.hasMatch(trimmed);
  }

  /// Safely dispatches an asynchronous notification task with error logging.
  ///
  /// Guarantees that:
  /// - Asynchronous notification failures NEVER break the caller's primary workflow.
  /// - Diagnostic errors are logged with useful event context without leaking secrets or tokens.
  /// - Unhandled zone exceptions are prevented.
  static void safeDispatch(
    Future<dynamic> Function() action, {
    required String context,
  }) {
    unawaited(
      () async {
        try {
          await action();
        } catch (error, stackTrace) {
          debugPrint('[NotificationDispatch] Error in $context: $error\n$stackTrace');
        }
      }(),
    );
  }

  // ===========================================================================
  // REALTIME SUBSCRIPTION & AUTH STATE LIFECYCLE
  // ===========================================================================

  /// Initializes reactive authentication listener for Realtime subscriptions.
  void initializeAuthStateListener() {
    final client = _client;
    if (client == null) return;

    _authSubscription?.cancel();
    _authSubscription = client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;
      final userId = session?.user.id;

      switch (event) {
        case AuthChangeEvent.initialSession:
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.tokenRefreshed:
        case AuthChangeEvent.userUpdated:
          if (userId != null && isValidUuid(userId)) {
            if (_subscribedUserId != userId || _realtimeChannel == null) {
              subscribeToRealtimeNotifications(userId);
            }
          }
          break;
        case AuthChangeEvent.signedOut:
          unsubscribeFromRealtime();
          break;
        default:
          break;
      }
    });

    final currentUid = client.auth.currentUser?.id;
    if (currentUid != null && isValidUuid(currentUid)) {
      subscribeToRealtimeNotifications(currentUid);
    }
  }

  /// Subscribes to real-time notification inserts for [userId].
  void subscribeToRealtimeNotifications(String userId) {
    final client = _client;
    if (client == null || userId.isEmpty) return;

    // Security & User Isolation: ensure user only subscribes to their own notifications
    if (!useMockOnly && client.auth.currentUser != null) {
      final currentAuthUid = client.auth.currentUser?.id;
      if (currentAuthUid != null && isValidUuid(currentAuthUid) && currentAuthUid != userId) {
        debugPrint(
          '[NotificationService] Subscription rejected: user $currentAuthUid cannot subscribe to channel for $userId',
        );
        return;
      }
    }

    if (_subscribedUserId == userId && _realtimeChannel != null) {
      return;
    }

    unsubscribeFromRealtime();
    _subscribedUserId = userId;

    try {
      final channelName = 'notifications_user_$userId';
      _realtimeChannel = client
          .channel(channelName)
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (payload) {
              try {
                final newRecord =
                    Map<String, dynamic>.from(payload.newRecord);
                final notif = AppNotification.fromJson(newRecord);
                _handleIncomingRealtimeNotification(notif);
              } catch (e) {
                debugPrint(
                    '[NotificationService] Error parsing realtime notification: $e');
              }
            },
          );

      _realtimeChannel?.subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          debugPrint(
            '[NotificationService] Realtime channel connected for user: $userId',
          );
        } else if (status == RealtimeSubscribeStatus.timedOut ||
            status == RealtimeSubscribeStatus.closed) {
          debugPrint(
            '[NotificationService] Realtime channel status changed: $status ($error)',
          );
        }
      });
    } catch (e) {
      debugPrint('[NotificationService] Realtime subscribe error: $e');
    }
  }

  /// Unsubscribes from active realtime notification channel.
  void unsubscribeFromRealtime() {
    if (_realtimeChannel != null) {
      try {
        _client?.removeChannel(_realtimeChannel!);
      } catch (_) {}
      _realtimeChannel = null;
      _subscribedUserId = null;
    }
  }

  void _handleIncomingRealtimeNotification(AppNotification notif) {
    if (notif.userId != _subscribedUserId) return;

    // Deduplication check for sound
    if (!_playedSoundNotificationIds.contains(notif.id)) {
      _playedSoundNotificationIds.add(notif.id);
      unawaited(SoundService.instance.playNotificationSound());
    }

    notifyListenersOfNewAlert(notif);
  }

  // ===========================================================================
  // DATA OPERATIONS
  // ===========================================================================

  /// Checks whether an exception specifically indicates that table `public.notifications`
  /// does not exist in the database or PostgREST schema cache.
  static bool isMissingNotificationsTableError(dynamic e) {
    if (e is PostgrestException) {
      final code = e.code ?? '';
      final msg = e.message.toLowerCase();
      final details = (e.details?.toString() ?? '').toLowerCase();

      if (code == 'PGRST205') {
        if (msg.contains('notifications') || details.contains('notifications')) {
          return true;
        }
      }

      if (code == '42P01' &&
          (msg.contains('notifications') || details.contains('notifications'))) {
        return true;
      }

      if (msg.contains('relation "public.notifications" does not exist') ||
          msg.contains('relation "notifications" does not exist') ||
          (msg.contains('could not find the table') &&
              msg.contains('notifications'))) {
        return true;
      }
    }

    final str = e.toString().toLowerCase();
    if (str.contains('pgrst205') && str.contains('notifications')) {
      return true;
    }
    if (str.contains('relation "public.notifications" does not exist') ||
        str.contains('relation "notifications" does not exist')) {
      return true;
    }

    return false;
  }

  /// Fetch all notifications for [userId] (ordered latest first).
  Future<List<AppNotification>> getNotifications({
    required String userId,
  }) async {
    final client = _client;
    if (!isReady || client == null) {
      return _mockStore.getNotifications(userId);
    }

    try {
      final response = await client
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final List<dynamic> data = response as List<dynamic>;
      final seenIds = <String>{};
      final uniqueList = <AppNotification>[];
      for (final json in data) {
        final notif = AppNotification.fromJson(json as Map<String, dynamic>);
        if (notif.id.isNotEmpty && seenIds.contains(notif.id)) continue;
        if (notif.id.isNotEmpty) seenIds.add(notif.id);
        uniqueList.add(notif);
      }
      return uniqueList;
    } catch (e) {
      if (isMissingNotificationsTableError(e)) {
        debugPrint(
          '[NotificationService] notifications table unmigrated remotely (PGRST205), falling back to mock store for user $userId',
        );
        return _mockStore.getNotifications(userId);
      }
      debugPrint('[NotificationService] Remote query failed: $e');
      rethrow;
    }
  }

  /// Get the number of unread notifications for [userId].
  Future<int> getUnreadCount({required String userId}) async {
    final client = _client;
    if (!isReady || client == null) {
      return _mockStore.getUnreadCount(userId);
    }

    try {
      final response = await client
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false);

      final List<dynamic> data = response as List<dynamic>;
      return data.length;
    } catch (e) {
      if (isMissingNotificationsTableError(e)) {
        return _mockStore.getUnreadCount(userId);
      }
      debugPrint('[NotificationService] Remote count failed: $e');
      rethrow;
    }
  }

  /// Safely and authoritatively resolves the organization UUID for notifications.
  ///
  /// Requirements:
  /// 1. Resolve organization UUID from authenticated user's actual profile/session.
  /// 2. If candidate is a legacy organization code such as 'SOBHA-001' or 'sobha',
  ///    resolve it using verified organization data without hardcoding a universal fallback.
  /// 3. Fail safely (return null) if unambiguous resolution is impossible or violates tenant isolation.
  Future<String?> resolveOrganizationUuid({
    String? candidateOrgId,
  }) async {
    final client = _client;

    // In mock/test environments without active remote Supabase client:
    if (client == null || !isReady || useMockOnly) {
      if (candidateOrgId != null && candidateOrgId.isNotEmpty) {
        return candidateOrgId;
      }
      return AuthService.instance.currentOrganizationId ?? Organization.sobhaId;
    }

    // When connected to Supabase:
    // 1. Check current authenticated user's organization from AuthService
    final currentOrgId = AuthService.instance.currentOrganizationId;
    final currentOrg = AuthService.instance.currentOrganization;

    // 2. Fetch authoritative caller org UUID from profiles if not cached
    String? authoritativeCallerOrgId = currentOrgId;
    if (authoritativeCallerOrgId == null || !isValidUuid(authoritativeCallerOrgId)) {
      final callerUid = client.auth.currentUser?.id;
      if (callerUid != null && isValidUuid(callerUid)) {
        try {
          final res = await client
              .from('profiles')
              .select('organization_id')
              .eq('id', callerUid)
              .maybeSingle();
          if (res != null && res['organization_id'] != null) {
            authoritativeCallerOrgId = res['organization_id'].toString();
          }
        } catch (e) {
          debugPrint('[NotificationService] Error looking up caller organization: $e');
        }
      }
    }

    // 3. If candidateOrgId is already a valid UUID:
    if (candidateOrgId != null && isValidUuid(candidateOrgId)) {
      if (authoritativeCallerOrgId != null &&
          isValidUuid(authoritativeCallerOrgId) &&
          candidateOrgId != authoritativeCallerOrgId) {
        debugPrint(
          '[NotificationService] Tenant isolation violation: candidate org $candidateOrgId does not match caller org $authoritativeCallerOrgId',
        );
        return null; // Cross-org forbidden
      }
      return candidateOrgId;
    }

    // 4. Resolve legacy code (e.g. 'SOBHA-001', 'sobha') using verified org data
    if (candidateOrgId != null && candidateOrgId.trim().isNotEmpty) {
      final cleanCandidate = candidateOrgId.trim().toLowerCase();

      // Check against caller's active organization code or name
      if (currentOrg != null) {
        final code = currentOrg.code.toLowerCase();
        final name = currentOrg.name.toLowerCase();
        if (code == cleanCandidate ||
            name == cleanCandidate ||
            (cleanCandidate == 'sobha-001' && code == 'sobha')) {
          return currentOrg.id;
        }
      }

      // Check against verified organizations table
      try {
        final orgQuery = await client
            .from('organizations')
            .select('id, code, name')
            .eq('is_active', true);
        for (final raw in orgQuery) {
          final row = Map<String, dynamic>.from(raw);
          final rowId = row['id']?.toString() ?? '';
          final rowCode = (row['code']?.toString() ?? '').toLowerCase();
          final rowName = (row['name']?.toString() ?? '').toLowerCase();

          if (cleanCandidate == rowCode ||
              cleanCandidate == rowName ||
              (cleanCandidate == 'sobha-001' && rowCode == 'sobha')) {
            if (authoritativeCallerOrgId != null &&
                isValidUuid(authoritativeCallerOrgId) &&
                rowId != authoritativeCallerOrgId) {
              debugPrint(
                '[NotificationService] Resolved org $rowId for code $candidateOrgId does not match caller org $authoritativeCallerOrgId',
              );
              return null;
            }
            return rowId;
          }
        }
      } catch (e) {
        debugPrint('[NotificationService] Error resolving legacy org code: $e');
      }
    }

    // 5. Fallback strictly to caller's verified active organization UUID
    if (authoritativeCallerOrgId != null && isValidUuid(authoritativeCallerOrgId)) {
      return authoritativeCallerOrgId;
    }

    debugPrint(
      '[NotificationService] Unable to unambiguously resolve organization UUID for candidate "$candidateOrgId"',
    );
    return null;
  }

  /// Validates whether [recipientUserId] is an active, valid UUID belonging to [organizationId].
  Future<bool> validateRecipient({
    required String recipientUserId,
    required String organizationId,
  }) async {
    final client = _client;
    if (client == null || !isReady || useMockOnly) {
      // In mock/test environments without Supabase client:
      return recipientUserId.isNotEmpty;
    }

    if (!isValidUuid(recipientUserId)) {
      debugPrint(
        '[NotificationService] Invalid recipient: "$recipientUserId" is not a valid UUID (employee codes or names cannot be used as auth UUIDs)',
      );
      return false;
    }

    if (!isValidUuid(organizationId)) {
      debugPrint(
        '[NotificationService] Invalid organizationId: "$organizationId" is not a valid UUID',
      );
      return false;
    }

    try {
      final res = await client
          .from('profiles')
          .select('id, organization_id, is_active')
          .eq('id', recipientUserId)
          .eq('is_active', true)
          .maybeSingle();

      if (res == null) {
        debugPrint(
          '[NotificationService] Recipient "$recipientUserId" not found or inactive in profiles',
        );
        return false;
      }

      final profileOrgId = res['organization_id']?.toString();
      if (profileOrgId != organizationId) {
        debugPrint(
          '[NotificationService] Recipient "$recipientUserId" belongs to organization "$profileOrgId", not "$organizationId"',
        );
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('[NotificationService] Note: Recipient validation check error: $e');
      // If network issue, allow RPC to be authoritative
      return true;
    }
  }

  /// Create a notification (idempotent, safe against cross-user RLS traps).
  Future<AppNotification?> createNotification(AppNotification notif) async {
    final client = _client;
    if (!isReady || client == null || useMockOnly) {
      final isExisting = _mockStore.hasNotificationWithIdempotencyKey(
        notif.idempotencyKey,
        notif.userId,
      );
      final created = _mockStore.createNotification(notif);
      if (!isExisting) {
        notifyListenersOfNewAlert(created);
      }
      return created;
    }

    // 1. Resolve organization UUID
    final resolvedOrgId = await resolveOrganizationUuid(
      candidateOrgId: notif.organizationId,
    );

    if (resolvedOrgId == null || !isValidUuid(resolvedOrgId)) {
      debugPrint(
        '[NotificationService] Skipped notification dispatch [event: ${notif.eventType}, title: "${notif.title}"]: Unable to resolve valid organization UUID from "${notif.organizationId}"',
      );
      return null;
    }

    // 2. Validate recipient UUID
    final isRecipientValid = await validateRecipient(
      recipientUserId: notif.userId,
      organizationId: resolvedOrgId,
    );

    if (!isRecipientValid) {
      debugPrint(
        '[NotificationService] Skipped notification dispatch [event: ${notif.eventType}, title: "${notif.title}"]: Recipient "${notif.userId}" is invalid or does not belong to active organization "$resolvedOrgId"',
      );
      return null;
    }

    // 3. Try create_app_notification RPC (bypasses cross-user .select() RLS trap)
    try {
      final rpcParams = <String, dynamic>{
        'p_user_id': notif.userId,
        'p_organization_id': resolvedOrgId,
        'p_title': notif.title,
        'p_message': notif.message,
        'p_event_type': notif.eventType,
        if (notif.actionId != null && notif.actionId!.isNotEmpty)
          'p_action_id': notif.actionId,
        if (notif.idempotencyKey != null && notif.idempotencyKey!.isNotEmpty)
          'p_idempotency_key': notif.idempotencyKey,
      };

      final rpcRes = await client.rpc(
        'create_app_notification',
        params: rpcParams,
      );

      if (rpcRes is Map) {
        final resMap = Map<String, dynamic>.from(rpcRes);
        final created = AppNotification.fromJson(resMap);
        final isDuplicate = resMap['is_duplicate'] == true;
        if (!isDuplicate) {
          notifyListenersOfNewAlert(created);
        }
        return created;
      }
      return null;
    } catch (rpcErr) {
      debugPrint(
        '[NotificationService] Notification RPC create_app_notification failed [event: ${notif.eventType}, recipient: ${notif.userId}, title: "${notif.title}"]: $rpcErr',
      );
      return null;
    }
  }

  /// Mark a single notification as read.
  Future<void> markAsRead({
    required String notificationId,
    required String userId,
  }) async {
    final client = _client;
    if (!isReady || client == null) {
      _mockStore.markAsRead(notificationId: notificationId, userId: userId);
      return;
    }

    try {
      await client
          .from('notifications')
          .update({
            'is_read': true,
            'read_at': DateTime.now().toIso8601String(),
          })
          .eq('id', notificationId)
          .eq('user_id', userId);
    } catch (e) {
      if (isMissingNotificationsTableError(e)) {
        _mockStore.markAsRead(notificationId: notificationId, userId: userId);
        return;
      }
      debugPrint('[NotificationService] Remote markAsRead failed: $e');
      rethrow;
    }
  }

  /// Toggle a notification's read state.
  Future<void> toggleRead({
    required String notificationId,
    required String userId,
    required bool isRead,
  }) async {
    final client = _client;
    if (!isReady || client == null) {
      _mockStore.toggleRead(
        notificationId: notificationId,
        userId: userId,
        isRead: isRead,
      );
      return;
    }

    try {
      await client
          .from('notifications')
          .update({
            'is_read': isRead,
            'read_at': isRead ? DateTime.now().toIso8601String() : null,
          })
          .eq('id', notificationId)
          .eq('user_id', userId);
    } catch (e) {
      if (isMissingNotificationsTableError(e)) {
        _mockStore.toggleRead(
          notificationId: notificationId,
          userId: userId,
          isRead: isRead,
        );
        return;
      }
      debugPrint('[NotificationService] Remote toggleRead failed: $e');
      rethrow;
    }
  }

  /// Mark all notifications as read for [userId].
  Future<void> markAllAsRead({required String userId}) async {
    final client = _client;
    if (!isReady || client == null) {
      _mockStore.markAllAsRead(userId: userId);
      return;
    }

    try {
      await client
          .from('notifications')
          .update({
            'is_read': true,
            'read_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', userId)
          .eq('is_read', false);
    } catch (e) {
      if (isMissingNotificationsTableError(e)) {
        _mockStore.markAllAsRead(userId: userId);
        return;
      }
      debugPrint('[NotificationService] Remote markAllAsRead failed: $e');
      rethrow;
    }
  }

  /// Delete a notification.
  Future<void> deleteNotification({
    required String notificationId,
    required String userId,
  }) async {
    final client = _client;
    if (!isReady || client == null) {
      _mockStore.deleteNotification(
        notificationId: notificationId,
        userId: userId,
      );
      return;
    }

    try {
      await client
          .from('notifications')
          .delete()
          .eq('id', notificationId)
          .eq('user_id', userId);
    } catch (e) {
      if (isMissingNotificationsTableError(e)) {
        _mockStore.deleteNotification(
          notificationId: notificationId,
          userId: userId,
        );
        return;
      }
      debugPrint('[NotificationService] Remote delete failed: $e');
      rethrow;
    }
  }

  // ===========================================================================
  // EVENT-SPECIFIC NOTIFICATION HELPERS
  // ===========================================================================

  // --- ACTION MANAGEMENT ---

  /// Event 1: Official HSSE Action is assigned to a staff or manager.
  Future<AppNotification?> notifyActionAssigned({
    required ActionRecord action,
    required String assigneeUserId,
    String? organizationId,
  }) async {
    if (assigneeUserId.isEmpty) return null;

    final actionRef =
        action.actionNumber.isNotEmpty ? action.actionNumber : action.id;
    final notif = AppNotification(
      id: '',
      userId: assigneeUserId,
      organizationId: organizationId ?? action.organizationId,
      title: 'Action Assigned: $actionRef',
      message: 'You have been assigned to HSSE Action: "${action.subject}".',
      eventType: NotificationEventType.actionAssigned.value,
      actionId: actionRef,
      isRead: false,
      idempotencyKey:
          'action_assigned_${action.id}_${assigneeUserId}_${action.history.length}',
      createdAt: DateTime.now(),
    );

    return createNotification(notif);
  }

  /// Event: Action forwarded to a user.
  Future<AppNotification?> notifyActionForwarded({
    required ActionRecord action,
    required String forwardedToUserId,
    required String forwardedByName,
    String? organizationId,
  }) async {
    if (forwardedToUserId.isEmpty) return null;

    final actionRef =
        action.actionNumber.isNotEmpty ? action.actionNumber : action.id;
    final notif = AppNotification(
      id: '',
      userId: forwardedToUserId,
      organizationId: organizationId ?? action.organizationId,
      title: 'Action Forwarded: $actionRef',
      message:
          'Action $actionRef was forwarded to you by $forwardedByName for collaboration.',
      eventType: NotificationEventType.actionForwarded.value,
      actionId: actionRef,
      isRead: false,
      idempotencyKey:
          'action_forwarded_${action.id}_${forwardedToUserId}_${action.history.length}',
      createdAt: DateTime.now(),
    );

    return createNotification(notif);
  }

  /// Event: Contributor added to an action.
  Future<AppNotification?> notifyContributorAdded({
    required ActionRecord action,
    required String contributorUserId,
    required String addedByName,
    String? organizationId,
  }) async {
    if (contributorUserId.isEmpty) return null;

    final actionRef =
        action.actionNumber.isNotEmpty ? action.actionNumber : action.id;
    final notif = AppNotification(
      id: '',
      userId: contributorUserId,
      organizationId: organizationId ?? action.organizationId,
      title: 'Added as Contributor: $actionRef',
      message:
          'You have been added as a contributor to Action "$actionRef" by $addedByName.',
      eventType: NotificationEventType.contributorAdded.value,
      actionId: actionRef,
      isRead: false,
      idempotencyKey:
          'contributor_added_${action.id}_${contributorUserId}_${action.contributors.length}',
      createdAt: DateTime.now(),
    );

    return createNotification(notif);
  }

  /// Event: Subtask assigned to a user.
  Future<AppNotification?> notifySubtaskAssigned({
    required ActionRecord action,
    required String assigneeUserId,
    required String subtaskTitle,
    String? assignedByName,
    String? organizationId,
  }) async {
    if (assigneeUserId.isEmpty) return null;

    final actionRef =
        action.actionNumber.isNotEmpty ? action.actionNumber : action.id;
    final assignerStr =
        assignedByName != null && assignedByName.isNotEmpty ? ' by $assignedByName' : '';
    final notif = AppNotification(
      id: '',
      userId: assigneeUserId,
      organizationId: organizationId ?? action.organizationId,
      title: 'Subtask Assigned: $actionRef',
      message:
          'You have been assigned to subtask "$subtaskTitle" in Action $actionRef$assignerStr.',
      eventType: NotificationEventType.subtaskAssigned.value,
      actionId: actionRef,
      isRead: false,
      idempotencyKey:
          'subtask_assigned_${action.id}_${assigneeUserId}_${subtaskTitle.hashCode}',
      createdAt: DateTime.now(),
    );

    return createNotification(notif);
  }

  /// Event: Subtask delegated or reassigned.
  Future<AppNotification?> notifySubtaskDelegated({
    required ActionRecord action,
    required String delegatedToUserId,
    required String subtaskTitle,
    required String delegatedByName,
    String? organizationId,
  }) async {
    if (delegatedToUserId.isEmpty) return null;

    final actionRef =
        action.actionNumber.isNotEmpty ? action.actionNumber : action.id;
    final notif = AppNotification(
      id: '',
      userId: delegatedToUserId,
      organizationId: organizationId ?? action.organizationId,
      title: 'Subtask Delegated: $actionRef',
      message:
          'Subtask "$subtaskTitle" in Action $actionRef was delegated to you by $delegatedByName.',
      eventType: NotificationEventType.subtaskDelegated.value,
      actionId: actionRef,
      isRead: false,
      idempotencyKey:
          'subtask_delegated_${action.id}_${delegatedToUserId}_${subtaskTitle.hashCode}_${DateTime.now().millisecondsSinceEpoch}',
      createdAt: DateTime.now(),
    );

    return createNotification(notif);
  }

  /// Event: Action's due date is approaching (within 48h).
  Future<AppNotification?> notifyDueDateApproaching({
    required ActionRecord action,
    required String recipientUserId,
    String? organizationId,
    int hoursRemaining = 48,
  }) async {
    if (recipientUserId.isEmpty) return null;

    final actionRef =
        action.actionNumber.isNotEmpty ? action.actionNumber : action.id;
    final notif = AppNotification(
      id: '',
      userId: recipientUserId,
      organizationId: organizationId ?? action.organizationId,
      title: 'Target Date Approaching',
      message:
          'Action $actionRef target completion date is in $hoursRemaining hours (${action.targetDate}).',
      eventType: NotificationEventType.dueDateApproaching.value,
      actionId: actionRef,
      isRead: false,
      idempotencyKey:
          'due_date_approaching_${action.id}_${recipientUserId}_${action.targetDate}',
      createdAt: DateTime.now(),
    );

    return createNotification(notif);
  }

  /// Event: Action becomes overdue.
  Future<AppNotification?> notifyActionOverdue({
    required ActionRecord action,
    required String recipientUserId,
    String? organizationId,
  }) async {
    if (recipientUserId.isEmpty) return null;

    final actionRef =
        action.actionNumber.isNotEmpty ? action.actionNumber : action.id;
    final notif = AppNotification(
      id: '',
      userId: recipientUserId,
      organizationId: organizationId ?? action.organizationId,
      title: 'Action Overdue Alert',
      message:
          'Action $actionRef has exceeded its target completion date (${action.targetDate}). Immediate attention required.',
      eventType: NotificationEventType.actionOverdue.value,
      actionId: actionRef,
      isRead: false,
      idempotencyKey:
          'action_overdue_${action.id}_${recipientUserId}_${action.targetDate}',
      createdAt: DateTime.now(),
    );

    return createNotification(notif);
  }

  /// Event: Action status changes.
  Future<AppNotification?> notifyStatusChanged({
    required ActionRecord action,
    required String recipientUserId,
    required String oldStatus,
    required String newStatus,
    String? organizationId,
  }) async {
    if (recipientUserId.isEmpty || oldStatus == newStatus) return null;

    final actionRef =
        action.actionNumber.isNotEmpty ? action.actionNumber : action.id;
    final notif = AppNotification(
      id: '',
      userId: recipientUserId,
      organizationId: organizationId ?? action.organizationId,
      title: 'Action Status Changed',
      message:
          'Action $actionRef status changed from "$oldStatus" to "$newStatus".',
      eventType: NotificationEventType.statusChanged.value,
      actionId: actionRef,
      isRead: false,
      idempotencyKey:
          'status_changed_${action.id}_${recipientUserId}_${newStatus}_${action.history.length}',
      createdAt: DateTime.now(),
    );

    return createNotification(notif);
  }

  /// Event: Staff member submits a progress update or marks an action complete.
  Future<AppNotification?> notifyActionUpdatedOrCompleted({
    required ActionRecord action,
    required String managerUserId,
    required String updatedByName,
    required bool isCompleted,
    String? organizationId,
    String? notes,
  }) async {
    if (managerUserId.isEmpty) return null;

    final actionRef =
        action.actionNumber.isNotEmpty ? action.actionNumber : action.id;
    final eventType = isCompleted
        ? NotificationEventType.actionCompleted.value
        : NotificationEventType.actionUpdated.value;

    final title = isCompleted
        ? 'Action Completed: $actionRef'
        : 'Progress Update: $actionRef';
    final message = isCompleted
        ? '$updatedByName marked action $actionRef as 100% completed and submitted for verification.'
        : '$updatedByName updated progress to ${action.percentComplete}% on action $actionRef.${notes != null && notes.isNotEmpty ? " Remarks: $notes" : ""}';

    final idempotencyKey = isCompleted
        ? 'action_completed_${action.id}_${managerUserId}_${action.history.length}'
        : 'action_updated_${action.id}_${managerUserId}_${action.percentComplete}_${action.progressUpdates.length}';

    final notif = AppNotification(
      id: '',
      userId: managerUserId,
      organizationId: organizationId ?? action.organizationId,
      title: title,
      message: message,
      eventType: eventType,
      actionId: actionRef,
      isRead: false,
      idempotencyKey: idempotencyKey,
      createdAt: DateTime.now(),
    );

    return createNotification(notif);
  }

  /// Event: Manager reopens an action, notifying assigned staff.
  Future<AppNotification?> notifyActionReopened({
    required ActionRecord action,
    required String assigneeUserId,
    required String reopenedByName,
    String? organizationId,
    String? reason,
  }) async {
    if (assigneeUserId.isEmpty) return null;

    final actionRef =
        action.actionNumber.isNotEmpty ? action.actionNumber : action.id;
    final reasonSuffix =
        (reason != null && reason.isNotEmpty) ? ' Reason: $reason' : '';

    final notif = AppNotification(
      id: '',
      userId: assigneeUserId,
      organizationId: organizationId ?? action.organizationId,
      title: 'Action Reopened: $actionRef',
      message:
          '$reopenedByName reopened action "$actionRef" for further corrective action.$reasonSuffix',
      eventType: NotificationEventType.actionReopened.value,
      actionId: actionRef,
      isRead: false,
      idempotencyKey:
          'action_reopened_${action.id}_${assigneeUserId}_${action.history.length}',
      createdAt: DateTime.now(),
    );

    return createNotification(notif);
  }

  /// Evaluates action list and triggers approaching/overdue notifications idempotently.
  Future<void> checkActionReminders({
    required List<ActionRecord> actions,
    required String userId,
    bool isManager = false,
  }) async {
    if (userId.isEmpty || actions.isEmpty) return;
    final now = DateTime.now();

    for (final action in actions) {
      if (action.isExternalRecipient) continue;
      if (action.targetDate.isEmpty) continue;
      final target = DateTime.tryParse(action.targetDate);
      if (target == null) continue;

      final isFinished =
          action.status.toLowerCase() == 'completed' ||
          action.status.toLowerCase() == 'closed';
      if (isFinished) continue;

      // Verify recipient relevance
      if (!isManager && action.assignedToId != userId) {
        continue;
      }
      if (isManager) {
        final creatorId = action.createdById.isNotEmpty
            ? action.createdById
            : (action.assignedByPerson?.personId ?? '');
        final isAssignee = action.assignedToId == userId;
        final isCreator = creatorId == userId;
        if (!isAssignee && !isCreator) {
          continue;
        }
      }

      // Check if overdue
      if (target.isBefore(now)) {
        final reminderKey =
            '${action.id}_${userId}_${action.targetDate}_overdue';
        if (!_evaluatedReminderKeys.contains(reminderKey)) {
          _evaluatedReminderKeys.add(reminderKey);
          await notifyActionOverdue(
            action: action,
            recipientUserId: userId,
            organizationId: action.organizationId,
          );
        }
      } else {
        // Check if within 48 hours
        final hoursDiff = target.difference(now).inHours;
        if (hoursDiff <= 48 && hoursDiff >= 0) {
          final reminderKey =
              '${action.id}_${userId}_${action.targetDate}_approaching';
          if (!_evaluatedReminderKeys.contains(reminderKey)) {
            _evaluatedReminderKeys.add(reminderKey);
            await notifyDueDateApproaching(
              action: action,
              recipientUserId: userId,
              organizationId: action.organizationId,
              hoursRemaining: hoursDiff > 0 ? hoursDiff : 1,
            );
          }
        }
      }
    }
  }

  // --- REQUEST MANAGEMENT ---

  /// Event: New request submitted, notifying approver.
  Future<AppNotification?> notifyRequestSubmitted({
    required String requestId,
    required String requestCode,
    required String approverUserId,
    required String requesterName,
    required String requestTitle,
    String? organizationId,
  }) async {
    if (approverUserId.isEmpty) return null;

    final notif = AppNotification(
      id: '',
      userId: approverUserId,
      organizationId: organizationId,
      title: 'Request Approval Required: $requestCode',
      message:
          '$requesterName submitted request "$requestTitle" ($requestCode) awaiting your review.',
      eventType: NotificationEventType.requestSubmitted.value,
      actionId: requestCode,
      isRead: false,
      idempotencyKey: 'req_sub_${requestId}_$approverUserId',
      createdAt: DateTime.now(),
    );

    return createNotification(notif);
  }

  /// Event: Request assigned to next sequential or parallel approver.
  Future<AppNotification?> notifyRequestAssigned({
    required String requestId,
    required String requestCode,
    required String approverUserId,
    required String requestTitle,
    String? organizationId,
  }) async {
    if (approverUserId.isEmpty) return null;

    final notif = AppNotification(
      id: '',
      userId: approverUserId,
      organizationId: organizationId,
      title: 'Request Assigned: $requestCode',
      message:
          'Request "$requestTitle" ($requestCode) has been assigned to you for approval.',
      eventType: NotificationEventType.requestAssigned.value,
      actionId: requestCode,
      isRead: false,
      idempotencyKey: 'req_asgn_${requestId}_$approverUserId',
      createdAt: DateTime.now(),
    );

    return createNotification(notif);
  }

  /// Event: Request approved, notifying requester.
  Future<AppNotification?> notifyRequestApproved({
    required String requestId,
    required String requestCode,
    required String requesterUserId,
    required String approverName,
    required String requestTitle,
    bool isCompleted = false,
    String? organizationId,
  }) async {
    if (requesterUserId.isEmpty) return null;

    final eventType = isCompleted
        ? NotificationEventType.requestCompleted.value
        : NotificationEventType.requestApproved.value;
    final title = isCompleted
        ? 'Request Completed: $requestCode'
        : 'Request Approved: $requestCode';
    final message = isCompleted
        ? 'Your request "$requestTitle" ($requestCode) has been fully approved by $approverName and completed.'
        : 'Your request "$requestTitle" ($requestCode) was approved by $approverName.';

    final notif = AppNotification(
      id: '',
      userId: requesterUserId,
      organizationId: organizationId,
      title: title,
      message: message,
      eventType: eventType,
      actionId: requestCode,
      isRead: false,
      idempotencyKey: 'req_appr_${requestId}_${requesterUserId}_$eventType',
      createdAt: DateTime.now(),
    );

    return createNotification(notif);
  }

  /// Event: Request rejected, notifying requester.
  Future<AppNotification?> notifyRequestRejected({
    required String requestId,
    required String requestCode,
    required String requesterUserId,
    required String approverName,
    required String requestTitle,
    String? reason,
    String? organizationId,
  }) async {
    if (requesterUserId.isEmpty) return null;

    final reasonStr =
        reason != null && reason.isNotEmpty ? ' Reason: "$reason"' : '';
    final notif = AppNotification(
      id: '',
      userId: requesterUserId,
      organizationId: organizationId,
      title: 'Request Rejected: $requestCode',
      message:
          'Your request "$requestTitle" ($requestCode) was rejected by $approverName.$reasonStr',
      eventType: NotificationEventType.requestRejected.value,
      actionId: requestCode,
      isRead: false,
      idempotencyKey: 'req_rej_${requestId}_$requesterUserId',
      createdAt: DateTime.now(),
    );

    return createNotification(notif);
  }

  /// Event: Request forwarded / delegated to a new approver.
  Future<AppNotification?> notifyRequestForwarded({
    required String requestId,
    required String requestCode,
    required String delegatedToUserId,
    required String forwardedByName,
    required String requestTitle,
    String? organizationId,
  }) async {
    if (delegatedToUserId.isEmpty) return null;

    final notif = AppNotification(
      id: '',
      userId: delegatedToUserId,
      organizationId: organizationId,
      title: 'Request Delegated: $requestCode',
      message:
          'Request "$requestTitle" ($requestCode) was forwarded to you by $forwardedByName for review.',
      eventType: NotificationEventType.requestForwarded.value,
      actionId: requestCode,
      isRead: false,
      idempotencyKey:
          'req_fwd_${requestId}_${delegatedToUserId}_${DateTime.now().millisecondsSinceEpoch}',
      createdAt: DateTime.now(),
    );

    return createNotification(notif);
  }

  // --- CALENDAR MANAGEMENT ---

  /// Event: Calendar task assigned.
  Future<AppNotification?> notifyCalendarEventAssigned({
    required String taskId,
    required String taskTitle,
    required String assigneeUserId,
    required String scheduledDate,
    String? assignedByName,
    String? organizationId,
  }) async {
    if (assigneeUserId.isEmpty) return null;

    final assignerStr =
        assignedByName != null && assignedByName.isNotEmpty ? ' by $assignedByName' : '';
    final notif = AppNotification(
      id: '',
      userId: assigneeUserId,
      organizationId: organizationId,
      title: 'Calendar Task: $taskTitle',
      message:
          'You were assigned to calendar task "$taskTitle" scheduled for $scheduledDate$assignerStr.',
      eventType: NotificationEventType.calendarEventAssigned.value,
      actionId: 'CAL-$taskId',
      isRead: false,
      idempotencyKey: 'cal_asgn_${taskId}_$assigneeUserId',
      createdAt: DateTime.now(),
    );

    return createNotification(notif);
  }

  /// Event: Calendar task rescheduled or updated.
  Future<AppNotification?> notifyCalendarEventUpdated({
    required String taskId,
    required String taskTitle,
    required String recipientUserId,
    required String newDate,
    String? updatedByName,
    String? organizationId,
  }) async {
    if (recipientUserId.isEmpty) return null;

    final updaterStr =
        updatedByName != null && updatedByName.isNotEmpty ? ' by $updatedByName' : '';
    final notif = AppNotification(
      id: '',
      userId: recipientUserId,
      organizationId: organizationId,
      title: 'Event Rescheduled: $taskTitle',
      message:
          'Calendar task "$taskTitle" was rescheduled to $newDate$updaterStr.',
      eventType: NotificationEventType.calendarEventUpdated.value,
      actionId: 'CAL-$taskId',
      isRead: false,
      idempotencyKey:
          'cal_upd_${taskId}_${recipientUserId}_${newDate}_${DateTime.now().millisecondsSinceEpoch}',
      createdAt: DateTime.now(),
    );

    return createNotification(notif);
  }
}
