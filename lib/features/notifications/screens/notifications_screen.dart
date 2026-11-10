import 'package:flutter/material.dart';
import '../../../core/config/supabase_config.dart';
import '../widgets/notification_centre_view.dart';

/// Standalone Notifications Screen for ActionFlow.
class NotificationsScreen extends StatefulWidget {
  final String? userId;
  final String? organizationId;
  final bool isManager;
  final void Function(String actionId)? onActionTap;

  const NotificationsScreen({
    super.key,
    this.userId,
    this.organizationId,
    this.isManager = false,
    this.onActionTap,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String get _effectiveUserId =>
      widget.userId ??
      SupabaseConfig.clientOrNull?.auth.currentUser?.id ??
      'system-user';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications & Alerts'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: NotificationCentreView(
          userId: _effectiveUserId,
          organizationId: widget.organizationId,
          isManager: widget.isManager,
          onActionTap: widget.onActionTap,
        ),
      ),
    );
  }
}
