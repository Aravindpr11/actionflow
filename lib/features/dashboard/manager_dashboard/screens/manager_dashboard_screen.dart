import 'dart:async';
import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/core/theme/theme_controller.dart';
import 'package:action_flow/features/auth/screens/login_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/profile/widgets/profile_view_card.dart';
import 'package:action_flow/features/users/screens/users_screen.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:action_flow/widgets/common/action_flow_logo.dart';
import 'package:action_flow/widgets/common/theme_toggle_button.dart';
import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:action_flow/services/excel_export_service.dart';
import 'package:action_flow/services/report_service.dart';
import 'package:action_flow/features/reports/screens/reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:action_flow/services/email_service.dart';
import 'package:action_flow/features/notifications/models/app_notification.dart';
import 'package:action_flow/services/notification_service.dart';
import 'package:action_flow/services/sound_service.dart';
import 'package:action_flow/features/notifications/widgets/notification_dropdown_overlay.dart';
import 'package:action_flow/features/notifications/widgets/quick_alert_toast.dart';
import 'package:action_flow/features/calendar/widgets/calendar_view.dart';
import 'package:action_flow/features/notifications/widgets/notification_centre_view.dart';
import 'package:action_flow/models/document_record.dart';
import 'package:action_flow/services/document_service.dart';
import 'package:action_flow/widgets/documents/document_upload_dialog.dart';
import 'package:action_flow/widgets/documents/document_share_dialog.dart';
import 'package:action_flow/widgets/document_preview/document_preview_dialog.dart';

import '../models/action_record.dart';
import '../widgets/dashboard_header_banner.dart';
import '../widgets/dashboard_attention_section.dart';
import '../widgets/dashboard_kpi_cards.dart';
import '../widgets/dashboard_quick_actions.dart';
import '../widgets/dashboard_forwarded_actions_card.dart';
import '../widgets/dashboard_status_and_progress.dart';
import '../widgets/dashboard_workload_section.dart';
import '../widgets/dashboard_timeline_panel.dart';
import '../widgets/dashboard_upcoming_followups.dart';
import '../widgets/dashboard_recent_activity.dart';
import '../widgets/dashboard_followups_dialog.dart';
import 'package:action_flow/features/calendar/models/calendar_task.dart';
import 'package:action_flow/services/calendar_task_service.dart';
import 'package:action_flow/features/requests/models/request_models.dart';
import 'package:action_flow/features/requests/services/request_service.dart';
import 'package:action_flow/features/requests/screens/new_request_screen.dart';
import 'package:action_flow/features/requests/screens/request_approval_screen.dart';
import 'package:action_flow/features/requests/screens/my_requests_screen.dart';
import 'action_details_screen.dart';
import 'add_action_screen.dart';
import 'manager_action_update_screen.dart';

class ManagerDashboardScreen extends StatefulWidget {
  const ManagerDashboardScreen({
    super.key,
    this.userProfile,
    this.managerContext,
    this.initialActions,
    this.initialMyActions,
  });

  final UserProfile? userProfile;
  final ManagerContext? managerContext;
  final List<ActionRecord>? initialActions;
  final List<ActionRecord>? initialMyActions;

  @override
  State<ManagerDashboardScreen> createState() => _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends State<ManagerDashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Manager Context & Profile state
  late UserProfile _managerProfile;
  ManagerContext? _managerContext;

  // Real Supabase Actions & Metrics
  List<ActionRecord> _actions = [];
  List<ActionRecord> _myActions = [];
  List<CalendarTask> _personalTasks = [];
  DateTime? _calendarInitialDate;
  CalendarItemTypeFilter? _calendarInitialTypeFilter;
  bool _isLoadingActions = true;
  String? _errorMessage;

  // Request Overview State
  ManagerRequestOverviewCounts _managerRequestCounts = ManagerRequestOverviewCounts.zero;
  bool _isLoadingRequestCounts = true;
  String? _requestCountsError;
  int _requestApprovalInitialTab = 0;
  String _requestInitialStatus = 'All Statuses';
  // Navigation State
  int _selectedNavIndex = 0;

  // Filter States
  String _searchQuery = '';
  String _selectedStatus = 'All Status';
  String _selectedForwarded = 'All Actions';
  String _selectedDivision = 'All Divisions';
  String _selectedDepartment = 'All Departments';
  String _selectedSite = 'All Sites';
  String _selectedPriority = 'All Priority';
  String _selectedPerson = 'All People';
  String _selectedDate = 'Date';
  String _selectedDateField = 'All Dates';
  DateTime? _customDateStart;
  DateTime? _customDateEnd;
  String _selectedSort = 'Newest First';

  final Set<String> _selectedActionIds = <String>{};

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _managerProfile =
        widget.userProfile ??
        widget.managerContext?.profile ??
        UserProfile.mockManager();
    _managerContext = widget.managerContext;

    if (widget.initialActions != null || widget.initialMyActions != null) {
      _actions = List.from(widget.initialActions ?? []);
      _myActions = List.from(widget.initialMyActions ?? []);
      _isLoadingActions = false;
      _loadPersonalTasks();
      _loadRequestOverviewCounts();
    } else {
      _loadManagerData();
    }

