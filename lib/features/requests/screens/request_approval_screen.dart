import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/request_models.dart';
import '../services/request_service.dart';
import '../widgets/forward_request_dialog.dart';
import '../widgets/request_filter_bar.dart';
import 'request_details_screen.dart';

/// Screen for reviewing and approving incoming requests.
/// Used by Managers and Staff members who have been designated as approvers.
class RequestApprovalScreen extends StatefulWidget {
  const RequestApprovalScreen({
    super.key,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserRole,
    this.currentUserEmail = '',
    required this.organizationId,
    this.isManager = false,
    this.initialTabIndex = 0,
    this.initialStatus = 'All Statuses',
    this.onNewRequest,
    this.onViewDetails,
  });

  final String currentUserId;
  final String currentUserName;
  final String currentUserRole;
  final String currentUserEmail;
  final String organizationId;
  final bool isManager;
  final int initialTabIndex;
  final String initialStatus;
  final VoidCallback? onNewRequest;
  final void Function(RequestRecord request)? onViewDetails;

  @override
  State<RequestApprovalScreen> createState() => _RequestApprovalScreenState();
}

class _RequestApprovalScreenState extends State<RequestApprovalScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<RequestRecord> _allRequests = [];
  RequestApprovalSummaryCounts _summaryCounts = const RequestApprovalSummaryCounts();
  int _totalCount = 0;
  int _totalPages = 1;
  bool _hasNextPage = false;
  bool _hasPreviousPage = false;
  bool _isLoading = true;
  String? _errorMessage;

  // Filters
  String _searchQuery = '';
  String _selectedType = 'All Types';
  String _selectedStatus = 'All Statuses';
  String _selectedPriority = 'All Priorities';
  String _selectedDepartment = 'All Departments';
  String _selectedSite = 'All Sites';
  DateTimeRange? _dateRange;
  String _selectedSort = 'Newest First';
  int _currentPage = 1;
  int _pageSize = 10;
  final Set<String> _knownDepartments = {};
  final Set<String> _knownSites = {};

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.initialStatus;
    _tabController = TabController(
      length: 5,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 4),
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) {
        _currentPage = 1;
        _loadRequests(page: 1, refreshCounts: false);
      }
    });
    _loadRequests(refreshCounts: true);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSummaryCounts() async {
    try {
      final counts = await RequestService.instance.getApprovalSummaryCounts(
        userId: widget.currentUserId,
        organizationId: widget.organizationId,
        isManager: widget.isManager,
        departmentId: _selectedDepartment,
        siteId: _selectedSite,
        startDate: _dateRange?.start,
        endDate: _dateRange?.end,
        requestType: _selectedType,
        priority: _selectedPriority,
      );
      if (mounted) {
        setState(() {
          _summaryCounts = counts;
        });
      }
    } catch (e) {
      debugPrint('[RequestApprovalScreen] Error loading summary counts: $e');
    }
  }

  Future<void> _loadRequests({int? page, bool refreshCounts = true}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      if (page != null) _currentPage = page;
    });

    if (refreshCounts) {
      _loadSummaryCounts();
    }

    try {
      final res = await RequestService.instance.getApprovalRequests(
        userId: widget.currentUserId,
        organizationId: widget.organizationId,
        isManager: widget.isManager,
        tabIndex: _tabController.index,
        page: _currentPage,
        pageSize: _pageSize,
        searchQuery: _searchQuery,
        requestType: _selectedType,
        status: _tabController.index == 4 ? _selectedStatus : null,
        priority: _selectedPriority,
        departmentId: _selectedDepartment,
        siteId: _selectedSite,
        startDate: _dateRange?.start,
        endDate: _dateRange?.end,
        sortBy: _selectedSort,
      );
      if (mounted) {
        setState(() {
          _allRequests = res.items;
          _totalCount = res.totalCount;
          _totalPages = res.totalPages;
          _hasNextPage = res.hasNextPage;
          _hasPreviousPage = res.hasPreviousPage;
          _knownDepartments.addAll(
            res.items.map((r) => r.departmentName.trim()).where((s) => s.isNotEmpty),
          );
          _knownSites.addAll(
            res.items.map((r) => r.siteName.trim()).where((s) => s.isNotEmpty),
          );
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load approval requests: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _resetFilters() {
    setState(() {
      _searchQuery = '';
      _selectedType = 'All Types';
      _selectedStatus = 'All Statuses';
      _selectedPriority = 'All Priorities';
      _selectedDepartment = 'All Departments';
      _selectedSite = 'All Sites';
      _dateRange = null;
      _selectedSort = 'Newest First';
      _currentPage = 1;
    });
    _loadRequests(page: 1);
  }

  List<String> get _availableDepartments {
    final depts = _knownDepartments.toList()..sort();
    return ['All Departments', ...depts];
  }

  List<String> get _availableSites {
    final sites = _knownSites.toList()..sort();
    return ['All Sites', ...sites];
  }

  void _openDetails(RequestRecord request) {
    if (widget.onViewDetails != null) {
      widget.onViewDetails!(request);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RequestDetailsScreen(
          requestId: request.id,
          initialRequest: request,
          currentUserId: widget.currentUserId,
          currentUserName: widget.currentUserName,
          currentUserRole: widget.currentUserRole,
          currentUserEmail: widget.currentUserEmail,
          organizationId: widget.organizationId,
          isManager: widget.isManager,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    ).then((_) => _loadRequests());
  }

  void _openForwardDialog(RequestRecord request) {
    showDialog<void>(
      context: context,
      builder: (ctx) => ForwardRequestDialog(
        request: request,
        currentUserId: widget.currentUserId,
        currentUserName: widget.currentUserName,
        currentUserRole: widget.currentUserRole,
        organizationId: widget.organizationId,
        onForwardSuccess: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Request ${request.displayId} forwarded successfully.'),
              backgroundColor: const Color(0xFF16A34A),
            ),
          );
          _loadRequests();
        },
      ),
    );
  }

  // ===========================================================================
  // APPROVE DIALOG
  // ===========================================================================
  Future<void> _handleApprove(RequestRecord request) async {
    final commentController = TextEditingController();
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A).withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_outline_rounded,
                        color: Color(0xFF16A34A), size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Text('Approve Request'),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You are approving request ${request.displayId}: "${request.title}".',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    if (request.isSequential)
                      Text(
                        'This will record your step approval and advance the request to the subsequent approver or mark it fully Approved.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context)),
                      )
                    else
                      Text(
                        'Parallel workflow: Your approval will be recorded alongside other assigned approvers.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context)),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: commentController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Approval Comments (Optional)',
                        hintText: 'Add any notes, conditions, or instructions...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);
                          try {
                            await RequestService.instance.recordApprovalDecision(
                              requestId: request.id,
                              decision: 'Approved',
                              comments: commentController.text.trim(),
                              currentUserId: widget.currentUserId,
                              currentUserName: widget.currentUserName,
                              currentUserRole: widget.currentUserRole,
                            );
                            if (dialogCtx.mounted) Navigator.of(ctx).pop();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Request ${request.displayId} successfully approved.'),
                                  backgroundColor: const Color(0xFF16A34A),
                                ),
                              );
                              _loadRequests();
                            }
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            if (dialogCtx.mounted) {
                              ScaffoldMessenger.of(dialogCtx).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to approve request: $e'),
                                  backgroundColor: const Color(0xFFDC2626),
                                ),
                              );
                            }
                          }
                        },
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Confirm Approval'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // REJECT DIALOG
  // ===========================================================================
  Future<void> _handleReject(RequestRecord request) async {
    final reasonController = TextEditingController();
    String? validationError;
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626).withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.cancel_outlined,
                        color: Color(0xFFDC2626), size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Text('Reject Request'),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You are rejecting request ${request.displayId}: "${request.title}".',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Rejection will immediately terminate the workflow and notify the requester. A clear reason is required.',
                      style: TextStyle(fontSize: 12, color: Color(0xFFDC2626)),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: reasonController,
                      maxLines: 3,
                      onChanged: (_) {
                        if (validationError != null) {
                          setDialogState(() => validationError = null);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'Rejection Reason (Required) *',
                        hintText: 'Specify why this request cannot be approved...',
                        errorText: validationError,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final reason = reasonController.text.trim();
                          if (reason.isEmpty) {
                            setDialogState(() {
                              validationError = 'Rejection reason is mandatory.';
                            });
                            return;
                          }

                          setDialogState(() => isSubmitting = true);
                          try {
                            await RequestService.instance.recordApprovalDecision(
                              requestId: request.id,
                              decision: 'Rejected',
                              comments: reason,
                              currentUserId: widget.currentUserId,
                              currentUserName: widget.currentUserName,
                              currentUserRole: widget.currentUserRole,
                            );
                            if (dialogCtx.mounted) Navigator.of(ctx).pop();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Request ${request.displayId} has been rejected.'),
                                  backgroundColor: const Color(0xFFDC2626),
                                ),
                              );
                              _loadRequests();
                            }
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            if (dialogCtx.mounted) {
                              ScaffoldMessenger.of(dialogCtx).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to reject request: $e'),
                                  backgroundColor: const Color(0xFFDC2626),
                                ),
                              );
                            }
                          }
                        },
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text('Confirm Rejection'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final myPendingCount =
        _allRequests.where((r) => r.canUserApprove(widget.currentUserId)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        _buildHeader(context, myPendingCount),
        const SizedBox(height: 16),

        // Metrics Overview
        _buildMetricsOverview(context),
        const SizedBox(height: 16),

        // Tabs
        Container(
          decoration: BoxDecoration(
            color: AppTheme.containerBg(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.cardBorder(context)),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: AppTheme.primaryColor,
            labelColor: AppTheme.primaryColor,
            unselectedLabelColor: AppTheme.textSecondary(context),
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Pending My Action'),
                    if (myPendingCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$myPendingCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Tab(text: 'Under Review'),
              const Tab(text: 'Approved'),
              const Tab(text: 'Rejected'),
              Tab(
                text: widget.isManager
                    ? 'All Requests (${_tabController.index == 4 ? _totalCount : _allRequests.length})'
                    : 'All Assigned (${_tabController.index == 4 ? _totalCount : _allRequests.length})',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Search & Filter Bar
        RequestFilterBar(
          searchQuery: _searchQuery,
          onSearchChanged: (q) {
            setState(() {
              _searchQuery = q;
              _currentPage = 1;
            });
            _loadRequests(page: 1);
          },
          selectedType: _selectedType,
          onTypeChanged: (t) {
            setState(() {
              _selectedType = t;
              _currentPage = 1;
            });
            _loadRequests(page: 1);
          },
          selectedStatus: _selectedStatus,
          onStatusChanged: (s) {
            setState(() {
              _selectedStatus = s;
              _currentPage = 1;
            });
            _loadRequests(page: 1);
          },
          selectedPriority: _selectedPriority,
          onPriorityChanged: (p) {
            setState(() {
              _selectedPriority = p;
              _currentPage = 1;
            });
            _loadRequests(page: 1);
          },
          selectedDepartment: _selectedDepartment,
          availableDepartments: _availableDepartments,
          onDepartmentChanged: (d) {
            setState(() {
              _selectedDepartment = d;
              _currentPage = 1;
            });
            _loadRequests(page: 1);
          },
          selectedSite: _selectedSite,
          availableSites: _availableSites,
          onSiteChanged: (st) {
            setState(() {
              _selectedSite = st;
              _currentPage = 1;
            });
            _loadRequests(page: 1);
          },
          dateRange: _dateRange,
          onDateRangeChanged: (r) {
            setState(() {
              _dateRange = r;
              _currentPage = 1;
            });
            _loadRequests(page: 1);
          },
          selectedSort: _selectedSort,
          onSortChanged: (s) {
            setState(() => _selectedSort = s);
            _loadRequests(page: 1);
          },
          onResetFilters: _resetFilters,
          showStatusFilter: _tabController.index == 4,
        ),
        const SizedBox(height: 16),

        // List
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_errorMessage != null)
          _buildErrorCard(context)
        else if (_allRequests.isEmpty)
          _buildEmptyState(context)
        else ...[
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _allRequests.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return _buildApprovalCard(context, _allRequests[index], isDark);
            },
          ),
          _buildPagination(context, _totalCount, _totalPages),
        ],
      ],
    );
  }

  // ===========================================================================
  // HEADER
  // ===========================================================================
  Widget _buildHeader(BuildContext context, int pendingCount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 6,
                children: [
                  Text(
                    'Request Approval',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (pendingCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFDC2626).withOpacity(0.4)),
                      ),
                      child: Text(
                        '$pendingCount Action(s) Required',
                        style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                widget.isManager
                    ? 'Review, approve, or reject operational and HSSE requests across your scope.'
                    : 'Review requests where your designated sign-off is required.',
                style: TextStyle(
                  color: AppTheme.textSecondary(context),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _loadRequests,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Refresh'),
        ),
      ],
    );
  }

  // ===========================================================================
  // METRICS OVERVIEW
  // ===========================================================================
  Widget _buildMetricsOverview(BuildContext context) {
    final myPending = _summaryCounts.myActionRequired;
    final totalInScope = _summaryCounts.totalInScope;
    final approved = _summaryCounts.approved;
    final rejected = _summaryCounts.rejected;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth < 700
            ? (constraints.maxWidth - 12) / 2
            : (constraints.maxWidth - 36) / 4;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildMetricCard(
              context: context,
              title: 'My Action Required',
              value: '$myPending',
              icon: Icons.pending_actions_rounded,
              color: myPending > 0 ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
              width: cardWidth,
            ),
            _buildMetricCard(
              context: context,
              title: 'Total In Scope',
              value: '$totalInScope',
              icon: Icons.inbox_rounded,
              color: const Color(0xFF0284C7),
              width: cardWidth,
            ),
            _buildMetricCard(
              context: context,
              title: 'Approved',
              value: '$approved',
              icon: Icons.check_circle_outline_rounded,
              color: const Color(0xFF16A34A),
              width: cardWidth,
            ),
            _buildMetricCard(
              context: context,
              title: 'Rejected',
              value: '$rejected',
              icon: Icons.cancel_outlined,
              color: const Color(0xFFDC2626),
              width: cardWidth,
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard({
    required BuildContext context,
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.containerBg(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // APPROVAL CARD
  // ===========================================================================
  Widget _buildApprovalCard(BuildContext context, RequestRecord req, bool isDark) {
    final statusColor = RequestStatus.getColor(req.status);
    final priorityColor = RequestPriority.getColor(req.priority);
    final typeColor = RequestType.getColor(req.requestType);
    final canIApprove = req.canUserApprove(widget.currentUserId);

    // Overdue flag
    bool isOverdue = false;
    final parsedDate = DateTime.tryParse(req.requiredByDate);
    if (parsedDate != null && !req.isApproved && !req.isCompleted) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (parsedDate.isBefore(today)) isOverdue = true;
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: canIApprove ? const Color(0xFFDC2626).withOpacity(0.4) : AppTheme.cardBorder(context),
          width: canIApprove ? 1.5 : 1.0,
        ),
      ),
      color: AppTheme.containerBg(context),
      child: InkWell(
        onTap: () => _openDetails(req),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Badges
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Display ID
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
                    ),
                    child: Text(
                      req.displayId,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Type
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: typeColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(RequestType.getIcon(req.requestType), size: 14, color: typeColor),
                        const SizedBox(width: 4),
                        Text(
                          req.requestType,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: typeColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Priority
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: priorityColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      req.priority,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: priorityColor,
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Action required chip if current user can approve
                  if (canIApprove) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bolt_rounded, size: 13, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            'Your Decision Needed',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // Status
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: statusColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(RequestStatus.getIcon(req.status), size: 14, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          req.status,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Title
              Text(
                req.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),

              // Requester and description
              Row(
                children: [
                  Icon(Icons.person_outline_rounded, size: 15, color: AppTheme.textSecondary(context)),
                  const SizedBox(width: 4),
                  Text(
                    'Requester: ${req.createdByName} (${req.createdByRole})',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                req.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary(context),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),

              // Department, Site, Required Date
              Wrap(
                spacing: 16,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (req.departmentName.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.business_outlined, size: 14, color: AppTheme.textSecondary(context)),
                        const SizedBox(width: 4),
                        Text(
                          req.departmentName,
                          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context)),
                        ),
                      ],
                    ),
                  if (req.siteName.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textSecondary(context)),
                        const SizedBox(width: 4),
                        Text(
                          req.siteName,
                          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context)),
                        ),
                      ],
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 14,
                        color: isOverdue ? const Color(0xFFDC2626) : AppTheme.textSecondary(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Required By: ${req.requiredByDate}${req.requiredByTime.isNotEmpty ? " (${req.requiredByTime})" : ""}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
                          color: isOverdue ? const Color(0xFFDC2626) : AppTheme.textSecondary(context),
                        ),
                      ),
                      if (isOverdue) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'OVERDUE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        req.isSequential ? Icons.format_list_numbered_rounded : Icons.alt_route_rounded,
                        size: 14,
                        color: AppTheme.textSecondary(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${req.approvalType} Approval',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Progress Bar
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.cardBorder(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Approval Chain (${req.approvers.length} Approver(s))',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                        Text(
                          req.approvalProgress,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: req.isApproved ? const Color(0xFF16A34A) : AppTheme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: req.approvalProgressFraction,
                        minHeight: 6,
                        backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          req.isApproved
                              ? const Color(0xFF16A34A)
                              : req.isRejected
                                  ? const Color(0xFFDC2626)
                                  : AppTheme.primaryColor,
                        ),
                      ),
                    ),
                    if (req.isPending || req.isUnderReview) ...[
                      const SizedBox(height: 6),
                      Text(
                        canIApprove
                            ? 'Action required from you: Click "Approve" or "Reject" below.'
                            : 'Currently waiting on: ${req.pendingApproversSummary}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: canIApprove ? FontWeight.bold : FontWeight.normal,
                          color: canIApprove ? const Color(0xFFDC2626) : AppTheme.textSecondary(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Action Buttons Row
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _openForwardDialog(req),
                    icon: const Icon(Icons.forward_to_inbox_rounded, size: 16),
                    label: const Text('Forward'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (canIApprove) ...[
                    OutlinedButton.icon(
                      onPressed: () => _handleReject(req),
                      icon: const Icon(Icons.cancel_outlined, size: 16, color: Color(0xFFDC2626)),
                      label: const Text('Reject', style: TextStyle(color: Color(0xFFDC2626))),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFDC2626)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _handleApprove(req),
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text('Approve'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  ElevatedButton.icon(
                    onPressed: () => _openDetails(req),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    label: const Text('Details'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // EMPTY & ERROR STATES
  // ===========================================================================
  Widget _buildEmptyState(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: AppTheme.containerBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.checklist_rtl_rounded,
            size: 56,
            color: AppTheme.textSecondary(context).withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Requests in this Queue',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty || _selectedType != 'All Types' || _selectedPriority != 'All Priorities'
                ? 'No requests match your selected filters. Try clearing or relaxing search criteria.'
                : 'There are currently no requests requiring review in this category.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary(context),
            ),
          ),
          if (_searchQuery.isNotEmpty || _selectedType != 'All Types' || _selectedPriority != 'All Priorities') ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _resetFilters,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
              label: const Text('Reset Filters'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFDC2626).withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDC2626).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage ?? 'An unexpected error occurred.',
              style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: _loadRequests,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildPagination(BuildContext context, int totalItems, int totalPages) {
    if (totalPages <= 1 && totalItems <= _pageSize) return const SizedBox.shrink();
    final startIdx = totalItems == 0 ? 0 : ((_currentPage - 1) * _pageSize) + 1;
    final endIdx = (_currentPage * _pageSize).clamp(0, totalItems);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Showing $startIdx–$endIdx of $totalItems requests',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary(context),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'Rows per page:',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary(context),
                ),
              ),
              const SizedBox(width: 6),
              DropdownButton<int>(
                value: _pageSize,
                underline: const SizedBox.shrink(),
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 10, child: Text('10', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 25, child: Text('25', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 50, child: Text('50', style: TextStyle(fontSize: 12))),
                ],
                onChanged: (newSize) {
                  if (newSize != null && newSize != _pageSize) {
                    setState(() {
                      _pageSize = newSize;
                      _currentPage = 1;
                    });
                    _loadRequests(page: 1);
                  }
                },
              ),
            ],
          ),
          Row(
            children: [
              OutlinedButton.icon(
                key: const Key('request_prev_page_button'),
                onPressed: _hasPreviousPage ? () => _loadRequests(page: _currentPage - 1, refreshCounts: false) : null,
                icon: const Icon(Icons.chevron_left_rounded, size: 16),
                label: const Text('Previous'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Page $_currentPage of ${totalPages > 0 ? totalPages : 1}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('request_next_page_button'),
                onPressed: _hasNextPage ? () => _loadRequests(page: _currentPage + 1, refreshCounts: false) : null,
                icon: const Icon(Icons.chevron_right_rounded, size: 16),
                label: const Text('Next'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
