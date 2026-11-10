import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/request_models.dart';
import '../services/request_service.dart';
import '../widgets/forward_request_dialog.dart';
import '../widgets/request_filter_bar.dart';
import 'new_request_screen.dart';
import 'request_details_screen.dart';

/// Screen displaying requests created/submitted by the current user.
/// Shared by both Manager Portal and Staff Portal.
class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({
    super.key,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserRole,
    this.currentUserEmail = '',
    required this.organizationId,
    this.isManager = false,
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
  final String initialStatus;
  final VoidCallback? onNewRequest;
  final void Function(RequestRecord request)? onViewDetails;

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  List<RequestRecord> _allRequests = [];
  int _totalCount = 0;
  int _totalPages = 1;
  bool _hasNextPage = false;
  bool _hasPreviousPage = false;
  bool _isLoading = true;
  String? _errorMessage;

  // Filter state
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
    _loadRequests();
  }

  Future<void> _loadRequests({int? page}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      if (page != null) _currentPage = page;
    });

    try {
      final res = await RequestService.instance.getMyRequests(
        userId: widget.currentUserId,
        organizationId: widget.organizationId,
        page: _currentPage,
        pageSize: _pageSize,
        searchQuery: _searchQuery,
        requestType: _selectedType,
        status: _selectedStatus,
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
          _errorMessage = 'Failed to load requests: $e';
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

  void _navigateToNewRequest() {
    if (widget.onNewRequest != null) {
      widget.onNewRequest!();
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          body: NewRequestScreen(
            currentUserId: widget.currentUserId,
            currentUserName: widget.currentUserName,
            currentUserRole: widget.currentUserRole,
            currentUserEmail: widget.currentUserEmail,
            organizationId: widget.organizationId,
            onRequestSubmitted: (newReq) {
              _loadRequests();
            },
            onCancel: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    ).then((_) => _loadRequests());
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

  Future<void> _handleCompleteRequest(RequestRecord request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark Request as Completed'),
        content: Text(
          'Are you sure you want to mark request ${request.displayId} as completed? This signifies that all related execution or fulfillment is finalized.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm Completion'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await RequestService.instance.completeRequest(
        requestId: request.id,
        currentUserId: widget.currentUserId,
        currentUserName: widget.currentUserName,
        currentUserRole: widget.currentUserRole,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Request ${request.displayId} has been marked Completed.'),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
        _loadRequests();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to complete request: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Screen Header
        _buildHeader(context),
        const SizedBox(height: 16),

        // KPI Summary Cards
        _buildKpiCards(context),
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
          showStatusFilter: true,
        ),
        const SizedBox(height: 16),

        // Main Content Area
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
              return _buildRequestCard(context, _allRequests[index], isDark);
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
  Widget _buildHeader(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        final buttons = [
          OutlinedButton.icon(
            key: const Key('my_requests_refresh_button'),
            onPressed: _loadRequests,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Refresh'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            key: const Key('my_requests_new_button'),
            onPressed: _navigateToNewRequest,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('New Request'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ];

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'My Requests',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Track, monitor, and manage the requests you have submitted.',
                style: TextStyle(
                  color: AppTheme.textSecondary(context),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              Row(children: buttons),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My Requests',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Track, monitor, and manage the requests you have submitted.',
                    style: TextStyle(
                      color: AppTheme.textSecondary(context),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Row(children: buttons),
          ],
        );
      },
    );
  }

  // ===========================================================================
  // KPI METRIC CARDS
  // ===========================================================================
  Widget _buildKpiCards(BuildContext context) {
    final total = _totalCount;
    final pending = _allRequests.where((r) => r.isPending || r.isUnderReview).length;
    final approved = _allRequests.where((r) => r.isApproved).length;
    final completed = _allRequests.where((r) => r.isCompleted).length;
    final rejected = _allRequests.where((r) => r.isRejected).length;

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
              title: 'Total Submitted',
              value: '$total',
              icon: Icons.assignment_outlined,
              color: const Color(0xFF0284C7),
              width: cardWidth,
            ),
            _buildMetricCard(
              context: context,
              title: 'In Progress',
              value: '$pending',
              icon: Icons.hourglass_top_rounded,
              color: const Color(0xFFD97706),
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
              title: 'Completed / Rejected',
              value: '$completed / $rejected',
              icon: Icons.task_alt_rounded,
              color: const Color(0xFF475569),
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
  // REQUEST CARD
  // ===========================================================================
  Widget _buildRequestCard(BuildContext context, RequestRecord req, bool isDark) {
    final statusColor = RequestStatus.getColor(req.status);
    final priorityColor = RequestPriority.getColor(req.priority);
    final typeColor = RequestType.getColor(req.requestType);

    // Overdue detection
    bool isOverdue = false;
    final parsedDate = DateTime.tryParse(req.requiredByDate);
    if (parsedDate != null && !req.isApproved && !req.isCompleted) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (parsedDate.isBefore(today)) {
        isOverdue = true;
      }
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppTheme.cardBorder(context)),
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
              // Top Metadata Row: Display ID, Type, Priority, Status
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Display ID Badge
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

                  // Request Type Badge
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

                  // Priority Badge
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

                  // Status Pill
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

              // Description preview
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
              const SizedBox(height: 14),

              // Department, Site, Required Date, Workflow details
              Wrap(
                spacing: 16,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (req.departmentName.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.business_outlined, size: 15, color: AppTheme.textSecondary(context)),
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
                        Icon(Icons.location_on_outlined, size: 15, color: AppTheme.textSecondary(context)),
                        const SizedBox(width: 4),
                        Text(
                          req.siteName,
                          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context)),
                        ),
                      ],
                    ),
                  // Required By Date
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
                        'Required: ${req.requiredByDate}${req.requiredByTime.isNotEmpty ? " (${req.requiredByTime})" : ""}',
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
                  // Workflow Type
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        req.isSequential ? Icons.format_list_numbered_rounded : Icons.alt_route_rounded,
                        size: 15,
                        color: AppTheme.textSecondary(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${req.approvalType} Approval',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context)),
                      ),
                    ],
                  ),
                  if (req.attachments.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.attach_file_rounded, size: 15, color: AppTheme.textSecondary(context)),
                        const SizedBox(width: 2),
                        Text(
                          '${req.attachments.length} attachment(s)',
                          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context)),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 14),

              // Approval Progress Bar & Summary
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
                          'Workflow Progress',
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
                        'Pending on: ${req.pendingApproversSummary}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary(context),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Bottom Actions Row
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
                  if (req.canUserComplete(
                    widget.currentUserId,
                    isManager: widget.isManager,
                    isCompanyAdmin: widget.currentUserRole.toLowerCase().contains('admin'),
                    isScoped: widget.isManager,
                  )) ...[
                    ElevatedButton.icon(
                      onPressed: () => _handleCompleteRequest(req),
                      icon: const Icon(Icons.task_alt_rounded, size: 16),
                      label: const Text('Mark Completed'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  ElevatedButton.icon(
                    onPressed: () => _openDetails(req),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    label: const Text('View Details'),
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
            Icons.inbox_outlined,
            size: 56,
            color: AppTheme.textSecondary(context).withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Requests Found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty ||
                    _selectedType != 'All Types' ||
                    _selectedStatus != 'All Statuses' ||
                    _selectedPriority != 'All Priorities'
                ? 'No requests match your selected filters. Try clearing or relaxing search criteria.'
                : 'You have not submitted any requests yet. Click the button below to submit your first request.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 20),
          if (_searchQuery.isNotEmpty ||
              _selectedType != 'All Types' ||
              _selectedStatus != 'All Statuses' ||
              _selectedPriority != 'All Priorities')
            OutlinedButton.icon(
              onPressed: _resetFilters,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
              label: const Text('Reset Filters'),
            )
          else
            ElevatedButton.icon(
              onPressed: _navigateToNewRequest,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Create New Request'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
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
                onPressed: _hasPreviousPage ? () => _loadRequests(page: _currentPage - 1) : null,
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
                onPressed: _hasNextPage ? () => _loadRequests(page: _currentPage + 1) : null,
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