    final authId = SupabaseConfig.clientOrNull?.auth.currentUser?.id ?? _managerProfile.id;
    if (authId.isNotEmpty) {
      NotificationService.instance.subscribeToRealtimeNotifications(authId);
    }
  }

  Future<void> _loadPersonalTasks() async {
    final currentAuthId =
        SupabaseConfig.clientOrNull?.auth.currentUser?.id ?? _managerProfile.id;
    if (currentAuthId.isEmpty) return;
    try {
      final tasks = await CalendarTaskService().getTasks(userId: currentAuthId);
      if (mounted) {
        setState(() {
          _personalTasks = tasks;
        });
      }
    } catch (e) {
      debugPrint('[ManagerDashboard] Error loading personal tasks: $e');
    }
  }

  Future<void> _loadManagerData() async {
    setState(() {
      _isLoadingActions = true;
      _errorMessage = null;
    });

    try {
      if (!SupabaseConfig.isInitialized) {
        await _loadRequestOverviewCounts();
        if (mounted) {
          setState(() {
            _isLoadingActions = false;
          });
        }
        return;
      }

      final currentAuthId =
          SupabaseConfig.client.auth.currentUser?.id ?? _managerProfile.id;

      if (currentAuthId.isNotEmpty) {
        final loadedCtx = await AuthService.instance.fetchManagerContext(
          currentAuthId,
        );
        if (loadedCtx != null) {
          _managerContext = loadedCtx;
          _managerProfile = loadedCtx.profile;
        }
      }

      final orgId =
          _managerContext?.organizationId ??
          _managerProfile.organizationId ??
          Organization.sobhaId;

      _loadRequestOverviewCounts();

      final results = await Future.wait([
        ActionService.instance.fetchManagerActions(
          organizationId: orgId,
          createdById: currentAuthId,
        ),
        ActionService.instance.fetchMyActions(
          organizationId: orgId,
          userId: currentAuthId,
        ),
        CalendarTaskService().getTasks(userId: currentAuthId),
      ]);

      final actions = results[0] as List<ActionRecord>;
      final myActions = results[1] as List<ActionRecord>;
      final personalTasks = results[2] as List<CalendarTask>;

      if (mounted) {
        setState(() {
          final Set<String> fetchedIds = actions.map((a) => a.id).toSet();
          final List<ActionRecord> merged = [...actions];
          for (final local in _actions) {
            if (!fetchedIds.contains(local.id)) {
              merged.insert(0, local);
            }
          }
          _actions = merged.where((a) => !a.isDeleted).toList();
          _myActions = myActions.where((a) => !a.isDeleted).toList();
          _personalTasks = personalTasks;
          final allKnownIds = {
            ...merged.map((a) => a.id),
            ...myActions.map((a) => a.id),
          };
          _selectedActionIds.removeWhere((id) => !allKnownIds.contains(id));
          _isLoadingActions = false;
        });
      }
    } catch (e, st) {
      debugPrint('[ManagerDashboard] Error loading manager data: $e\n$st');
      if (mounted) {
        setState(() {
          _errorMessage = 'Unable to load actions: $e';
          _isLoadingActions = false;
        });
      }
    }
  }

  Future<void> _loadRequestOverviewCounts() async {
    final currentAuthId =
        SupabaseConfig.clientOrNull?.auth.currentUser?.id ?? _managerProfile.id;
    final orgId = _managerContext?.organizationId ??
        _managerProfile.organizationId ??
        Organization.sobhaId;
    final roleLower = _managerProfile.role.trim().toLowerCase();
    final isCompanyAdmin = roleLower == 'admin' ||
        roleLower == 'superadmin' ||
        roleLower == 'super_admin' ||
        roleLower == 'company_admin' ||
        roleLower == 'platform_admin';

    final scopedDeptIds = _managerContext?.scopedDepartmentIds ?? <String>{};
    final scopedSiteIds = _managerContext?.scopedSiteIds ?? <String>{};
    final scopedDeptNames = _managerContext?.scopedDepartmentNames ?? <String>[];
    final scopedSiteNames = _managerContext?.scopedSiteNames ?? <String>[];

    try {
      final counts = await RequestService.instance.getManagerRequestOverviewCounts(
        userId: currentAuthId,
        organizationId: orgId,
        isCompanyAdmin: isCompanyAdmin,
        scopedDepartmentIds: scopedDeptIds,
        scopedSiteIds: scopedSiteIds,
        scopedDepartmentNames: scopedDeptNames,
        scopedSiteNames: scopedSiteNames,
      );
      if (mounted) {
        setState(() {
          _managerRequestCounts = counts;
          _isLoadingRequestCounts = false;
          _requestCountsError = null;
        });
      }
    } catch (e) {
      debugPrint('[ManagerDashboard] Error loading request overview counts: $e');
      if (mounted) {
        setState(() {
          _isLoadingRequestCounts = false;
          _requestCountsError = e.toString();
        });
      }
    }
  }

  void _navigateToRequestApproval({int tabIndex = 0, String status = 'All Statuses'}) {
    setState(() {
      _requestApprovalInitialTab = tabIndex;
      _requestInitialStatus = status;
      _selectedNavIndex = 12;
    });
  }

  Widget _buildRequestOverviewSection(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    if (_isLoadingRequestCounts) {
      return Container(
        height: 110,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.cardBg(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.cardBorder(context)),
        ),
        child: const Center(
          child: SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_requestCountsError != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.cardBg(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Color(0xFFDC2626), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Could not load request overview counts: $_requestCountsError',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _loadRequestOverviewCounts,
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('Retry', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    }

    final cards = [
      _ManagerRequestOverviewData(
        label: 'Total Requests',
        value: '${_managerRequestCounts.total}',
        subtext: 'In authorized scope',
        color: const Color(0xFF2563EB),
        bgColor: const Color(0xFFDBEAFE),
        icon: Icons.inbox_rounded,
        onTap: () => _navigateToRequestApproval(tabIndex: 4, status: 'All Statuses'),
      ),
      _ManagerRequestOverviewData(
        label: 'Pending My Approval',
        value: '${_managerRequestCounts.pendingMyApproval}',
        subtext: 'Awaiting your action',
        color: const Color(0xFFDC2626),
        bgColor: const Color(0xFFFEE2E2),
        icon: Icons.pending_actions_rounded,
        onTap: () => _navigateToRequestApproval(tabIndex: 0),
      ),
      _ManagerRequestOverviewData(
        label: 'Under Review',
        value: '${_managerRequestCounts.underReview}',
        subtext: 'In approval chain',
        color: const Color(0xFFD97706),
        bgColor: const Color(0xFFFEF3C7),
        icon: Icons.rule_rounded,
        onTap: () => _navigateToRequestApproval(tabIndex: 1),
      ),
      _ManagerRequestOverviewData(
        label: 'Approved',
        value: '${_managerRequestCounts.approved}',
        subtext: 'Ready for fulfillment',
        color: const Color(0xFF059669),
        bgColor: const Color(0xFFD1FAE5),
        icon: Icons.check_circle_outline_rounded,
        onTap: () => _navigateToRequestApproval(tabIndex: 2),
      ),
      _ManagerRequestOverviewData(
        label: 'Rejected',
        value: '${_managerRequestCounts.rejected}',
        subtext: 'Declined requests',
        color: const Color(0xFFE11D48),
        bgColor: const Color(0xFFFFE4E6),
        icon: Icons.cancel_outlined,
        onTap: () => _navigateToRequestApproval(tabIndex: 3),
      ),
      _ManagerRequestOverviewData(
        label: 'Completed',
        value: '${_managerRequestCounts.completed}',
        subtext: 'Fulfilled & closed',
        color: const Color(0xFF6B7280),
        bgColor: const Color(0xFFF3F4F6),
        icon: Icons.task_alt_rounded,
        onTap: () => _navigateToRequestApproval(tabIndex: 4, status: 'Completed'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            Row(
              children: [
                Icon(
                  Icons.assignment_outlined,
                  size: 18,
                  color: AppTheme.primaryAccent(context),
                ),
                const SizedBox(width: 8),
                Text(
                  'Request Overview',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            InkWell(
              onTap: () => _navigateToRequestApproval(tabIndex: 4),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    Text(
                      'View All Requests',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryAccent(context),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: AppTheme.primaryAccent(context),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            if (w >= 1200) {
              return Row(
                children: cards.map((data) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _ManagerRequestOverviewCard(data: data),
                    ),
                  );
                }).toList(),
              );
            } else if (w >= 768) {
              final cardWidth = (w - (2 * 12)) / 3;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: cards.map((data) {
                  return SizedBox(
                    width: cardWidth,
                    child: _ManagerRequestOverviewCard(data: data),
                  );
                }).toList(),
              );
            } else if (w >= 480) {
              final cardWidth = (w - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: cards.map((data) {
                  return SizedBox(
                    width: cardWidth,
                    child: _ManagerRequestOverviewCard(data: data),
                  );
                }).toList(),
              );
            } else {
              return Column(
                children: cards.map((data) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ManagerRequestOverviewCard(data: data),
                  );
                }).toList(),
              );
            }
          },
        ),
      ],
    );
  }

  List<String> _getUniqueAssignees() {
    final people = _actions
        .map((a) => a.assignedTo.trim())
        .where((p) => p.isNotEmpty && p != 'Unassigned' && p != 'Select staff')
        .toSet()
        .toList();
    people.sort();
    return people;
  }

  int get _followUpCount {
    int count = 0;
    for (final a in _actions) {
      if (a.isClosed || a.isDeleted) continue;
      final existingDates = <DateTime>{};
      final inactiveDates = <DateTime>{};

      for (final f in a.followUps) {
        final d = ReportService.parseDate(f.followUpDate);
        if (d != null) {
          final norm = DateTime(d.year, d.month, d.day);
          if (f.isCompleted || f.status.trim().toLowerCase() == 'cancelled') {
            inactiveDates.add(norm);
          } else {
            existingDates.add(norm);
            count++;
          }
        }
      }

      if (a.nextFollowUpDate.isNotEmpty &&
          a.nextFollowUpDate != 'Not set') {
        final d = ReportService.parseDate(a.nextFollowUpDate);
        if (d != null) {
          final norm = DateTime(d.year, d.month, d.day);
          if (!inactiveDates.contains(norm) && !existingDates.contains(norm)) {
            count++;
          }
        }
      }
    }
    return count;
  }

  String get _followUpSubtext {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int overdue = 0;
    int dueToday = 0;

    for (final a in _actions) {
      if (a.isClosed || a.isDeleted) continue;
      final existingDates = <DateTime>{};
      final inactiveDates = <DateTime>{};

      for (final f in a.followUps) {
        final d = ReportService.parseDate(f.followUpDate);
        if (d != null) {
          final norm = DateTime(d.year, d.month, d.day);
          if (f.isCompleted || f.status.trim().toLowerCase() == 'cancelled') {
            inactiveDates.add(norm);
          } else {
            existingDates.add(norm);
            if (norm.isBefore(today)) {
              overdue++;
            } else if (norm.year == today.year &&
                norm.month == today.month &&
                norm.day == today.day) {
              dueToday++;
            }
          }
        }
      }

      if (a.nextFollowUpDate.isNotEmpty &&
          a.nextFollowUpDate != 'Not set') {
        final d = ReportService.parseDate(a.nextFollowUpDate);
        if (d != null) {
          final norm = DateTime(d.year, d.month, d.day);
          if (!inactiveDates.contains(norm) && !existingDates.contains(norm)) {
            if (norm.isBefore(today)) {
              overdue++;
            } else if (norm.year == today.year &&
                norm.month == today.month &&
                norm.day == today.day) {
              dueToday++;
            }
          }
        }
      }
    }

    if (dueToday > 0) {
      return '$dueToday due today';
    } else if (overdue > 0) {
      return '$overdue overdue';
    } else {
      final total = _followUpCount;
      return total > 0 ? '$total pending' : 'No follow-ups';
    }
  }

  int get _personalTaskCount {
    return _personalTasks.where((t) => !t.isCompleted).length;
  }

  String get _personalTaskSubtext {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueToday = _personalTasks.where((t) {
      if (t.isCompleted) return false;
      return t.dueDate.year == today.year &&
          t.dueDate.month == today.month &&
          t.dueDate.day == today.day;
    }).length;

    if (dueToday > 0) {
      return '$dueToday due today';
    } else {
      final total = _personalTaskCount;
      return total > 0 ? '$total active' : 'No active tasks';
    }
  }

  void _showFollowUpsDialog(BuildContext context, [FollowUpClassification? initialClassification]) {
    DashboardFollowupsDialog.show(
      context,
      actions: _actions,
      onActionTap: _openActionDetails,
      initialClassification: initialClassification,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    NotificationService.instance.unsubscribeFromRealtime();
    super.dispose();
  }

  void _openAddAction() {
    setState(() {
      _selectedNavIndex =
          2; // Switch to embedded Add Action in persistent shell
    });
  }

  void _openActionDetails(ActionRecord action) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ActionDetailsScreen(
              action: action,
              currentUserId: _managerProfile.id,
              onUpdateAction: _loadManagerData,
              managerContext: _managerContext,
            ),
          ),
        )
        .then((_) => _loadManagerData());
  }

  Future<void> _handleNotificationTap(AppNotification notif) async {
    // 1. Mark as read immediately
    unawaited(NotificationService.instance.markAsRead(
      notificationId: notif.id,
      userId: notif.userId.isNotEmpty ? notif.userId : _managerProfile.id,
    ));

    // Request-related notification routing
    final combined = '${notif.title} ${notif.message} ${notif.actionId ?? ''}'.toUpperCase();
    final isRequest = combined.contains('REQ-') ||
        notif.eventType.toLowerCase().contains('request') ||
        (notif.actionId != null && notif.actionId!.toUpperCase().startsWith('REQ-'));

    if (isRequest) {
      if (!mounted) return;
      setState(() {
        _selectedNavIndex = 13; // My Requests
      });
      return;
    }

    // 2. Non-action notification
    if (!notif.isActionRelated) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(notif.message.isNotEmpty ? notif.message : notif.title),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // 3. Action-related notification
    final actionRef = notif.effectiveActionIdentifier;
    if (actionRef == null || actionRef.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Action reference is missing from this notification.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await _handleNotificationActionTap(actionRef);
  }

  Future<void> _handleNotificationActionTap(String actionId) async {
    final cleanId = ActionService.cleanActionId(actionId);
    if (cleanId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Action reference is missing from this notification.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // 1. Check in-memory actions list
    ActionRecord? match;
    for (final a in _actions) {
      if (ActionService.isActionMatch(a, cleanId)) {
        match = a;
        break;
      }
    }

    // 2. Check _myActions if separate
    if (match == null) {
      for (final a in _myActions) {
        if (ActionService.isActionMatch(a, cleanId)) {
          match = a;
          break;
        }
      }
    }

    // 3. If not in memory, query ActionService
    if (match == null) {
      try {
        match = await ActionService.instance.fetchActionById(cleanId);
      } on ActionLookupException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to load action: ${e.message}'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading action "$actionId". Please check your connection and try again.'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    if (!mounted) return;

    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Action "$actionId" could not be found.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // 4. Verify tenant isolation (organization check)
    final mgrOrgId = (_managerProfile.organizationId ??
            _managerContext?.organizationId ??
            '')
        .trim();
    if (mgrOrgId.isNotEmpty &&
        match.organizationId.trim().isNotEmpty &&
        match.organizationId.trim().toLowerCase() != mgrOrgId.toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You do not have permission to view action "$actionId".'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _openActionDetails(match);
  }

  void _openUpdateAction(ActionRecord action) {
    Navigator.of(context)
        .push<ActionRecord>(
          MaterialPageRoute(
            builder: (_) => ManagerActionUpdateScreen(
              action: action,
              currentUserId: _managerProfile.id,
            ),
          ),
        )
        .then((_) => _loadManagerData());
  }


  void _toggleActionSelection(String actionId) {
    setState(() {
      if (_selectedActionIds.contains(actionId)) {
        _selectedActionIds.remove(actionId);
      } else {
        _selectedActionIds.add(actionId);
      }
    });
  }

  void _selectAllVisibleActions(List<ActionRecord> visibleActions, bool select) {
    setState(() {
      if (select) {
        _selectedActionIds.addAll(visibleActions.map((a) => a.id));
      } else {
        _selectedActionIds.removeAll(visibleActions.map((a) => a.id));
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedActionIds.clear();
    });
  }

  void _resetAllFilters() {
    setState(() {
      _selectedStatus = 'All Status';
      _selectedForwarded = 'All Actions';
      _selectedPriority = 'All Priority';
      _selectedDivision = 'All Divisions';
      _selectedDepartment = 'All Departments';
      _selectedSite = 'All Sites';
      _selectedPerson = 'All People';
      _selectedDate = 'Date';
      _selectedDateField = 'All Dates';
      _customDateStart = null;
      _customDateEnd = null;
      _selectedSort = 'Newest First';
      _searchQuery = '';
      _searchController.clear();
    });
  }

  static DateTime? _parseDateString(String dateStr) {
    if (dateStr.isEmpty) return null;
    try {
      final parsed = DateTime.tryParse(dateStr);
      if (parsed != null) {
        final local = parsed.isUtc ? parsed.toLocal() : parsed;
        return DateTime(local.year, local.month, local.day);
      }
    } catch (_) {}

    // Handle DD Mon YYYY, DD-MM-YYYY, YYYY-MM-DD
    try {
      final parts = dateStr.trim().split(RegExp(r'[\s\-/]+'));
      if (parts.length >= 3) {
        // Check if first part is 4-digit year: YYYY-MM-DD
        if (parts[0].length == 4) {
          final year = int.tryParse(parts[0]);
          final month = int.tryParse(parts[1]);
          final day = int.tryParse(parts[2]);
          if (year != null && month != null && day != null) {
            return DateTime(year, month, day);
          }
        }

        final int? day = int.tryParse(parts[0]);
        final int? year = int.tryParse(parts[2]);
        int? month;

        final monthStr = parts[1].toLowerCase();
        const months = {
          'jan': 1,
          'january': 1,
          'feb': 2,
          'february': 2,
          'mar': 3,
          'march': 3,
          'apr': 4,
          'april': 4,
          'may': 5,
          'jun': 6,
          'june': 6,
          'jul': 7,
          'july': 7,
          'aug': 8,
          'august': 8,
          'sep': 9,
          'september': 9,
          'oct': 10,
          'october': 10,
          'nov': 11,
          'november': 11,
          'dec': 12,
          'december': 12,
        };
        month = months[monthStr] ?? int.tryParse(parts[1]);

        if (day != null && month != null && year != null) {
          return DateTime(year, month, day);
        }
      }
    } catch (_) {}
    return null;
  }

  static List<DateTime> _extractActionDates(ActionRecord action, String field) {
    switch (field) {
      case 'Target/Due Date':
      case 'Target / Due Date':
      case 'Due Date':
      case 'Target Date':
        final d = _parseDateString(action.targetDate);
        if (d != null) return [d];
        if (action.targetDateTime != null) {
          final t = action.targetDateTime!;
          return [DateTime(t.year, t.month, t.day)];
        }
        return [];
      case 'Raised Date':
      case 'Date Raised':
      case 'Created Date':
        final list = <DateTime>[];
        final d1 = _parseDateString(action.dateRaised);
        if (d1 != null) list.add(d1);
        if (action.createdAt != null) {
          final c = action.createdAt!.isUtc
              ? action.createdAt!.toLocal()
              : action.createdAt!;
          list.add(DateTime(c.year, c.month, c.day));
        }
        return list.toSet().toList();
      case 'Start Date':
        final list = <DateTime>[];
        final d1 = _parseDateString(action.startDate);
        if (d1 != null) list.add(d1);
        return list;
      case 'Follow-Up Date':
      case 'Next Follow-up Date':
      case 'Next Follow-Up Date':
      case 'Follow up Date':
        final list = <DateTime>[];
        final d1 = _parseDateString(action.nextFollowUpDate);
        if (d1 != null) list.add(d1);
        final d2 = _parseDateString(action.lastFollowUpDate);
        if (d2 != null) list.add(d2);
        for (final f in action.followUps) {
          final df = _parseDateString(f.followUpDate);
          if (df != null) list.add(df);
          if (f.createdAt != null) {
            final fc = f.createdAt!.isUtc
                ? f.createdAt!.toLocal()
                : f.createdAt!;
            list.add(DateTime(fc.year, fc.month, fc.day));
          }
        }
        return list.toSet().toList();
      case 'Closed Date':
      case 'Close Date':
        final list = <DateTime>[];
        if (action.closedAt != null) {
          final local = action.closedAt!.isUtc
              ? action.closedAt!.toLocal()
              : action.closedAt!;
          list.add(DateTime(local.year, local.month, local.day));
        }
        final d = _parseDateString(action.closeDate);
        if (d != null) list.add(d);
        return list.toSet().toList();
      case 'Update':
      case 'Update Date':
        final list = <DateTime>[];
        final dLatest = _parseDateString(action.latestUpdateDate);
        if (dLatest != null) list.add(dLatest);
        for (final u in action.progressUpdates) {
          final ud = _parseDateString(u.updateDate);
          if (ud != null) list.add(ud);
          if (u.createdAt != null) {
            final uc = u.createdAt!.isUtc
                ? u.createdAt!.toLocal()
                : u.createdAt!;
            list.add(DateTime(uc.year, uc.month, uc.day));
          }
        }
        return list.toSet().toList();
      case 'All Dates':
      default:
        final set = <DateTime>{};
        final dRaised = _parseDateString(action.dateRaised);
        if (dRaised != null) set.add(dRaised);
        final dStart = _parseDateString(action.startDate);
        if (dStart != null) set.add(dStart);
        final dDue = _parseDateString(action.targetDate);
        if (dDue != null) set.add(dDue);
        final dFollow = _parseDateString(action.nextFollowUpDate);
        if (dFollow != null) set.add(dFollow);
        final dLastFollow = _parseDateString(action.lastFollowUpDate);
        if (dLastFollow != null) set.add(dLastFollow);
        for (final f in action.followUps) {
          final df = _parseDateString(f.followUpDate);
          if (df != null) set.add(df);
          if (f.createdAt != null) {
            final fc = f.createdAt!.isUtc
                ? f.createdAt!.toLocal()
                : f.createdAt!;
            set.add(DateTime(fc.year, fc.month, fc.day));
          }
        }
        if (action.closedAt != null) {
          final c = action.closedAt!.isUtc
              ? action.closedAt!.toLocal()
              : action.closedAt!;
          set.add(DateTime(c.year, c.month, c.day));
        }
        final dClose = _parseDateString(action.closeDate);
        if (dClose != null) set.add(dClose);
        for (final u in action.progressUpdates) {
          final ud = _parseDateString(u.updateDate);
          if (ud != null) set.add(ud);
          if (u.createdAt != null) {
            final uc = u.createdAt!.isUtc
                ? u.createdAt!.toLocal()
                : u.createdAt!;
            set.add(DateTime(uc.year, uc.month, uc.day));
          }
        }
        return set.toList();
    }
  }

  static bool _dateMatchesPeriod(
    DateTime d,
    String filter, {
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (filter == 'Today') {
      return d.year == today.year &&
          d.month == today.month &&
          d.day == today.day;
    } else if (filter == 'Yesterday') {
      final yesterday = today.subtract(const Duration(days: 1));
      return d.year == yesterday.year &&
          d.month == yesterday.month &&
          d.day == yesterday.day;
    } else if (filter == 'This Week') {
      // Strict Monday to Sunday
      final monday = DateTime(
        today.year,
        today.month,
        today.day - (today.weekday - 1),
      );
      final sunday = DateTime(
        monday.year,
        monday.month,
        monday.day + 6,
        23,
        59,
        59,
      );
      return (d.isAtSameMomentAs(monday) || d.isAfter(monday)) &&
          (d.isAtSameMomentAs(sunday) || d.isBefore(sunday));
    } else if (filter == 'This Month') {
      return d.year == today.year && d.month == today.month;
    } else if (filter == 'This Year') {
      return d.year == today.year;
    } else if (filter == 'Custom Range') {
      if (customStart != null &&
          d.isBefore(
            DateTime(customStart.year, customStart.month, customStart.day),
          )) {
        return false;
      }
      if (customEnd != null &&
          d.isAfter(
            DateTime(
              customEnd.year,
              customEnd.month,
              customEnd.day,
              23,
              59,
              59,
            ),
          )) {
        return false;
      }
      return true;
    } else {
      // Month-Year format, e.g. "September 2026"
      const monthNames = [
        '',
        'january',
        'february',
        'march',
        'april',
        'may',
        'june',
        'july',
        'august',
        'september',
        'october',
        'november',
        'december',
      ];
      final lowerFilter = filter.toLowerCase();
      if (d.month >= 1 && d.month <= 12) {
        final mName = monthNames[d.month];
        final mShort = mName.substring(0, 3);
        final yearStr = d.year.toString();
        if ((lowerFilter.contains(mName) || lowerFilter.contains(mShort)) &&
            lowerFilter.contains(yearStr)) {
          return true;
        }
      }
      return false;
    }
  }

  static bool _matchesDateFilter(
    ActionRecord action,
    String filter, {
    String dateField = 'All Dates',
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    final hasDateField = dateField != 'All Dates';
    final hasPeriod = filter != 'Date' && filter != 'All Time';

    if (!hasDateField && !hasPeriod) return true;

    final dates = _extractActionDates(action, dateField);
    if (dates.isEmpty) return false;

    if (!hasPeriod) return true;

    return dates.any(
      (d) => _dateMatchesPeriod(
        d,
        filter,
        customStart: customStart,
        customEnd: customEnd,
      ),
    );
  }

  List<ActionRecord> _filterAndSortActionList(List<ActionRecord> list) {
    final filtered = list.where((action) {
      if (action.isDeleted) return false;
      // Search query filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.trim().toLowerCase();
        final matchesId = action.displayId.toLowerCase().contains(query);
        final matchesNumber = action.actionNumber.toLowerCase().contains(query);
        final matchesSubject = action.subject.toLowerCase().contains(query);
        final matchesDesc = action.description.toLowerCase().contains(query);
        final matchesReq = action.actionRequired.toLowerCase().contains(query);
        final matchesAssigned = action.assignedTo.toLowerCase().contains(query);
        final matchesPrimary =
            action.primaryAssignee?.name.toLowerCase().contains(query) ?? false;
        final matchesSite = action.site.toLowerCase().contains(query);
        final matchesDept = action.department.toLowerCase().contains(query);
        final matchesDiv = action.division.toLowerCase().contains(query);
        final matchesSec = action.section.toLowerCase().contains(query);
        final matchesAssignees = action.assignees.any(
          (a) => a.profileName.toLowerCase().contains(query),
        );
        final matchesContributors = action.contributors.any(
          (c) => c.userName.toLowerCase().contains(query),
        );
        if (!matchesId &&
            !matchesNumber &&
            !matchesSubject &&
            !matchesDesc &&
            !matchesReq &&
            !matchesAssigned &&
            !matchesPrimary &&
            !matchesSite &&
            !matchesDept &&
            !matchesDiv &&
            !matchesSec &&
            !matchesAssignees &&
            !matchesContributors) {
          return false;
        }
      }

      // Status filter
      if (_selectedStatus != 'All Status') {
        if (_selectedStatus == 'Closed') {
          if (!action.isClosed &&
              action.status.toLowerCase() != 'closed') {
            return false;
          }
        } else if (_selectedStatus == 'Ready for Review') {
          if (!action.isReadyForReview &&
              action.status.toLowerCase() != 'ready for review') {
            return false;
          }
        } else if (_selectedStatus == 'Pending Review') {
          if (action.status.toLowerCase() != 'pending review' &&
              !action.isReadyForReview) {
            return false;
          }
        } else if (_selectedStatus == 'Overdue') {
          if (!action.isOverdue &&
              action.status.toLowerCase() != 'overdue') {
            return false;
          }
        } else if (_selectedStatus == 'Open') {
          if (action.status.toLowerCase() != 'open') {
            return false;
          }
        } else if (_selectedStatus == 'In Progress') {
          if (action.status.toLowerCase() != 'in progress') {
            return false;
          }
        } else if (action.status.toLowerCase() !=
            _selectedStatus.toLowerCase()) {
          return false;
        }
      }

      // Forwarded filter
      if (_selectedForwarded != 'All Actions') {
        final uid = _managerProfile.id;
        final uname = _managerProfile.name;
        final uemail = _managerProfile.email;
        if (_selectedForwarded == 'Forwarded by Me') {
          if (!action.isForwardedBy(uid, uname, uemail)) return false;
        } else if (_selectedForwarded == 'Forwarded to Me') {
          if (!action.isForwardedTo(uid, uname, uemail)) return false;
        } else if (_selectedForwarded == 'Forwarded Only') {
          if (!action.isForwarded) return false;
        } else if (_selectedForwarded == 'Direct Only') {
          if (action.isForwarded) return false;
        }
      }

      // Priority filter
      if (_selectedPriority != 'All Priority') {
        if (_selectedPriority == 'Critical / High') {
          if (action.priority != 'Critical' && action.priority != 'High') {
            return false;
          }
        } else if (action.priority.toLowerCase() !=
            _selectedPriority.toLowerCase()) {
          return false;
        }
      }

      // Division filter
      if (_selectedDivision != 'All Divisions') {
        if (action.division.trim().toLowerCase() !=
            _selectedDivision.trim().toLowerCase()) {
          return false;
        }
      }

      // Department filter
      if (_selectedDepartment != 'All Departments') {
        if (action.department.trim().toLowerCase() !=
            _selectedDepartment.trim().toLowerCase()) {
          return false;
        }
      }

      // Site filter
      if (_selectedSite != 'All Sites') {
        if (action.site.trim().toLowerCase() !=
            _selectedSite.trim().toLowerCase()) {
          return false;
        }
      }

      // Person filter
      if (_selectedPerson != 'All People') {
        final p = _selectedPerson.trim().toLowerCase();
        final matchesDirect = action.assignedTo.toLowerCase().contains(p);
        final matchesPrimary =
            action.primaryAssignee?.name.toLowerCase().contains(p) ?? false;
        final matchesAssignees = action.assignees.any(
          (a) => a.profileName.toLowerCase().contains(p),
        );
        final matchesContributors = action.contributors.any(
          (c) => c.userName.toLowerCase().contains(p),
        );
        if (!matchesDirect &&
            !matchesPrimary &&
            !matchesAssignees &&
            !matchesContributors) {
          return false;
        }
      }

      // Date filter
      if (_selectedDateField != 'All Dates' ||
          (_selectedDate != 'Date' && _selectedDate != 'All Time')) {
        if (!_matchesDateFilter(
          action,
          _selectedDate,
          dateField: _selectedDateField,
          customStart: _customDateStart,
          customEnd: _customDateEnd,
        )) {
          return false;
        }
      }

      return true;
    }).toList();

    if (_selectedSort == 'Target Date') {
      filtered.sort((a, b) => a.targetDate.compareTo(b.targetDate));
    } else if (_selectedSort == 'Priority') {
      const rank = {'Critical': 0, 'High': 1, 'Medium': 2, 'Low': 3};
      filtered.sort(
        (a, b) => (rank[a.priority] ?? 4).compareTo(rank[b.priority] ?? 4),
      );
    } else if (_selectedSort == 'Progress') {
      filtered.sort((a, b) => b.percentComplete.compareTo(a.percentComplete));
    } else if (_selectedSort == 'Newest First') {
      filtered.sort((a, b) {
        final da = _parseDateString(a.dateRaised) ??
            a.createdAt ??
            a.createdDateTime ??
            DateTime(1970);
        final db = _parseDateString(b.dateRaised) ??
            b.createdAt ??
            b.createdDateTime ??
            DateTime(1970);
        final cmp = db.compareTo(da);
        if (cmp != 0) return cmp;
        return b.displayId.compareTo(a.displayId);
      });
    } else if (_selectedSort == 'Oldest First') {
      filtered.sort((a, b) {
        final da = _parseDateString(a.dateRaised) ??
            a.createdAt ??
            a.createdDateTime ??
            DateTime(1970);
        final db = _parseDateString(b.dateRaised) ??
            b.createdAt ??
            b.createdDateTime ??
            DateTime(1970);
        final cmp = da.compareTo(db);
        if (cmp != 0) return cmp;
        return a.displayId.compareTo(b.displayId);
      });
    }

    return filtered;
  }

  void _handleExportExcel(List<ActionRecord> actionsToExport) {
    final activeFilters = <String, String>{};
    if (_searchQuery.isNotEmpty) activeFilters['Search'] = _searchQuery;
    if (_selectedStatus != 'All Status') {
      activeFilters['Status'] = _selectedStatus;
    }
    if (_selectedForwarded != 'All Actions') {
      activeFilters['Forwarded'] = _selectedForwarded;
    }
    if (_selectedPriority != 'All Priority') {
      activeFilters['Priority'] = _selectedPriority;
    }
    if (_selectedDivision != 'All Divisions') {
      activeFilters['Division'] = _selectedDivision;
    }
    if (_selectedDepartment != 'All Departments') {
      activeFilters['Department'] = _selectedDepartment;
    }
    if (_selectedSite != 'All Sites') {
      activeFilters['Site'] = _selectedSite;
    }
    if (_selectedPerson != 'All People') {
      activeFilters['Person'] = _selectedPerson;
    }
    if (_selectedDateField != 'All Dates') {
      activeFilters['Date Field'] = _selectedDateField;
    }
    if (_selectedDate != 'Date' && _selectedDate != 'All Time') {
      if (_selectedDate == 'Custom Range' &&
          _customDateStart != null &&
          _customDateEnd != null) {
        final s = _customDateStart!;
        final e = _customDateEnd!;
        activeFilters['Date Range'] =
            '${s.day.toString().padLeft(2, '0')}/${s.month.toString().padLeft(2, '0')}/${s.year} - ${e.day.toString().padLeft(2, '0')}/${e.month.toString().padLeft(2, '0')}/${e.year}';
      } else {
        activeFilters['Date'] = _selectedDate;
      }
    }

    ExcelExportService.instance.exportFilteredActions(
      context: context,
      filteredActions: actionsToExport,
      userName: _managerProfile.name.isNotEmpty
          ? _managerProfile.name
          : 'Operations Manager',
      userRole: _managerProfile.role,
      organizationName: _managerProfile.organizationName.isNotEmpty
          ? _managerProfile.organizationName
          : Organization.sobhaName,
      activeFilters: activeFilters,
    );
  }

  void _handleExportReportExcel(
    List<ActionRecord> actionsToExport,
    Map<String, String> activeFilters,
  ) {
    ExcelExportService.instance.exportReportExcel(
      context: context,
      filteredActions: actionsToExport,
      userName: _managerProfile.name.isNotEmpty
          ? _managerProfile.name
          : 'Operations Manager',
      userRole: _managerProfile.role,
      organizationName: _managerProfile.organizationName.isNotEmpty
          ? _managerProfile.organizationName
          : Organization.sobhaName,
      activeFilters: activeFilters,
    );
  }

  void _handleEditAction(ActionRecord action) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => AddActionScreen(
              actionId: action.id,
              existingAction: action,
              managerContext: _managerContext,
              isEmbedded: false,
              onSaved: (_) => _loadManagerData(),
            ),
          ),
        )
        .then((_) => _loadManagerData());
  }

  Future<void> _handleDeleteAction(
    ActionRecord action, {
    bool allowClosedDelete = false,
  }) async {
    if (action.isClosed && !allowClosedDelete) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.cardBg(ctx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  color: Color(0xFF16A34A),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Closed Action Retained',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Text(
            'Action ${action.displayId} has been formally closed and verified.\n\n'
            'Under safety and quality compliance standards, closed actions cannot be deleted. '
            'They are permanently retained in the Action Register for audit trails, reporting, and historical verification.',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textPrimary(ctx),
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Understood'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardBg(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.delete_forever_rounded,
                color: Color(0xFFDC2626),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Delete Action',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.actionIdBg(ctx),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.actionIdBorder(ctx)),
              ),
              child: Text(
                action.displayId,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.actionIdText(ctx),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              action.subject,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary(ctx),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Are you sure you want to permanently delete this action? '
              'All associated progress history will be removed. This operation cannot be undone.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSecondary(ctx),
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete Action'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final res = await ActionService.instance.deleteActionAuthorized(
        action.id,
        allowClosed: allowClosedDelete,
      );
      if (!mounted) return;

      if (res.success) {
        setState(() {
          _actions.removeWhere((a) => a.id == action.id);
          _myActions.removeWhere((a) => a.id == action.id);
          _selectedActionIds.remove(action.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Action ${action.displayId} was deleted successfully.',
            ),
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (res.error == 'CLOSED_ACTION') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Closed actions cannot be deleted. Retained for audit.',
            ),
            backgroundColor: Color(0xFFD97706),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.error ?? 'Failed to delete action.'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleDeleteSelectedActions(List<ActionRecord> visibleActions) async {
    final selectedActions = visibleActions
        .where((a) => _selectedActionIds.contains(a.id))
        .toList();
    if (selectedActions.isEmpty) return;

    final count = selectedActions.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardBg(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.delete_sweep_rounded,
                color: Color(0xFFDC2626),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Delete Selected Actions',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete $count selected action${count == 1 ? '' : 's'}? '
          'These actions will be removed from active views. Their audit history will be retained.',
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.textPrimary(ctx),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: Text('Delete $count Action${count == 1 ? '' : 's'}'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final selectedIds = selectedActions.map((a) => a.id).toList();
      final res = await ActionService.instance.deleteActionsBulk(
        selectedIds,
        allowClosed: true,
      );
      if (!mounted) return;

      if (res.success || res.deletedCount > 0) {
        setState(() {
          _actions.removeWhere((a) => selectedIds.contains(a.id));
          _myActions.removeWhere((a) => selectedIds.contains(a.id));
          _selectedActionIds.removeAll(selectedIds);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${res.deletedCount} action${res.deletedCount == 1 ? '' : 's'} deleted successfully.',
            ),
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res.error ?? 'Failed to delete selected actions.',
            ),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  List<ActionRecord> _getFilteredActions() {
    final currentUserId =
        SupabaseConfig.clientOrNull?.auth.currentUser?.id ?? _managerProfile.id;
    final registerActions = currentUserId.isNotEmpty
        ? _actions.where((a) {
            // Manager Action Register strict isolation:
            // Only actions created or registered by the authenticated Manager are visible.
            // Actions with unknown/empty creators or created by Staff are strictly excluded.
            return a.createdById.isNotEmpty && a.createdById == currentUserId;
          }).toList()
        : _actions;
    return _filterAndSortActionList(registerActions);
  }

  List<ActionRecord> _getMyActions() {
    final currentUserId =
        SupabaseConfig.clientOrNull?.auth.currentUser?.id ?? _managerProfile.id;

    // Filter: MUST match authenticated user's profile UUID as Owner, Assignee, or Contributor.
    // External recipients are NEVER internal users and must NOT appear in My Actions.
    final myBase = _myActions.where((a) {
      if (a.isExternalRecipient) return false;
      if (currentUserId.isEmpty) return false;
      if (a.assignedToId == currentUserId) return true;
      if (a.assignees.any((asg) => asg.profileId == currentUserId)) return true;
      if (a.contributors.any((c) => c.profileId == currentUserId)) return true;
      return false;
    }).toList();

    return _filterAndSortActionList(myBase);
  }

  void _handleNavSelection(int index) {
    setState(() {
      _selectedNavIndex = index;
      if (index != 4) {
        _calendarInitialTypeFilter = null;
      }
    });
    if (index == 0) {
      _loadPersonalTasks();
    }
  }

  void _handleLogout() async {
    QuickAlertListener.resetSession(_managerProfile.id);
    await AuthService.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final navItems = <_NavItemData>[
      _NavItemData(
        'Dashboard',
        Icons.dashboard_rounded,
        _selectedNavIndex == 0,
        0,
      ),
      _NavItemData(
        'Action Register',
        Icons.table_chart_rounded,
        _selectedNavIndex == 1,
        1,
      ),
      _NavItemData(
        'Add Action',
        Icons.add_circle_outline_rounded,
        _selectedNavIndex == 2,
        2,
      ),
      _NavItemData(
        'My Actions',
        Icons.assignment_turned_in_rounded,
        _selectedNavIndex == 3,
        3,
      ),
      _NavItemData(
        'Calendar',
        Icons.calendar_month_rounded,
        _selectedNavIndex == 4,
        4,
      ),
      _NavItemData(
        'Reports & Graphs',
        Icons.bar_chart_rounded,
        _selectedNavIndex == 5,
        5,
      ),
      _NavItemData(
        'Notifications',
        Icons.notifications_none_rounded,
        _selectedNavIndex == 6,
        6,
      ),
      _NavItemData('Documents', Icons.folder_outlined, _selectedNavIndex == 7, 7),
      _NavItemData(
        'New Request',
        Icons.note_add_outlined,
        _selectedNavIndex == 11,
        11,
      ),
      _NavItemData(
        'Request Approval',
        Icons.fact_check_outlined,
        _selectedNavIndex == 12,
        12,
      ),
      _NavItemData(
        'My Requests',
        Icons.assignment_outlined,
        _selectedNavIndex == 13,
        13,
      ),
      _NavItemData('Users', Icons.people_alt_outlined, _selectedNavIndex == 8, 8),
      _NavItemData('Settings', Icons.settings_outlined, _selectedNavIndex == 9, 9),
      _NavItemData(
        'My Profile',
        Icons.account_circle_outlined,
        _selectedNavIndex == 10,
        10,
      ),
    ];

    final currentUserId = widget.userProfile?.id ??
        (_managerProfile.id.isNotEmpty ? _managerProfile.id : null) ??
        SupabaseConfig.clientOrNull?.auth.currentUser?.id ??
        'manager-user';

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.scaffoldBg(context),
      drawer: MediaQuery.sizeOf(context).width >= 1100
          ? null
          : Drawer(
              child: _EnterpriseSidebar(
                navItems: navItems,
                selectedIndex: _selectedNavIndex,
                onNavSelected: (index) {
                  Navigator.of(context).pop();
                  _handleNavSelection(index);
                },
              ),
            ),
      body: QuickAlertListener(
        userId: currentUserId,
        onActionTap: _handleNotificationActionTap,
        onNotificationTap: _handleNotificationTap,
        onViewNotifications: () {
          setState(() {
            _selectedNavIndex = 6;
          });
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showSidebar = constraints.maxWidth >= 1100;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Persistent Left Sidebar
                if (showSidebar)
                  _EnterpriseSidebar(
                    navItems: navItems,
                    selectedIndex: _selectedNavIndex,
                    onNavSelected: _handleNavSelection,
                  ),

                // Persistent Right Area (Header + Animated Content)
                Expanded(
                  child: Column(
                    children: [
                      // Persistent Top Header
                      _TopHeader(
                        isMobile: !showSidebar,
                        searchController: _searchController,
                        profile: _managerProfile,
                        userId: currentUserId,
                        organizationId: _managerProfile.organizationId ??
                            _managerContext?.organizationId,
                        onActionTap: _handleNotificationActionTap,
                        onNotificationItemTap: _handleNotificationTap,
                      onProfileTap: () {
                        setState(() {
                          _selectedNavIndex = 10;
                        });
                      },
                      onNotificationTap: () {
                        setState(() {
                          _selectedNavIndex = 6;
                        });
                      },
                      onSearchChanged: (val) {
                        setState(() {
                          _searchQuery = val;
                        });
                      },
                      onMenuTap: () {
                        _scaffoldKey.currentState?.openDrawer();
                      },
                      onLogout: _handleLogout,
                    ),

                    // Main Content Area with Subtle Transition
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOut,
                            ),
                            child: child,
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey(
                            'content_$_selectedNavIndex',
                          ),
                          child: _buildActiveContent(constraints: constraints),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      ),
    );
  }

  Widget _buildActiveContent({required BoxConstraints constraints}) {
    final horizontalPadding = constraints.maxWidth < 600 ? 12.0 : 20.0;
    final padding = EdgeInsets.fromLTRB(
      horizontalPadding,
      16.0,
      horizontalPadding,
      20.0,
    );

    if (_isLoadingActions) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.red,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textPrimary(context),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadManagerData,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // 1. Redesigned Executive Manager Dashboard (Index 0)
    if (_selectedNavIndex == 0) {
      final orgName = _managerProfile.organizationName.isNotEmpty
          ? _managerProfile.organizationName
          : (_managerContext?.organizationName ?? Organization.sobhaName);
      final mgrName = _managerProfile.name.isNotEmpty
          ? _managerProfile.name
          : 'Operations Manager';

      return SingleChildScrollView(
        key: const PageStorageKey('manager_dashboard_scroll'),
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header Banner
            DashboardHeaderBanner(
              organizationName: orgName,
              managerName: mgrName,
              onViewFullReports: () => _handleNavSelection(5),
            ),
            const SizedBox(height: 20),

            // "Needs Your Attention" Section
            DashboardAttentionSection(
              actions: _actions,
              onActionTap: _openActionDetails,
            ),
            const SizedBox(height: 20),

            // 9 KPI Summary Cards (Including Follow-ups & Personal Tasks)
            DashboardKpiCards(
              actions: _actions,
              followUpCount: _followUpCount,
              followUpSubtext: _followUpSubtext,
              personalTaskCount: _personalTaskCount,
              personalTaskSubtext: _personalTaskSubtext,
              onKpiTap: (label) {
                if (label == 'Total Actions') {
                  _selectedStatus = 'All Status';
                  _selectedPriority = 'All Priority';
                  _handleNavSelection(1);
                } else if (label == 'Open') {
                  _selectedStatus = 'Open';
                  _selectedPriority = 'All Priority';
                  _handleNavSelection(1);
                } else if (label == 'In Progress') {
                  _selectedStatus = 'In Progress';
                  _selectedPriority = 'All Priority';
                  _handleNavSelection(1);
                } else if (label == 'Overdue') {
                  _selectedStatus = 'Overdue';
                  _selectedPriority = 'All Priority';
                  _handleNavSelection(1);
                } else if (label == 'Ready for Review') {
                  _selectedStatus = 'Ready for Review';
                  _selectedPriority = 'All Priority';
                  _handleNavSelection(1);
                } else if (label == 'Closed') {
                  _selectedStatus = 'Closed';
                  _selectedPriority = 'All Priority';
                  _handleNavSelection(1);
                } else if (label == 'Average Completion %') {
                  _handleNavSelection(5);
                } else if (label == 'Follow-ups') {
                  _showFollowUpsDialog(context);
                } else if (label == 'Personal Tasks') {
                  setState(() {
                    _calendarInitialDate = DateTime.now();
                    _calendarInitialTypeFilter = CalendarItemTypeFilter.personalTasksOnly;
                  });
                  _handleNavSelection(4);
                }
              },
            ),
            const SizedBox(height: 20),

            _buildRequestOverviewSection(context),
            const SizedBox(height: 20),

            // Quick Actions Row
            DashboardQuickActions(
              onAddAction: _openAddAction,
              onActionRegister: () => _handleNavSelection(1),
              onMyActions: () => _handleNavSelection(3),
              onReports: () => _handleNavSelection(5),
              onCalendar: () => _handleNavSelection(4),
            ),
            const SizedBox(height: 20),

            // Forwarded Actions Card
            DashboardForwardedActionsCard(
              actions: _actions,
              currentUserId: _managerProfile.id,
              currentUserName: _managerProfile.name,
              currentUserEmail: _managerProfile.email,
              isManager: true,
              onTapCard: () {
                setState(() => _selectedForwarded = 'Forwarded Only');
                _handleNavSelection(1);
              },
              onTapForwardedToMe: () {
                setState(() => _selectedForwarded = 'Forwarded to Me');
                _handleNavSelection(1);
              },
              onTapForwardedByMe: () {
                setState(() => _selectedForwarded = 'Forwarded by Me');
                _handleNavSelection(1);
              },
            ),
            const SizedBox(height: 20),

            // Action Status Overview & Completion Overview
            DashboardStatusAndProgress(
              actions: _actions,
              onStatusTap: (status) {
                _selectedStatus = status;
                _handleNavSelection(1);
              },
            ),
            const SizedBox(height: 20),

            // Workload by Organization
            DashboardWorkloadSection(
              actions: _actions,
              onViewFullReports: () => _handleNavSelection(5),
            ),
            const SizedBox(height: 20),

            // Bottom Row: Actions Due vs Completed, Upcoming Follow-Ups, Recent Activity
            LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final isDesktop = w >= 1100;
                final isTablet = w >= 700 && !isDesktop;

                if (isDesktop) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 38,
                        child: DashboardTimelinePanel(actions: _actions),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 31,
                        child: DashboardUpcomingFollowups(
                          actions: _actions,
                          onActionTap: _openActionDetails,
                          onOpenCalendar: () => _handleNavSelection(4),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 31,
                        child: DashboardRecentActivity(
                          actions: _actions,
                          onActionTap: _openActionDetails,
                          onViewAll: () => _handleNavSelection(1),
                        ),
                      ),
                    ],
                  );
                } else if (isTablet) {
                  return Column(
                    children: [
                      DashboardTimelinePanel(actions: _actions),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: DashboardUpcomingFollowups(
                              actions: _actions,
                              onActionTap: _openActionDetails,
                              onOpenCalendar: () => _handleNavSelection(4),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: DashboardRecentActivity(
                              actions: _actions,
                              onActionTap: _openActionDetails,
                              onViewAll: () => _handleNavSelection(1),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      DashboardTimelinePanel(actions: _actions),
                      const SizedBox(height: 16),
                      DashboardUpcomingFollowups(
                        actions: _actions,
                        onActionTap: _openActionDetails,
                        onOpenCalendar: () => _handleNavSelection(4),
                      ),
                      const SizedBox(height: 16),
                      DashboardRecentActivity(
                        actions: _actions,
                        onActionTap: _openActionDetails,
                        onViewAll: () => _handleNavSelection(1),
                      ),
                    ],
                  );
                }
              },
            ),
          ],
        ),
      );
    }

    // 2. Action Register (Index 1)
    if (_selectedNavIndex == 1) {
      return SingleChildScrollView(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ActionRegisterSection(
              currentUserId: _managerProfile.id,
              isDrillDown: false,
              drillDownTitle: 'Action Register',
              actions: _getFilteredActions(),
              searchQuery: _searchQuery,
              selectedStatus: _selectedStatus,
              selectedForwarded: _selectedForwarded,
              selectedDivision: _selectedDivision,
              selectedDepartment: _selectedDepartment,
              selectedSite: _selectedSite,
              selectedPriority: _selectedPriority,
              selectedPerson: _selectedPerson,
              selectedDate: _selectedDate,
              selectedDateField: _selectedDateField,
              customDateStart: _customDateStart,
              customDateEnd: _customDateEnd,
              selectedSort: _selectedSort,
              departmentOptions: [
                'All Departments',
                ...(_managerContext?.scopedDepartmentNames ?? []),
              ],
              siteOptions: [
                'All Sites',
                ...(_managerContext != null
                    ? _managerContext!.permittedSiteNamesForDepartmentName(
                        _selectedDepartment,
                      )
                    : []),
              ],
              personOptions: ['All People', ..._getUniqueAssignees()],
              onSearchChanged: (val) => setState(() => _searchQuery = val),
              onStatusChanged: (val) => setState(() => _selectedStatus = val),
              onForwardedChanged: (val) => setState(() => _selectedForwarded = val),
              onDivisionChanged: (val) =>
                  setState(() => _selectedDivision = val),
              onDepartmentChanged: (val) =>
                  setState(() => _selectedDepartment = val),
              onSiteChanged: (val) => setState(() => _selectedSite = val),
              onPriorityChanged: (val) =>
                  setState(() => _selectedPriority = val),
              onPersonChanged: (val) => setState(() => _selectedPerson = val),
              onDateChanged: (val) => setState(() => _selectedDate = val),
              onDateFieldChanged: (val) =>
                  setState(() => _selectedDateField = val),
              onCustomDateRangeChanged: (range) => setState(() {
                _customDateStart = range?.start;
                _customDateEnd = range?.end;
              }),
              onSortChanged: (val) => setState(() => _selectedSort = val),
              onActionTap: (action) {
                Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => ActionDetailsScreen(
                          action: action,
                          onUpdateAction: _loadManagerData,
                          managerContext: _managerContext,
                        ),
                      ),
                    )
                    .then((_) => _loadManagerData());
              },
              onEditActionTap: _handleEditAction,
              onDeleteActionTap: _handleDeleteAction,
              onAddAction: _openAddAction,
              onExportExcel: _handleExportExcel,
              onResetFilters: _resetAllFilters,
              selectedActionIds: _selectedActionIds,
              onToggleSelect: _toggleActionSelection,
              onSelectAll: (val) =>
                  _selectAllVisibleActions(_getFilteredActions(), val),
              onDeleteSelected: () =>
                  _handleDeleteSelectedActions(_getFilteredActions()),
              onClearSelection: _clearSelection,
            ),
          ],
        ),
      );
    }

    // 3. Add Action (Index 2)
    if (_selectedNavIndex == 2) {
      return AddActionScreen(
        isEmbedded: true,
        actionId: 'AUTO',
        managerContext: _managerContext,
        onClose: () => setState(() => _selectedNavIndex = 0),
        onSaved: (action) {
          setState(() {
            _actions.removeWhere((a) => a.id == action.id);
            _actions.insert(0, action);
            _selectedNavIndex = 0;
          });
          _loadManagerData();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${action.displayId} added to the Action Register'),
              backgroundColor: const Color(0xFF1565C0),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      );
    }

    // 4. My Actions (Index 3)
    if (_selectedNavIndex == 3) {
      return SingleChildScrollView(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ActionRegisterSection(
              currentUserId: _managerProfile.id,
              isDrillDown: true,
              drillDownTitle: 'My Actions',
              actions: _getMyActions(),
              searchQuery: _searchQuery,
              selectedStatus: _selectedStatus,
              selectedForwarded: _selectedForwarded,
              selectedDivision: _selectedDivision,
              selectedDepartment: _selectedDepartment,
              selectedSite: _selectedSite,
              selectedPriority: _selectedPriority,
              selectedPerson: _selectedPerson,
              selectedDate: _selectedDate,
              selectedDateField: _selectedDateField,
              customDateStart: _customDateStart,
              customDateEnd: _customDateEnd,
              selectedSort: _selectedSort,
              departmentOptions: [
                'All Departments',
                ...(_managerContext?.scopedDepartmentNames ?? []),
              ],
              siteOptions: [
                'All Sites',
                ...(_managerContext != null
                    ? _managerContext!.permittedSiteNamesForDepartmentName(
                        _selectedDepartment,
                      )
                    : []),
              ],
              personOptions: ['All People', ..._getUniqueAssignees()],
              onSearchChanged: (val) => setState(() => _searchQuery = val),
              onStatusChanged: (val) => setState(() => _selectedStatus = val),
              onForwardedChanged: (val) => setState(() => _selectedForwarded = val),
              onDivisionChanged: (val) =>
                  setState(() => _selectedDivision = val),
              onDepartmentChanged: (val) =>
                  setState(() => _selectedDepartment = val),
              onSiteChanged: (val) => setState(() => _selectedSite = val),
              onPriorityChanged: (val) =>
                  setState(() => _selectedPriority = val),
              onPersonChanged: (val) => setState(() => _selectedPerson = val),
              onDateChanged: (val) => setState(() => _selectedDate = val),
              onDateFieldChanged: (val) =>
                  setState(() => _selectedDateField = val),
              onCustomDateRangeChanged: (range) => setState(() {
                _customDateStart = range?.start;
                _customDateEnd = range?.end;
              }),
              onSortChanged: (val) => setState(() => _selectedSort = val),
              onActionTap: (action) {
                Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => ActionDetailsScreen(
                          action: action,
                          onUpdateAction: _loadManagerData,
                          managerContext: _managerContext,
                        ),
                      ),
                    )
                    .then((_) => _loadManagerData());
              },
              onUpdateActionTap: _openUpdateAction,
              onEditActionTap: _handleEditAction,
              onDeleteActionTap: (action) =>
                  _handleDeleteAction(action, allowClosedDelete: true),
              onAddAction: _openAddAction,
              onExportExcel: _handleExportExcel,
              onResetFilters: _resetAllFilters,
              selectedActionIds: _selectedActionIds,
              onToggleSelect: _toggleActionSelection,
              onSelectAll: (val) =>
                  _selectAllVisibleActions(_getMyActions(), val),
              onDeleteSelected: () =>
                  _handleDeleteSelectedActions(_getMyActions()),
              onClearSelection: _clearSelection,
            ),
          ],
        ),
      );
    }

    // 5. Calendar (Index 4)
    if (_selectedNavIndex == 4) {
      return SingleChildScrollView(
        padding: padding,
        child: ActionFlowCalendarView(
          actions: _actions,
          currentUserId: _managerProfile.id,
          organizationId: _managerProfile.organizationId ??
              _managerContext?.organizationId,
          isManager: true,
          initialDate: _calendarInitialDate,
          initialTypeFilter: _calendarInitialTypeFilter,
          onActionTap: _openActionDetails,
          onRefresh: () {
            _loadManagerData();
            _loadPersonalTasks();
          },
        ),
      );
    }

    // 6. Reports & Graphs (Index 5)
    if (_selectedNavIndex == 5) {
      final deptNames = _managerContext?.scopedDepartmentNames ?? [];
      final siteNames = _managerContext?.scopedSiteNames ?? [];
      return SingleChildScrollView(
        padding: padding,
        child: ManagerReportsScreen(
          allActions: _actions,
          managerContext: _managerContext,
          userProfile: _managerProfile,
          onActionTap: (action) {
            Navigator.of(context)
                .push<void>(
                  MaterialPageRoute(
                    builder: (_) => ActionDetailsScreen(
                      action: action,
                      currentUserId: _managerProfile.id,
                      managerContext: _managerContext,
                      onUpdateAction: _loadManagerData,
                    ),
                  ),
                )
                .then((_) => _loadManagerData());
          },
          onExportExcel: (filteredActions, [filters]) {
            _handleExportReportExcel(filteredActions, filters ?? {});
          },
          onRefresh: () => _loadManagerData(),
          departmentOptions: ['All Departments', ...deptNames],
          siteOptions: ['All Sites', ...siteNames],
          divisionOptions: [],
          assigneeOptions: ['All People', ..._getUniqueAssignees()],
        ),
      );
    }

    // 7. Notifications (Index 6)
    if (_selectedNavIndex == 6) {
      return SingleChildScrollView(
        padding: padding,
        child: NotificationCentreView(
          userId: _managerProfile.id,
          organizationId: _managerProfile.organizationId ??
              _managerContext?.organizationId,
          isManager: true,
          title: 'Notifications & Alerts',
          onActionTap: _handleNotificationActionTap,
          onNotificationTap: _handleNotificationTap,
        ),
      );
    }

    // 8. Documents (Index 7)
    if (_selectedNavIndex == 7) {
      return SingleChildScrollView(
        padding: padding,
        child: _DocumentsPortalView(
          organizationId: _managerProfile.organizationId ??
              _managerContext?.organizationId,
          currentUserId: _managerProfile.id,
          currentUserName: _managerProfile.name,
          managerProfile: _managerProfile,
          actions: _actions,
          managerContext: _managerContext,
        ),
      );
    }

    // 9. Users (Index 8)
    if (_selectedNavIndex == 8) {
      return UsersScreen(
        isEmbedded: true,
        managerContext: _managerContext,
        onClose: () => setState(() => _selectedNavIndex = 0),
      );
    }

    // 10. Settings (Index 9)
    if (_selectedNavIndex == 9) {
      return SingleChildScrollView(
        padding: padding,
        child: const _SettingsPortalView(),
      );
    }

    // 11. Profile (Index 10)
    if (_selectedNavIndex == 10) {
      return SingleChildScrollView(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfileViewCard(
              profile: _managerProfile,
              title: 'Manager Profile',
              onProfileUpdated: (updated) {
                setState(() {
                  _managerProfile = updated;
                });
              },
            ),
            const SizedBox(height: 24),
            _ManagerScopesCard(managerContext: _managerContext),
          ],
        ),
      );
    }

    // 12. New Request (Index 11)
    if (_selectedNavIndex == 11) {
      return SingleChildScrollView(
        padding: padding,
        child: NewRequestScreen(
          currentUserId: _managerProfile.id,
          currentUserName: _managerProfile.name,
          currentUserRole: _managerProfile.role,
          currentUserEmail: _managerProfile.email,
          organizationId: _managerProfile.organizationId ??
              _managerContext?.organizationId ??
              '',
          onRequestSubmitted: (req) {
            setState(() => _selectedNavIndex = 12);
          },
          onCancel: () => setState(() => _selectedNavIndex = 0),
        ),
      );
    }

    // 13. Request Approval (Index 12)
    if (_selectedNavIndex == 12) {
      return SingleChildScrollView(
        padding: padding,
        child: RequestApprovalScreen(
          key: ValueKey('req_approval_${_requestApprovalInitialTab}_$_requestInitialStatus'),
          initialTabIndex: _requestApprovalInitialTab,
          initialStatus: _requestInitialStatus,
          currentUserId: _managerProfile.id,
          currentUserName: _managerProfile.name,
          currentUserRole: _managerProfile.role,
          currentUserEmail: _managerProfile.email,
          organizationId: _managerProfile.organizationId ??
              _managerContext?.organizationId ??
              '',
          isManager: true,
          onNewRequest: () => setState(() => _selectedNavIndex = 11),
        ),
      );
    }

    // 14. My Requests (Index 13)
    if (_selectedNavIndex == 13) {
      return SingleChildScrollView(
        padding: padding,
        child: MyRequestsScreen(
          key: ValueKey('my_requests_$_requestInitialStatus'),
          initialStatus: _requestInitialStatus,
          currentUserId: _managerProfile.id,
          currentUserName: _managerProfile.name,
          currentUserRole: _managerProfile.role,
          currentUserEmail: _managerProfile.email,
          organizationId: _managerProfile.organizationId ??
              _managerContext?.organizationId ??
              '',
          isManager: true,
          onNewRequest: () => setState(() => _selectedNavIndex = 11),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

// =============================================================================
// DARK ENTERPRISE SIDEBAR WITH POLISHED SUBTLE ANIMATIONS
// =============================================================================

class _EnterpriseSidebar extends StatelessWidget {
  const _EnterpriseSidebar({
    required this.navItems,
    required this.selectedIndex,
    required this.onNavSelected,
  });

  final List<_NavItemData> navItems;
  final int selectedIndex;
  final ValueChanged<int> onNavSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A), // Dark slate 900
        border: Border(right: BorderSide(color: Color(0xFF1E293B))),
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, top: 4, bottom: 20),
            child: ActionFlowBrand(logoSize: 36, fontSize: 17, isDark: true),
          ),
          const Divider(color: Color(0xFF1E293B), height: 1),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: navItems.length,
              separatorBuilder: (context, index) => const SizedBox(height: 2),
              itemBuilder: (context, index) {
                final item = navItems[index];
                return _AnimatedSidebarNavItem(
                  key: ValueKey('sidebar_item_${item.label}'),
                  item: item,
                  onTap: () => onNavSelected(item.index ?? index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedSidebarNavItem extends StatefulWidget {
  const _AnimatedSidebarNavItem({
    super.key,
    required this.item,
    required this.onTap,
  });

  final _NavItemData item;
  final VoidCallback onTap;

  @override
  State<_AnimatedSidebarNavItem> createState() =>
      _AnimatedSidebarNavItemState();
}

class _AnimatedSidebarNavItemState extends State<_AnimatedSidebarNavItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.item.isActive;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF1E293B)
                : (_isHovered
                      ? const Color(0xFF1E293B).withValues(alpha: 0.6)
                      : Colors.transparent),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive
                  ? const Color(0xFF334155)
                  : (_isHovered
                        ? const Color(0xFF334155).withValues(alpha: 0.35)
                        : Colors.transparent),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              AnimatedScale(
                scale: isActive ? 1.05 : (_isHovered ? 1.04 : 1.0),
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeInOut,
                child: Icon(
                  widget.item.icon,
                  size: 19,
                  color: isActive
                      ? const Color(0xFF38BDF8)
                      : (_isHovered
                            ? const Color(0xFFE2E8F0)
                            : const Color(0xFF94A3B8)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontFamily: 'Roboto',
                    fontWeight: isActive
                        ? FontWeight.w700
                        : (_isHovered ? FontWeight.w600 : FontWeight.w500),
                    color: isActive
                        ? Colors.white
                        : (_isHovered
                              ? const Color(0xFFF1F5F9)
                              : const Color(0xFF94A3B8)),
                  ),
                  child: Text(widget.item.label),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeInOut,
                width: isActive ? 6 : (_isHovered ? 4 : 0),
                height: isActive ? 6 : (_isHovered ? 4 : 0),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFF38BDF8)
                      : const Color(0xFF64748B),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// TOP HEADER
// =============================================================================

class _TopHeader extends StatelessWidget {
  const _TopHeader({
    required this.isMobile,
    required this.searchController,
    required this.profile,
    this.userId,
    this.organizationId,
    this.onActionTap,
    this.onNotificationItemTap,
    this.onProfileTap,
    this.onNotificationTap,
    required this.onSearchChanged,
    required this.onMenuTap,
    required this.onLogout,
  });

  final bool isMobile;
  final TextEditingController searchController;
  final UserProfile profile;
  final String? userId;
  final String? organizationId;
  final void Function(String actionId)? onActionTap;
  final void Function(AppNotification notification)? onNotificationItemTap;
  final VoidCallback? onProfileTap;
  final VoidCallback? onNotificationTap;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onMenuTap;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 20,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: AppTheme.headerBg(context),
        border: Border(
          bottom: BorderSide(color: AppTheme.headerBorder(context)),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 650;
          final isSmall = constraints.maxWidth < 360;

          return Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: isSmall ? 6 : 12,
            runSpacing: 10,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (isMobile) ...[
                    IconButton(
                      icon: Icon(
                        Icons.menu_rounded,
                        color: AppTheme.textPrimary(context),
                      ),
                      onPressed: onMenuTap,
                    ),
                    const SizedBox(width: 4),
                  ],
                  // Search Box
                  SizedBox(
                    width: isNarrow
                        ? (isSmall ? 130 : 160)
                        : (constraints.maxWidth > 900 ? 300 : 220),
                    height: 38,
                    child: TextField(
                      controller: searchController,
                      onChanged: onSearchChanged,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textPrimary(context),
                      ),
                      decoration: InputDecoration(
                        hintText: isNarrow
                            ? 'Search actions...'
                            : 'Search actions, projects, people',
                        hintStyle: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.textMuted(context),
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: AppTheme.textSecondary(context),
                        ),
                        filled: true,
                        fillColor: AppTheme.inputFill(context),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 0,
                          horizontal: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: AppTheme.inputBorder(context),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: AppTheme.inputBorder(context),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFF1565C0),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // Right-aligned controls: Theme toggle, Notification badge, Profile pill, Logout
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Global Light/Dark Theme Switcher
                  const ThemeToggleButton(size: 38),
                  const SizedBox(width: 8),

                  // Notifications Badge with Interactive Dropdown
                  NotificationBellButton(
                    userId: userId ??
                        SupabaseConfig.clientOrNull?.auth.currentUser?.id ??
                        'manager-user',
                    organizationId: organizationId,
                    isManager: true,
                    onActionTap: onActionTap,
                    onNotificationTap: onNotificationItemTap,
                    onViewAllNotifications: onNotificationTap,
                    customBuilder: (ctx, toggle, count, isOpen) {
                      return InkWell(
                        onTap: toggle,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          height: 38,
                          width: 38,
                          decoration: BoxDecoration(
                            color: AppTheme.cardBg(context),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isOpen
                                  ? const Color(0xFF1565C0)
                                  : AppTheme.cardBorder(context),
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
                                    ? const Color(0xFF1565C0)
                                    : AppTheme.textSecondary(context),
                              ),
                              if (count > 0)
                                Positioned(
                                  right: 6,
                                  top: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDC2626),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '$count',
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
                    },
                  ),
                  const SizedBox(width: 8),

                  // Manager Profile Badge
                  InkWell(
                    onTap: onProfileTap,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBg(context),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.cardBorder(context)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(
                              color: Color(0xFF1565C0),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              profile.initials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (!isNarrow) ...[
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  profile.name,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary(context),
                                  ),
                                ),
                                Text(
                                  profile.designation,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.textSecondary(context),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 4),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Header Logout Action
                  OutlinedButton.icon(
                    onPressed: onLogout,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                    icon: const Icon(Icons.logout_rounded, size: 16),
                    label: const Text(
                      'Logout',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// =============================================================================
// ACTION REGISTER SECTION & TABLE
// =============================================================================

typedef _ActionRegisterSection = ActionRegisterSection;

class ActionRegisterSection extends StatelessWidget {
  const ActionRegisterSection({
    required this.isDrillDown,
    this.drillDownTitle,
    required this.actions,
    required this.searchQuery,
    required this.selectedStatus,
    this.selectedForwarded = 'All Actions',
    required this.selectedDivision,
    required this.selectedDepartment,
    required this.selectedSite,
    required this.selectedPriority,
    required this.selectedPerson,
    required this.selectedDate,
    this.selectedDateField = 'All Dates',
    this.customDateStart,
    this.customDateEnd,
    required this.selectedSort,
    this.departmentOptions,
    this.siteOptions,
    this.personOptions,
    required this.onSearchChanged,
    required this.onStatusChanged,
    this.onForwardedChanged,
    required this.onDivisionChanged,
    required this.onDepartmentChanged,
    required this.onSiteChanged,
    required this.onPriorityChanged,
    required this.onPersonChanged,
    required this.onDateChanged,
    required this.onDateFieldChanged,
    this.onCustomDateRangeChanged,
    required this.onSortChanged,
    required this.onActionTap,
    this.onUpdateActionTap,
    this.onEditActionTap,
    this.onDeleteActionTap,
    required this.onAddAction,
    this.onExportExcel,
    this.onResetFilters,
    this.currentUserId,
    this.selectedActionIds,
    this.onToggleSelect,
    this.onSelectAll,
    this.onDeleteSelected,
    this.onClearSelection,
  });

  final bool isDrillDown;
  final String? drillDownTitle;
  final String? currentUserId;
  final List<ActionRecord> actions;
  final Set<String>? selectedActionIds;
  final ValueChanged<String>? onToggleSelect;
  final ValueChanged<bool>? onSelectAll;
  final VoidCallback? onDeleteSelected;
  final VoidCallback? onClearSelection;
  final String searchQuery;
  final String selectedStatus;
  final String selectedForwarded;
  final String selectedDivision;
  final String selectedDepartment;
  final String selectedSite;
  final String selectedPriority;
  final String selectedPerson;
  final String selectedDate;
  final String selectedDateField;
  final DateTime? customDateStart;
  final DateTime? customDateEnd;
  final String selectedSort;
  final List<String>? departmentOptions;
  final List<String>? siteOptions;
  final List<String>? personOptions;

  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String>? onForwardedChanged;
  final ValueChanged<String> onDivisionChanged;
  final ValueChanged<String> onDepartmentChanged;
  final ValueChanged<String> onSiteChanged;
  final ValueChanged<String> onPriorityChanged;
  final ValueChanged<String> onPersonChanged;
  final ValueChanged<String> onDateChanged;
  final ValueChanged<String> onDateFieldChanged;
  final ValueChanged<DateTimeRange?>? onCustomDateRangeChanged;
  final ValueChanged<String> onSortChanged;

  final ValueChanged<ActionRecord> onActionTap;
  final ValueChanged<ActionRecord>? onUpdateActionTap;
  final ValueChanged<ActionRecord>? onEditActionTap;
  final ValueChanged<ActionRecord>? onDeleteActionTap;
  final VoidCallback onAddAction;
  final void Function(List<ActionRecord>)? onExportExcel;
  final VoidCallback? onResetFilters;

  Future<void> _handleResendAssignment(
    BuildContext context,
    ActionRecord action,
  ) async {
    final hasEmail = action.isExternalRecipient
        ? ((action.externalRecipientEmail != null &&
                action.externalRecipientEmail!.isNotEmpty) ||
            (action.externalRecipient?.email != null &&
                action.externalRecipient!.email.isNotEmpty) ||
            (action.primaryAssignee?.email != null &&
                action.primaryAssignee!.email.isNotEmpty) ||
            (action.externalRecipientId != null &&
                action.externalRecipientId!.isNotEmpty))
        : ((action.primaryAssignee?.email != null &&
                action.primaryAssignee!.email.isNotEmpty) ||
            (action.assignedToId != null &&
                action.assignedToId!.isNotEmpty));

    if (!hasEmail) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot resend assignment: No assignee email address is associated with this action.',
          ),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    try {
      final result =
          await EmailService.instance.sendAssignmentEmail(action: action);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Assignment email sent successfully to ${result.recipientEmail ?? "assignee"}',
            ),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
      } else if (result.status == 'not_configured') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Email provider (Resend) is not configured in Supabase secrets.',
            ),
            backgroundColor: Color(0xFFD97706),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to send assignment email: ${result.errorMessage ?? "Unknown error"}',
            ),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending assignment email: $e'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Page Title & Subtitle Card
        _buildPageHeader(context),
        const SizedBox(height: 16),

        // 2. Filter & Search Card
        _buildFilterCard(context),
        const SizedBox(height: 14),

        // 2.5 Active Filter Summary & Result Counter
        _buildActiveFilterChips(context),
        const SizedBox(height: 16),

        // 3. Actions List / Table Card
        _buildTableCard(context),
      ],
    );
  }

  Widget _buildActiveFilterChips(BuildContext context) {
    final chips = <Widget>[];

    void addChip(String label, String value, VoidCallback onRemove) {
      chips.add(
        Chip(
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          backgroundColor: AppTheme.containerBg(context),
          side: BorderSide(color: AppTheme.cardBorder(context)),
          label: Text(
            '$label: $value',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary(context),
            ),
          ),
          deleteIcon: const Icon(Icons.close_rounded, size: 14),
          deleteIconColor: AppTheme.textSecondary(context),
          onDeleted: onRemove,
        ),
      );
    }

    if (searchQuery.isNotEmpty) {
      addChip('Search', searchQuery, () => onSearchChanged(''));
    }
    if (selectedStatus != 'All Status') {
      addChip('Status', selectedStatus, () => onStatusChanged('All Status'));
    }
    if (selectedForwarded != 'All Actions') {
      addChip(
        'Forwarded',
        selectedForwarded,
        () => onForwardedChanged?.call('All Actions'),
      );
    }
    if (selectedPriority != 'All Priority') {
      addChip(
        'Priority',
        selectedPriority,
        () => onPriorityChanged('All Priority'),
      );
    }
    if (selectedDepartment != 'All Departments') {
      addChip(
        'Department',
        selectedDepartment,
        () => onDepartmentChanged('All Departments'),
      );
    }
    if (selectedSite != 'All Sites') {
      addChip('Site', selectedSite, () => onSiteChanged('All Sites'));
    }
    if (selectedDivision != 'All Divisions') {
      addChip(
        'Division',
        selectedDivision,
        () => onDivisionChanged('All Divisions'),
      );
    }
    if (selectedPerson != 'All People') {
      addChip('Person', selectedPerson, () => onPersonChanged('All People'));
    }
    if (selectedDateField != 'All Dates') {
      addChip(
        'Date Field',
        selectedDateField,
        () => onDateFieldChanged('All Dates'),
      );
    }
    if (selectedDate != 'Date' && selectedDate != 'All Time') {
      if (selectedDate == 'Custom Range' &&
          customDateStart != null &&
          customDateEnd != null) {
        final s = customDateStart!;
        final e = customDateEnd!;
        addChip(
          'Date Range',
          '${s.day}/${s.month} - ${e.day}/${e.month}',
          () => onDateChanged('Date'),
        );
      } else {
        addChip('Date', selectedDate, () => onDateChanged('Date'));
      }
    }

    final hasActiveFilters = chips.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder(context)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.isDark(context)
                ? Colors.black.withValues(alpha: 0.2)
                : const Color(0x060F172A),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.analytics_outlined,
                size: 16,
                color: AppTheme.primaryAccent(context),
              ),
              const SizedBox(width: 8),
              Text(
                '${actions.length} Action${actions.length == 1 ? "" : "s"} found',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              if (hasActiveFilters) ...[
                const SizedBox(width: 8),
                Text(
                  '(matching current filters)',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
                const Spacer(),
                if (onResetFilters != null)
                  TextButton.icon(
                    onPressed: onResetFilters,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: const Color(0xFFDC2626),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                    ),
                    icon: const Icon(Icons.clear_all_rounded, size: 15),
                    label: const Text(
                      'Clear All',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ],
          ),
          if (hasActiveFilters) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: chips,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPageHeader(BuildContext context) {
    final title = drillDownTitle ?? 'Action Register';
    final subtitle = title == 'My Actions'
        ? '${actions.length} action${actions.length == 1 ? '' : 's'} assigned to you requiring execution or review'
        : '${actions.length} action${actions.length == 1 ? '' : 's'} recorded in register';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder(context)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.isDark(context)
                ? Colors.black.withValues(alpha: 0.2)
                : const Color(0x060F172A),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 750;
          final isCompact = constraints.maxWidth < 600;

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1565C0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        title == 'My Actions'
                            ? Icons.assignment_turned_in_rounded
                            : Icons.table_chart_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary(context),
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (title != 'My Actions') ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onAddAction,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text(
                        'Add Action',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  title == 'My Actions'
                      ? Icons.assignment_turned_in_rounded
                      : Icons.table_chart_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(context),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (title != 'My Actions') ...[
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: onAddAction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: isNarrow ? 12 : 16,
                      vertical: 10,
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(
                    'Add Action',
                    style: TextStyle(
                      fontSize: isNarrow ? 12 : 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder(context)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.isDark(context)
                ? Colors.black.withValues(alpha: 0.2)
                : const Color(0x060F172A),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.filter_list_rounded,
                size: 18,
                color: Color(0xFF1565C0),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Filter & Search Actions',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final int columns;
              if (width >= 1300) {
                columns = 5;
              } else if (width >= 1000) {
                columns = 4;
              } else if (width >= 700) {
                columns = 3;
              } else if (width >= 480) {
                columns = 2;
              } else {
                columns = 1;
              }

              final double fieldWidth = (width - (columns - 1) * 10) / columns;

              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  // 1. Search Field
                  SizedBox(
                    width: fieldWidth,
                    child: TextFormField(
                      initialValue: searchQuery,
                      onChanged: onSearchChanged,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textPrimary(context),
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search actions...',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted(context),
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: AppTheme.textSecondary(context),
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: AppTheme.inputFill(context),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: AppTheme.inputBorder(context),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: AppTheme.inputBorder(context),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: AppTheme.primaryAccent(context),
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                      ),
                    ),
                  ),
                  // 2. Status Filter
                  SizedBox(
                    width: fieldWidth,
                    child: _filterDropdown(
                      context: context,
                      label: 'Status',
                      value: selectedStatus,
                      items: const [
                        'All Status',
                        'Open',
                        'In Progress',
                        'Overdue',
                        'Pending Review',
                        'Ready for Review',
                        'Closed',
                      ],
                      onChanged: onStatusChanged,
                    ),
                  ),
                  // Forwarded Filter
                  SizedBox(
                    width: fieldWidth,
                    child: _filterDropdown(
                      context: context,
                      label: 'Forwarded',
                      value: selectedForwarded,
                      items: const [
                        'All Actions',
                        'Forwarded by Me',
                        'Forwarded to Me',
                        'Forwarded Only',
                        'Direct Only',
                      ],
                      onChanged: onForwardedChanged ?? (_) {},
                    ),
                  ),
                  // 3. Department Filter
                  SizedBox(
                    width: fieldWidth,
                    child: _filterDropdown(
                      context: context,
                      label: 'Department',
                      value: selectedDepartment,
                      items:
                          departmentOptions ??
                          const [
                            'All Departments',
                            'HSE',
                            'Maintenance',
                            'Operations',
                          ],
                      onChanged: onDepartmentChanged,
                    ),
                  ),
                  // 4. Site Filter
                  SizedBox(
                    width: fieldWidth,
                    child: _filterDropdown(
                      context: context,
                      label: 'Site',
                      value: selectedSite,
                      items:
                          siteOptions ??
                          const [
                            'All Sites',
                            'North Plant',
                            'Warehouse B',
                            'Central Yard',
                            'Admin Block',
                            'Storage Area',
                          ],
                      onChanged: onSiteChanged,
                    ),
                  ),
                  // 5. Priority Filter
                  SizedBox(
                    width: fieldWidth,
                    child: _filterDropdown(
                      context: context,
                      label: 'Priority',
                      value: selectedPriority,
                      items: const [
                        'All Priority',
                        'Critical',
                        'High',
                        'Medium',
                        'Low',
                      ],
                      onChanged: onPriorityChanged,
                    ),
                  ),
                  // 6. Person Filter
                  SizedBox(
                    width: fieldWidth,
                    child: _filterDropdown(
                      context: context,
                      label: 'Person',
                      value: selectedPerson,
                      items:
                          personOptions ??
                          const [
                            'All People',
                            'R. Kumar',
                            'M. Ali',
                            'S. Jones',
                            'N. Shah',
                            'T. Reed',
                          ],
                      onChanged: onPersonChanged,
                    ),
                  ),
                  // 7. Division Filter
                  SizedBox(
                    width: fieldWidth,
                    child: _filterDropdown(
                      context: context,
                      label: 'Division',
                      value: selectedDivision,
                      items: const [
                        'All Divisions',
                        'Operations',
                        'Projects',
                        'Corporate',
                      ],
                      onChanged: onDivisionChanged,
                    ),
                  ),
                  // 8. Date Field Selector
                  SizedBox(
                    width: fieldWidth,
                    child: _filterDropdown(
                      context: context,
                      label: 'Date Field',
                      value: selectedDateField,
                      items: const [
                        'All Dates',
                        'Raised Date',
                        'Start Date',
                        'Follow-Up Date',
                        'Target/Due Date',
                        'Due Date',
                        'Closed Date',
                        'Update',
                      ],
                      onChanged: onDateFieldChanged,
                    ),
                  ),
                  // 9. Date Period Filter
                  SizedBox(
                    width: fieldWidth,
                    child: _filterDropdown(
                      context: context,
                      label: 'Date Period',
                      value: selectedDate,
                      items: const [
                        'Date',
                        'Today',
                        'Yesterday',
                        'This Week',
                        'This Month',
                        'This Year',
                        'September 2026',
                        'Custom Range',
                        'All Time',
                      ],
                      onChanged: (val) async {
                        if (val == 'Custom Range') {
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                            initialDateRange:
                                customDateStart != null && customDateEnd != null
                                ? DateTimeRange(
                                    start: customDateStart!,
                                    end: customDateEnd!,
                                  )
                                : null,
                          );
                          if (picked != null) {
                            onCustomDateRangeChanged?.call(picked);
                            onDateChanged(val);
                          }
                        } else {
                          onDateChanged(val);
                        }
                      },
                    ),
                  ),
                  // 9. Sort By Filter
                  SizedBox(
                    width: fieldWidth,
                    child: _filterDropdown(
                      context: context,
                      label: 'Sort By',
                      value: selectedSort,
                      items: const [
                        'Newest First',
                        'Target Date',
                        'Priority',
                        'Progress',
                      ],
                      onChanged: onSortChanged,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _filterDropdown({
    required BuildContext context,
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String> onChanged,
  }) {
    final uniqueItems = items.toSet().toList();
    final currentVal = uniqueItems.contains(value)
        ? value
        : (uniqueItems.isNotEmpty ? uniqueItems.first : value);

    return DropdownButtonFormField<String>(
      isExpanded: true,
      dropdownColor: AppTheme.cardBg(context),
      icon: Icon(
        Icons.arrow_drop_down_rounded,
        size: 20,
        color: AppTheme.textSecondary(context),
      ),
      key: ValueKey('${label == 'Date Period' ? 'Date' : label}_$currentVal'),
      initialValue: currentVal,
      style: TextStyle(fontSize: 12, color: AppTheme.textPrimary(context)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          fontSize: 11.5,
          color: AppTheme.textSecondary(context),
        ),
        isDense: true,
        filled: true,
        fillColor: AppTheme.inputFill(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.inputBorder(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.inputBorder(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.primaryAccent(context)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      ),
      items: items
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(
                item,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textPrimary(context),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (val) {
        if (val != null) onChanged(val);
      },
    );
  }

  Widget _buildTableCard(BuildContext context) {
    final title = drillDownTitle ?? 'Action Register';
    final effectiveUserId =
        currentUserId ??
        SupabaseConfig.clientOrNull?.auth.currentUser?.id ??
        AuthService.instance.currentUser?.id;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder(context)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.isDark(context)
                ? Colors.black.withValues(alpha: 0.2)
                : const Color(0x060F172A),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                title == 'My Actions'
                    ? Icons.assignment_turned_in_rounded
                    : Icons.table_chart_rounded,
                size: 18,
                color: const Color(0xFF1565C0),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$title (${actions.length})',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ),
              if (onExportExcel != null)
                ElevatedButton.icon(
                  onPressed: () => onExportExcel!(actions),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  icon: const Icon(Icons.file_download_outlined, size: 16),
                  label: const Text(
                    'Export Excel',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          if (selectedActionIds != null && selectedActionIds!.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.isDark(context)
                    ? const Color(0xFF1E3A5F)
                    : const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.isDark(context)
                      ? const Color(0xFF2563EB)
                      : const Color(0xFFBFDBFE),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: AppTheme.primaryAccent(context),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${selectedActionIds!.length} action${selectedActionIds!.length == 1 ? '' : 's'} selected',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const Spacer(),
                  if (onExportExcel != null)
                    TextButton.icon(
                      onPressed: () {
                        final selectedActions = actions
                            .where((a) => selectedActionIds!.contains(a.id))
                            .toList();
                        onExportExcel!(
                          selectedActions.isNotEmpty
                              ? selectedActions
                              : actions,
                        );
                      },
                      icon: const Icon(Icons.file_download_outlined, size: 14),
                      label: const Text(
                        'Export Selected',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF0F766E),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  if (onDeleteSelected != null) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: onDeleteSelected,
                      icon: const Icon(Icons.delete_outline_rounded, size: 14),
                      label: const Text(
                        'Delete Selected',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: onClearSelection,
                    icon: const Icon(Icons.close_rounded, size: 14),
                    label: const Text(
                      'Deselect All',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (actions.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 40),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.containerBg(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cardBorder(context)),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.assignment_outlined,
                    size: 40,
                    color: AppTheme.textMuted(context),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    title == 'My Actions'
                        ? 'No actions assigned to you.'
                        : 'No actions matching the selected filters',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title == 'My Actions'
                        ? 'You currently have no actions assigned to your account.'
                        : 'Try adjusting your search query or reset filter options.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted(context),
                    ),
                  ),
                ],
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final isMobileView = constraints.maxWidth < 900;

                if (isMobileView) {
                  return Column(
                    children: actions.map((action) {
                      return _buildMobileActionCard(context, action);
                    }).toList(),
                  );
                }

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: AppTheme.dividerColor(context)),
                      child: DataTable(
                        showCheckboxColumn: true,
                        onSelectAll: (val) => onSelectAll?.call(val ?? false),
                        columnSpacing: 18,
                        horizontalMargin: 12,
                        headingRowHeight: 42,
                        dataRowMinHeight: 52,
                        dataRowMaxHeight: 56,
                        headingRowColor: WidgetStateProperty.all(
                          AppTheme.tableHeaderBg(context),
                        ),
                        columns: [
                          DataColumn(
                            label: Text(
                              'Action ID',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: AppTheme.textSecondary(context),
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Subject',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: AppTheme.textSecondary(context),
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Project / Site',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: AppTheme.textSecondary(context),
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Assigned To',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: AppTheme.textSecondary(context),
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Priority',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: AppTheme.textSecondary(context),
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Status',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: AppTheme.textSecondary(context),
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Target Date',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: AppTheme.textSecondary(context),
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              '% Complete',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: AppTheme.textSecondary(context),
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Next Follow-up',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: AppTheme.textSecondary(context),
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Action',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: AppTheme.textSecondary(context),
                              ),
                            ),
                          ),
                        ],
                        rows: actions.map((action) {
                          final isSelected =
                              selectedActionIds?.contains(action.id) ?? false;
                          return DataRow(
                            key: ValueKey('action_row_${action.id}'),
                            selected: isSelected,
                            color: WidgetStateProperty.resolveWith<Color?>((
                              states,
                            ) {
                              if (states.contains(WidgetState.selected)) {
                                return AppTheme.isDark(context)
                                    ? const Color(0xFF1E3A5F).withValues(alpha: 0.5)
                                    : const Color(0xFFE0F2FE);
                              }
                              return null;
                            }),
                            onSelectChanged: (val) =>
                                onToggleSelect?.call(action.id),
                            cells: [
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.actionIdBg(context),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: AppTheme.actionIdBorder(context),
                                    ),
                                  ),
                                  child: Text(
                                    action.displayId,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11.5,
                                      color: AppTheme.actionIdText(context),
                                    ),
                                  ),
                                ),
                                onTap: () => onActionTap(action),
                              ),
                              DataCell(
                                Text(
                                  action.subject,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: AppTheme.textPrimary(context),
                                  ),
                                ),
                                onTap: () => onActionTap(action),
                              ),
                              DataCell(
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      action.site.isNotEmpty
                                          ? action.site
                                          : 'Main Plant',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: AppTheme.textSecondary(context),
                                      ),
                                    ),
                                    if (action.section.isNotEmpty)
                                      Text(
                                        action.section,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: AppTheme.primaryAccent(
                                            context,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              DataCell(
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.person_outline_rounded,
                                          size: 15,
                                          color: AppTheme.textSecondary(
                                            context,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          action.assignedTo,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color: AppTheme.textPrimary(
                                              context,
                                            ),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        if (action.isExternalRecipient) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 5,
                                              vertical: 1.5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppTheme.isDark(context)
                                                  ? const Color(0xFF334155)
                                                  : const Color(0xFFF1F5F9),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: AppTheme.isDark(context)
                                                    ? const Color(0xFF475569)
                                                    : const Color(0xFFCBD5E1),
                                              ),
                                            ),
                                            child: Text(
                                              'External',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.isDark(context)
                                                    ? Colors.white70
                                                    : const Color(0xFF475569),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (title == 'My Actions') ...[
                                      const SizedBox(height: 3),
                                      _RoleBadge(
                                        role: action.getUserRoleInAction(
                                          effectiveUserId,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              DataCell(
                                _PriorityPill(priority: action.priority),
                              ),
                              DataCell(_StatusPill(status: action.status)),
                              DataCell(
                                Text(
                                  action.targetDate,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary(context),
                                  ),
                                ),
                              ),
                              DataCell(
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 44,
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            child: LinearProgressIndicator(
                                              minHeight: 6,
                                              value:
                                                  action.percentComplete /
                                                  100.0,
                                              backgroundColor:
                                                  AppTheme.progressTrackBg(
                                                    context,
                                                  ),
                                              valueColor:
                                                  AlwaysStoppedAnimation(
                                                    _statusColor(action.status),
                                                  ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          action.percent,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textSecondary(
                                              context,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (action.subTasks.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Tasks: ${action.subTasks.where((t) => t.isCompleted).length}/${action.subTasks.length}',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                    if (title == 'My Actions') ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Mine: ${action.myContribution(effectiveUserId)}%',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF0F766E),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              DataCell(
                                Text(
                                  action.followUp,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary(context),
                                  ),
                                ),
                              ),
                              DataCell(
                                title == 'My Actions'
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ElevatedButton.icon(
                                            onPressed: () {
                                              if (onUpdateActionTap != null) {
                                                onUpdateActionTap!(action);
                                              } else {
                                                onActionTap(action);
                                              }
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(
                                                0xFF1565C0,
                                              ),
                                              foregroundColor: Colors.white,
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                            ),
                                            icon: const Icon(
                                              Icons.edit_note_rounded,
                                              size: 15,
                                            ),
                                            label: const Text(
                                              'Update Action',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          OutlinedButton(
                                            onPressed: () =>
                                                onActionTap(action),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor:
                                                  AppTheme.primaryAccent(
                                                    context,
                                                  ),
                                              side: BorderSide(
                                                color: AppTheme.isDark(context)
                                                    ? const Color(0xFF1E40AF)
                                                    : const Color(0xFFBFDBFE),
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                            ),
                                            child: const Text(
                                              'Details',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          OutlinedButton.icon(
                                            onPressed: () =>
                                                onDeleteActionTap?.call(action),
                                            icon: const Icon(
                                              Icons.delete_outline_rounded,
                                              size: 14,
                                            ),
                                            label: const Text(
                                              'Delete',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: const Color(
                                                0xFFDC2626,
                                              ),
                                              side: BorderSide(
                                                color: const Color(0xFFDC2626)
                                                    .withValues(alpha: 0.3),
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          OutlinedButton(
                                            onPressed: () =>
                                                onActionTap(action),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor:
                                                  AppTheme.primaryAccent(
                                                    context,
                                                  ),
                                              side: BorderSide(
                                                color: AppTheme.isDark(context)
                                                    ? const Color(0xFF1E40AF)
                                                    : const Color(0xFFBFDBFE),
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                            ),
                                            child: const Text(
                                              'Details',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          OutlinedButton.icon(
                                            onPressed: () =>
                                                onEditActionTap?.call(action),
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                              size: 14,
                                            ),
                                            label: const Text(
                                              'Edit',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: const Color(
                                                0xFF2563EB,
                                              ),
                                              side: BorderSide(
                                                color: const Color(0xFF2563EB)
                                                    .withValues(alpha: 0.3),
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          OutlinedButton.icon(
                                            key: Key(
                                              'resend_assignment_table_btn_${action.id}',
                                            ),
                                            onPressed: () =>
                                                _handleResendAssignment(
                                                  context,
                                                  action,
                                                ),
                                            icon: const Icon(
                                              Icons.send_rounded,
                                              size: 14,
                                            ),
                                            label: const Text(
                                              'Resend',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: const Color(
                                                0xFF0F766E,
                                              ),
                                              side: BorderSide(
                                                color: const Color(
                                                  0xFF0F766E,
                                                ).withValues(alpha: 0.3),
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          OutlinedButton.icon(
                                            onPressed: () =>
                                                onDeleteActionTap?.call(action),
                                            icon: Icon(
                                              action.isClosed
                                                  ? Icons.lock_outline_rounded
                                                  : Icons
                                                        .delete_outline_rounded,
                                              size: 14,
                                            ),
                                            label: Text(
                                              action.isClosed
                                                  ? 'Closed'
                                                  : 'Delete',
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: action.isClosed
                                                  ? const Color(0xFF16A34A)
                                                  : const Color(0xFFDC2626),
                                              side: BorderSide(
                                                color:
                                                    (action.isClosed
                                                            ? const Color(
                                                                0xFF16A34A,
                                                              )
                                                            : const Color(
                                                                0xFFDC2626,
                                                              ))
                                                        .withValues(alpha: 0.3),
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildMobileActionCard(BuildContext context, ActionRecord action) {
    final isSelected = selectedActionIds?.contains(action.id) ?? false;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isSelected
            ? (AppTheme.isDark(context)
                ? const Color(0xFF1E3A5F)
                : const Color(0xFFEFF6FF))
            : AppTheme.containerBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? (AppTheme.isDark(context)
                  ? const Color(0xFF2563EB)
                  : const Color(0xFF93C5FD))
              : AppTheme.cardBorder(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (onToggleSelect != null)
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: isSelected,
                        onChanged: (_) => onToggleSelect?.call(action.id),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.actionIdBg(context),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppTheme.actionIdBorder(context),
                      ),
                    ),
                    child: Text(
                      action.displayId,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.actionIdText(context),
                      ),
                    ),
                  ),
                  _PriorityPill(priority: action.priority),
                  _StatusPill(status: action.status),
                ],
              ),
              Text(
                action.percent,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => onActionTap(action),
            child: Text(
              action.subject,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${action.site.isNotEmpty ? action.site : 'Main'} â€¢ ${action.department}${action.section.isNotEmpty ? ' â€¢ ${action.section}' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.person_outline_rounded,
                size: 14,
                color: AppTheme.textSecondary(context),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  action.assignedTo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textPrimary(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.event_outlined,
                size: 14,
                color: AppTheme.textSecondary(context),
              ),
              const SizedBox(width: 4),
              Text(
                action.targetDate,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: action.percentComplete / 100.0,
              backgroundColor: AppTheme.progressTrackBg(context),
              valueColor: AlwaysStoppedAnimation(_statusColor(action.status)),
            ),
          ),
          if (action.subTasks.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Tasks: ${action.subTasks.where((t) => t.isCompleted).length}/${action.subTasks.length}',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                onPressed: () => onActionTap(action),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryAccent(context),
                  side: BorderSide(
                    color: AppTheme.isDark(context)
                        ? const Color(0xFF1E40AF)
                        : const Color(0xFFBFDBFE),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
                icon: const Icon(Icons.visibility_outlined, size: 14),
                label: const Text(
                  'Details',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
              ),
              if (drillDownTitle == 'My Actions') ...[
                ElevatedButton.icon(
                  onPressed: () {
                    if (onUpdateActionTap != null) {
                      onUpdateActionTap!(action);
                    } else {
                      onActionTap(action);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                  ),
                  icon: const Icon(Icons.edit_note_rounded, size: 15),
                  label: const Text(
                    'Update Action',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => onDeleteActionTap?.call(action),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: BorderSide(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.3),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 14),
                  label: const Text(
                    'Delete',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ] else ...[
                OutlinedButton.icon(
                  onPressed: () => onEditActionTap?.call(action),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2563EB),
                    side: BorderSide(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.3),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text(
                    'Edit',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => onDeleteActionTap?.call(action),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: action.isClosed
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFDC2626),
                    side: BorderSide(
                      color:
                          (action.isClosed
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFFDC2626))
                              .withValues(alpha: 0.3),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                  icon: Icon(
                    action.isClosed
                        ? Icons.lock_outline_rounded
                        : Icons.delete_outline_rounded,
                    size: 14,
                  ),
                  label: Text(
                    action.isClosed ? 'Closed' : 'Delete',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// PILL / BADGE COMPONENTS
// =============================================================================

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    final isDark = AppTheme.isDark(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.45 : 0.25),
        ),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: isDark ? color : color,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _PriorityPill extends StatelessWidget {
  const _PriorityPill({required this.priority});

  final String priority;

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (priority) {
      case 'Critical':
        color = const Color(0xFFDC2626);
        break;
      case 'High':
        color = const Color(0xFFEA580C);
        break;
      case 'Medium':
        color = const Color(0xFF1565C0);
        break;
      case 'Low':
        color = const Color(0xFF16A34A);
        break;
      default:
        color = const Color(0xFF64748B);
    }
    final isDark = AppTheme.isDark(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.1),
        borderRadius: BorderRadius.circular(6),
        border: isDark
            ? Border.all(color: color.withValues(alpha: 0.35))
            : null,
      ),
      child: Text(
        priority,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (role.toLowerCase()) {
      case 'owner':
        color = const Color(0xFF1D4ED8); // blue
        break;
      case 'contributor':
        color = const Color(0xFF7C3AED); // purple
        break;
      case 'assignee':
      default:
        color = const Color(0xFF0F766E); // teal
    }
    final isDark = AppTheme.isDark(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.25 : 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.45 : 0.25),
          width: 0.8,
        ),
      ),
      child: Text(
        role.toUpperCase(),
        style: TextStyle(
          color: isDark ? color.withValues(alpha: 0.9) : color,
          fontWeight: FontWeight.w700,
          fontSize: 9.5,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

// =============================================================================
// EMBEDDED PORTAL VIEWS (DOCUMENTS, SETTINGS)
// =============================================================================

enum _ManagerDocTab {
  allDocuments,
  myUploads,
  sharedWithMe,
  sharedByMe,
  guidelinesAndPolicies,
}

class _DocumentsPortalView extends StatefulWidget {
  const _DocumentsPortalView({
    this.organizationId,
    this.currentUserId,
    this.currentUserName,
    this.actions = const [],
    this.managerContext,
    this.managerProfile,
  });

  final String? organizationId;
  final String? currentUserId;
  final String? currentUserName;
  final List<ActionRecord> actions;
  final ManagerContext? managerContext;
  final UserProfile? managerProfile;

  @override
  State<_DocumentsPortalView> createState() => _DocumentsPortalViewState();
}

class _DocumentsPortalViewState extends State<_DocumentsPortalView> {
  final DocumentService _docService = DocumentService.instance;
  final TextEditingController _searchController = TextEditingController();

  List<DocumentRecord> _documents = [];
  bool _isLoading = true;
  String _selectedCategory = 'All';
  String _searchQuery = '';
  _ManagerDocTab _selectedTab = _ManagerDocTab.allDocuments;

  String get _effectiveOrgId =>
      (widget.organizationId != null && widget.organizationId!.isNotEmpty)
          ? widget.organizationId!
          : 'SOBHA-001';

  String get _effectiveUserId =>
      (widget.currentUserId != null && widget.currentUserId!.isNotEmpty)
          ? widget.currentUserId!
          : 'usr-mgr-001';

  String get _effectiveUserName =>
      (widget.currentUserName != null && widget.currentUserName!.isNotEmpty)
          ? widget.currentUserName!
          : 'Manager';

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  @override
  void dispose() {
    _searchController.dispose();
    NotificationService.instance.unsubscribeFromRealtime();
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    setState(() => _isLoading = true);
    try {
      final docs = await _docService.fetchDocuments(
        organizationId: _effectiveOrgId,
      );
      if (mounted) {
        setState(() {
          _documents = docs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showUploadDialog() {
    DocumentUploadDialog.show(
      context,
      organizationId: _effectiveOrgId,
      userId: _effectiveUserId,
      userName: _effectiveUserName,
      departmentId: widget.managerProfile?.departmentId ??
          widget.managerContext?.scopedDepartmentIds.firstOrNull,
      departmentName: widget.managerProfile?.department ??
          widget.managerContext?.scopedDepartmentNames.firstOrNull,
      actions: widget.actions,
      onDocumentUploaded: (doc) {
        _loadDocuments();
      },
    );
  }

  void _showShareDialog(DocumentRecord doc) {
    DocumentShareDialog.show(
      context,
      document: doc,
      organizationId: _effectiveOrgId,
      currentUserId: _effectiveUserId,
      currentUserName: _effectiveUserName,
      currentUserRole: 'manager',
      currentUserDepartment: widget.managerProfile?.department ??
          widget.managerContext?.scopedDepartmentNames.firstOrNull,
      currentUserDepartmentId: widget.managerProfile?.departmentId ??
          widget.managerContext?.scopedDepartmentIds.firstOrNull,
      allowedDepartmentIds: widget.managerContext?.scopedDepartmentIds ?? {},
      onSharesUpdated: () {
        _loadDocuments();
      },
    );
  }

  void _showPreviewDialog(DocumentRecord doc) {
    DocumentPreviewDialog.show(
      context,
      doc: doc,
      organizationId: _effectiveOrgId,
    );
  }

  Future<void> _downloadDocument(DocumentRecord doc) async {
    try {
      final success = await _docService.downloadAndSaveDocument(
        doc: doc,
        organizationId: _effectiveOrgId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Downloaded "${doc.title}" successfully.'
                  : 'Download initiated for "${doc.title}".',
            ),
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: ${DocumentService.formatDownloadError(e)}'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteDocument(DocumentRecord doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Document'),
        content: Text('Are you sure you want to delete "${doc.title}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _docService.deleteDocument(
          documentId: doc.id,
          organizationId: _effectiveOrgId,
          userId: _effectiveUserId,
          userRole: 'manager',
          userName: _effectiveUserName,
        );
        _loadDocuments();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete document: $e'),
              backgroundColor: const Color(0xFFDC2626),
            ),
          );
        }
      }
    }
  }

  Color _categoryColor(String category, String fileType) {
    final lowerCat = category.toLowerCase();
    final lowerType = fileType.toLowerCase();
    if (lowerType.contains('pdf') || lowerCat.contains('manual')) {
      return const Color(0xFFDC2626);
    }
    if (lowerType.contains('sheet') || lowerType.contains('excel') || lowerType.contains('xls') || lowerCat.contains('audit')) {
      return const Color(0xFF1565C0);
    }
    if (lowerCat.contains('incident') || lowerCat.contains('risk')) {
      return const Color(0xFFEA580C);
    }
    if (lowerCat.contains('policy')) {
      return const Color(0xFF16A34A);
    }
    return const Color(0xFF2563EB);
  }

  IconData _fileIcon(DocumentRecord doc) {
    if (doc.isPdf) return Icons.picture_as_pdf_outlined;
    if (doc.isExcel) return Icons.table_chart_outlined;
    if (doc.isWord) return Icons.description_outlined;
    if (doc.isImage) return Icons.image_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  Widget _buildTabChip(
    BuildContext context, {
    required Key key,
    required String label,
    required int count,
    required _ManagerDocTab tab,
  }) {
    final isSelected = _selectedTab == tab;
    final primaryColor = const Color(0xFF1565C0);
    return InkWell(
      key: key,
      onTap: () => setState(() => _selectedTab = tab),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withValues(alpha: 0.12)
              : AppTheme.containerBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? primaryColor : AppTheme.cardBorder(context),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? primaryColor : AppTheme.textSecondary(context),
          ),
        ),
      ),
    );
  }

  Widget _buildSmallKpiChip(
    BuildContext context,
    IconData icon,
    String label,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _effectiveUserId;
    final allDocs = _documents;
    final myUploads = _documents.where((d) => d.createdBy == uid).toList();
    final sharedWithMe = _documents.where((d) {
      if (d.createdBy == uid) return false;
      return d.sharedWithUserIds.contains(uid) ||
          MockDocumentStore.instance.shares.any((s) => s.documentId == d.id && s.userId == uid);
    }).toList();
    final sharedByMe = _documents.where((d) {
      if (d.createdBy != uid) return false;
      return d.sharedInternalCount > 0 ||
          d.sharedExternalCount > 0 ||
          MockDocumentStore.instance.shares.any((s) => s.documentId == d.id);
    }).toList();
    final guidelines = _documents.where((d) {
      final cat = d.category.toLowerCase();
      return d.category == DocumentCategory.policies ||
          d.category == DocumentCategory.hsseManuals ||
          cat.contains('policy') ||
          cat.contains('manual') ||
          cat.contains('guideline') ||
          cat.contains('standard');
    }).toList();

    List<DocumentRecord> tabDocs;
    switch (_selectedTab) {
      case _ManagerDocTab.myUploads:
        tabDocs = myUploads;
        break;
      case _ManagerDocTab.sharedWithMe:
        tabDocs = sharedWithMe;
        break;
      case _ManagerDocTab.sharedByMe:
        tabDocs = sharedByMe;
        break;
      case _ManagerDocTab.guidelinesAndPolicies:
        tabDocs = guidelines;
        break;
      case _ManagerDocTab.allDocuments:
        tabDocs = allDocs;
        break;
    }

    final filteredDocs = tabDocs.where((d) {
      if (_selectedCategory != 'All' &&
          d.category.toLowerCase() != _selectedCategory.toLowerCase()) {
        return false;
      }
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        return d.title.toLowerCase().contains(q) ||
            d.fileName.toLowerCase().contains(q) ||
            d.description.toLowerCase().contains(q) ||
            (d.actionNumber != null && d.actionNumber!.toLowerCase().contains(q));
      }
      return true;
    }).toList();

    final categoriesWithDocs = _documents.map((d) => d.category).toSet().length;
    final totalShares = _documents.fold<int>(
      0,
      (acc, d) => acc + d.sharedInternalCount + d.sharedExternalCount,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder(context)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.isDark(context)
                ? Colors.black.withValues(alpha: 0.2)
                : const Color(0x060F172A),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header Row
          Row(
            children: [
              const Icon(
                Icons.folder_outlined,
                color: Color(0xFF1565C0),
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Safety Documents & Guidelines',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: 'Refresh Documents',
                onPressed: _loadDocuments,
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const Key('documents_upload_button'),
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: const Text('Upload Document'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _showUploadDialog,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Central repository for HSSE operating procedures, risk assessments, and compliance evidence.',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 16),

          // 2. Summary KPI row
          Row(
            children: [
              _buildSmallKpiChip(
                context,
                Icons.description_outlined,
                '${_documents.length} Total Documents',
                const Color(0xFF1565C0),
              ),
              const SizedBox(width: 10),
              _buildSmallKpiChip(
                context,
                Icons.category_outlined,
                '$categoriesWithDocs Categories',
                const Color(0xFF16A34A),
              ),
              const SizedBox(width: 10),
              _buildSmallKpiChip(
                context,
                Icons.share_outlined,
                '$totalShares Active Shares',
                const Color(0xFFEA580C),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 3. Tab Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTabChip(
                  context,
                  key: const Key('manager_doc_tab_all_documents'),
                  label: 'All Documents',
                  count: allDocs.length,
                  tab: _ManagerDocTab.allDocuments,
                ),
                const SizedBox(width: 8),
                _buildTabChip(
                  context,
                  key: const Key('manager_doc_tab_my_uploads'),
                  label: 'My Uploads',
                  count: myUploads.length,
                  tab: _ManagerDocTab.myUploads,
                ),
                const SizedBox(width: 8),
                _buildTabChip(
                  context,
                  key: const Key('manager_doc_tab_shared_with_me'),
                  label: 'Shared with Me',
                  count: sharedWithMe.length,
                  tab: _ManagerDocTab.sharedWithMe,
                ),
                const SizedBox(width: 8),
                _buildTabChip(
                  context,
                  key: const Key('manager_doc_tab_shared_by_me'),
                  label: 'Shared by Me',
                  count: sharedByMe.length,
                  tab: _ManagerDocTab.sharedByMe,
                ),
                const SizedBox(width: 8),
                _buildTabChip(
                  context,
                  key: const Key('manager_doc_tab_guidelines_&_policies'),
                  label: 'Guidelines & Policies',
                  count: guidelines.length,
                  tab: _ManagerDocTab.guidelinesAndPolicies,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4. Search and Category Filter Bar
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.containerBg(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.cardBorder(context)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Search by title, file name, description, or action number...',
                      hintStyle: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary(context),
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: AppTheme.textSecondary(context),
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    style: TextStyle(fontSize: 13, color: AppTheme.textPrimary(context)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Category Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                'All',
                ...DocumentCategory.all,
              ].map((cat) {
                final isSelected = _selectedCategory.toLowerCase() == cat.toLowerCase();
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected ? Colors.white : AppTheme.textPrimary(context),
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: const Color(0xFF1565C0),
                    backgroundColor: AppTheme.containerBg(context),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedCategory = cat);
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),

          // 5. Document List
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              ),
            )
          else if (filteredDocs.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Column(
                  children: [
                    Icon(
                      Icons.folder_open_rounded,
                      size: 44,
                      color: AppTheme.textMuted(context),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No documents found matching your filter criteria.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredDocs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (ctx, index) {
                final doc = filteredDocs[index];
                final color = _categoryColor(doc.category, doc.fileType);
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBg(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.cardBorder(context)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(_fileIcon(doc), color: color, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    doc.title,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary(context),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    doc.category,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: color,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedTab == _ManagerDocTab.sharedWithMe && doc.sharedByUserName != null && doc.sharedByUserName!.isNotEmpty
                                  ? '${doc.fileName} â€¢ ${doc.formattedFileSize} â€¢ Shared by ${doc.sharedByUserName} on ${_formatDate(doc.sharedAt ?? doc.createdAt)}'
                                  : '${doc.fileName} â€¢ ${doc.formattedFileSize} â€¢ Uploaded by ${doc.createdByName.isNotEmpty ? doc.createdByName : doc.createdBy} on ${_formatDate(doc.createdAt)}',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppTheme.textSecondary(context),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (doc.description.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                doc.description,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: AppTheme.textMuted(context),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.visibility_outlined, size: 20),
                            tooltip: 'Preview',
                            onPressed: () => _showPreviewDialog(doc),
                          ),
                          IconButton(
                            icon: const Icon(Icons.download_rounded, size: 20),
                            tooltip: 'Download Document',
                            onPressed: () => _downloadDocument(doc),
                          ),
                          IconButton(
                            icon: const Icon(Icons.share_outlined, size: 20),
                            tooltip: 'Share Document',
                            onPressed: () => _showShareDialog(doc),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, size: 20),
                            tooltip: 'Delete Document',
                            onPressed: () => _confirmDeleteDocument(doc),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _SettingsPortalView extends StatefulWidget {
  const _SettingsPortalView();

  @override
  State<_SettingsPortalView> createState() => _SettingsPortalViewState();
}

class _SettingsPortalViewState extends State<_SettingsPortalView> {
  bool _emailReminders = true;
  bool _overdueAlerts = true;
  bool _dailySummary = false;
  String _dispatchInterval = '14-day cycle';
  bool _compactRows = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final currentMode = ThemeController.instance.themeMode;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Appearance & Theme Card
            Material(
              color: AppTheme.cardBg(context),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.cardBorder(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.palette_outlined,
                          color: AppTheme.primaryAccent(context),
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Appearance & Theme Mode',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Select your interface visual theme. Preferences are saved locally offline.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _buildThemeOption(
                          context,
                          title: 'Light Theme',
                          mode: ThemeMode.light,
                          currentMode: currentMode,
                          icon: Icons.light_mode_rounded,
                          color: const Color(0xFFEAB308),
                        ),
                        _buildThemeOption(
                          context,
                          title: 'Dark Theme',
                          mode: ThemeMode.dark,
                          currentMode: currentMode,
                          icon: Icons.dark_mode_outlined,
                          color: const Color(0xFF38BDF8),
                        ),
                        _buildThemeOption(
                          context,
                          title: 'System Default',
                          mode: ThemeMode.system,
                          currentMode: currentMode,
                          icon: Icons.settings_brightness_outlined,
                          color: const Color(0xFF8B5CF6),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Notification & Reminder Settings Card
            Material(
              color: AppTheme.cardBg(context),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.cardBorder(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.notifications_active_outlined,
                          color: Color(0xFF1565C0),
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Notification & Reminder Triggers',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Configure automated alerts, email dispatch frequency, and escalation triggers.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Notification Audio Chime',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      subtitle: Text(
                        'Play an audible tone when a new notification arrives',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                      value: SoundService.instance.isSoundEnabled,
                      onChanged: (val) {
                        setState(() {
                          SoundService.instance.setSoundEnabled(val);
                        });
                        if (val) {
                          SoundService.instance.playNotificationSound();
                        }
                      },
                    ),
                    Divider(color: AppTheme.dividerColor(context), height: 1),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Action Due Reminders',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      subtitle: Text(
                        'Trigger notifications 48h prior to action target completion date',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                      value: _emailReminders,
                      onChanged: (val) => setState(() => _emailReminders = val),
                    ),
                    Divider(color: AppTheme.dividerColor(context), height: 1),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Overdue Escalation Alerts',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      subtitle: Text(
                        'Instant alert when an action misses its target date',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                      value: _overdueAlerts,
                      onChanged: (val) => setState(() => _overdueAlerts = val),
                    ),
                    Divider(color: AppTheme.dividerColor(context), height: 1),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Daily Action Summary Digest',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      subtitle: Text(
                        'Morning digest email summarizing all active and pending actions',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                      value: _dailySummary,
                      onChanged: (val) => setState(() => _dailySummary = val),
                    ),
                    Divider(color: AppTheme.dividerColor(context), height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Email Dispatch Schedule',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary(context),
                            ),
                          ),
                          DropdownButton<String>(
                            value: _dispatchInterval,
                            dropdownColor: AppTheme.cardBg(context),
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.textPrimary(context),
                            ),
                            items:
                                ['14-day cycle', '7-day cycle', 'Daily digest']
                                    .map(
                                      (i) => DropdownMenuItem(
                                        value: i,
                                        child: Text(i),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _dispatchInterval = val);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Display & Table Density Card
            Material(
              color: AppTheme.cardBg(context),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.cardBorder(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.table_chart_outlined,
                          color: Color(0xFF1565C0),
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Workspace & Table Density',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Configure register layout density and row compactness.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Compact Table Rows',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      subtitle: Text(
                        'Fit more action rows per screen with reduced padding',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                      value: _compactRows,
                      onChanged: (val) => setState(() => _compactRows = val),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Save Preferences Action
            ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Manager portal preferences saved successfully.',
                    ),
                    backgroundColor: Color(0xFF1565C0),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save Portal Preferences'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 28),

            // Danger Zone / Account Deletion Card
            Material(
              color: AppTheme.cardBg(context),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFDC2626).withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFDC2626),
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Danger Zone',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Permanently delete your account, authentication credentials, and user profile from the system.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => _handleDeleteAccount(context),
                      icon: const Icon(
                        Icons.delete_forever_rounded,
                        color: Color(0xFFDC2626),
                        size: 18,
                      ),
                      label: const Text(
                        'Delete My Account',
                        style: TextStyle(
                          color: Color(0xFFDC2626),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFDC2626)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleDeleteAccount(BuildContext context) async {
    final currentUser = AuthService.instance.currentUser;
    final userEmail = currentUser?.email ?? 'your account';

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.cardBg(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppTheme.cardBorder(context)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_forever_rounded,
                color: Color(0xFFDC2626),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Delete Your Account',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to permanently delete your account?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.inputFill(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.cardBorder(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Account: $userEmail',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Role: Manager / Action Approver',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This will permanently remove your login credentials, profile, team memberships, and manager scopes. Any actions you created will be preserved and reassigned to your organization administrator. You will be signed out immediately.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary(context),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.delete_forever_rounded, size: 16),
            label: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await AuthService.instance.deleteSelfAccount();
      if (!mounted || !context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const LoginScreen(
            initialErrorMessage: 'Your account has been permanently deleted.',
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete account: $e'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }

  Widget _buildThemeOption(
    BuildContext context, {
    required String title,
    required ThemeMode mode,
    required ThemeMode currentMode,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = mode == currentMode;

    return InkWell(
      onTap: () => ThemeController.instance.setThemeMode(mode),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryAccent(context).withValues(alpha: 0.1)
              : AppTheme.containerBg(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryAccent(context)
                : AppTheme.cardBorder(context),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// HELPER MODELS & UTILITIES
// =============================================================================


Color _statusColor(String status) {
  switch (status) {
    case 'Open':
      return const Color(0xFF1565C0);
    case 'In Progress':
      return const Color(0xFF16A34A);
    case 'Overdue':
      return const Color(0xFFEA580C);
    case 'Pending Review':
      return const Color(0xFF7C3AED);
    case 'Closed':
      return const Color(0xFF059669);
    default:
      return const Color(0xFF64748B);
  }
}

class _NavItemData {
  const _NavItemData(this.label, this.icon, [this.isActive = false, this.index]);

  final String label;
  final IconData icon;
  final bool isActive;
  final int? index;
}



class _ManagerScopesCard extends StatelessWidget {
  const _ManagerScopesCard({this.managerContext});

  final ManagerContext? managerContext;

  @override
  Widget build(BuildContext context) {
    final scopes = managerContext?.activeScopes ?? [];
    final orgName = managerContext?.organizationName ?? 'Sobha';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder(context)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.isDark(context)
                ? Colors.black.withValues(alpha: 0.2)
                : const Color(0x060F172A),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.verified_user_rounded,
                  color: Color(0xFF1565C0),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Manager Authority & Assigned Scopes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Organization: $orgName Â· Scope-enforced via Row-Level Security (RLS)',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(height: 1, color: AppTheme.cardBorder(context)),
          const SizedBox(height: 16),
          if (scopes.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.amber,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No operational scopes are currently assigned to this account. Please contact your Company Administrator to assign department and site scopes.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Text(
              'Active Operating Scopes (${scopes.length})',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary(context),
              ),
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: scopes.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final scope = scopes[index];
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.isDark(context)
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.cardBorder(context)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.business_rounded,
                        size: 18,
                        color: Color(0xFF1565C0),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Department: ${scope.departmentName}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary(context),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Site: ${scope.siteName}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16A34A)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'ACTIVE SCOPE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF16A34A),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.isDark(context)
                  ? const Color(0xFF0F172A)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: AppTheme.textSecondary(context),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Security Notice: In accordance with tenant-isolation and manager-authority policies, you are strictly authorized to view, create, and manage actions within your explicitly assigned scopes. Scope modifications are controlled server-side by Company Administrators.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSecondary(context),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _ManagerRequestOverviewData {
  const _ManagerRequestOverviewData({
    required this.label,
    required this.value,
    required this.subtext,
    required this.color,
    required this.bgColor,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final String subtext;
  final Color color;
  final Color bgColor;
  final IconData icon;
  final VoidCallback onTap;
}

class _ManagerRequestOverviewCard extends StatefulWidget {
  const _ManagerRequestOverviewCard({required this.data});

  final _ManagerRequestOverviewData data;

  @override
  State<_ManagerRequestOverviewCard> createState() =>
      _ManagerRequestOverviewCardState();
}

class _ManagerRequestOverviewCardState
    extends State<_ManagerRequestOverviewCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final isDark = AppTheme.isDark(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: d.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.cardBg(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isHovered
                  ? d.color.withValues(alpha: 0.6)
                  : AppTheme.cardBorder(context),
              width: _isHovered ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: _isHovered
                    ? d.color.withValues(alpha: 0.12)
                    : (isDark
                        ? Colors.black.withValues(alpha: 0.2)
                        : const Color(0x060F172A)),
                blurRadius: _isHovered ? 8 : 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark
                      ? d.color.withValues(alpha: 0.18)
                      : d.bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Icon(d.icon, color: d.color, size: 20),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      d.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      d.value,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      d.subtext,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppTheme.textSecondary(context).withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
