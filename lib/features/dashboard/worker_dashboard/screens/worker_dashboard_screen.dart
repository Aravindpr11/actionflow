import 'dart:async';
import 'package:collection/collection.dart';

import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/core/theme/theme_controller.dart';
import 'package:action_flow/features/auth/screens/login_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/action_details_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/add_action_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart'
    show ActionRegisterSection;
import 'package:action_flow/features/dashboard/manager_dashboard/widgets/dashboard_attention_section.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/widgets/dashboard_forwarded_actions_card.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/widgets/dashboard_header_banner.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/widgets/dashboard_kpi_cards.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/widgets/dashboard_recent_activity.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/widgets/dashboard_status_and_progress.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/widgets/dashboard_timeline_panel.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/widgets/dashboard_upcoming_followups.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/profile/widgets/profile_view_card.dart';
import 'package:action_flow/features/reports/screens/reports_screen.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:action_flow/services/excel_export_service.dart';
import 'package:action_flow/widgets/common/action_flow_logo.dart';
import 'package:action_flow/widgets/common/theme_toggle_button.dart';
import 'package:action_flow/models/document_record.dart';
import 'package:action_flow/services/document_service.dart';
import 'package:action_flow/widgets/document_preview/document_preview_dialog.dart';
import 'package:action_flow/widgets/documents/document_upload_dialog.dart';
import 'package:action_flow/widgets/documents/document_share_dialog.dart';
import 'package:action_flow/features/calendar/widgets/calendar_view.dart';
import 'package:action_flow/features/calendar/models/calendar_task.dart';
import 'package:action_flow/services/calendar_task_service.dart';
import 'package:action_flow/services/report_service.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/widgets/dashboard_followups_dialog.dart';
import 'package:action_flow/features/notifications/widgets/notification_centre_view.dart';
import 'package:action_flow/features/notifications/widgets/notification_dropdown_overlay.dart';
import 'package:action_flow/features/notifications/widgets/quick_alert_toast.dart';
import 'package:action_flow/services/notification_service.dart';
import 'package:action_flow/services/sound_service.dart';
import 'package:action_flow/features/notifications/models/app_notification.dart';
import 'package:flutter/material.dart';

import 'worker_action_update_screen.dart';
import 'package:action_flow/features/requests/screens/new_request_screen.dart';
import 'package:action_flow/features/requests/screens/request_approval_screen.dart';
import 'package:action_flow/features/requests/screens/my_requests_screen.dart';
import 'package:action_flow/features/requests/models/request_models.dart';
import 'package:action_flow/features/requests/services/request_service.dart';

class WorkerDashboardScreen extends StatefulWidget {
  const WorkerDashboardScreen({
    super.key,
    this.userProfile,
    this.initialNavIndex = 0,
    this.initialActions,
  });

  final UserProfile? userProfile;
  final int initialNavIndex;
  final List<ActionRecord>? initialActions;

  @override
  State<WorkerDashboardScreen> createState() => _WorkerDashboardScreenState();
}

