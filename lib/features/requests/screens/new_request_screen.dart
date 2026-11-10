import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/app_file_picker_service.dart';
import '../../../services/company_structure_service.dart';
import '../../../services/user_service.dart';
import '../../users/data/mock_people_store.dart';
import '../../users/models/person.dart';
import '../../users/models/team.dart';
import '../models/request_models.dart';
import '../services/request_service.dart';

/// Enterprise Request Creation Screen shared by Manager and Staff portals.
class NewRequestScreen extends StatefulWidget {
  const NewRequestScreen({
    super.key,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserRole,
    this.currentUserEmail = '',
    required this.organizationId,
    this.initialDepartmentId,
    this.initialDepartmentName = '',
    this.initialSiteId,
    this.initialSiteName = '',
    this.onRequestSubmitted,
    this.onCancel,
  });

  final String currentUserId;
  final String currentUserName;
  final String currentUserRole;
  final String currentUserEmail;
  final String organizationId;
  final String? initialDepartmentId;
  final String initialDepartmentName;
  final String? initialSiteId;
  final String initialSiteName;
  final void Function(RequestRecord createdRequest)? onRequestSubmitted;
  final VoidCallback? onCancel;

  @override
  State<NewRequestScreen> createState() => _NewRequestScreenState();
}

class _NewRequestScreenState extends State<NewRequestScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _additionalNotesController = TextEditingController();
  final TextEditingController _approverSearchController = TextEditingController();
  String _approverSearchQuery = '';

  String _selectedType = RequestType.ptw;
  String _selectedPriority = RequestPriority.medium;
  String _approvalType = ApprovalType.sequential;

  DateTime _requiredByDate = DateTime.now().add(const Duration(days: 3));
  TimeOfDay _requiredByTime = const TimeOfDay(hour: 17, minute: 0);

  String? _selectedDepartmentId;
  String _selectedDepartmentName = '';
  String? _selectedSiteId;
  String _selectedSiteName = '';

  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _sites = [];
  List<Person> _availableUsers = [];
  bool _isLoadingStructure = true;

  // Designated approvers in order
  final List<RequestApproverRecord> _designatedApprovers = [];
  Person? _pendingApproverSelection;

  // Selected local attachments before upload
  final List<AppPickedFile> _selectedFiles = [];

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedDepartmentId = widget.initialDepartmentId;
    _selectedDepartmentName = widget.initialDepartmentName;
    _selectedSiteId = widget.initialSiteId;
    _selectedSiteName = widget.initialSiteName;

    _loadStructureAndUsers();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _additionalNotesController.dispose();
    _approverSearchController.dispose();
    super.dispose();
  }

  /// Strict Admin exclusion: Users with the canonical Admin role must NEVER be eligible designated approvers.
  /// Note: Non-admin users whose job title/designation happens to contain "admin" (e.g. "Database Administrator",
  /// "Contracts Administrator", "Administrative Assistant") remain eligible based on their canonical role.
  bool _isUserAdmin(Person u) {
    if (u.role == UserRole.admin) return true;
    final roleLower = u.roleLabel.toLowerCase();
    if (roleLower.contains('admin')) return true;
    return false;
  }

  /// Case-insensitive multi-field search across name, employee ID, department, designation, and site.
  List<Person> get _filteredEligibleApprovers {
    final eligible = _availableUsers.where((u) => !_isUserAdmin(u));
    if (_approverSearchQuery.isEmpty) {
      return eligible.toList();
    }
    final q = _approverSearchQuery.toLowerCase();
    return eligible.where((u) {
      final matchName = u.name.toLowerCase().contains(q);
      final matchId = u.id.toLowerCase().contains(q);
      final matchDept = u.department.toLowerCase().contains(q);
      final matchDesig = u.designation.toLowerCase().contains(q);
      final matchSite = u.site.toLowerCase().contains(q);
      final matchEmail = u.email.toLowerCase().contains(q);
      return matchName || matchId || matchDept || matchDesig || matchSite || matchEmail;
    }).toList();
  }

  Future<void> _loadStructureAndUsers() async {
    try {
      final deptFuture = CompanyStructureService.instance
          .fetchDepartments(widget.organizationId)
          .catchError((_) => <Map<String, dynamic>>[]);

      final siteFuture = CompanyStructureService.instance
          .fetchSites(widget.organizationId)
          .catchError((_) => <Map<String, dynamic>>[]);

      final userFuture = UserService.instance
          .fetchUsers(widget.organizationId, allowMockFallback: true)
          .catchError((_) => MockPeopleStore.instance.people);

      final results = await Future.wait([deptFuture, siteFuture, userFuture]);

      if (mounted) {
        setState(() {
          var depts = results[0] as List<Map<String, dynamic>>;
          var sites = results[1] as List<Map<String, dynamic>>;
          var rawUsers = results[2] as List<Person>;

          if (rawUsers.isEmpty) {
            rawUsers = MockPeopleStore.instance.people;
          }

          _departments = depts;
          _sites = sites;
          // Strict Admin exclusion from available approvers
          _availableUsers = rawUsers.where((u) => !_isUserAdmin(u)).toList();

          if (_selectedDepartmentName.isEmpty && _departments.isNotEmpty) {
            _selectedDepartmentId = _departments.first['id']?.toString();
            _selectedDepartmentName = _departments.first['name']?.toString() ?? '';
          }
          if (_selectedSiteName.isEmpty && _sites.isNotEmpty) {
            _selectedSiteId = _sites.first['id']?.toString();
            _selectedSiteName = _sites.first['name']?.toString() ?? '';
          }
          _isLoadingStructure = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingStructure = false;
          _errorMessage = 'Failed to load organization structure: $e';
        });
      }
    }
  }

  void _addApprover() {
    if (_pendingApproverSelection == null) return;
    final user = _pendingApproverSelection!;

    // Strict Admin exclusion guard
    if (_isUserAdmin(user)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Administrator accounts cannot be designated as approvers.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    // Check duplicate
    if (_designatedApprovers.any((a) => a.approverId == user.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${user.name} is already designated as an approver.'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
      return;
    }

    setState(() {
      _designatedApprovers.add(
        RequestApproverRecord(
          id: '',
          requestId: '',
          approverId: user.id,
          approverName: user.name,
          approverRole: user.roleLabel,
          approverDepartment: user.department,
          stepOrder: _designatedApprovers.length + 1,
        ),
      );
      _pendingApproverSelection = null;
    });
  }

  void _removeApprover(int index) {
    setState(() {
      _designatedApprovers.removeAt(index);
      // Re-index steps
      for (int i = 0; i < _designatedApprovers.length; i++) {
        final item = _designatedApprovers[i];
        _designatedApprovers[i] = RequestApproverRecord(
          id: item.id,
          requestId: item.requestId,
          approverId: item.approverId,
          approverName: item.approverName,
          approverRole: item.approverRole,
          approverDepartment: item.approverDepartment,
          stepOrder: i + 1,
        );
      }
    });
  }

  void _moveApproverUp(int index) {
    if (index <= 0) return;
    setState(() {
      final item = _designatedApprovers.removeAt(index);
      _designatedApprovers.insert(index - 1, item);
      for (int i = 0; i < _designatedApprovers.length; i++) {
        final a = _designatedApprovers[i];
        _designatedApprovers[i] = RequestApproverRecord(
          id: a.id,
          requestId: a.requestId,
          approverId: a.approverId,
          approverName: a.approverName,
          approverRole: a.approverRole,
          approverDepartment: a.approverDepartment,
          stepOrder: i + 1,
        );
      }
    });
  }

  void _moveApproverDown(int index) {
    if (index >= _designatedApprovers.length - 1) return;
    setState(() {
      final item = _designatedApprovers.removeAt(index);
      _designatedApprovers.insert(index + 1, item);
      for (int i = 0; i < _designatedApprovers.length; i++) {
        final a = _designatedApprovers[i];
        _designatedApprovers[i] = RequestApproverRecord(
          id: a.id,
          requestId: a.requestId,
          approverId: a.approverId,
          approverName: a.approverName,
          approverRole: a.approverRole,
          approverDepartment: a.approverDepartment,
          stepOrder: i + 1,
        );
      }
    });
  }

  Future<void> _pickAttachments() async {
    try {
      final picked = await AppFilePicker.pickMultipleFiles(
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'docx', 'xlsx', 'txt'],
      );
      if (picked.isNotEmpty && mounted) {
        setState(() {
          _selectedFiles.addAll(picked);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File selection failed: $e')),
        );
      }
    }
  }

  void _removeFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    if (_designatedApprovers.isEmpty) {
      setState(() {
        _errorMessage = 'At least one approver must be designated.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final formattedDate =
        '${_requiredByDate.year}-${_requiredByDate.month.toString().padLeft(2, '0')}-${_requiredByDate.day.toString().padLeft(2, '0')}';
    final formattedTime =
        '${_requiredByTime.hour.toString().padLeft(2, '0')}:${_requiredByTime.minute.toString().padLeft(2, '0')}';

    final rawAttachments = _selectedFiles.map((f) => {
      'name': f.name,
      'bytes': f.bytes,
      'size': f.size,
      'contentType': f.extension == 'pdf' ? 'application/pdf' : 'application/octet-stream',
    }).toList();

    try {
      final created = await RequestService.instance.submitRequest(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        requestType: _selectedType,
        priority: _selectedPriority,
        departmentId: _selectedDepartmentId,
        departmentName: _selectedDepartmentName,
        siteId: _selectedSiteId,
        siteName: _selectedSiteName,
        requiredByDate: formattedDate,
        requiredByTime: formattedTime,
        approvalType: _approvalType,
        additionalNotes: _additionalNotesController.text.trim(),
        approvers: _designatedApprovers,
        rawAttachments: rawAttachments,
        organizationId: widget.organizationId,
        currentUserId: widget.currentUserId,
        currentUserName: widget.currentUserName,
        currentUserRole: widget.currentUserRole,
        currentUserEmail: widget.currentUserEmail,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Request ${created.displayId} submitted successfully!'),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
        widget.onRequestSubmitted?.call(created);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Submission failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingStructure) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 700;

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Bar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'New Operational Request',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary(context),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Submit a request for PTW, equipment, materials, or site access.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary(context),
                              ),
                            ),
                          ],
                        ),
                        if (widget.onCancel != null)
                          TextButton.icon(
                            onPressed: _isSubmitting ? null : widget.onCancel,
                            icon: const Icon(Icons.arrow_back_rounded, size: 16),
                            label: const Text('Back'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Error banner
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Card 1: Request Details
                    _buildSectionCard(
                      context,
                      title: '1. Request Details',
                      icon: Icons.article_rounded,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isNarrow) ...[
                            _buildTypeDropdown(),
                            const SizedBox(height: 14),
                            _buildPriorityDropdown(),
                          ] else
                            Row(
                              children: [
                                Expanded(child: _buildTypeDropdown()),
                                const SizedBox(width: 14),
                                Expanded(child: _buildPriorityDropdown()),
                              ],
                            ),
                          const SizedBox(height: 14),

                          // Title
                          TextFormField(
                            key: const Key('new_request_title_field'),
                            controller: _titleController,
                            enabled: !_isSubmitting,
                            decoration: const InputDecoration(
                              labelText: 'Request Title / Short Summary *',
                              hintText: 'e.g. Scaffolding Inspection & Hot Work Permit',
                            ),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? 'Please enter a request title' : null,
                          ),
                          const SizedBox(height: 14),

                          // Description
                          TextFormField(
                            key: const Key('new_request_description_field'),
                            controller: _descriptionController,
                            enabled: !_isSubmitting,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: 'Detailed Description & Purpose *',
                              hintText: 'Describe the scope of work, technical specifications, or justification...',
                              alignLabelWithHint: true,
                            ),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? 'Please enter detailed description' : null,
                          ),
                          const SizedBox(height: 14),

                          // Department & Site
                          if (isNarrow) ...[
                            _buildDepartmentDropdown(),
                            const SizedBox(height: 14),
                            _buildSiteDropdown(),
                          ] else
                            Row(
                              children: [
                                Expanded(child: _buildDepartmentDropdown()),
                                const SizedBox(width: 14),
                                Expanded(child: _buildSiteDropdown()),
                              ],
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Card 2: Schedule & Approval Type
                    _buildSectionCard(
                      context,
                      title: '2. Required Schedule & Approval Configuration',
                      icon: Icons.tune_rounded,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isNarrow) ...[
                            _buildDatePicker(),
                            const SizedBox(height: 14),
                            _buildTimePicker(),
                          ] else
                            Row(
                              children: [
                                Expanded(child: _buildDatePicker()),
                                const SizedBox(width: 14),
                                Expanded(child: _buildTimePicker()),
                              ],
                            ),
                          const SizedBox(height: 18),

                          Text(
                            'Approval Workflow Type *',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary(context),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Radio cards for Sequential vs Parallel
                          Row(
                            children: [
                              Expanded(
                                child: _buildApprovalTypeRadio(
                                  type: ApprovalType.sequential,
                                  title: 'Sequential Approval',
                                  subtitle: 'Approvers review in defined order. Each step unlocks upon prior approval.',
                                  icon: Icons.linear_scale_rounded,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildApprovalTypeRadio(
                                  type: ApprovalType.parallel,
                                  title: 'Parallel Approval',
                                  subtitle: 'All designated approvers receive tasks concurrently and review independently.',
                                  icon: Icons.alt_route_rounded,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Card 3: Designated Approvers
                    _buildSectionCard(
                      context,
                      title: '3. Designated Approvers *',
                      icon: Icons.people_outline_rounded,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Real-time search field for approvers
                          TextFormField(
                            key: const Key('approver_search_field'),
                            controller: _approverSearchController,
                            enabled: !_isSubmitting,
                            decoration: InputDecoration(
                              labelText: 'Search Approvers',
                              hintText: 'Search by name, employee ID, department, or designation...',
                              prefixIcon: const Icon(Icons.search_rounded, size: 20),
                              suffixIcon: _approverSearchQuery.isNotEmpty
                                  ? IconButton(
                                      key: const Key('clear_approver_search_button'),
                                      icon: const Icon(Icons.clear_rounded, size: 18),
                                      tooltip: 'Clear search',
                                      onPressed: () {
                                        _approverSearchController.clear();
                                        setState(() {
                                          _approverSearchQuery = '';
                                          if (_pendingApproverSelection != null &&
                                              !_filteredEligibleApprovers.contains(_pendingApproverSelection)) {
                                            _pendingApproverSelection = null;
                                          }
                                        });
                                      },
                                    )
                                  : null,
                              isDense: true,
                            ),
                            onChanged: (val) {
                              setState(() {
                                _approverSearchQuery = val.trim();
                                if (_pendingApproverSelection != null &&
                                    !_filteredEligibleApprovers.contains(_pendingApproverSelection)) {
                                  _pendingApproverSelection = null;
                                }
                              });
                            },
                          ),
                          const SizedBox(height: 12),

                          if (_filteredEligibleApprovers.isEmpty) ...[
                            Container(
                              key: const Key('no_approvers_found_state'),
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppTheme.containerBg(context),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.cardBorder(context)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.search_off_rounded, size: 20, color: AppTheme.textSecondary(context)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _approverSearchQuery.isNotEmpty
                                          ? 'No eligible approvers found matching "$_approverSearchQuery".'
                                          : 'No eligible manager or staff approvers available in this organization.',
                                      style: TextStyle(fontSize: 13, color: AppTheme.textSecondary(context)),
                                    ),
                                  ),
                                  if (_approverSearchQuery.isNotEmpty)
                                    TextButton(
                                      onPressed: () {
                                        _approverSearchController.clear();
                                        setState(() {
                                          _approverSearchQuery = '';
                                        });
                                      },
                                      child: const Text('Clear Filter', style: TextStyle(fontSize: 12)),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ] else ...[
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<Person>(
                                    key: const Key('approver_selection_dropdown'),
                                    value: (_pendingApproverSelection != null &&
                                            _filteredEligibleApprovers.contains(_pendingApproverSelection))
                                        ? _pendingApproverSelection
                                        : null,
                                    isExpanded: true,
                                    hint: Text(
                                      _approverSearchQuery.isNotEmpty
                                          ? 'Select from matching approvers (${_filteredEligibleApprovers.length})'
                                          : 'Select eligible manager or staff approver',
                                    ),
                                    decoration: const InputDecoration(
                                      labelText: 'Select Approver',
                                      isDense: true,
                                    ),
                                    items: _filteredEligibleApprovers.map((u) {
                                      final isAlreadyAdded = _designatedApprovers.any((a) => a.approverId == u.id);
                                      return DropdownMenuItem<Person>(
                                        value: u,
                                        child: Text(
                                          '${u.name} (${u.roleLabel} - ${u.department})${isAlreadyAdded ? " [Added]" : ""}',
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: isAlreadyAdded
                                                ? AppTheme.textSecondary(context)
                                                : AppTheme.textPrimary(context),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: _isSubmitting
                                        ? null
                                        : (p) => setState(() => _pendingApproverSelection = p),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  key: const Key('add_approver_button'),
                                  onPressed: _isSubmitting || _pendingApproverSelection == null ? null : _addApprover,
                                  icon: const Icon(Icons.person_add_rounded, size: 16),
                                  label: const Text('Add Approver'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],

                          if (_designatedApprovers.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppTheme.scaffoldBg(context),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.cardBorder(context), style: BorderStyle.solid),
                              ),
                              child: Center(
                                child: Text(
                                  'No approvers designated yet. Add at least one authorized approver.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textSecondary(context),
                                  ),
                                ),
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _designatedApprovers.length,
                              separatorBuilder: (context, index) => const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final appr = _designatedApprovers[index];
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.scaffoldBg(context),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppTheme.cardBorder(context)),
                                  ),
                                  child: Row(
                                    children: [
                                      // Step order pill
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryColor.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          _approvalType == ApprovalType.sequential
                                              ? 'Step ${appr.stepOrder}'
                                              : 'Approver',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.primaryColor,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              appr.approverName,
                                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                            ),
                                            Text(
                                              '${appr.approverRole} ${appr.approverDepartment.isNotEmpty ? "• ${appr.approverDepartment}" : ""}',
                                              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary(context)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (_approvalType == ApprovalType.sequential) ...[
                                        IconButton(
                                          icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                                          tooltip: 'Move Up',
                                          onPressed: index > 0 && !_isSubmitting ? () => _moveApproverUp(index) : null,
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                                          tooltip: 'Move Down',
                                          onPressed: index < _designatedApprovers.length - 1 && !_isSubmitting
                                              ? () => _moveApproverDown(index)
                                              : null,
                                        ),
                                      ],
                                      IconButton(
                                        icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFFDC2626)),
                                        tooltip: 'Remove',
                                        onPressed: _isSubmitting ? null : () => _removeApprover(index),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Card 4: Attachments & Additional Notes
                    _buildSectionCard(
                      context,
                      title: '4. Attachments & Additional Information',
                      icon: Icons.attach_file_rounded,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              ElevatedButton.icon(
                                key: const Key('attach_files_button'),
                                onPressed: _isSubmitting ? null : _pickAttachments,
                                icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                                label: const Text('Attach Files'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.containerBg(context),
                                  foregroundColor: AppTheme.textPrimary(context),
                                  side: BorderSide(color: AppTheme.cardBorder(context)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Supported: PDF, Images, Word, Excel (Max 25MB)',
                                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context)),
                              ),
                            ],
                          ),
                          if (_selectedFiles.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _selectedFiles.asMap().entries.map((entry) {
                                final idx = entry.key;
                                final file = entry.value;
                                return Chip(
                                  avatar: const Icon(Icons.insert_drive_file_outlined, size: 16),
                                  label: Text('${file.name} (${file.formattedSize})'),
                                  onDeleted: _isSubmitting ? null : () => _removeFile(idx),
                                  deleteIconColor: const Color(0xFFDC2626),
                                );
                              }).toList(),
                            ),
                          ],
                          const SizedBox(height: 16),

                          // Additional Notes
                          TextFormField(
                            key: const Key('new_request_notes_field'),
                            controller: _additionalNotesController,
                            enabled: !_isSubmitting,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Additional Notes / References (Optional)',
                              hintText: 'e.g. Reference PO-9821, Contractor Safety Pass #412',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Submission Buttons Bar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (widget.onCancel != null)
                          TextButton(
                            onPressed: _isSubmitting ? null : widget.onCancel,
                            child: const Text('Cancel'),
                          ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          key: const Key('submit_request_button'),
                          onPressed: _isSubmitting ? null : _submitRequest,
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.send_rounded, size: 16),
                          label: Text(_isSubmitting ? 'Submitting...' : 'Submit Request'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
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
      },
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.containerBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.primaryColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Divider(height: 24),
          child,
        ],
      ),
    );
  }

  Widget _buildTypeDropdown() {
    return DropdownButtonFormField<String>(
      key: const Key('request_type_dropdown'),
      value: _selectedType,
      decoration: const InputDecoration(labelText: 'Request Type *'),
      items: RequestType.values.map((t) {
        return DropdownMenuItem(
          value: t,
          child: Row(
            children: [
              Icon(RequestType.getIcon(t), size: 16, color: RequestType.getColor(t)),
              const SizedBox(width: 8),
              Text(t),
            ],
          ),
        );
      }).toList(),
      onChanged: _isSubmitting ? null : (v) => setState(() => _selectedType = v ?? _selectedType),
    );
  }

  Widget _buildPriorityDropdown() {
    return DropdownButtonFormField<String>(
      key: const Key('request_priority_dropdown'),
      value: _selectedPriority,
      decoration: const InputDecoration(labelText: 'Priority *'),
      items: RequestPriority.values.map((p) {
        return DropdownMenuItem(
          value: p,
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: RequestPriority.getColor(p),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(p),
            ],
          ),
        );
      }).toList(),
      onChanged: _isSubmitting ? null : (v) => setState(() => _selectedPriority = v ?? _selectedPriority),
    );
  }

  Widget _buildDepartmentDropdown() {
    return DropdownButtonFormField<String>(
      key: const Key('request_department_dropdown'),
      value: _selectedDepartmentName.isNotEmpty ? _selectedDepartmentName : null,
      decoration: const InputDecoration(labelText: 'Department *'),
      items: _departments.map((d) {
        final name = d['name']?.toString() ?? '';
        return DropdownMenuItem(value: name, child: Text(name));
      }).toList(),
      onChanged: _isSubmitting
          ? null
          : (v) {
              final dept = _departments.firstWhere((d) => d['name'] == v, orElse: () => {});
              setState(() {
                _selectedDepartmentName = v ?? '';
                _selectedDepartmentId = dept['id']?.toString();
              });
            },
    );
  }

  Widget _buildSiteDropdown() {
    return DropdownButtonFormField<String>(
      key: const Key('request_site_dropdown'),
      value: _selectedSiteName.isNotEmpty ? _selectedSiteName : null,
      decoration: const InputDecoration(labelText: 'Site / Facility *'),
      items: _sites.map((s) {
        final name = s['name']?.toString() ?? '';
        return DropdownMenuItem(value: name, child: Text(name));
      }).toList(),
      onChanged: _isSubmitting
          ? null
          : (v) {
              final site = _sites.firstWhere((s) => s['name'] == v, orElse: () => {});
              setState(() {
                _selectedSiteName = v ?? '';
                _selectedSiteId = site['id']?.toString();
              });
            },
    );
  }

  Widget _buildDatePicker() {
    final display = '${_requiredByDate.day}/${_requiredByDate.month}/${_requiredByDate.year}';
    return InkWell(
      key: const Key('request_date_picker_button'),
      onTap: _isSubmitting
          ? null
          : () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _requiredByDate,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _requiredByDate = picked);
            },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Required By Date *',
          suffixIcon: Icon(Icons.calendar_today_rounded, size: 18),
        ),
        child: Text(display),
      ),
    );
  }

  Widget _buildTimePicker() {
    final display = _requiredByTime.format(context);
    return InkWell(
      key: const Key('request_time_picker_button'),
      onTap: _isSubmitting
          ? null
          : () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: _requiredByTime,
              );
              if (picked != null) setState(() => _requiredByTime = picked);
            },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Required By Time *',
          suffixIcon: Icon(Icons.access_time_rounded, size: 18),
        ),
        child: Text(display),
      ),
    );
  }

  Widget _buildApprovalTypeRadio({
    required String type,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _approvalType == type;
    return InkWell(
      key: Key('approval_type_radio_$type'),
      onTap: _isSubmitting ? null : () => setState(() => _approvalType = type),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withValues(alpha: 0.08)
              : AppTheme.scaffoldBg(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : AppTheme.cardBorder(context),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 18,
              color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 14, color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary(context)),
                      const SizedBox(width: 4),
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? AppTheme.primaryColor : AppTheme.textPrimary(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondary(context)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

