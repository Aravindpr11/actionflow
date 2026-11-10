import 'package:flutter/material.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/organization.dart';
import '../../../services/action_service.dart';
import '../../../services/auth_service.dart';
import '../../dashboard/manager_dashboard/models/action_record.dart';
import '../../dashboard/manager_dashboard/screens/action_details_screen.dart';
import '../widgets/calendar_view.dart';

/// Standalone Calendar Screen for ActionFlow.
class CalendarScreen extends StatefulWidget {
  final List<ActionRecord>? actions;
  final String? currentUserId;
  final String? organizationId;
  final bool isManager;
  final void Function(ActionRecord action)? onActionTap;

  const CalendarScreen({
    super.key,
    this.actions,
    this.currentUserId,
    this.organizationId,
    this.isManager = false,
    this.onActionTap,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final ActionService _actionService = ActionService.instance;
  List<ActionRecord> _actions = [];
  bool _isLoading = false;
  String _effectiveUserId = '';
  String _effectiveOrgId = '';

  @override
  void initState() {
    super.initState();
    _effectiveUserId = _resolveCurrentUserId();
    _effectiveOrgId = _resolveOrganizationId();

    if (widget.actions != null) {
      _actions = widget.actions!;
    } else {
      _loadActions();
    }
  }

  @override
  void didUpdateWidget(CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUserId != widget.currentUserId ||
        oldWidget.organizationId != widget.organizationId) {
      _effectiveUserId = _resolveCurrentUserId();
      _effectiveOrgId = _resolveOrganizationId();
      _loadActions();
    }
  }

  String _resolveCurrentUserId() {
    if (widget.currentUserId != null && widget.currentUserId!.isNotEmpty) {
      return widget.currentUserId!;
    }
    try {
      final authId = SupabaseConfig.clientOrNull?.auth.currentUser?.id;
      if (authId != null && authId.isNotEmpty) return authId;
    } catch (_) {}
    try {
      final profileId = AuthService.instance.currentProfile?.id;
      if (profileId != null && profileId.isNotEmpty) return profileId;
    } catch (_) {}
    return '';
  }

  String _resolveOrganizationId() {
    if (widget.organizationId != null && widget.organizationId!.isNotEmpty) {
      return widget.organizationId!;
    }
    try {
      final orgId = AuthService.instance.currentOrganizationId;
      if (orgId != null && orgId.isNotEmpty) return orgId;
    } catch (_) {}
    return Organization.sobhaId;
  }

  Future<void> _loadActions() async {
    setState(() => _isLoading = true);
    try {
      List<ActionRecord> fetched = [];
      if (widget.isManager) {
        fetched = await _actionService.fetchManagerActions(
          organizationId: _effectiveOrgId,
        );
      } else {
        fetched = await _actionService.fetchMyActions(
          userId: _effectiveUserId,
          organizationId: _effectiveOrgId,
        );
      }
      if (mounted) {
        setState(() {
          _actions = fetched;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _handleActionTap(ActionRecord action) {
    if (widget.onActionTap != null) {
      widget.onActionTap!(action);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActionDetailsScreen(
          action: action,
          isWorker: !widget.isManager,
          currentUserId: _effectiveUserId,
          onUpdateAction: _loadActions,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      appBar: AppBar(
        title: const Text('Action & Schedule Calendar'),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ActionFlowCalendarView(
                actions: _actions,
                currentUserId: _effectiveUserId,
                organizationId: _effectiveOrgId,
                isManager: widget.isManager,
                onActionTap: _handleActionTap,
                onRefresh: _loadActions,
              ),
            ),
    );
  }
}