class _WorkerDashboardScreenState extends State<WorkerDashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final MockActionStore _store = MockActionStore.instance;

  // Staff Profile state
  late UserProfile _staffProfile;
  List<ActionRecord>? _liveActions;
  List<ActionRecord>? _createdActions;
  bool _isLoadingActions = false;
  String? _actionLoadError;

  // Personal Tasks & Calendar State
  List<CalendarTask> _personalTasks = [];
  DateTime? _calendarInitialDate;
  CalendarItemTypeFilter? _calendarInitialTypeFilter;

  // Navigation State
  late int _selectedNavIndex = widget.initialNavIndex;
  bool _hasStaffApprovalAuthority = false;
  StaffRequestOverviewCounts _staffRequestCounts = StaffRequestOverviewCounts.zero;
  bool _isLoadingRequestCounts = true;
  String? _requestCountsError;
  String _myRequestsInitialStatus = 'All Statuses';
  int _requestApprovalInitialTab = 0;

  // Search & Filter State
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'All Statuses';
  String _priorityFilter = 'All Priorities';
  String _siteFilter = 'All Sites';
  String _forwardedFilter = 'All Actions'; // 'All Actions', 'Forwarded Only', 'Direct Only'
  String _selectedDateField = 'All Dates';

  // Action Register State
  String _regSearchQuery = '';
  String _regStatus = 'All Status';
  String _regForwarded = 'All Actions';
  String _regDivision = 'All Divisions';
  String _regDepartment = 'All Departments';
  String _regSite = 'All Sites';
  String _regPriority = 'All Priority';
  String _regPerson = 'All People';
  String _regDate = 'Date';
  String _regDateField = 'All Dates';
  DateTime? _regCustomDateStart;
  DateTime? _regCustomDateEnd;
  String _regSort = 'Target Date (Earliest First)';

  // Permission helpers
  bool _isActionAssignedToCurrentUser(ActionRecord action) {
    final staffId = _staffProfile.id.trim();
    final authId = SupabaseConfig.clientOrNull?.auth.currentUser?.id.trim() ?? '';
    final staffName = _staffProfile.name.trim().toLowerCase();
    final staffEmail = _staffProfile.email.trim().toLowerCase();

    // Direct assignedToId or primaryAssignee personId
    if (staffId.isNotEmpty &&
        (action.assignedToId?.trim() == staffId ||
            action.primaryAssignee?.personId.trim() == staffId)) {
      return true;
    }
    if (authId.isNotEmpty &&
        (action.assignedToId?.trim() == authId ||
            action.primaryAssignee?.personId.trim() == authId)) {
      return true;
    }

    // Name or Email of assignee
    if (staffName.isNotEmpty &&
        (action.assignedTo.trim().toLowerCase() == staffName ||
            action.primaryAssignee?.name.trim().toLowerCase() == staffName)) {
      return true;
    }
    if (staffEmail.isNotEmpty &&
        action.primaryAssignee?.email.trim().toLowerCase() == staffEmail) {
      return true;
    }

    // In assignees list
    for (final a in action.assignees) {
      final pId = a.profileId.trim();
      final pEmail = a.profileEmail.trim().toLowerCase();
      if (staffId.isNotEmpty && pId == staffId) return true;
      if (authId.isNotEmpty && pId == authId) return true;
      if (staffEmail.isNotEmpty && pEmail == staffEmail) return true;
    }

    return false;
  }

  /// Staff My Actions: Delete only Closed actions currently assigned to the authenticated Staff user.
  /// Crucial Rule: Do not allow a creator-only match to grant deletion permission through My Actions.
  bool _canDeleteFromMyActions(ActionRecord action) {
    if (_staffProfile.role == 'admin') return true;
    if (!action.isClosed) return false;
    return _isActionAssignedToCurrentUser(action);
  }

  /// Staff Action Register: Delete actions created by the authenticated Staff user regardless of status.
  bool _canDeleteFromActionRegister(ActionRecord action) {
    if (_staffProfile.role == 'admin') return true;

    final staffId = _staffProfile.id.trim();
    final authId = SupabaseConfig.clientOrNull?.auth.currentUser?.id.trim() ?? '';
    final cId = action.createdById.trim();

    return (staffId.isNotEmpty && cId == staffId) ||
        (authId.isNotEmpty && cId == authId);
  }

  @visibleForTesting
  bool canDeleteAction(ActionRecord action) => _canDeleteFromMyActions(action);

  @visibleForTesting
  bool canDeleteFromMyActions(ActionRecord action) => _canDeleteFromMyActions(action);

  @visibleForTesting
  bool canDeleteFromActionRegister(ActionRecord action) => _canDeleteFromActionRegister(action);

  bool _canEditAction(ActionRecord action) {
    final staffId = _staffProfile.id.trim();
    final staffName = _staffProfile.name.trim();
    final staffEmail = _staffProfile.email.trim();
    return (staffId.isNotEmpty && action.createdById == staffId) ||
        action.isOwner(staffId, staffName, staffEmail) ||
        _staffProfile.role == 'admin';
  }

  // Selection State
  final Set<String> _selectedActionIds = <String>{};

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

  int _unreadNotificationCount = 3;

  Future<void> _updateNotificationCount() async {
    try {
      final count = await NotificationService.instance.getUnreadCount(
        userId: _staffProfile.id,
      );
      if (mounted) {
        setState(() => _unreadNotificationCount = count);
      }
    } catch (_) {}
  }

  List<DocumentRecord>? _workerDocuments;
  bool _isLoadingWorkerDocuments = false;
  String _documentFilter = 'All'; // 'All', 'My Uploads', 'Shared with Me', 'Shared by Me', 'Guidelines & Policies'
  final TextEditingController _docSearchController = TextEditingController();

  void _loadWorkerDocuments() {
    if (_isLoadingWorkerDocuments) return;
    setState(() {
      _isLoadingWorkerDocuments = true;
    });
    DocumentService.instance.fetchDocuments(
      organizationId: _effectiveOrgId,
      currentUserId: _staffProfile.id,
      userRole: 'staff',
    ).then((docs) {
      if (mounted) {
        setState(() {
          _workerDocuments = docs;
          _isLoadingWorkerDocuments = false;
        });
      }
    }).catchError((err) {
      debugPrint('[WorkerDashboard] Error loading documents: $err');
      if (mounted) {
        setState(() {
          _workerDocuments = MockDocumentStore.instance.documents;
          _isLoadingWorkerDocuments = false;
        });
      }
    });
  }

  String get _effectiveOrgId {
    final orgId = _staffProfile.organizationId?.trim();
    if (orgId != null && orgId.isNotEmpty) {
      if (orgId == 'SOBHA-001' || orgId == 'org-sobha-01') {
        return Organization.sobhaId;
      }
      return orgId;
    }
    return Organization.sobhaId;
  }

  void _showDocumentPreview(DocumentRecord doc) {
    final effectiveOrg = doc.organizationId.isNotEmpty
        ? doc.organizationId
        : _effectiveOrgId;
    DocumentPreviewDialog.show(
      context,
      doc: doc,
      organizationId: effectiveOrg,
    );
  }

  Future<void> _downloadDocument(DocumentRecord doc) async {
    final effectiveOrg = doc.organizationId.isNotEmpty
        ? doc.organizationId
        : _effectiveOrgId;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Downloading "${doc.fileName}"...'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final success = await DocumentService.instance.downloadAndSaveDocument(
        doc: doc,
        organizationId: effectiveOrg,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Downloaded "${doc.fileName}".'
                  : 'Download cancelled.',
            ),
            backgroundColor: success
                ? const Color(0xFF16A34A)
                : const Color(0xFF64748B),
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

  void _openUploadDocumentDialog() {
    DocumentUploadDialog.show(
      context,
      organizationId: _effectiveOrgId,
      userId: _staffProfile.id,
      userName: _staffProfile.name,
      departmentId: _staffProfile.departmentId,
      departmentName: _staffProfile.department,
      actions: _myActions,
      onDocumentUploaded: (newDoc) {
        _loadWorkerDocuments();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Document "${newDoc.title}" uploaded successfully.'),
              backgroundColor: const Color(0xFF16A34A),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
    );
  }

  void _openShareDocumentDialog(DocumentRecord doc) {
    DocumentShareDialog.show(
      context,
      document: doc,
      organizationId: _effectiveOrgId,
      currentUserId: _staffProfile.id,
      currentUserName: _staffProfile.name,
      currentUserRole: 'staff',
      currentUserDepartment: _staffProfile.department,
      currentUserDepartmentId: doc.departmentId ?? _staffProfile.departmentId,
      onSharesUpdated: _loadWorkerDocuments,
    );
  }

  void _confirmDeleteDocument(DocumentRecord doc) {
    final isOwner = doc.isOwnedBy(_staffProfile.id) ||
        (doc.createdByName.isNotEmpty &&
            doc.createdByName.toLowerCase() ==
                _staffProfile.name.toLowerCase());
    if (!isOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are only authorized to delete documents you uploaded.'),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    bool isDeleting = false;
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: AppTheme.cardBg(dialogCtx),
              title: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red.shade600, size: 24),
                  const SizedBox(width: 10),
                  Text(
                    'Delete Document',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(dialogCtx),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: Text(
                  'Are you sure you want to delete "${doc.title}"?\n\nThis will remove the file from storage, delete all metadata, and permanently revoke all active shares.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary(dialogCtx)),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isDeleting ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                  onPressed: isDeleting
                      ? null
                      : () async {
                          setModalState(() => isDeleting = true);
                          try {
                            await DocumentService.instance.deleteDocument(
                              documentId: doc.id,
                              organizationId: _effectiveOrgId,
                              userId: _staffProfile.id,
                              userRole: 'staff',
                              userName: _staffProfile.name,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            _loadWorkerDocuments();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Document "${doc.title}" deleted.'),
                                  backgroundColor: const Color(0xFFDC2626),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            setModalState(() => isDeleting = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Deletion failed: $e'),
                                  backgroundColor: Colors.red,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        },
                  child: isDeleting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Delete'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _selectedDate = 'Date';
  DateTime? _customDateStart;
  DateTime? _customDateEnd;
  String _sortOrder = 'Newest First';

  @override
  void initState() {
    super.initState();
    final authenticatedProfile =
        AuthService.instance.currentProfileData?.userProfile;
    _staffProfile =
        widget.userProfile ?? authenticatedProfile ?? UserProfile.mockStaff();
    if (widget.initialActions != null) {
      _liveActions = List.from(widget.initialActions!);
    } else if (SupabaseConfig.isInitialized) {
      if (widget.userProfile == null && authenticatedProfile == null) {
        _liveActions = const [];
        _actionLoadError =
            'Your staff profile could not be verified. Please sign in again.';
      } else {
        unawaited(_loadStaffActions());
      }
    }
    _checkStaffApprovalAuthority();

    final authId = SupabaseConfig.clientOrNull?.auth.currentUser?.id ?? _staffProfile.id;
    if (authId.isNotEmpty) {
      NotificationService.instance.subscribeToRealtimeNotifications(authId);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _docSearchController.dispose();
    NotificationService.instance.unsubscribeFromRealtime();
    super.dispose();
  }

  Future<void> _checkStaffApprovalAuthority() async {
    try {
      final hasAuth = await RequestService.instance.hasStaffApprovalAuthority(
        userId: _staffProfile.id,
        organizationId: _staffProfile.organizationId ?? '',
      );
      if (mounted) {
        setState(() {
          _hasStaffApprovalAuthority = hasAuth;
        });
      }
    } catch (_) {}

    await _loadRequestOverviewCounts();
  }

  Future<void> _loadRequestOverviewCounts() async {
    final currentUserId = _staffProfile.id;
    final orgId = _staffProfile.organizationId ?? Organization.sobhaId;

    try {
      final counts = await RequestService.instance.getStaffRequestOverviewCounts(
        userId: currentUserId,
        organizationId: orgId,
        hasApprovalAuthority: _hasStaffApprovalAuthority,
      );
      if (mounted) {
        setState(() {
          _staffRequestCounts = counts;
          _isLoadingRequestCounts = false;
          _requestCountsError = null;
        });
      }
    } catch (e) {
      debugPrint('[WorkerDashboard] Error loading request overview counts: $e');
      if (mounted) {
        setState(() {
          _isLoadingRequestCounts = false;
          _requestCountsError = e.toString();
        });
      }
    }
  }

  void _navigateToMyRequests({String status = 'All Statuses'}) {
    setState(() {
      _myRequestsInitialStatus = status;
      _selectedNavIndex = 10;
    });
  }

  void _navigateToRequestApproval({int tabIndex = 0}) {
    setState(() {
      _requestApprovalInitialTab = tabIndex;
      _selectedNavIndex = 11;
    });
  }

  Widget _buildRequestOverviewSection(BoxConstraints constraints) {
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
      _WorkerRequestOverviewData(
        label: 'My Submitted Requests',
        value: '${_staffRequestCounts.mySubmittedTotal}',
        subtext: 'Your total requests',
        color: const Color(0xFF2563EB),
        bgColor: const Color(0xFFDBEAFE),
        icon: Icons.inbox_rounded,
        onTap: () => _navigateToMyRequests(status: 'All Statuses'),
      ),
      _WorkerRequestOverviewData(
        label: 'Pending Approval',
        value: '${_staffRequestCounts.pendingApproval}',
        subtext: 'Awaiting first review',
        color: const Color(0xFFD97706),
        bgColor: const Color(0xFFFEF3C7),
        icon: Icons.hourglass_top_rounded,
        onTap: () => _navigateToMyRequests(status: 'Submitted'),
      ),
      _WorkerRequestOverviewData(
        label: 'Under Review',
        value: '${_staffRequestCounts.underReview}',
        subtext: 'In approval chain',
        color: const Color(0xFF8B5CF6),
        bgColor: const Color(0xFFEDE9FE),
        icon: Icons.rule_rounded,
        onTap: () => _navigateToMyRequests(status: 'Under Review'),
      ),
      _WorkerRequestOverviewData(
        label: 'Approved',
        value: '${_staffRequestCounts.approved}',
        subtext: 'Ready for fulfillment',
        color: const Color(0xFF059669),
        bgColor: const Color(0xFFD1FAE5),
        icon: Icons.check_circle_outline_rounded,
        onTap: () => _navigateToMyRequests(status: 'Approved'),
      ),
      _WorkerRequestOverviewData(
        label: 'Rejected',
        value: '${_staffRequestCounts.rejected}',
        subtext: 'Declined requests',
        color: const Color(0xFFE11D48),
        bgColor: const Color(0xFFFFE4E6),
        icon: Icons.cancel_outlined,
        onTap: () => _navigateToMyRequests(status: 'Rejected'),
      ),
      _WorkerRequestOverviewData(
        label: 'Completed',
        value: '${_staffRequestCounts.completed}',
        subtext: 'Fulfilled & closed',
        color: const Color(0xFF6B7280),
        bgColor: const Color(0xFFF3F4F6),
        icon: Icons.task_alt_rounded,
        onTap: () => _navigateToMyRequests(status: 'Completed'),
      ),
      if (_hasStaffApprovalAuthority && _staffRequestCounts.pendingMyApproval != null)
        _WorkerRequestOverviewData(
          label: 'Pending My Approval',
          value: '${_staffRequestCounts.pendingMyApproval ?? 0}',
          subtext: 'Awaiting your action',
          color: const Color(0xFFDC2626),
          bgColor: const Color(0xFFFEE2E2),
          icon: Icons.pending_actions_rounded,
          onTap: () => _navigateToRequestApproval(tabIndex: 0),
        ),
    ];

    final w = constraints.maxWidth;
    Widget cardsWidget;

    if (w >= 1400) {
      cardsWidget = Row(
        children: cards.map((data) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _WorkerRequestOverviewCard(data: data),
            ),
          );
        }).toList(),
      );
    } else if (w >= 850) {
      final cols = w >= 1150 ? (cards.length > 6 ? 4 : 3) : 3;
      final cardWidth = (w - ((cols - 1) * 12)) / cols;
      cardsWidget = Wrap(
        spacing: 12,
        runSpacing: 12,
        children: cards.map((data) {
          return SizedBox(
            width: cardWidth,
            child: _WorkerRequestOverviewCard(data: data),
          );
        }).toList(),
      );
    } else if (w >= 480) {
      final cardWidth = (w - 12) / 2;
      cardsWidget = Wrap(
        spacing: 12,
        runSpacing: 12,
        children: cards.map((data) {
          return SizedBox(
            width: cardWidth,
            child: _WorkerRequestOverviewCard(data: data),
          );
        }).toList(),
      );
    } else {
      cardsWidget = Column(
        children: cards.map((data) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _WorkerRequestOverviewCard(data: data),
          );
        }).toList(),
      );
    }

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
                  'My Request Overview',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            InkWell(
              onTap: () => _navigateToMyRequests(status: 'All Statuses'),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    Text(
                      'View My Requests',
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
        cardsWidget,
      ],
    );
  }

  List<ActionRecord> get _myActions {
    final actions = _liveActions ?? _store.actions;
    final staffName = _staffProfile.name.trim();
    final staffId = _staffProfile.id.trim();
    final staffEmail = _staffProfile.email.trim();
    return actions.where((a) {
      if (a.isDeleted) return false;
      if (a.isExternalRecipient) return false;
      final assignedName = a.assignedTo.trim();
      final assignedId = a.assignedToId?.trim() ?? '';
      final primaryName = a.primaryAssignee?.name.trim() ?? '';
      final primaryId = a.primaryAssignee?.personId.trim() ?? '';
      final isDirectAssignee =
          (staffName.isNotEmpty &&
              (assignedName.toLowerCase() == staffName.toLowerCase() ||
                  primaryName.toLowerCase() == staffName.toLowerCase())) ||
          (staffId.isNotEmpty &&
              (assignedId == staffId || primaryId == staffId)) ||
          a.assignees.any((asg) =>
              (staffId.isNotEmpty && asg.profileId == staffId) ||
              (staffName.isNotEmpty &&
                  asg.profileName.toLowerCase() == staffName.toLowerCase()));
      if (isDirectAssignee) return true;

      // Forwarded check: Contributor or Sub-task
      if (a.isForwardedTo(staffId, staffName, staffEmail)) return true;

      return false;
    }).toList();
  }

  /// Staff Action Register: Only actions created by this authenticated Staff member.
  List<ActionRecord> get _staffCreatedActions {
    final actions = _createdActions;
    if (actions != null) {
      return actions.where((a) => !a.isDeleted && !a.isExternalRecipient).toList();
    }
    final staffId = _staffProfile.id.trim().toLowerCase();
    final currentAuthId = SupabaseConfig.clientOrNull?.auth.currentUser?.id.trim().toLowerCase();
    final effectiveUid = (currentAuthId != null && currentAuthId.isNotEmpty)
        ? currentAuthId
        : staffId;
    return _store.actions.where((a) {
      if (a.isDeleted || a.isExternalRecipient) return false;
      return a.createdById.trim().toLowerCase() == effectiveUid;
    }).toList();
  }

  int get _followUpCount {
    int count = 0;
    for (final a in _myActions) {
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

    for (final a in _myActions) {
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

  Future<void> _loadPersonalTasks() async {
    final currentAuthId = SupabaseConfig.clientOrNull?.auth.currentUser?.id;
    final userId = (currentAuthId != null && currentAuthId.isNotEmpty)
        ? currentAuthId
        : _staffProfile.id.trim();
    if (userId.isEmpty) return;
    try {
      final tasks = await CalendarTaskService().getTasks(userId: userId);
      if (mounted) {
        setState(() {
          _personalTasks = tasks;
        });
      }
    } catch (e) {
      debugPrint('[WorkerDashboard] Error loading personal tasks: $e');
    }
  }

  void _showFollowUpsDialog(BuildContext context, [FollowUpClassification? initialClassification]) {
    DashboardFollowupsDialog.show(
      context,
      actions: _myActions,
      onActionTap: _openDetails,
      initialClassification: initialClassification,
    );
  }

  Future<void> _loadStaffActions() async {
    final organizationId = _effectiveOrgId;
    unawaited(_loadRequestOverviewCounts());
    unawaited(_loadPersonalTasks());
    final currentAuthId = SupabaseConfig.clientOrNull?.auth.currentUser?.id;
    final userId = (currentAuthId != null && currentAuthId.isNotEmpty)
        ? currentAuthId
        : _staffProfile.id.trim();
    if (organizationId.isEmpty || userId.isEmpty) {
      setState(() {
        _liveActions = const [];
        _actionLoadError =
            'Your staff account is missing its organization details.';
        _isLoadingActions = false;
      });
      return;
    }

    setState(() {
      _isLoadingActions = true;
      _actionLoadError = null;
    });
    try {
      final results = await Future.wait([
        ActionService.instance.fetchMyActions(
          organizationId: organizationId,
          userId: userId,
        ),
        ActionService.instance.fetchStaffCreatedActions(
          organizationId: organizationId,
          userId: userId,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _liveActions = results[0]
            .where((action) => !action.isExternalRecipient)
            .toList();
        _createdActions = results[1]
            .where((action) => !action.isExternalRecipient)
            .toList();
        _selectedActionIds.removeWhere(
          (id) => !_myActions.any((a) => a.id == id),
        );
        _isLoadingActions = false;
      });
      unawaited(
        NotificationService.instance.checkActionReminders(
          actions: _liveActions ?? [],
          userId: userId,
          isManager: false,
        ),
      );
    } catch (e, st) {
      debugPrint('[WorkerDashboardScreen] Error loading staff actions: $e\n$st');
      if (!mounted) return;
      setState(() {
        _liveActions = const [];
        _createdActions = const [];
        _actionLoadError =
            'Unable to load your assigned actions. Please try again.';
        _isLoadingActions = false;
      });
    }
  }

  void _resetStaffFilters() {
    setState(() {
      _searchQuery = '';
      _searchController.clear();
      _statusFilter = 'All Statuses';
      _priorityFilter = 'All Priorities';
      _siteFilter = 'All Sites';
      _forwardedFilter = 'All Actions';
      _selectedDateField = 'All Dates';
      _selectedDate = 'Date';
      _customDateStart = null;
      _customDateEnd = null;
      _sortOrder = 'Newest First';
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

      // Format: DD MMM YYYY (e.g. "15 Sep 2026")
      final parts = dateStr.trim().split(RegExp(r'\s+'));
      if (parts.length >= 3) {
        final day = int.tryParse(parts[0]);
        final year = int.tryParse(parts[2]);
        final monthStr = parts[1].toLowerCase();
        int? month;
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
        }
        if (action.closedAt != null) {
          final c = action.closedAt!.isUtc
              ? action.closedAt!.toLocal()
              : action.closedAt!;
          set.add(DateTime(c.year, c.month, c.day));
        }
        final dClose = _parseDateString(action.closeDate);
        if (dClose != null) set.add(dClose);
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
    } else if (filter == 'All Time' || filter == 'Date') {
      return true;
    }
    return true;
  }

  static bool _matchesDateFilter(
    ActionRecord action,
    String filter, {
    String dateField = 'All Dates',
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    if (filter == 'Date' && dateField == 'All Dates') return true;
    final dates = _extractActionDates(action, dateField);
    if (dates.isEmpty) return false;
    return dates.any(
      (d) => _dateMatchesPeriod(
        d,
        filter,
        customStart: customStart,
        customEnd: customEnd,
      ),
    );
  }

  Future<void> _selectCustomDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      initialDateRange: _customDateStart != null && _customDateEnd != null
          ? DateTimeRange(start: _customDateStart!, end: _customDateEnd!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: const Color(0xFF1565C0),
              onPrimary: Colors.white,
              surface: AppTheme.cardBg(context),
              onSurface: AppTheme.textPrimary(context),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _customDateStart = picked.start;
        _customDateEnd = picked.end;
        _selectedDate = 'Custom Range';
      });
    }
  }

  void _exportStaffReport(
    List<ActionRecord> actions, [
    Map<String, String>? filters,
  ]) {
    final activeFilters = <String, String>{};
    if (filters != null) {
      activeFilters.addAll(filters);
    } else {
      if (_searchQuery.isNotEmpty) activeFilters['Search'] = _searchQuery;
      if (_statusFilter != 'All Statuses') activeFilters['Status'] = _statusFilter;
      if (_priorityFilter != 'All Priorities') {
        activeFilters['Priority'] = _priorityFilter;
      }
      if (_siteFilter != 'All Sites') activeFilters['Site'] = _siteFilter;
      if (_forwardedFilter != 'All Actions') {
        activeFilters['Forwarded'] = _forwardedFilter;
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
    }

    unawaited(
      ExcelExportService.instance.exportReportExcel(
        context: context,
        filteredActions: actions,
        userName: _staffProfile.name,
        userRole: _staffProfile.role,
        organizationName: _staffProfile.organizationName.isNotEmpty
            ? _staffProfile.organizationName
            : Organization.sobhaName,
        activeFilters: activeFilters,
      ),
    );
  }

  List<ActionRecord> get _visibleActions {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = _myActions.where((action) {
      final matchesQuery = query.isEmpty ||
          action.displayId.toLowerCase().contains(query) ||
          action.actionNumber.toLowerCase().contains(query) ||
          action.subject.toLowerCase().contains(query) ||
          action.description.toLowerCase().contains(query) ||
          action.actionRequired.toLowerCase().contains(query) ||
          action.site.toLowerCase().contains(query) ||
          action.department.toLowerCase().contains(query) ||
          action.division.toLowerCase().contains(query) ||
          action.assignedTo.toLowerCase().contains(query) ||
          (action.primaryAssignee?.name.toLowerCase().contains(query) ?? false) ||
          action.assignees.any(
            (a) => a.profileName.toLowerCase().contains(query),
          ) ||
          action.contributors.any(
            (c) => c.profileName.toLowerCase().contains(query),
          );

      final matchesStatus = _statusFilter == 'All Statuses' ||
          (_statusFilter == 'Closed' &&
              (action.isClosed || action.status.toLowerCase() == 'closed')) ||
          (_statusFilter == 'Pending Review' &&
              (action.status.toLowerCase() == 'pending review' ||
                  action.isReadyForReview)) ||
          (_statusFilter == 'Overdue' &&
              (action.isOverdue || action.status.toLowerCase() == 'overdue')) ||
          (_statusFilter == 'Open' &&
              action.status.toLowerCase() == 'open') ||
          (_statusFilter == 'In Progress' &&
              action.status.toLowerCase() == 'in progress') ||
          action.status.toLowerCase() == _statusFilter.toLowerCase();

      final matchesPriority =
          _priorityFilter == 'All Priorities' ||
          (_priorityFilter == 'Critical / High'
              ? (action.priority == 'Critical' || action.priority == 'High')
              : action.priority.toLowerCase() == _priorityFilter.toLowerCase());

      final matchesSite =
          _siteFilter == 'All Sites' ||
          action.site.toLowerCase() == _siteFilter.toLowerCase();

      // Forwarded filter
      if (_forwardedFilter != 'All Actions') {
        final staffId = _staffProfile.id;
        final staffName = _staffProfile.name;
        final staffEmail = _staffProfile.email;
        if (_forwardedFilter == 'Forwarded by Me') {
          if (!action.isForwardedBy(staffId, staffName, staffEmail)) return false;
        } else if (_forwardedFilter == 'Forwarded to Me') {
          if (!action.isForwardedTo(staffId, staffName, staffEmail)) return false;
        } else if (_forwardedFilter == 'Forwarded Only') {
          if (!action.isForwarded) return false;
        } else if (_forwardedFilter == 'Direct Only') {
          if (action.isForwarded) return false;
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

      return matchesQuery && matchesStatus && matchesPriority && matchesSite;
    }).toList();

    if (_sortOrder == 'Target Date') {
      filtered.sort((a, b) {
        final aTarget = a.targetDateTime;
        final bTarget = b.targetDateTime;
        if (aTarget != null && bTarget != null) {
          final cmp = aTarget.compareTo(bTarget);
          if (cmp != 0) return cmp;
        } else if (aTarget != null) {
          return -1;
        } else if (bTarget != null) {
          return 1;
        }
        return a.targetDate.compareTo(b.targetDate);
      });
    } else if (_sortOrder == 'Priority') {
      const rank = {'Critical': 0, 'High': 1, 'Medium': 2, 'Low': 3};
      filtered.sort(
        (a, b) => (rank[a.priority] ?? 4).compareTo(rank[b.priority] ?? 4),
      );
    } else if (_sortOrder == 'Progress') {
      filtered.sort((a, b) => b.percentComplete.compareTo(a.percentComplete));
    } else if (_sortOrder == 'Newest First') {
      filtered.sort((a, b) {
        final aTime = a.createdAt ?? a.createdDateTime;
        final bTime = b.createdAt ?? b.createdDateTime;
        if (aTime != null && bTime != null) {
          final cmp = bTime.compareTo(aTime);
          if (cmp != 0) return cmp;
        } else if (bTime != null) {
          return 1;
        } else if (aTime != null) {
          return -1;
        }
        return b.displayId.compareTo(a.displayId);
      });
    } else if (_sortOrder == 'Oldest First') {
      filtered.sort((a, b) {
        final aTime = a.createdAt ?? a.createdDateTime;
        final bTime = b.createdAt ?? b.createdDateTime;
        if (aTime != null && bTime != null) {
          final cmp = aTime.compareTo(bTime);
          if (cmp != 0) return cmp;
        } else if (aTime != null) {
          return -1;
        } else if (bTime != null) {
          return 1;
        }
        return a.displayId.compareTo(b.displayId);
      });
    }
    return filtered;
  }

  Future<void> _openUpdate(ActionRecord action) async {
    final updated = await Navigator.of(context).push<ActionRecord>(
      MaterialPageRoute(
        builder: (_) => WorkerActionUpdateScreen(
          action: action,
          currentUserId: _staffProfile.id,
          currentUserName: _staffProfile.name,
          currentUserEmail: _staffProfile.email,
        ),
      ),
    );
    if (updated != null && mounted) {
      ActionRecord finalAction = updated;
      try {
        final saved = await ActionService.instance.submitProgressUpdate(
          actionId: updated.id,
          updateDate: DateTime.now(),
          progress: updated.percentComplete,
          status: updated.status,
          comments: updated.workerMessage.isNotEmpty
              ? updated.workerMessage
              : 'Staff progress update',
          attachments: updated.attachments,
          subTasks: updated.subTasks,
          history: updated.history,
        );
        finalAction = saved;
      } catch (e) {
        debugPrint('[WorkerDashboard] Progress update error: $e');
      }
      _store.update(finalAction);
      if (SupabaseConfig.isInitialized) {
        unawaited(_loadStaffActions());
      }
      setState(() {});
      final isPendingReview = updated.status == 'Pending Review';
      final message = isPendingReview
          ? '${updated.id}: Action submitted for Manager verification.'
          : '${updated.id}: Progress update saved successfully.';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isPendingReview
              ? const Color(0xFF7C3AED)
              : const Color(0xFF1565C0),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openDetails(ActionRecord action) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActionDetailsScreen(
          action: action,
          isWorker: true,
          currentUserId: _staffProfile.id,
          onUpdateAction: () => _openUpdate(action),
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() {});
        if (SupabaseConfig.isInitialized) {
          unawaited(_loadStaffActions());
        }
      }
    });
  }

  void _handleEditAction(ActionRecord action) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddActionScreen(
          actionId: action.id,
          existingAction: action,
          isEmbedded: false,
          isManager: false,
          isStaff: true,
          organizationId: _effectiveOrgId,
          onSaved: (_) {
            if (mounted) {
              setState(() {});
              if (SupabaseConfig.isInitialized) {
                unawaited(_loadStaffActions());
              }
            }
          },
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() {});
        if (SupabaseConfig.isInitialized) {
          unawaited(_loadStaffActions());
        }
      }
    });
  }

  Future<void> _handleDeleteAction(
    ActionRecord action, {
    bool fromActionRegister = false,
  }) async {
    final isStaff = _staffProfile.role != 'admin' && _staffProfile.role != 'manager';
    if (isStaff && !action.isClosed && !fromActionRegister) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Staff members can only delete closed actions from My Actions.'),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final canDelete = fromActionRegister
        ? _canDeleteFromActionRegister(action)
        : _canDeleteFromMyActions(action);
    if (!canDelete) {
      final reason = fromActionRegister
          ? 'Staff members can only delete actions created by them from Action Register.'
          : 'Staff members can only delete closed actions assigned to them from My Actions.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You do not have permission to delete action ${action.displayId}. $reason',
          ),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
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
            Expanded(
              child: Text(
                action.isClosed ? 'Delete Closed Action' : 'Delete Action',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete ${action.isClosed ? 'closed ' : ''}action ${action.displayId}?\n\n'
          'This action will be removed from your assigned actions. Its history and audit trail will be retained.',
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
            child: const Text('Delete Action'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final res = await ActionService.instance.deleteActionAuthorized(
        action.id,
        allowClosed: true,
        portalContext: fromActionRegister ? 'action_register' : 'my_actions',
      );
      if (!mounted) return;
      if (res.success) {
        setState(() {
          _liveActions?.removeWhere((a) => a.id == action.id);
          _createdActions?.removeWhere((a) => a.id == action.id);
          _store.actions.removeWhere((a) => a.id == action.id);
          _selectedActionIds.remove(action.id);
        });
        unawaited(_loadStaffActions());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Action ${action.displayId} deleted successfully.'),
            backgroundColor: const Color(0xFF16A34A),
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

  Future<void> _handleDeleteSelectedActions([
    List<ActionRecord>? visibleActions,
    bool fromActionRegister = false,
  ]) async {
    if (_selectedActionIds.isEmpty) return;

    final selectedIds = _selectedActionIds.toList();
    final count = selectedIds.length;

    // Validate permissions for each action across all available actions
    final pool = <ActionRecord>{
      ..._myActions,
      ..._staffCreatedActions,
      if (_liveActions != null) ..._liveActions!,
      ..._store.actions,
      if (visibleActions != null) ...visibleActions,
    }.toList();
    final unauthorized = <ActionRecord>[];
    for (final id in selectedIds) {
      final act = pool.firstWhereOrNull((a) => a.id == id);
      if (act != null) {
        final allowed = fromActionRegister
            ? _canDeleteFromActionRegister(act)
            : _canDeleteFromMyActions(act);
        if (!allowed) {
          unauthorized.add(act);
        }
      }
    }

    if (unauthorized.isNotEmpty) {
      final reason = fromActionRegister
          ? 'Staff members can only delete actions created by them.'
          : 'Staff members can only delete closed actions assigned to them.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot delete ${unauthorized.length} selected action(s). $reason',
          ),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
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
                'Delete Selected Actions',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete $count selected actions? These actions will be removed from active views. Their audit history will be retained.',
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
            child: Text('Delete $count Actions'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final res = await ActionService.instance.deleteActionsBulk(
        selectedIds,
        allowClosed: true,
        portalContext: fromActionRegister ? 'action_register' : 'my_actions',
      );
      if (!mounted) return;

      if (res.success) {
        setState(() {
          _liveActions?.removeWhere((a) => selectedIds.contains(a.id));
          _createdActions?.removeWhere((a) => selectedIds.contains(a.id));
          _store.actions.removeWhere((a) => selectedIds.contains(a.id));
          _selectedActionIds.clear();
        });
        unawaited(_loadStaffActions());
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully deleted ${res.deletedCount} action${res.deletedCount == 1 ? '' : 's'}.',
            ),
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        final failedIds = res.failedIds;
        final successfulIds =
            selectedIds.where((id) => !failedIds.contains(id)).toList();
        setState(() {
          if (successfulIds.isNotEmpty) {
            _liveActions?.removeWhere((a) => successfulIds.contains(a.id));
            _createdActions?.removeWhere((a) => successfulIds.contains(a.id));
            _store.actions.removeWhere((a) => successfulIds.contains(a.id));
            _selectedActionIds.removeWhere((id) => successfulIds.contains(id));
          }
        });
        unawaited(_loadStaffActions());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Deleted ${res.deletedCount} action(s). Failed: ${failedIds.length}. ${res.error ?? "Unauthorized or cannot delete."}',
            ),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleNotificationTap(AppNotification notif) async {
    unawaited(NotificationService.instance.markAsRead(
      notificationId: notif.id,
      userId: notif.userId.isNotEmpty ? notif.userId : _staffProfile.id,
    ));
    unawaited(_updateNotificationCount());

    final combined = '${notif.title} ${notif.message} ${notif.actionId ?? ''}'.toUpperCase();
    final isRequest = combined.contains('REQ-') ||
        notif.eventType.toLowerCase().contains('request') ||
        (notif.actionId != null && notif.actionId!.toUpperCase().startsWith('REQ-'));

    if (isRequest) {
      if (!mounted) return;
      setState(() {
        _selectedNavIndex = 10;
      });
      return;
    }

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

    // 1. Search in local staff-assigned actions first
    ActionRecord? match;
    for (final a in _myActions) {
      if (ActionService.isActionMatch(a, cleanId)) {
        match = a;
        break;
      }
    }

    // 2. Search in all store actions if not in _myActions
    if (match == null) {
      for (final a in _store.actions) {
        if (ActionService.isActionMatch(a, cleanId)) {
          match = a;
          break;
        }
      }
    }

    // 3. If not found in memory, query ActionService
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
    final staffOrgId = _staffProfile.organizationId?.trim() ?? '';
    if (staffOrgId.isNotEmpty &&
        match.organizationId.trim().isNotEmpty &&
        match.organizationId.trim().toLowerCase() != staffOrgId.toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You do not have permission to view action "$actionId".'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // 5. Verify staff-level access permissions
    final staffName = _staffProfile.name.trim();
    final staffId = _staffProfile.id.trim();
    final staffEmail = _staffProfile.email.trim();

    final isAssigned = (staffName.isNotEmpty &&
            (match.assignedTo.trim().toLowerCase() == staffName.toLowerCase() ||
                (match.primaryAssignee?.name.trim().toLowerCase() ?? '') == staffName.toLowerCase())) ||
        (staffId.isNotEmpty &&
            ((match.assignedToId?.trim() ?? '') == staffId ||
                (match.primaryAssignee?.personId.trim() ?? '') == staffId)) ||
        match.assignees.any((asg) =>
            (staffId.isNotEmpty && asg.profileId == staffId) ||
            (staffName.isNotEmpty && asg.profileName.trim().toLowerCase() == staffName.toLowerCase())) ||
        match.additionalPeople.any((p) =>
            (staffId.isNotEmpty && p.personId.trim() == staffId) ||
            (staffEmail.isNotEmpty && p.email.trim().toLowerCase() == staffEmail.toLowerCase()) ||
            (staffName.isNotEmpty && p.name.trim().toLowerCase() == staffName.toLowerCase())) ||
        match.contributors.any((c) =>
            (staffId.isNotEmpty && (c.profileId.trim() == staffId || c.id.trim() == staffId)) ||
            (staffEmail.isNotEmpty && c.profileEmail.trim().toLowerCase() == staffEmail.toLowerCase()) ||
            (staffName.isNotEmpty && c.profileName.trim().toLowerCase() == staffName.toLowerCase())) ||
        (staffId.isNotEmpty && match.createdById.trim() == staffId) ||
        match.isForwardedTo(staffId, staffName, staffEmail);

    if (!isAssigned) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You do not have permission to view action "$actionId".'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _openDetails(match);
  }

  void _logout() async {
    QuickAlertListener.resetSession(_staffProfile.id);
    await AuthService.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _handleNavSelection(int index) {
    setState(() {
      _selectedNavIndex = index;
      if (index != 4) {
        _calendarInitialTypeFilter = null;
      }
    });
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
    if (index == 0) {
      _loadPersonalTasks();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.scaffoldBg(context),
      drawer: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 950) return const SizedBox.shrink();
          return Drawer(
            child: _WorkerSidebar(
              selectedIndex: _selectedNavIndex,
              onNavSelected: _handleNavSelection,
              hasStaffApprovalAuthority: _hasStaffApprovalAuthority,
            ),
          );
        },
      ),
      body: QuickAlertListener(
        userId: _staffProfile.id,
        onActionTap: _handleNotificationActionTap,
        onNotificationTap: _handleNotificationTap,
        onViewNotifications: () => setState(() => _selectedNavIndex = 5),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showSidebar = constraints.maxWidth >= 950;

            return Row(
              children: [
                // Persistent Left Sidebar
                if (showSidebar)
                  _WorkerSidebar(
                    selectedIndex: _selectedNavIndex,
                    onNavSelected: _handleNavSelection,
                    hasStaffApprovalAuthority: _hasStaffApprovalAuthority,
                  ),

                // Persistent Right Area (Header + Animated Content)
                Expanded(
                  child: Column(
                    children: [
                      // Persistent Top Header
                      _WorkerTopHeader(
                        workerName: _staffProfile.name,
                        profile: _staffProfile,
                        isMobile: !showSidebar,
                        searchController: _searchController,
                        unreadCount: _unreadNotificationCount,
                        onSearchChanged: (val) {
                          setState(() {
                            _searchQuery = val;
                          });
                        },
                        onMenuTap: () {
                          _scaffoldKey.currentState?.openDrawer();
                        },
                        onNotificationTap: () {
                          setState(() => _selectedNavIndex = 5);
                        },
                        onViewAllNotifications: () {
                          setState(() => _selectedNavIndex = 5);
                        },
                        onActionTap: _handleNotificationActionTap,
                        onNotificationItemTap: _handleNotificationTap,
                        onUnreadCountChanged: _updateNotificationCount,
                        onProfileTap: () {
                          setState(() => _selectedNavIndex = 7);
                        },
                        onLogout: _logout,
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
                            child: SlideTransition(
                              position:
                                  Tween<Offset>(
                                    begin: const Offset(0.015, 0),
                                    end: Offset.zero,
                                  ).animate(
                                    CurvedAnimation(
                                      parent: animation,
                                      curve: Curves.easeOutCubic,
                                    ),
                                  ),
                              child: child,
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey('worker_tab_$_selectedNavIndex'),
                          child: _buildActiveContent(constraints),
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

  Widget _buildActiveContent(BoxConstraints constraints) {
    final horizontalPadding = constraints.maxWidth < 600 ? 12.0 : 20.0;
    final padding = EdgeInsets.fromLTRB(
      horizontalPadding,
      16.0,
      horizontalPadding,
      24.0,
    );

    switch (_selectedNavIndex) {
      case 0:
        if (constraints.maxWidth < 440) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12.0, 16.0, 12.0, 24.0),
                child: _buildDashboardView(
                  const BoxConstraints(maxWidth: 440, minWidth: 440),
                ),
              ),
            ),
          );
        }
        return SingleChildScrollView(
          padding: padding,
          child: _buildDashboardView(constraints),
        );
      case 1:
        return SingleChildScrollView(
          padding: padding,
          child: _buildMyActionsView(constraints),
        );
      case 2:
        return SingleChildScrollView(
          padding: padding,
          child: _buildReportsView(constraints),
        );
      case 3:
        return SingleChildScrollView(
          padding: padding,
          child: _buildPendingUpdatesView(constraints),
        );
      case 4:
        return SingleChildScrollView(
          padding: padding,
          child: _buildCalendarView(constraints),
        );
      case 5:
        return SingleChildScrollView(
          padding: padding,
          child: _buildNotificationsView(constraints),
        );
      case 6:
        return SingleChildScrollView(
          padding: padding,
          child: _buildDocumentsView(constraints),
        );
      case 7:
        return SingleChildScrollView(
          padding: padding,
          child: _buildProfileView(constraints),
        );
      case 8:
        return SingleChildScrollView(
          padding: padding,
          child: _buildSettingsView(constraints),
        );
      case 9:
        return SingleChildScrollView(
          padding: padding,
          child: NewRequestScreen(
            currentUserId: _staffProfile.id,
            currentUserName: _staffProfile.name,
            currentUserRole: _staffProfile.role,
            currentUserEmail: _staffProfile.email,
            organizationId: _staffProfile.organizationId ?? '',
            onRequestSubmitted: (req) {
              setState(() => _selectedNavIndex = 10);
            },
            onCancel: () => setState(() => _selectedNavIndex = 0),
          ),
        );
      case 10:
        return SingleChildScrollView(
          padding: padding,
          child: MyRequestsScreen(
            key: ValueKey('staff_my_requests_$_myRequestsInitialStatus'),
            initialStatus: _myRequestsInitialStatus,
            currentUserId: _staffProfile.id,
            currentUserName: _staffProfile.name,
            currentUserRole: _staffProfile.role,
            currentUserEmail: _staffProfile.email,
            organizationId: _staffProfile.organizationId ?? '',
            isManager: false,
            onNewRequest: () => setState(() => _selectedNavIndex = 9),
          ),
        );
      case 11:
        return SingleChildScrollView(
          padding: padding,
          child: RequestApprovalScreen(
            key: ValueKey('staff_req_approval_$_requestApprovalInitialTab'),
            initialTabIndex: _requestApprovalInitialTab,
            currentUserId: _staffProfile.id,
            currentUserName: _staffProfile.name,
            currentUserRole: _staffProfile.role,
            currentUserEmail: _staffProfile.email,
            organizationId: _staffProfile.organizationId ?? '',
            isManager: false,
            onNewRequest: () => setState(() => _selectedNavIndex = 9),
          ),
        );
      case 12:
        return SingleChildScrollView(
          padding: padding,
          child: _buildActionRegisterView(constraints),
        );
      case 13:
        return AddActionScreen(
          actionId: 'ACT-${DateTime.now().millisecondsSinceEpoch}',
          isEmbedded: true,
          isManager: false,
          isStaff: true,
          organizationId: _effectiveOrgId,
          onClose: () => setState(() => _selectedNavIndex = 0),
          onSaved: (act) {
            if (mounted) {
              unawaited(_loadStaffActions());
              setState(() => _selectedNavIndex = 12);
            }
          },
        );
      default:
        return SingleChildScrollView(
          padding: padding,
          child: _buildDashboardView(constraints),
        );
    }
  }

  // ===========================================================================
  // ACTION REGISTER VIEW
  // ===========================================================================

  Widget _buildActionRegisterView(BoxConstraints constraints) {
    return ActionRegisterSection(
      currentUserId: _staffProfile.id,
      isDrillDown: false,
      drillDownTitle: 'Action Register',
      actions: _getRegisterFilteredActions(),
      searchQuery: _regSearchQuery,
      selectedStatus: _regStatus,
      selectedForwarded: _regForwarded,
      selectedDivision: _regDivision,
      selectedDepartment: _regDepartment,
      selectedSite: _regSite,
      selectedPriority: _regPriority,
      selectedPerson: _regPerson,
      selectedDate: _regDate,
      selectedDateField: _regDateField,
      customDateStart: _regCustomDateStart,
      customDateEnd: _regCustomDateEnd,
      selectedSort: _regSort,
      departmentOptions: [
        'All Departments',
        ..._getRegisterDepartments(),
      ],
      siteOptions: [
        'All Sites',
        ..._getRegisterSites(),
      ],
      personOptions: ['All People', ..._getRegisterAssignees()],
      onSearchChanged: (val) => setState(() => _regSearchQuery = val),
      onStatusChanged: (val) => setState(() => _regStatus = val),
      onForwardedChanged: (val) => setState(() => _regForwarded = val),
      onDivisionChanged: (val) => setState(() => _regDivision = val),
      onDepartmentChanged: (val) => setState(() => _regDepartment = val),
      onSiteChanged: (val) => setState(() => _regSite = val),
      onPriorityChanged: (val) => setState(() => _regPriority = val),
      onPersonChanged: (val) => setState(() => _regPerson = val),
      onDateChanged: (val) => setState(() => _regDate = val),
      onDateFieldChanged: (val) => setState(() => _regDateField = val),
      onCustomDateRangeChanged: (range) => setState(() {
        _regCustomDateStart = range?.start;
        _regCustomDateEnd = range?.end;
      }),
      onSortChanged: (val) => setState(() => _regSort = val),
      onActionTap: _openDetails,
      onUpdateActionTap: _openUpdate,
      onEditActionTap: _handleEditAction,
      onDeleteActionTap: (action) =>
          _handleDeleteAction(action, fromActionRegister: true),
      onAddAction: () => setState(() => _selectedNavIndex = 13),
      onExportExcel: _handleExportExcel,
      onResetFilters: _resetRegisterFilters,
      selectedActionIds: _selectedActionIds,
      onToggleSelect: _toggleActionSelection,
      onSelectAll: (val) =>
          _selectAllVisibleActions(_getRegisterFilteredActions(), val),
      onDeleteSelected: () =>
          _handleDeleteSelectedActions(_getRegisterFilteredActions(), true),
      onClearSelection: _clearSelection,
    );
  }

  void _handleExportExcel(List<ActionRecord> actionsToExport) {
    if (actionsToExport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No actions available to export with current filters.'),
          backgroundColor: Color(0xFFD97706),
        ),
      );
      return;
    }
    final activeFilters = <String, String>{};
    if (_regSearchQuery.isNotEmpty) activeFilters['Search'] = _regSearchQuery;
    if (_regStatus != 'All Status') activeFilters['Status'] = _regStatus;
    if (_regPriority != 'All Priority') activeFilters['Priority'] = _regPriority;
    if (_regDepartment != 'All Departments') activeFilters['Department'] = _regDepartment;
    if (_regSite != 'All Sites') activeFilters['Site'] = _regSite;
    if (_regDateField != 'All Dates' ||
        (_regDate != 'Date' && _regDate != 'All Time')) {
      activeFilters['Date'] = '$_regDateField: $_regDate';
    }

    unawaited(
      ExcelExportService.instance.exportReportExcel(
        context: context,
        filteredActions: actionsToExport,
        userName: _staffProfile.name,
        userRole: _staffProfile.role,
        organizationName: _staffProfile.organizationName.isNotEmpty
            ? _staffProfile.organizationName
            : Organization.sobhaName,
        activeFilters: activeFilters,
      ),
    );
  }

  List<String> _getRegisterDepartments() {
    final depts = <String>{};
    for (final a in _staffCreatedActions) {
      if (a.department.isNotEmpty) depts.add(a.department);
    }
    final sorted = depts.toList()..sort();
    return sorted;
  }

  List<String> _getRegisterSites() {
    final sites = <String>{};
    for (final a in _staffCreatedActions) {
      if (a.site.isNotEmpty) sites.add(a.site);
    }
    final sorted = sites.toList()..sort();
    return sorted;
  }

  List<String> _getRegisterAssignees() {
    final people = <String>{};
    for (final a in _staffCreatedActions) {
      if (a.assignedTo.isNotEmpty) people.add(a.assignedTo);
      for (final asg in a.assignees) {
        if (asg.profileName.isNotEmpty) people.add(asg.profileName);
      }
    }
    final sorted = people.toList()..sort();
    return sorted;
  }

  List<ActionRecord> _getRegisterFilteredActions() {
    final filtered = _staffCreatedActions.where((action) {
      if (action.isDeleted) return false;

      // Search query filter
      if (_regSearchQuery.isNotEmpty) {
        final query = _regSearchQuery.trim().toLowerCase();
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
      if (_regStatus != 'All Status') {
        if (_regStatus == 'Closed') {
          if (!action.isClosed && action.status.toLowerCase() != 'closed') {
            return false;
          }
        } else if (_regStatus == 'Pending Review' ||
            _regStatus == 'Ready for Review') {
          if (action.status.toLowerCase() != 'pending review' &&
              !action.isReadyForReview) {
            return false;
          }
        } else if (_regStatus == 'Overdue') {
          if (!action.isOverdue && action.status.toLowerCase() != 'overdue') {
            return false;
          }
        } else if (_regStatus == 'Open') {
          if (action.status.toLowerCase() != 'open') {
            return false;
          }
        } else if (_regStatus == 'In Progress') {
          if (action.status.toLowerCase() != 'in progress') {
            return false;
          }
        } else if (action.status.toLowerCase() != _regStatus.toLowerCase()) {
          return false;
        }
      }

      // Forwarded filter
      if (_regForwarded != 'All Actions') {
        final staffId = _staffProfile.id;
        final staffName = _staffProfile.name;
        final staffEmail = _staffProfile.email;
        if (_regForwarded == 'Forwarded by Me') {
          if (!action.isForwardedBy(staffId, staffName, staffEmail)) {
            return false;
          }
        } else if (_regForwarded == 'Forwarded to Me') {
          if (!action.isForwardedTo(staffId, staffName, staffEmail)) {
            return false;
          }
        } else if (_regForwarded == 'Forwarded Only') {
          if (!action.isForwarded) return false;
        } else if (_regForwarded == 'Direct Only') {
          if (action.isForwarded) return false;
        }
      }

      // Priority filter
      if (_regPriority != 'All Priority') {
        if (action.priority.toLowerCase() != _regPriority.toLowerCase()) {
          return false;
        }
      }

      // Department filter
      if (_regDepartment != 'All Departments') {
        if (action.department.toLowerCase() != _regDepartment.toLowerCase()) {
          return false;
        }
      }

      // Site filter
      if (_regSite != 'All Sites') {
        if (action.site.toLowerCase() != _regSite.toLowerCase()) {
          return false;
        }
      }

      // Division filter
      if (_regDivision != 'All Divisions') {
        if (action.division.toLowerCase() != _regDivision.toLowerCase()) {
          return false;
        }
      }

      // Person filter
      if (_regPerson != 'All People') {
        final p = _regPerson.toLowerCase();
        final isPrimary = action.assignedTo.toLowerCase() == p ||
            (action.primaryAssignee?.name.toLowerCase() == p);
        final isAssignee = action.assignees.any(
          (a) => a.profileName.toLowerCase() == p,
        );
        if (!isPrimary && !isAssignee) {
          return false;
        }
      }

      // Date filter
      if (_regDateField != 'All Dates' ||
          (_regDate != 'Date' && _regDate != 'All Time')) {
        if (!_matchesDateFilter(
          action,
          _regDate,
          dateField: _regDateField,
          customStart: _regCustomDateStart,
          customEnd: _regCustomDateEnd,
        )) {
          return false;
        }
      }

      return true;
    }).toList();

    // Sorting
    if (_regSort == 'Target Date (Earliest First)') {
      filtered.sort((a, b) {
        final aTarget = a.targetDateTime;
        final bTarget = b.targetDateTime;
        if (aTarget != null && bTarget != null) {
          final cmp = aTarget.compareTo(bTarget);
          if (cmp != 0) return cmp;
        } else if (aTarget != null) {
          return -1;
        } else if (bTarget != null) {
          return 1;
        }
        return a.targetDate.compareTo(b.targetDate);
      });
    } else if (_regSort == 'Target Date (Latest First)') {
      filtered.sort((a, b) {
        final aTarget = a.targetDateTime;
        final bTarget = b.targetDateTime;
        if (aTarget != null && bTarget != null) {
          final cmp = bTarget.compareTo(aTarget);
          if (cmp != 0) return cmp;
        } else if (aTarget != null) {
          return 1;
        } else if (bTarget != null) {
          return -1;
        }
        return b.targetDate.compareTo(a.targetDate);
      });
    } else if (_regSort == 'Priority (Highest First)') {
      const rank = {'Critical': 0, 'High': 1, 'Medium': 2, 'Low': 3};
      filtered.sort(
        (a, b) => (rank[a.priority] ?? 4).compareTo(rank[b.priority] ?? 4),
      );
    } else if (_regSort == 'Status') {
      filtered.sort((a, b) => a.status.compareTo(b.status));
    } else if (_regSort == 'Date Raised (Newest First)') {
      filtered.sort((a, b) {
        final aTime = a.createdAt ?? a.createdDateTime;
        final bTime = b.createdAt ?? b.createdDateTime;
        if (aTime != null && bTime != null) {
          final cmp = bTime.compareTo(aTime);
          if (cmp != 0) return cmp;
        }
        return b.displayId.compareTo(a.displayId);
      });
    }

    return filtered;
  }

  void _resetRegisterFilters() {
    setState(() {
      _regSearchQuery = '';
      _regStatus = 'All Status';
      _regPriority = 'All Priority';
      _regDepartment = 'All Departments';
      _regSite = 'All Sites';
      _regDivision = 'All Divisions';
      _regPerson = 'All People';
      _regDate = 'Date';
      _regDateField = 'All Dates';
      _regCustomDateStart = null;
      _regCustomDateEnd = null;
      _regSort = 'Target Date (Earliest First)';
      _regForwarded = 'All Actions';
    });
  }

  // ===========================================================================
  // 0. MY DASHBOARD VIEW
  // ===========================================================================

  Widget _buildDashboardView(BoxConstraints constraints) {
    final actions = _myActions;
    final orgName = _staffProfile.organizationName.isNotEmpty
        ? _staffProfile.organizationName
        : Organization.sobhaName;
    final staffName = _staffProfile.name.isNotEmpty
        ? _staffProfile.name
        : 'Field Staff';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Top Header Banner
        DashboardHeaderBanner(
          title: 'Staff Dashboard',
          subtitle: 'My Action Management Overview',
          organizationName: orgName,
          managerName: staffName,
          onViewFullReports: () => _handleNavSelection(2),
        ),
        const SizedBox(height: 20),

        if (_isLoadingActions) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: LinearProgressIndicator(),
          ),
        ],
        if (_actionLoadError != null) ...[
          _workerCard(
            title: 'Actions unavailable',
            icon: Icons.sync_problem_rounded,
            child: Row(
              children: [
                Expanded(child: Text(_actionLoadError!)),
                TextButton.icon(
                  onPressed: _loadStaffActions,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 2. "Needs Your Attention" Section (staff-scoped)
        DashboardAttentionSection(
          actions: actions,
          onActionTap: _openDetails,
          onViewAll: () => _handleNavSelection(1),
        ),
        const SizedBox(height: 20),

        // 3. 9 KPI Summary Cards (staff-scoped, including Follow-ups & Personal Tasks)
        DashboardKpiCards(
          actions: actions,
          followUpCount: _followUpCount,
          followUpSubtext: _followUpSubtext,
          personalTaskCount: _personalTaskCount,
          personalTaskSubtext: _personalTaskSubtext,
          onKpiTap: (label) {
            if (label == 'Total Actions') {
              _statusFilter = 'All Statuses';
              _priorityFilter = 'All Priorities';
              _handleNavSelection(1);
            } else if (label == 'Open') {
              _statusFilter = 'Open';
              _priorityFilter = 'All Priorities';
              _handleNavSelection(1);
            } else if (label == 'In Progress') {
              _statusFilter = 'In Progress';
              _priorityFilter = 'All Priorities';
              _handleNavSelection(1);
            } else if (label == 'Overdue') {
              _statusFilter = 'Overdue';
              _priorityFilter = 'All Priorities';
              _handleNavSelection(1);
            } else if (label == 'Ready for Review') {
              _statusFilter = 'Pending Review';
              _priorityFilter = 'All Priorities';
              _handleNavSelection(1);
            } else if (label == 'Closed') {
              _statusFilter = 'Closed';
              _priorityFilter = 'All Priorities';
              _handleNavSelection(1);
            } else if (label == 'Average Completion %') {
              _handleNavSelection(2);
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

        _buildRequestOverviewSection(constraints),
        const SizedBox(height: 20),

        // 4. Staff Quick Actions Toolbar
        _buildStaffQuickActionsCard(),
        const SizedBox(height: 20),

        // Forwarded Actions Card
        DashboardForwardedActionsCard(
          actions: actions,
          currentUserId: _staffProfile.id,
          currentUserName: _staffProfile.name,
          currentUserEmail: _staffProfile.email,
          isManager: false,
          onTapCard: () {
            setState(() => _forwardedFilter = 'Forwarded Only');
            _handleNavSelection(1);
          },
          onTapForwardedToMe: () {
            setState(() => _forwardedFilter = 'Forwarded to Me');
            _handleNavSelection(1);
          },
          onTapForwardedByMe: () {
            setState(() => _forwardedFilter = 'Forwarded by Me');
            _handleNavSelection(1);
          },
        ),
        const SizedBox(height: 20),

        // 5. Action Status Overview & Completion Overview (donut chart + progress breakdown)
        DashboardStatusAndProgress(
          actions: actions,
          onStatusTap: (status) {
            _statusFilter =
                status == 'Ready for Review' ? 'Pending Review' : status;
            _handleNavSelection(1);
          },
        ),
        const SizedBox(height: 20),

        // 6. Responsive Bottom Row: Timeline, Upcoming Follow-Ups, Recent Activity
        LayoutBuilder(
          builder: (context, boxConstraints) {
            final w = boxConstraints.maxWidth;
            final isDesktop = w >= 1100;
            final isTablet = w >= 700 && !isDesktop;

            if (isDesktop) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 38,
                    child: DashboardTimelinePanel(actions: actions),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 31,
                    child: DashboardUpcomingFollowups(
                      actions: actions,
                      onActionTap: _openDetails,
                      onOpenCalendar: () => _handleNavSelection(4),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 31,
                    child: DashboardRecentActivity(
                      actions: actions,
                      onActionTap: _openDetails,
                      onViewAll: () => _handleNavSelection(1),
                    ),
                  ),
                ],
              );
            } else if (isTablet) {
              return Column(
                children: [
                  DashboardTimelinePanel(actions: actions),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DashboardUpcomingFollowups(
                          actions: actions,
                          onActionTap: _openDetails,
                          onOpenCalendar: () => _handleNavSelection(4),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: DashboardRecentActivity(
                          actions: actions,
                          onActionTap: _openDetails,
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
                  DashboardTimelinePanel(actions: actions),
                  const SizedBox(height: 16),
                  DashboardUpcomingFollowups(
                    actions: actions,
                    onActionTap: _openDetails,
                    onOpenCalendar: () => _handleNavSelection(4),
                  ),
                  const SizedBox(height: 16),
                  DashboardRecentActivity(
                    actions: actions,
                    onActionTap: _openDetails,
                    onViewAll: () => _handleNavSelection(1),
                  ),
                ],
              );
            }
          },
        ),
      ],
    );
  }

  Widget _buildStaffQuickActionsCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder(context)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.isDark(context)
                ? Colors.black.withValues(alpha: 0.2)
                : const Color(0x060F172A),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 650;

          return Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.bolt_rounded,
                    color: Color(0xFFEAB308),
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                ],
              ),
              if (!isNarrow) const SizedBox(width: 6),
              ElevatedButton.icon(
                onPressed: () => _handleNavSelection(13),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 17),
                label: const Text(
                  'Add Action',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _handleNavSelection(12),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1565C0),
                  side: BorderSide(
                    color: const Color(0xFF1565C0).withValues(
                      alpha: AppTheme.isDark(context) ? 0.5 : 0.3,
                    ),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                ),
                icon: const Icon(Icons.table_chart_rounded, size: 17),
                label: const Text(
                  'Action Register',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _handleNavSelection(1),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                ),
                icon: const Icon(Icons.assignment_turned_in_rounded, size: 17),
                label: const Text(
                  'My Actions',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _handleNavSelection(3),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFD97706),
                  side: BorderSide(
                    color: const Color(0xFFD97706).withValues(
                      alpha: AppTheme.isDark(context) ? 0.5 : 0.3,
                    ),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                ),
                icon: const Icon(Icons.pending_actions_rounded, size: 17),
                label: const Text(
                  'Pending Updates',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _handleNavSelection(2),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0284C7),
                  side: BorderSide(
                    color: const Color(0xFF0284C7).withValues(
                      alpha: AppTheme.isDark(context) ? 0.5 : 0.3,
                    ),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                ),
                icon: const Icon(Icons.bar_chart_rounded, size: 17),
                label: const Text(
                  'Reports & Analytics',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _handleNavSelection(4),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF7C3AED),
                  side: BorderSide(
                    color: const Color(0xFF7C3AED).withValues(
                      alpha: AppTheme.isDark(context) ? 0.5 : 0.3,
                    ),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                ),
                icon: const Icon(Icons.calendar_month_rounded, size: 17),
                label: const Text(
                  'Calendar',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ===========================================================================
  // 2. REPORTS VIEW
  // ===========================================================================

  Widget _buildReportsView(BoxConstraints constraints) {
    return LayoutBuilder(
      builder: (context, reportConstraints) {
        final reports = ManagerReportsScreen(
          allActions: _myActions,
          userProfile: _staffProfile,
          onActionTap: _openDetails,
          onExportExcel: _exportStaffReport,
          onRefresh: _loadStaffActions,
        );
        if (reportConstraints.maxWidth >= 1200) return reports;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: 1200, child: reports),
        );
      },
    );
  }

  // ===========================================================================
  // 1. MY ACTIONS VIEW
  // ===========================================================================

  Widget _buildMyActionsView(BoxConstraints constraints) {
    final visible = _visibleActions;
    final isMobile = constraints.maxWidth < 768;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filter toolbar
        _buildFilterToolbar(constraints),
        const SizedBox(height: 16),

        // Selection banner
        if (_selectedActionIds.isNotEmpty) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                  '${_selectedActionIds.length} action${_selectedActionIds.length == 1 ? '' : 's'} selected',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _handleDeleteSelectedActions,
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
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _clearSelection,
                  icon: const Icon(Icons.close_rounded, size: 14),
                  label: const Text(
                    'Deselect All',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
        ],

        // Actions Header with Count
        _workerCard(
          title: 'My Assigned Actions (${visible.length})',
          icon: Icons.assignment_rounded,
          child: visible.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      'No matching actions found with current filters.',
                      style: TextStyle(color: AppTheme.textSecondary(context)),
                    ),
                  ),
                )
              : isMobile
                  ? Column(
                      children: visible.map((act) {
                        return _buildWorkerActionCard(act);
                      }).toList(),
                    )
                  : _buildWorkerActionTable(visible, constraints),
        ),
      ],
    );
  }

  Widget _buildFilterToolbar(BoxConstraints constraints) {
    final dynamicSites = {
      ..._myActions.map((a) => a.site.trim()).where((s) => s.isNotEmpty),
    };
    final siteOptions = [
      'All Sites',
      if (dynamicSites.isNotEmpty) ...dynamicSites else ...const [
        'North Plant',
        'Warehouse B',
        'Central Yard',
        'Admin Block',
        'Storage Area',
      ],
    ];

    return _workerCard(
      title: 'Filter & Search Actions',
      icon: Icons.filter_list_rounded,
      child: LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth;
          final double fieldWidth;
          if (width >= 1100) {
            fieldWidth = (width - 48) / 4;
          } else if (width >= 800) {
            fieldWidth = (width - 36) / 3;
          } else if (width >= 520) {
            fieldWidth = (width - 12) / 2;
          } else {
            fieldWidth = width;
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  // 1. Search Box
                  SizedBox(
                    width: fieldWidth,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val),
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textPrimary(context),
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search by ID, title, site, person...',
                        hintStyle: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.textMuted(context),
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: AppTheme.textSecondary(context),
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 16),
                                onPressed: () {
                                  setState(() {
                                    _searchQuery = '';
                                    _searchController.clear();
                                  });
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: AppTheme.inputFill(context),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
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
                          borderSide: const BorderSide(color: Color(0xFF1565C0)),
                        ),
                      ),
                    ),
                  ),

                  // 2. Status Filter
                  SizedBox(
                    width: fieldWidth,
                    child: _dropdownFilter(
                      label: 'Status',
                      value: _statusFilter,
                      options: const [
                        'All Statuses',
                        'Open',
                        'In Progress',
                        'Pending Review',
                        'Overdue',
                        'Closed',
                      ],
                      onChanged: (val) => setState(() => _statusFilter = val!),
                    ),
                  ),

                  // 3. Priority Filter
                  SizedBox(
                    width: fieldWidth,
                    child: _dropdownFilter(
                      label: 'Priority',
                      value: _priorityFilter,
                      options: const [
                        'All Priorities',
                        'Critical',
                        'High',
                        'Critical / High',
                        'Medium',
                        'Low',
                      ],
                      onChanged: (val) =>
                          setState(() => _priorityFilter = val!),
                    ),
                  ),

                  // 4. Site Filter
                  SizedBox(
                    width: fieldWidth,
                    child: _dropdownFilter(
                      label: 'Site',
                      value: _siteFilter,
                      options: siteOptions,
                      onChanged: (val) => setState(() => _siteFilter = val!),
                    ),
                  ),

                  // 5. Forwarded Action Filter
                  SizedBox(
                    width: fieldWidth,
                    child: _dropdownFilter(
                      label: 'Forwarded Actions',
                      value: _forwardedFilter,
                      options: const [
                        'All Actions',
                        'Forwarded to Me',
                        'Forwarded by Me',
                        'Forwarded Only',
                        'Direct Only',
                      ],
                      onChanged: (val) =>
                          setState(() => _forwardedFilter = val!),
                    ),
                  ),

                  // 6. Date Field Filter
                  SizedBox(
                    width: fieldWidth,
                    child: _dropdownFilter(
                      label: 'Date Field',
                      value: _selectedDateField,
                      options: const [
                        'All Dates',
                        'Raised Date',
                        'Start Date',
                        'Follow-Up Date',
                        'Target/Due Date',
                        'Closed Date',
                      ],
                      onChanged: (val) =>
                          setState(() => _selectedDateField = val!),
                    ),
                  ),

                  // 7. Date Period Filter
                  SizedBox(
                    width: fieldWidth,
                    child: _dropdownFilter(
                      label: 'Date Period',
                      value: _selectedDate,
                      options: const [
                        'Date',
                        'Today',
                        'Yesterday',
                        'This Week',
                        'This Month',
                        'This Year',
                        'Custom Range',
                        'All Time',
                      ],
                      onChanged: (val) {
                        if (val == 'Custom Range') {
                          _selectCustomDateRange();
                        } else {
                          setState(() {
                            _selectedDate = val!;
                            _customDateStart = null;
                            _customDateEnd = null;
                          });
                        }
                      },
                    ),
                  ),

                  // 8. Sort Order
                  SizedBox(
                    width: fieldWidth,
                    child: _dropdownFilter(
                      label: 'Sort By',
                      value: _sortOrder,
                      options: const [
                        'Newest First',
                        'Target Date',
                        'Priority',
                        'Progress',
                      ],
                      onChanged: (val) => setState(() => _sortOrder = val!),
                    ),
                  ),
                ],
              ),

              // Active filter chips & reset button
              _buildActiveFilterChips(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActiveFilterChips() {
    final chips = <Widget>[];

    void addChip(String label, String value, VoidCallback onRemove) {
      chips.add(
        Chip(
          label: Text(
            '$label: $value',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.isDark(context)
                  ? const Color(0xFF93C5FD)
                  : const Color(0xFF1E40AF),
            ),
          ),
          deleteIcon: const Icon(Icons.close_rounded, size: 14),
          onDeleted: onRemove,
          backgroundColor: AppTheme.isDark(context)
              ? const Color(0xFF1E293B)
              : const Color(0xFFEFF6FF),
          side: BorderSide(
            color: AppTheme.isDark(context)
                ? const Color(0xFF3B82F6).withValues(alpha: 0.3)
                : const Color(0xFFBFDBFE),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    if (_searchQuery.isNotEmpty) {
      addChip('Search', _searchQuery, () {
        setState(() {
          _searchQuery = '';
          _searchController.clear();
        });
      });
    }
    if (_statusFilter != 'All Statuses') {
      addChip(
        'Status',
        _statusFilter,
        () => setState(() => _statusFilter = 'All Statuses'),
      );
    }
    if (_priorityFilter != 'All Priorities') {
      addChip(
        'Priority',
        _priorityFilter,
        () => setState(() => _priorityFilter = 'All Priorities'),
      );
    }
    if (_siteFilter != 'All Sites') {
      addChip(
        'Site',
        _siteFilter,
        () => setState(() => _siteFilter = 'All Sites'),
      );
    }
    if (_forwardedFilter != 'All Actions') {
      addChip(
        'Forwarded',
        _forwardedFilter,
        () => setState(() => _forwardedFilter = 'All Actions'),
      );
    }
    if (_selectedDateField != 'All Dates') {
      addChip(
        'Date Field',
        _selectedDateField,
        () => setState(() => _selectedDateField = 'All Dates'),
      );
    }
    if (_selectedDate != 'Date' && _selectedDate != 'All Time') {
      if (_selectedDate == 'Custom Range' &&
          _customDateStart != null &&
          _customDateEnd != null) {
        final s = _customDateStart!;
        final e = _customDateEnd!;
        addChip(
          'Date Range',
          '${s.day}/${s.month} - ${e.day}/${e.month}',
          () => setState(() {
            _selectedDate = 'Date';
            _customDateStart = null;
            _customDateEnd = null;
          }),
        );
      } else {
        addChip(
          'Date',
          _selectedDate,
          () => setState(() => _selectedDate = 'Date'),
        );
      }
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ...chips,
          TextButton.icon(
            onPressed: _resetStaffFilters,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: const Color(0xFFEF4444),
            ),
            icon: const Icon(Icons.clear_all_rounded, size: 14),
            label: const Text(
              'Clear All',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdownFilter({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    final effectiveValue = options.contains(value) ? value : options.first;
    return DropdownButtonFormField<String>(
      key: ValueKey('$label-$value'),
      isExpanded: true,
      initialValue: effectiveValue,
      dropdownColor: AppTheme.cardBg(context),
      style: TextStyle(fontSize: 12.5, color: AppTheme.textPrimary(context)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          fontSize: 12,
          color: AppTheme.textSecondary(context),
        ),
        filled: true,
        fillColor: AppTheme.inputFill(context),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          borderSide: const BorderSide(color: Color(0xFF1565C0)),
        ),
      ),
      items: options
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(
                item,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textPrimary(context),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildWorkerActionCard(ActionRecord action) {
    final isSelected = _selectedActionIds.contains(action.id);
    final canEdit = _canEditAction(action);
    final canDelete = _canDeleteFromMyActions(action);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
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
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (_) => _toggleActionSelection(action.id),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
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
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.actionIdText(context),
                      ),
                    ),
                  ),
                  _priorityBadge(action.priority),
                  _statusBadge(action.status),
                  if (action.isForwarded)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.forward_rounded,
                            size: 12,
                            color: Color(0xFF8B5CF6),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Forwarded',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF8B5CF6),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              Text(
                action.subTasks.isNotEmpty
                    ? '${action.percentComplete}% (${action.subTasks.where((s) => s.isCompleted).length}/${action.subTasks.length} Tasks)'
                    : '${action.percentComplete}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _statusColor(action.status),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => _openDetails(action),
            child: Text(
              action.subject,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Site: ${action.site.isNotEmpty ? action.site : 'Main'}  Ã¢â‚¬Â¢  Target: ${action.targetDate}  Ã¢â‚¬Â¢  Follow-up: ${action.followUp}',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: action.percentComplete / 100.0,
              minHeight: 6,
              backgroundColor: AppTheme.progressTrackBg(context),
              valueColor: AlwaysStoppedAnimation<Color>(
                _statusColor(action.status),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openDetails(action),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textPrimary(context),
                  side: BorderSide(color: AppTheme.cardBorder(context)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                icon: const Icon(Icons.visibility_outlined, size: 15),
                label: const Text(
                  'Details',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              if (!action.isClosed && action.status.toLowerCase() != 'completed')
                ElevatedButton.icon(
                  onPressed: () => _openUpdate(action),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                  icon: const Icon(Icons.edit_note_rounded, size: 16),
                  label: const Text(
                    'Update Action',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              if (canEdit) ...[
                OutlinedButton.icon(
                  onPressed: () => _openUpdate(action),
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text(
                    'Edit',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2563EB),
                    side: BorderSide(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.3),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
              if (canDelete) ...[
                OutlinedButton.icon(
                  onPressed: () => _handleDeleteAction(action),
                  icon: const Icon(Icons.delete_outline_rounded, size: 14),
                  label: const Text(
                    'Delete',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: BorderSide(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.3),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
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

  Widget _buildWorkerActionTable(
    List<ActionRecord> actions,
    BoxConstraints constraints,
  ) {
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
            onSelectAll: (val) =>
                _selectAllVisibleActions(actions, val ?? false),
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
              final isSelected = _selectedActionIds.contains(action.id);
              final canEdit = _canEditAction(action);
              final canDelete = _canDeleteFromMyActions(action);

              return DataRow(
                key: ValueKey('worker_action_row_${action.id}'),
                selected: isSelected,
                color: WidgetStateProperty.resolveWith<Color?>((states) {
                  if (states.contains(WidgetState.selected)) {
                    return AppTheme.isDark(context)
                        ? const Color(0xFF1E3A5F).withValues(alpha: 0.5)
                        : const Color(0xFFE0F2FE);
                  }
                  return null;
                }),
                onSelectChanged: (val) => _toggleActionSelection(action.id),
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
                    onTap: () => _openDetails(action),
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
                    onTap: () => _openDetails(action),
                  ),
                  DataCell(
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          action.site.isNotEmpty ? action.site : 'Main Plant',
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
                              color: AppTheme.primaryAccent(context),
                            ),
                          ),
                      ],
                    ),
                    onTap: () => _openDetails(action),
                  ),
                  DataCell(_priorityBadge(action.priority)),
                  DataCell(_statusBadge(action.status)),
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
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  minHeight: 6,
                                  value: action.percentComplete / 100.0,
                                  backgroundColor: AppTheme.progressTrackBg(
                                    context,
                                  ),
                                  valueColor: AlwaysStoppedAnimation(
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
                                color: AppTheme.textSecondary(context),
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton(
                          onPressed: () => _openDetails(action),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryAccent(context),
                            side: BorderSide(
                              color: AppTheme.isDark(context)
                                  ? const Color(0xFF1E40AF)
                                  : const Color(0xFFBFDBFE),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            padding: const EdgeInsets.symmetric(
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
                        ElevatedButton.icon(
                          onPressed: () => _openUpdate(action),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                          ),
                          icon: const Icon(
                            Icons.edit_note_rounded,
                            size: 15,
                          ),
                          label: const Text(
                            'Update',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (canEdit) ...[
                          const SizedBox(width: 6),
                          OutlinedButton.icon(
                            onPressed: () => _openUpdate(action),
                            icon: const Icon(Icons.edit_outlined, size: 14),
                            label: const Text(
                              'Edit',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF2563EB),
                              side: BorderSide(
                                color: const Color(0xFF2563EB).withValues(
                                  alpha: 0.3,
                                ),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                            ),
                          ),
                        ],
                        if (canDelete) ...[
                          const SizedBox(width: 6),
                          OutlinedButton.icon(
                            onPressed: () => _handleDeleteAction(action),
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
                              foregroundColor: const Color(0xFFDC2626),
                              side: BorderSide(
                                color: const Color(0xFFDC2626).withValues(
                                  alpha: 0.3,
                                ),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                            ),
                          ),
                        ],
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
  }

  // ===========================================================================
  // 2. PENDING UPDATES VIEW
  // ===========================================================================

  Widget _buildPendingUpdatesView(BoxConstraints constraints) {
    final pendingActions = _myActions.where((a) {
      if (a.isDeleted) return false;
      final s = a.status.toLowerCase();
      if (a.isClosed || s == 'completed' || s == 'cancelled') {
        return false;
      }
      return a.percentComplete < 100 ||
          s == 'pending review' ||
          s == 'ready for review';
    }).toList();

    final isMobile = constraints.maxWidth < 768;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _workerCard(
          title: 'Pending Action Updates (${pendingActions.length})',
          icon: Icons.pending_actions_rounded,
          child: pendingActions.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.task_alt_rounded,
                          size: 40,
                          color: const Color(0xFF10B981).withValues(alpha: 0.7),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'All assigned actions are updated! No pending updates required.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : isMobile
                  ? Column(
                      children:
                          pendingActions.map(_buildPendingUpdateCard).toList(),
                    )
                  : _buildPendingUpdateTable(pendingActions),
        ),
      ],
    );
  }

  Widget _buildPendingUpdateCard(ActionRecord act) {
    final isAwaitingReview =
        act.status.toLowerCase() == 'pending review' ||
        act.status.toLowerCase() == 'ready for review' ||
        act.percentComplete >= 100;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.containerBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.actionIdBg(context),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppTheme.actionIdBorder(context),
                      ),
                    ),
                    child: Text(
                      act.displayId,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.actionIdText(context),
                      ),
                    ),
                  ),
                  _statusBadge(act.status),
                  _priorityBadge(act.priority),
                  if (act.isForwarded)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color:
                              const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.forward_rounded,
                            size: 12,
                            color: Color(0xFF8B5CF6),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Forwarded',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF8B5CF6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (isAwaitingReview)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.hourglass_top_rounded,
                            size: 12,
                            color: Color(0xFFD97706),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Awaiting Manager Review',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD97706),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              Text(
                'Due: ${act.targetDate}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFEA580C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _openDetails(act),
            child: Text(
              act.subject,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            act.actionRequired.isNotEmpty
                ? 'Required: ${act.actionRequired}'
                : 'Update progress and provide completion evidence for HSSE verification.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: act.percentComplete / 100.0,
              minHeight: 6,
              backgroundColor: AppTheme.progressTrackBg(context),
              valueColor: AlwaysStoppedAnimation<Color>(
                _statusColor(act.status),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openDetails(act),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textPrimary(context),
                  side: BorderSide(color: AppTheme.cardBorder(context)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                icon: const Icon(Icons.visibility_outlined, size: 15),
                label: const Text(
                  'Details',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              if (isAwaitingReview)
                OutlinedButton.icon(
                  onPressed: () => _openDetails(act),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFD97706),
                    side: BorderSide(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                  icon: const Icon(
                    Icons.rate_review_outlined,
                    size: 15,
                  ),
                  label: const Text(
                    'View Status',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: () => _openUpdate(act),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                  icon: const Icon(
                    Icons.send_rounded,
                    size: 15,
                  ),
                  label: const Text(
                    'Submit Update',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPendingUpdateTable(List<ActionRecord> actions) {
    final staffId = _staffProfile.id.trim();
    final staffName = _staffProfile.name.trim();
    final staffEmail = _staffProfile.email.trim();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Theme(
            data: Theme.of(
              context,
            ).copyWith(dividerColor: AppTheme.dividerColor(context)),
            child: DataTable(
              showCheckboxColumn: false,
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
                final isForwarded =
                    action.isForwardedTo(staffId, staffName, staffEmail);
                final isAwaitingReview =
                    action.status.toLowerCase() == 'pending review' ||
                    action.status.toLowerCase() == 'ready for review' ||
                    action.percentComplete >= 100;

                return DataRow(
                  key: ValueKey('worker_pending_action_row_${action.id}'),
                  cells: [
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3.5,
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
                    ),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: InkWell(
                          onTap: () => _openDetails(action),
                          child: Text(
                            action.subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryAccent(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        action.site.isNotEmpty ? action.site : 'Main',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                    ),
                    DataCell(_priorityBadge(action.priority)),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _statusBadge(action.status),
                          if (isForwarded) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8B5CF6)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Icon(
                                Icons.forward_rounded,
                                size: 12,
                                color: Color(0xFF8B5CF6),
                              ),
                            ),
                          ],
                          if (isAwaitingReview) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: const Color(0xFFF59E0B)
                                      .withValues(alpha: 0.35),
                                ),
                              ),
                              child: const Text(
                                'Review',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFD97706),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    DataCell(
                      Text(
                        action.targetDate,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 50,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: action.percentComplete / 100.0,
                                minHeight: 6,
                                backgroundColor:
                                    AppTheme.progressTrackBg(context),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  _statusColor(action.status),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${action.percentComplete}%',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: _statusColor(action.status),
                            ),
                          ),
                        ],
                      ),
                    ),
                    DataCell(
                      Text(
                        action.followUp.isNotEmpty ? action.followUp : '-',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _openDetails(action),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.textPrimary(context),
                              side: BorderSide(
                                color: AppTheme.cardBorder(context),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                            ),
                            icon: const Icon(
                              Icons.visibility_outlined,
                              size: 14,
                            ),
                            label: const Text(
                              'Details',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (isAwaitingReview)
                            OutlinedButton.icon(
                              onPressed: () => _openDetails(action),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFD97706),
                                side: BorderSide(
                                  color: const Color(0xFFF59E0B)
                                      .withValues(alpha: 0.5),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                              ),
                              icon: const Icon(
                                Icons.rate_review_outlined,
                                size: 14,
                              ),
                              label: const Text(
                                'View Status',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          else
                            ElevatedButton.icon(
                              onPressed: () => _openUpdate(action),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1565C0),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                              ),
                              icon: const Icon(Icons.send_rounded, size: 13),
                              label: const Text(
                                'Submit Update',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
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
      ),
    );
  }

  // ===========================================================================
  // 3. CALENDAR VIEW
  // ===========================================================================

  Widget _buildCalendarView(BoxConstraints constraints) {
    return ActionFlowCalendarView(
      actions: _myActions,
      currentUserId: _staffProfile.id,
      organizationId: _effectiveOrgId,
      isManager: false,
      initialDate: _calendarInitialDate,
      initialTypeFilter: _calendarInitialTypeFilter,
      onActionTap: _openDetails,
      onRefresh: () {
        _loadStaffActions();
        _loadPersonalTasks();
      },
    );
  }

  // ===========================================================================
  // 4. NOTIFICATIONS VIEW
  // ===========================================================================

  Widget _buildNotificationsView(BoxConstraints constraints) {
    return NotificationCentreView(
      userId: _staffProfile.id,
      organizationId: _staffProfile.organizationId,
      isManager: false,
      title: 'Notifications & Alerts',
      onUnreadCountChanged: _updateNotificationCount,
      onActionTap: _handleNotificationActionTap,
      onNotificationTap: _handleNotificationTap,
    );
  }

  // ===========================================================================
  // 5. DOCUMENTS VIEW
  // ===========================================================================

  Widget _buildDocumentsView(BoxConstraints constraints) {
    if (_workerDocuments == null && !_isLoadingWorkerDocuments) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadWorkerDocuments());
    }

    final uploadButton = FilledButton.icon(
      key: const Key('staff_documents_upload_button'),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: const Icon(Icons.cloud_upload_outlined, size: 16),
      label: const Text(
        'Upload Document',
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      onPressed: _openUploadDocumentDialog,
    );

    if (_isLoadingWorkerDocuments && _workerDocuments == null) {
      return _workerCard(
        title: 'Safety Documents & Guidelines',
        icon: Icons.folder_rounded,
        trailing: uploadButton,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(32.0),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final allDocs = _workerDocuments ?? MockDocumentStore.instance.documents;
    final myUploads = allDocs
        .where((d) =>
            d.isOwnedBy(_staffProfile.id) ||
            (d.createdByName.isNotEmpty &&
                d.createdByName.toLowerCase() == _staffProfile.name.toLowerCase()))
        .toList();
    final sharedWithMe = allDocs
        .where((d) =>
            d.isSharedWith(_staffProfile.id) ||
            (!d.isOwnedBy(_staffProfile.id) &&
                d.createdByName.toLowerCase() != _staffProfile.name.toLowerCase() &&
                d.totalSharedCount > 0))
        .toList();
    final guidelines = allDocs
        .where((d) =>
            d.category == 'Policies & Procedures' ||
            d.category == 'Manuals & Guides' ||
            d.category.toLowerCase().contains('polic') ||
            d.category.toLowerCase().contains('guide'))
        .toList();

    List<DocumentRecord> filteredDocs;
    switch (_documentFilter) {
      case 'My Uploads':
        filteredDocs = myUploads;
        break;
      case 'Shared with Me':
        filteredDocs = sharedWithMe;
        break;
      case 'Guidelines & Policies':
        filteredDocs = guidelines;
        break;
      case 'All':
      default:
        filteredDocs = allDocs;
        break;
    }

    return _workerCard(
      title: 'Safety Documents & Guidelines',
      icon: Icons.folder_rounded,
      trailing: uploadButton,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Access safety procedures, policies, manuals, and documents shared within your department.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildDocFilterChip('All', allDocs.length),
              _buildDocFilterChip('My Uploads', myUploads.length),
              _buildDocFilterChip('Shared with Me', sharedWithMe.length),
              _buildDocFilterChip('Guidelines & Policies', guidelines.length),
            ],
          ),
          const SizedBox(height: 16),
          if (filteredDocs.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32.0),
                child: Column(
                  children: [
                    Icon(
                      Icons.folder_open_rounded,
                      size: 40,
                      color: AppTheme.textMuted(context),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _documentFilter == 'All'
                          ? 'No documents available for your department.'
                          : 'No documents match the "$_documentFilter" filter.',
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
            Column(
              children: filteredDocs.map((doc) {
                final isOwner = doc.isOwnedBy(_staffProfile.id) ||
                    (doc.createdByName.isNotEmpty &&
                        doc.createdByName.toLowerCase() ==
                            _staffProfile.name.toLowerCase());
                final isShared = doc.isSharedWith(_staffProfile.id) ||
                    (!isOwner && doc.totalSharedCount > 0);

                final IconData iconData;
                if (doc.isPdf) {
                  iconData = Icons.picture_as_pdf_outlined;
                } else if (doc.isExcel) {
                  iconData = Icons.table_chart_outlined;
                } else if (doc.isWord) {
                  iconData = Icons.description_outlined;
                } else if (doc.isImage) {
                  iconData = Icons.image_outlined;
                } else {
                  iconData = Icons.insert_drive_file_outlined;
                }

                final Color iconColor;
                if (doc.isPdf) {
                  iconColor = const Color(0xFFDC2626);
                } else if (doc.isExcel) {
                  iconColor = const Color(0xFF1565C0);
                } else if (doc.isImage) {
                  iconColor = const Color(0xFF7C3AED);
                } else {
                  iconColor = const Color(0xFF16A34A);
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.containerBg(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.cardBorder(context)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(iconData, color: iconColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => _showDocumentPreview(doc),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      doc.title,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary(context),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isOwner) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0D9488)
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'My Upload',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0D9488),
                                        ),
                                      ),
                                    ),
                                  ] else if (isShared) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1565C0)
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'Shared with Me',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF1565C0),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${doc.category} Ã¢â‚¬Â¢ ${doc.formattedFileSize} Ã¢â‚¬Â¢ Uploaded by ${isOwner ? 'Me' : (doc.createdByName.isNotEmpty ? doc.createdByName : 'Department Manager')}${doc.isPersisted ? '' : ' Ã¢â‚¬Â¢ Preview Only'}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: doc.isPersisted
                                      ? AppTheme.textSecondary(context)
                                      : const Color(0xFFD97706),
                                  fontWeight: doc.isPersisted
                                      ? FontWeight.normal
                                      : FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.visibility_outlined,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF60A5FA)
                              : const Color(0xFF1565C0),
                          size: 20,
                        ),
                        tooltip: 'Preview Document',
                        onPressed: () => _showDocumentPreview(doc),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.download_rounded,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF60A5FA)
                              : const Color(0xFF1565C0),
                          size: 20,
                        ),
                        tooltip: 'Download Document',
                        onPressed: () => _downloadDocument(doc),
                      ),
                      if (isOwner) ...[
                        IconButton(
                          icon: Icon(
                            Icons.share_outlined,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF60A5FA)
                                : const Color(0xFF1565C0),
                            size: 20,
                          ),
                          tooltip: 'Share with Department',
                          onPressed: () => _openShareDocumentDialog(doc),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.red.shade400,
                            size: 20,
                          ),
                          tooltip: 'Delete Document',
                          onPressed: () => _confirmDeleteDocument(doc),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildDocFilterChip(String label, int count) {
    final isSelected = _documentFilter == label;
    final primaryColor = const Color(0xFF1565C0);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _documentFilter = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withValues(alpha: 0.12)
              : AppTheme.containerBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? primaryColor : AppTheme.cardBorder(context),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? primaryColor
                    : AppTheme.textSecondary(context),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? primaryColor
                    : AppTheme.cardBorder(context).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : AppTheme.textSecondary(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 6. PROFILE VIEW
  // ===========================================================================

  Widget _buildProfileView(BoxConstraints constraints) {
    final actions = _myActions;
    final total = actions.length;
    final completed = actions
        .where(
          (a) =>
              a.percentComplete == 100 ||
              a.status == 'Closed' ||
              a.status == 'Completed',
        )
        .length;
    final inProgress = actions.where((a) => a.status == 'In Progress').length;
    final overdue = actions.where((a) => a.status == 'Overdue').length;

    return ProfileViewCard(
      profile: _staffProfile,
      title: 'Staff Profile',
      allowDesignationEdit: false,
      showPerformanceStats: true,
      performanceStats: _workerCard(
        title: 'Action Performance Summary',
        icon: Icons.analytics_outlined,
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _profileStatChip(
              'Total Actions',
              '$total',
              const Color(0xFF1565C0),
            ),
            _profileStatChip(
              'In Progress',
              '$inProgress',
              const Color(0xFF2E7D32),
            ),
            _profileStatChip(
              'Completed',
              '$completed',
              const Color(0xFF16A34A),
            ),
            _profileStatChip('Overdue', '$overdue', const Color(0xFFEA580C)),
          ],
        ),
      ),
      onProfileUpdated: (updated) {
        setState(() {
          _staffProfile = updated;
        });
      },
    );
  }

  Widget _profileStatChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.08,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark ? 0.35 : 0.2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 7. SETTINGS VIEW
  // ===========================================================================

  Widget _buildSettingsView(BoxConstraints constraints) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final currentMode = ThemeController.instance.themeMode;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.settings_rounded,
                  color: AppTheme.primaryAccent(context),
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'Preferences & Settings',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Theme & Appearance Card
            _workerCard(
              title: 'Appearance & Theme Mode',
              icon: Icons.palette_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select interface theme. Settings persist across device sessions offline.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _buildWorkerThemeTile(
                        context,
                        title: 'Light Theme',
                        mode: ThemeMode.light,
                        currentMode: currentMode,
                        icon: Icons.light_mode_rounded,
                        color: const Color(0xFFEAB308),
                      ),
                      _buildWorkerThemeTile(
                        context,
                        title: 'Dark Theme',
                        mode: ThemeMode.dark,
                        currentMode: currentMode,
                        icon: Icons.dark_mode_outlined,
                        color: const Color(0xFF38BDF8),
                      ),
                      _buildWorkerThemeTile(
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
            const SizedBox(height: 16),

            // Notification & Task Reminders Card
            _workerCard(
              title: 'Notification & Task Alert Preferences',
              icon: Icons.notifications_active_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Notification Audio Chime',
                      style: TextStyle(
                        fontSize: 13.5,
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
                  Divider(color: AppTheme.dividerColor(context)),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Action Due Reminders',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    subtitle: Text(
                      'Receive notifications when assigned action target date approaches',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                    value: true,
                    onChanged: (val) {},
                  ),
                  Divider(color: AppTheme.dividerColor(context)),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Manager Feedback Alerts',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    subtitle: Text(
                      'Get notified when manager reviews your update submission',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                    value: true,
                    onChanged: (val) {},
                  ),
                  Divider(color: AppTheme.dividerColor(context)),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Daily Task Summary Email',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    subtitle: Text(
                      'Receive morning digest of active and pending items',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                    value: false,
                    onChanged: (val) {},
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Staff preferences saved successfully.',
                          ),
                          backgroundColor: Color(0xFF1565C0),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(Icons.save_rounded, size: 17),
                    label: const Text('Save Preferences'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Danger Zone / Account Deletion Card
            _workerCard(
              title: 'Danger Zone',
              icon: Icons.warning_amber_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Permanently delete your account, authentication credentials, and user profile from ActionFlow.',
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
                      'Role: Staff / Action Assignee',
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
                'This will permanently remove your login credentials, profile, and team memberships. Any assigned actions will be unassigned and reassigned by your manager. You will be signed out immediately.',
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

  Widget _buildWorkerThemeTile(
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

  // ===========================================================================
  // SHARED CARD BUILDER & BADGES
  // ===========================================================================

  Widget _workerCard({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder(context)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, cardConstraints) {
                final isNarrowCard = cardConstraints.maxWidth < 320;
                if (isNarrowCard && trailing != null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(icon, size: 20, color: const Color(0xFF1565C0)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Align(alignment: Alignment.centerRight, child: trailing),
                    ],
                  );
                }
                return Row(
                  children: [
                    Icon(icon, size: 20, color: const Color(0xFF1565C0)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      trailing,
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _priorityBadge(String priority) {
    final Color color;
    switch (priority) {
      case 'Critical':
        color = const Color(0xFFDC2626);
        break;
      case 'High':
        color = const Color(0xFFEA580C);
        break;
      case 'Medium':
        color = const Color(0xFFD97706);
        break;
      case 'Low':
      default:
        color = const Color(0xFF0284C7);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        priority,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Open':
        return const Color(0xFF0284C7);
      case 'In Progress':
        return const Color(0xFF2E7D32);
      case 'Pending Review':
      case 'Pending':
        return const Color(0xFF7C3AED);
      case 'Overdue':
        return const Color(0xFFEA580C);
      case 'Completed':
      case 'Closed':
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFF64748B);
    }
  }
}

// =============================================================================
// PERSISTENT WORKER SIDEBAR
// =============================================================================

class _WorkerSidebar extends StatelessWidget {
  const _WorkerSidebar({
    required this.selectedIndex,
    required this.onNavSelected,
    this.hasStaffApprovalAuthority = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onNavSelected;
  final bool hasStaffApprovalAuthority;

  @override
  Widget build(BuildContext context) {
    final navItems = <_WorkerNavItemData>[
      _WorkerNavItemData(
        label: 'My Dashboard',
        icon: Icons.dashboard_rounded,
        isActive: selectedIndex == 0,
        index: 0,
      ),
      _WorkerNavItemData(
        label: 'Action Register',
        icon: Icons.table_chart_rounded,
        isActive: selectedIndex == 12,
        index: 12,
      ),
      _WorkerNavItemData(
        label: 'Add Action',
        icon: Icons.add_circle_outline_rounded,
        isActive: selectedIndex == 13,
        index: 13,
      ),
      _WorkerNavItemData(
        label: 'My Actions',
        icon: Icons.assignment_turned_in_rounded,
        isActive: selectedIndex == 1,
        index: 1,
      ),
      _WorkerNavItemData(
        label: 'Reports',
        icon: Icons.bar_chart_rounded,
        isActive: selectedIndex == 2,
        index: 2,
      ),
      _WorkerNavItemData(
        label: 'Pending Updates',
        icon: Icons.pending_actions_rounded,
        isActive: selectedIndex == 3,
        index: 3,
      ),
      _WorkerNavItemData(
        label: 'Calendar',
        icon: Icons.calendar_month_rounded,
        isActive: selectedIndex == 4,
        index: 4,
      ),
      _WorkerNavItemData(
        label: 'Notifications',
        icon: Icons.notifications_rounded,
        isActive: selectedIndex == 5,
        index: 5,
      ),
      _WorkerNavItemData(
        label: 'Documents',
        icon: Icons.folder_rounded,
        isActive: selectedIndex == 6,
        index: 6,
      ),
      _WorkerNavItemData(
        label: 'New Request',
        icon: Icons.note_add_outlined,
        isActive: selectedIndex == 9,
        index: 9,
      ),
      _WorkerNavItemData(
        label: 'My Requests',
        icon: Icons.assignment_outlined,
        isActive: selectedIndex == 10,
        index: 10,
      ),
      _WorkerNavItemData(
        label: 'Request Approval',
        icon: Icons.fact_check_outlined,
        isActive: selectedIndex == 11,
        index: 11,
      ),
      _WorkerNavItemData(
        label: 'Profile',
        icon: Icons.person_rounded,
        isActive: selectedIndex == 7,
        index: 7,
      ),
      _WorkerNavItemData(
        label: 'Settings',
        icon: Icons.settings_rounded,
        isActive: selectedIndex == 8,
        index: 8,
      ),
    ];

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
                return _WorkerAnimatedSidebarNavItem(
                  key: ValueKey('worker_sidebar_item_${item.label}'),
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

class _WorkerNavItemData {
  const _WorkerNavItemData({
    required this.label,
    required this.icon,
    required this.isActive,
    this.index,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final int? index;
}

class _WorkerAnimatedSidebarNavItem extends StatefulWidget {
  const _WorkerAnimatedSidebarNavItem({
    super.key,
    required this.item,
    required this.onTap,
  });

  final _WorkerNavItemData item;
  final VoidCallback onTap;

  @override
  State<_WorkerAnimatedSidebarNavItem> createState() =>
      _WorkerAnimatedSidebarNavItemState();
}

class _WorkerAnimatedSidebarNavItemState
    extends State<_WorkerAnimatedSidebarNavItem> {
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
// PERSISTENT TOP HEADER
// =============================================================================

class _WorkerTopHeader extends StatelessWidget {
  const _WorkerTopHeader({
    required this.workerName,
    required this.profile,
    this.onProfileTap,
    required this.isMobile,
    required this.searchController,
    this.unreadCount = 3,
    required this.onSearchChanged,
    required this.onMenuTap,
    required this.onNotificationTap,
    this.onViewAllNotifications,
    this.onActionTap,
    this.onNotificationItemTap,
    this.onUnreadCountChanged,
    required this.onLogout,
  });

  final String workerName;
  final UserProfile profile;
  final VoidCallback? onProfileTap;
  final bool isMobile;
  final TextEditingController searchController;
  final int unreadCount;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onMenuTap;
  final VoidCallback onNotificationTap;
  final VoidCallback? onViewAllNotifications;
  final void Function(String actionId)? onActionTap;
  final void Function(AppNotification notification)? onNotificationItemTap;
  final VoidCallback? onUnreadCountChanged;
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
                            : 'Search my actions, sites...',
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
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Global Light/Dark Theme Switcher
                  const ThemeToggleButton(size: 38),
                  const SizedBox(width: 8),

                  // Notifications button with Dropdown Overlay
                  NotificationBellButton(
                    userId: profile.id,
                    organizationId: profile.organizationId,
                    isManager: false,
                    unreadCount: unreadCount,
                    onActionTap: onActionTap,
                    onNotificationTap: onNotificationItemTap,
                    onViewAllNotifications:
                        onViewAllNotifications ?? onNotificationTap,
                    onUnreadCountChanged: onUnreadCountChanged,
                    customBuilder: (ctx, toggle, count, isOpen) {
                      return Stack(
                        children: [
                          IconButton(
                            onPressed: toggle,
                            icon: Icon(
                              isOpen
                                  ? Icons.notifications_active_rounded
                                  : Icons.notifications_none_rounded,
                              color: isOpen
                                  ? AppTheme.primaryColor
                                  : AppTheme.textSecondary(context),
                              size: 22,
                            ),
                            tooltip: 'Notifications',
                          ),
                          if (count > 0)
                            Positioned(
                              right: 8,
                              top: 8,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFEF4444),
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 14,
                                  minHeight: 14,
                                ),
                                child: Text(
                                  '$count',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(width: 8),

                  // Worker Profile Pill
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

                  // Logout button
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
                    icon: const Icon(Icons.logout_rounded, size: 15),
                    label: const Text(
                      'Logout',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
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


class _WorkerRequestOverviewData {
  const _WorkerRequestOverviewData({
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

class _WorkerRequestOverviewCard extends StatefulWidget {
  const _WorkerRequestOverviewCard({required this.data});

  final _WorkerRequestOverviewData data;

  @override
  State<_WorkerRequestOverviewCard> createState() =>
      _WorkerRequestOverviewCardState();
}

class _WorkerRequestOverviewCardState
    extends State<_WorkerRequestOverviewCard> {
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
