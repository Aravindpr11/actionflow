import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../services/app_file_picker_service.dart';
import '../../../services/notification_service.dart';
import '../models/request_models.dart';

/// Singleton Service for Request Management and Multi-level Approval Workflows
class RequestService {
  RequestService({SupabaseClient? client}) : _customClient = client;

  static final RequestService instance = RequestService();
  final SupabaseClient? _customClient;

  SupabaseClient? get _client => _customClient ?? SupabaseConfig.clientOrNull;

  /// Test hook to force mock-only mode during unit / widget tests
  static bool useMockOnly = false;

  /// In-memory store for offline development and testing
  final List<RequestRecord> _mockRequests = [];

  List<RequestRecord> get mockRequests => List.unmodifiable(_mockRequests);

  void clearMockStore() {
    _mockRequests.clear();
  }

  void seedMockRequest(RequestRecord req) {
    _mockRequests.removeWhere((r) => r.id == req.id);
    _mockRequests.add(req);
  }

  // ===========================================================================
  // 1. SUBMIT NEW REQUEST
  // ===========================================================================

  Future<RequestRecord> submitRequest({
    required String title,
    required String description,
    required String requestType,
    required String priority,
    String? departmentId,
    String departmentName = '',
    String? siteId,
    String siteName = '',
    required String requiredByDate,
    String requiredByTime = '',
    String approvalType = ApprovalType.sequential,
    String additionalNotes = '',
    required List<RequestApproverRecord> approvers,
    List<Map<String, dynamic>> rawAttachments = const [],
    required String organizationId,
    required String currentUserId,
    required String currentUserName,
    required String currentUserRole,
    String currentUserEmail = '',
  }) async {
    final client = _client;
    final isLive = client != null && SupabaseConfig.isInitialized && !useMockOnly;

    if (title.trim().isEmpty) {
      throw ArgumentError('Request Title is required.');
    }
    if (description.trim().isEmpty) {
      throw ArgumentError('Detailed Description is required.');
    }
    if (approvers.isEmpty) {
      throw ArgumentError('At least one approver must be designated.');
    }

    // Approver validations: Reject duplicates and strictly exclude Admin roles
    final designatedIds = <String>{};
    for (final appr in approvers) {
      if (!designatedIds.add(appr.approverId)) {
        throw ArgumentError('Duplicate approver designated: "${appr.approverName}". Each approver can only be designated once.');
      }
      final roleLower = appr.approverRole.toLowerCase();
      if (roleLower.contains('admin')) {
        throw ArgumentError('Administrator "${appr.approverName}" cannot be designated as an approver.');
      }
    }

    final cleanDeptId = (departmentId != null && departmentId.trim().isNotEmpty) ? departmentId.trim() : null;
    final cleanSiteId = (siteId != null && siteId.trim().isNotEmpty) ? siteId.trim() : null;

    if (isLive) {
      // 1. Verify organization identity from authenticated user context
      String verifiedOrgId = organizationId;
      try {
        final profileRes = await client
            .from('profiles')
            .select('organization_id')
            .eq('id', currentUserId)
            .maybeSingle();
        if (profileRes != null && profileRes['organization_id'] != null) {
          verifiedOrgId = profileRes['organization_id'].toString();
        }
      } catch (_) {}

      // 2. Upload files to Supabase Storage ('documents' bucket) under <verified_org_id>/requests/<unique_filename>
      final uploadedAttachments = <Map<String, dynamic>>[];
      for (final att in rawAttachments) {
        final name = att['name']?.toString() ?? 'attachment';
        final bytes = att['bytes'] as Uint8List?;
        final size = (att['size'] as num?)?.toInt() ?? bytes?.length ?? 0;
        final contentType = att['contentType']?.toString() ?? 'application/octet-stream';

        if (bytes != null && bytes.isNotEmpty) {
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final sanitizedName = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
          // Structured path adhering to storage policy: <verified_org_id>/requests/<timestamp>_<filename>
          final storagePath = '$verifiedOrgId/requests/${timestamp}_$sanitizedName';

          try {
            await client.storage.from('documents').uploadBinary(
              storagePath,
              bytes,
              fileOptions: FileOptions(contentType: contentType, upsert: false),
            );
            uploadedAttachments.add({
              'file_name': name,
              'file_path': storagePath,
              'file_size': size,
              'content_type': contentType,
            });
          } catch (e) {
            debugPrint('[RequestService] Storage upload error for $name: $e');
            // Re-throw if storage fails to avoid orphaned database records
            throw Exception('Failed to upload attachment "$name": $e');
          }
        }
      }

      // 3. Prepare Approvers JSON payload
      final approversPayload = approvers.map((a) => {
        'approver_id': a.approverId,
        'approver_name': a.approverName,
        'approver_role': a.approverRole,
        'approver_department': a.approverDepartment,
        'step_order': a.stepOrder,
      }).toList();

      // 4. Call atomic PostgreSQL RPC `submit_new_request`
      try {
        final dynamic res = await client.rpc(
          'submit_new_request',
          params: {
            'p_title': title.trim(),
            'p_description': description.trim(),
            'p_request_type': requestType,
            'p_priority': priority,
            'p_department_id': cleanDeptId,
            'p_department_name': departmentName,
            'p_site_id': cleanSiteId,
            'p_site_name': siteName,
            'p_required_by_date': requiredByDate,
            'p_required_by_time': requiredByTime,
            'p_approval_type': approvalType,
            'p_additional_notes': additionalNotes.trim(),
            'p_approvers': approversPayload,
            'p_attachments': uploadedAttachments,
          },
        );

        final map = Map<String, dynamic>.from(res as Map);
        final newId = map['id']?.toString() ?? '';
        final details = await getRequestDetails(newId);

        // Notify designated approver(s)
        final approversToNotify = approvalType == ApprovalType.parallel
            ? details.approvers
            : (details.approvers.isNotEmpty ? [details.approvers.first] : <RequestApproverRecord>[]);
        for (final appr in approversToNotify) {
          NotificationService.safeDispatch(
            () => NotificationService.instance.notifyRequestSubmitted(
              requestId: details.id,
              requestCode: details.displayId,
              approverUserId: appr.approverId,
              requesterName: currentUserName,
              requestTitle: details.title,
              organizationId: verifiedOrgId,
            ),
            context: 'RequestService.submitRequest',
          );
        }
        return details;
      } catch (e) {
        debugPrint('[RequestService] submit_new_request RPC error: $e');
        rethrow;
      }
    }

    // -------------------------------------------------------------------------
    // Offline / Mock Fallback for Unit & Widget Tests
    // -------------------------------------------------------------------------
    final mockId = 'req-${DateTime.now().microsecondsSinceEpoch}-${_mockRequests.length + 1}';
    final mockDisplayId = 'REQ-${1000 + _mockRequests.length + 1}';

    final createdApprovers = approvers.asMap().entries.map((entry) {
      final idx = entry.key;
      final appr = entry.value;
      return RequestApproverRecord(
        id: 'appr-$mockId-${idx + 1}',
        requestId: mockId,
        approverId: appr.approverId,
        approverName: appr.approverName,
        approverRole: appr.approverRole,
        approverDepartment: appr.approverDepartment,
        stepOrder: appr.stepOrder > 0 ? appr.stepOrder : (idx + 1),
        status: 'Pending',
        createdAt: DateTime.now(),
      );
    }).toList();

    final createdAttachments = rawAttachments.asMap().entries.map((entry) {
      final idx = entry.key;
      final att = entry.value;
      return RequestAttachmentRecord(
        id: 'att-$mockId-${idx + 1}',
        requestId: mockId,
        fileName: att['name']?.toString() ?? 'File_${idx + 1}',
        filePath: '$organizationId/requests/$mockId/${att['name']}',
        fileSize: (att['size'] as num?)?.toInt() ?? 1024,
        contentType: att['contentType']?.toString() ?? 'application/pdf',
        uploadedBy: currentUserId,
        createdAt: DateTime.now(),
      );
    }).toList();

    final mockRecord = RequestRecord(
      id: mockId,
      displayId: mockDisplayId,
      organizationId: organizationId,
      title: title.trim(),
      description: description.trim(),
      requestType: requestType,
      priority: priority,
      departmentId: departmentId,
      departmentName: departmentName,
      siteId: siteId,
      siteName: siteName,
      requiredByDate: requiredByDate,
      requiredByTime: requiredByTime,
      approvalType: approvalType,
      status: RequestStatus.pending,
      createdBy: currentUserId,
      createdByName: currentUserName,
      createdByRole: currentUserRole,
      createdByEmail: currentUserEmail,
      additionalNotes: additionalNotes.trim(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      approvers: createdApprovers,
      attachments: createdAttachments,
      history: [
        RequestHistoryRecord(
          id: 'hist-$mockId-1',
          requestId: mockId,
          actorId: currentUserId,
          actorName: currentUserName,
          actorRole: currentUserRole,
          action: 'Submitted',
          details: 'Request submitted with ${createdApprovers.length} designated approver(s).',
          createdAt: DateTime.now(),
        ),
      ],
    );

    _mockRequests.insert(0, mockRecord);

    final approversToNotify = approvalType == ApprovalType.parallel
        ? mockRecord.approvers
        : (mockRecord.approvers.isNotEmpty ? [mockRecord.approvers.first] : <RequestApproverRecord>[]);
    for (final appr in approversToNotify) {
      NotificationService.safeDispatch(
        () => NotificationService.instance.notifyRequestSubmitted(
          requestId: mockRecord.id,
          requestCode: mockRecord.displayId,
          approverUserId: appr.approverId,
          requesterName: currentUserName,
          requestTitle: mockRecord.title,
          organizationId: organizationId,
        ),
        context: 'RequestService.submitRequest (mock)',
      );
    }

    return mockRecord;
  }

  // ===========================================================================
  // 2. FETCH "MY REQUESTS" (Server-side Paginated)
  // ===========================================================================

  Future<PaginatedRequestsResult> getMyRequests({
    required String userId,
    required String organizationId,
    int page = 1,
    int pageSize = 10,
    String? searchQuery,
    String? requestType,
    String? status,
    String? priority,
    String? departmentId,
    String? siteId,
    DateTime? startDate,
    DateTime? endDate,
    String? sortBy,
  }) async {
    final client = _client;
    final isLive = client != null && SupabaseConfig.isInitialized && !useMockOnly;

    final safePage = page > 0 ? page : 1;
    final safePageSize = pageSize > 0 ? pageSize : 10;
    final from = (safePage - 1) * safePageSize;
    final to = from + safePageSize - 1;

    if (isLive) {
      try {
        // Lightweight list: only include approvers, omit heavy history/attachments/forwards
        var query = client
            .from('requests')
            .select('*, request_approvers (*)')
            .eq('organization_id', organizationId)
            .eq('created_by', userId);

        if (searchQuery != null && searchQuery.trim().isNotEmpty) {
          final q = searchQuery.trim();
          query = query.or('display_id.ilike.%$q%,title.ilike.%$q%,description.ilike.%$q%,department_name.ilike.%$q%,site_name.ilike.%$q%');
        }
        if (requestType != null && requestType.isNotEmpty && requestType != 'All Types') {
          query = query.eq('request_type', requestType);
        }
        if (status != null && status.isNotEmpty && status != 'All Statuses') {
          query = query.ilike('status', status);
        }
        if (priority != null && priority.isNotEmpty && priority != 'All Priorities') {
          query = query.ilike('priority', priority);
        }
        if (departmentId != null && departmentId.isNotEmpty && departmentId != 'All Departments' && departmentId != 'all') {
          query = query.or('department_id.eq.$departmentId,department_name.ilike.$departmentId');
        }
        if (siteId != null && siteId.isNotEmpty && siteId != 'All Sites' && siteId != 'all') {
          query = query.or('site_id.eq.$siteId,site_name.ilike.$siteId');
        }
        if (startDate != null) {
          query = query.gte('required_by_date', startDate.toIso8601String().substring(0, 10));
        }
        if (endDate != null) {
          query = query.lte('required_by_date', endDate.toIso8601String().substring(0, 10));
        }

        // Sorting
        PostgrestTransformBuilder<List<Map<String, dynamic>>> orderedQuery;
        switch (sortBy) {
          case 'Oldest First':
            orderedQuery = query.order('created_at', ascending: true);
            break;
          case 'Required Date: Earliest':
            orderedQuery = query.order('required_by_date', ascending: true);
            break;
          case 'Priority: High to Low':
            orderedQuery = query.order('priority', ascending: false).order('created_at', ascending: false);
            break;
          case 'Newest First':
          default:
            orderedQuery = query.order('created_at', ascending: false);
            break;
        }

        final response = await orderedQuery.range(from, to).count(CountOption.exact);
        final dynamic raw = response.data;
        final totalCount = response.count;

        final items = (raw is List)
            ? raw.map((e) => RequestRecord.fromJson(Map<String, dynamic>.from(e as Map))).toList()
            : <RequestRecord>[];

        return PaginatedRequestsResult(
          items: items,
          totalCount: totalCount,
          page: safePage,
          pageSize: safePageSize,
        );
      } catch (e) {
        debugPrint('[RequestService] getMyRequests error: $e');
        rethrow;
      }
    }

    // Mock
    var filtered = _mockRequests.where((r) => r.createdBy == userId).toList();
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.toLowerCase().trim();
      filtered = filtered.where((r) {
        return r.displayId.toLowerCase().contains(q) ||
            r.title.toLowerCase().contains(q) ||
            r.description.toLowerCase().contains(q) ||
            r.departmentName.toLowerCase().contains(q) ||
            r.siteName.toLowerCase().contains(q);
      }).toList();
    }
    if (requestType != null && requestType.isNotEmpty && requestType != 'All Types') {
      filtered = filtered.where((r) => r.requestType == requestType).toList();
    }
    if (status != null && status.isNotEmpty && status != 'All Statuses') {
      filtered = filtered.where((r) => r.status.toLowerCase() == status.toLowerCase()).toList();
    }
    if (priority != null && priority.isNotEmpty && priority != 'All Priorities') {
      filtered = filtered.where((r) => r.priority.toLowerCase() == priority.toLowerCase()).toList();
    }
    if (departmentId != null && departmentId.isNotEmpty && departmentId != 'All Departments' && departmentId != 'all') {
      filtered = filtered.where((r) =>
          r.departmentId == departmentId ||
          r.departmentName.toLowerCase() == departmentId.toLowerCase()).toList();
    }
    if (siteId != null && siteId.isNotEmpty && siteId != 'All Sites' && siteId != 'all') {
      filtered = filtered.where((r) =>
          r.siteId == siteId ||
          r.siteName.toLowerCase() == siteId.toLowerCase()).toList();
    }
    if (startDate != null) {
      filtered = filtered.where((r) {
        final d = DateTime.tryParse(r.requiredByDate);
        return d != null && !d.isBefore(startDate);
      }).toList();
    }
    if (endDate != null) {
      filtered = filtered.where((r) {
        final d = DateTime.tryParse(r.requiredByDate);
        return d != null && !d.isAfter(endDate);
      }).toList();
    }

    // Sort mock
    switch (sortBy) {
      case 'Oldest First':
        filtered.sort((a, b) => (a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
        break;
      case 'Required Date: Earliest':
        filtered.sort((a, b) => a.requiredByDate.compareTo(b.requiredByDate));
        break;
      case 'Priority: High to Low':
        int rank(String p) => switch (p.toLowerCase()) {
              'critical' => 4,
              'high' => 3,
              'medium' => 2,
              _ => 1,
            };
        filtered.sort((a, b) => rank(b.priority).compareTo(rank(a.priority)));
        break;
      case 'Newest First':
      default:
        filtered.sort((a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
        break;
    }

    final totalCount = filtered.length;
    final items = filtered.skip(from).take(safePageSize).toList();

    return PaginatedRequestsResult(
      items: items,
      totalCount: totalCount,
      page: safePage,
      pageSize: safePageSize,
    );
  }

  // ===========================================================================
  // 3. FETCH "REQUEST APPROVAL" INBOX (Server-side Paginated)
  // ===========================================================================

  Future<PaginatedRequestsResult> getApprovalRequests({
    required String userId,
    required String organizationId,
    bool isManager = false,
    int tabIndex = 4, // 0: Pending My Approval, 1: Under Review, 2: Approved, 3: Completed, 4: All
    int page = 1,
    int pageSize = 10,
    String? searchQuery,
    String? requestType,
    String? status,
    String? priority,
    String? departmentId,
    String? siteId,
    DateTime? startDate,
    DateTime? endDate,
    String? sortBy,
  }) async {
    final client = _client;
    final isLive = client != null && SupabaseConfig.isInitialized && !useMockOnly;

    final safePage = page > 0 ? page : 1;
    final safePageSize = pageSize > 0 ? pageSize : 10;
    final from = (safePage - 1) * safePageSize;
    final to = from + safePageSize - 1;

    if (isLive) {
      try {
        var query = client
            .from('requests')
            .select(isManager ? '*, request_approvers (*)' : '*, request_approvers!inner (*)')
            .eq('organization_id', organizationId);

        if (!isManager) {
          query = query.eq('request_approvers.approver_id', userId);
        }

        // Tab index filtering
        if (tabIndex == 0) {
          query = query.inFilter('status', ['Pending', 'Under Review']);
        } else if (tabIndex == 1) {
          query = query.inFilter('status', ['Pending', 'Under Review']);
        } else if (tabIndex == 2) {
          query = query.eq('status', 'Approved');
        } else if (tabIndex == 3) {
          query = query.eq('status', 'Rejected');
        }

        // Specific dropdown status override if provided
        if (status != null && status.isNotEmpty && status != 'All Statuses') {
          query = query.ilike('status', status);
        }

        if (searchQuery != null && searchQuery.trim().isNotEmpty) {
          final q = searchQuery.trim();
          query = query.or('display_id.ilike.%$q%,title.ilike.%$q%,description.ilike.%$q%,created_by_name.ilike.%$q%,department_name.ilike.%$q%,site_name.ilike.%$q%');
        }
        if (requestType != null && requestType.isNotEmpty && requestType != 'All Types') {
          query = query.eq('request_type', requestType);
        }
        if (priority != null && priority.isNotEmpty && priority != 'All Priorities') {
          query = query.ilike('priority', priority);
        }
        if (departmentId != null && departmentId.isNotEmpty && departmentId != 'All Departments' && departmentId != 'all') {
          query = query.or('department_id.eq.$departmentId,department_name.ilike.$departmentId');
        }
        if (siteId != null && siteId.isNotEmpty && siteId != 'All Sites' && siteId != 'all') {
          query = query.or('site_id.eq.$siteId,site_name.ilike.$siteId');
        }
        if (startDate != null) {
          query = query.gte('required_by_date', startDate.toIso8601String().substring(0, 10));
        }
        if (endDate != null) {
          query = query.lte('required_by_date', endDate.toIso8601String().substring(0, 10));
        }

        // Sorting
        PostgrestTransformBuilder<List<Map<String, dynamic>>> orderedQuery;
        switch (sortBy) {
          case 'Oldest First':
            orderedQuery = query.order('created_at', ascending: true);
            break;
          case 'Required Date: Earliest':
            orderedQuery = query.order('required_by_date', ascending: true);
            break;
          case 'Priority: High to Low':
            orderedQuery = query.order('priority', ascending: false).order('created_at', ascending: false);
            break;
          case 'Newest First':
          default:
            orderedQuery = query.order('created_at', ascending: false);
            break;
        }

        final response = await orderedQuery.range(from, to).count(CountOption.exact);
        final dynamic raw = response.data;
        final totalCount = response.count;

        final items = (raw is List)
            ? raw.map((e) => RequestRecord.fromJson(Map<String, dynamic>.from(e as Map))).toList()
            : <RequestRecord>[];

        return PaginatedRequestsResult(
          items: items,
          totalCount: totalCount,
          page: safePage,
          pageSize: safePageSize,
        );
      } catch (e) {
        debugPrint('[RequestService] getApprovalRequests error: $e');
        rethrow;
      }
    }

    // Mock
    var filtered = isManager
        ? List<RequestRecord>.from(_mockRequests)
        : _mockRequests.where((r) => r.approvers.any((a) => a.approverId == userId)).toList();

    // Tab filter in mock
    switch (tabIndex) {
      case 0:
        filtered = filtered.where((r) => r.canUserApprove(userId)).toList();
        break;
      case 1:
        filtered = filtered.where((r) => r.isUnderReview || r.isPending).toList();
        break;
      case 2:
        filtered = filtered.where((r) => r.isApproved).toList();
        break;
      case 3:
        filtered = filtered.where((r) => r.isRejected).toList();
        break;
      case 4:
      default:
        break;
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.toLowerCase().trim();
      filtered = filtered.where((r) {
        return r.displayId.toLowerCase().contains(q) ||
            r.title.toLowerCase().contains(q) ||
            r.description.toLowerCase().contains(q) ||
            r.createdByName.toLowerCase().contains(q) ||
            r.departmentName.toLowerCase().contains(q) ||
            r.siteName.toLowerCase().contains(q);
      }).toList();
    }
    if (requestType != null && requestType.isNotEmpty && requestType != 'All Types') {
      filtered = filtered.where((r) => r.requestType == requestType).toList();
    }
    if (status != null && status.isNotEmpty && status != 'All Statuses') {
      filtered = filtered.where((r) => r.status.toLowerCase() == status.toLowerCase()).toList();
    }
    if (priority != null && priority.isNotEmpty && priority != 'All Priorities') {
      filtered = filtered.where((r) => r.priority.toLowerCase() == priority.toLowerCase()).toList();
    }
    if (departmentId != null && departmentId.isNotEmpty && departmentId != 'All Departments' && departmentId != 'all') {
      filtered = filtered.where((r) =>
          r.departmentId == departmentId ||
          r.departmentName.toLowerCase() == departmentId.toLowerCase()).toList();
    }
    if (siteId != null && siteId.isNotEmpty && siteId != 'All Sites' && siteId != 'all') {
      filtered = filtered.where((r) =>
          r.siteId == siteId ||
          r.siteName.toLowerCase() == siteId.toLowerCase()).toList();
    }
    if (startDate != null) {
      filtered = filtered.where((r) {
        final d = DateTime.tryParse(r.requiredByDate);
        return d != null && !d.isBefore(startDate);
      }).toList();
    }
    if (endDate != null) {
      filtered = filtered.where((r) {
        final d = DateTime.tryParse(r.requiredByDate);
        return d != null && !d.isAfter(endDate);
      }).toList();
    }

    // Sort mock
    switch (sortBy) {
      case 'Oldest First':
        filtered.sort((a, b) => (a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
        break;
      case 'Required Date: Earliest':
        filtered.sort((a, b) => a.requiredByDate.compareTo(b.requiredByDate));
        break;
      case 'Priority: High to Low':
        int rank(String p) => switch (p.toLowerCase()) {
              'critical' => 4,
              'high' => 3,
              'medium' => 2,
              _ => 1,
            };
        filtered.sort((a, b) => rank(b.priority).compareTo(rank(a.priority)));
        break;
      case 'Newest First':
      default:
        filtered.sort((a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
        break;
    }

    final totalCount = filtered.length;
    final items = filtered.skip(from).take(safePageSize).toList();

    return PaginatedRequestsResult(
      items: items,
      totalCount: totalCount,
      page: safePage,
      pageSize: safePageSize,
    );
  }

  // ===========================================================================
  // 4. FETCH SINGLE REQUEST DETAILS
  // ===========================================================================

  Future<RequestRecord> getRequestDetails(String requestId) async {
    final client = _client;
    final isLive = client != null && SupabaseConfig.isInitialized && !useMockOnly;

    if (isLive) {
      try {
        final dynamic raw = await client
            .from('requests')
            .select('''
              *,
              request_approvers (*),
              request_attachments (*),
              request_forwards (*),
              request_history (*)
            ''')
            .eq('id', requestId)
            .single();

        return RequestRecord.fromJson(Map<String, dynamic>.from(raw as Map));
      } catch (e) {
        debugPrint('[RequestService] getRequestDetails error: $e');
        rethrow;
      }
    }

    return _mockRequests.firstWhere(
      (r) => r.id == requestId,
      orElse: () => throw StateError('Request not found: $requestId'),
    );
  }

  // ===========================================================================
  // 5. RECORD APPROVAL DECISION
  // ===========================================================================

  Future<RequestRecord> recordApprovalDecision({
    required String requestId,
    required String decision, // 'Approved' or 'Rejected'
    String comments = '',
    required String currentUserId,
    required String currentUserName,
    required String currentUserRole,
  }) async {
    final client = _client;
    final isLive = client != null && SupabaseConfig.isInitialized && !useMockOnly;

    if (decision.toLowerCase() == 'rejected' && comments.trim().isEmpty) {
      throw ArgumentError('A rejection reason is required.');
    }

    if (isLive) {
      try {
        await client.rpc(
          'record_request_approval_decision',
          params: {
            'p_request_id': requestId,
            'p_decision': decision,
            'p_comments': comments.trim(),
          },
        );
        final updatedRecord = await getRequestDetails(requestId);
        final isApprovedDecision = decision.toLowerCase() == 'approved';

        if (!isApprovedDecision) {
          NotificationService.safeDispatch(
            () => NotificationService.instance.notifyRequestRejected(
              requestId: updatedRecord.id,
              requestCode: updatedRecord.displayId,
              requesterUserId: updatedRecord.createdBy,
              approverName: currentUserName,
              requestTitle: updatedRecord.title,
              reason: comments.trim(),
              organizationId: updatedRecord.organizationId,
            ),
            context: 'RequestService.recordApprovalDecision (rejected)',
          );
        } else {
          final isCompleted = updatedRecord.isApproved || updatedRecord.isCompleted;
          NotificationService.safeDispatch(
            () => NotificationService.instance.notifyRequestApproved(
              requestId: updatedRecord.id,
              requestCode: updatedRecord.displayId,
              requesterUserId: updatedRecord.createdBy,
              approverName: currentUserName,
              requestTitle: updatedRecord.title,
              isCompleted: isCompleted,
              organizationId: updatedRecord.organizationId,
            ),
            context: 'RequestService.recordApprovalDecision (approved)',
          );

          if (!isCompleted && updatedRecord.approvalType == ApprovalType.sequential) {
            final pendingApprovers = updatedRecord.approvers
                .where((a) => a.isPending)
                .toList()
              ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
            if (pendingApprovers.isNotEmpty) {
              NotificationService.safeDispatch(
                () => NotificationService.instance.notifyRequestAssigned(
                  requestId: updatedRecord.id,
                  requestCode: updatedRecord.displayId,
                  approverUserId: pendingApprovers.first.approverId,
                  requestTitle: updatedRecord.title,
                  organizationId: updatedRecord.organizationId,
                ),
                context: 'RequestService.recordApprovalDecision (next approver)',
              );
            }
          }
        }
        return updatedRecord;
      } catch (e) {
        debugPrint('[RequestService] recordApprovalDecision RPC error: $e');
        rethrow;
      }
    }

    // Mock implementation
    final idx = _mockRequests.indexWhere((r) => r.id == requestId);
    if (idx == -1) throw StateError('Request not found: $requestId');

    final req = _mockRequests[idx];
    if (req.isApproved || req.isCompleted || req.isRejected) {
      throw StateError('Cannot modify decision on a finalized request.');
    }

    final isDesignated = req.approvers.any((a) => a.approverId == currentUserId);
    if (!isDesignated) {
      throw StateError('Access Denied: You are not a designated approver for this request.');
    }

    final isApprovedDecision = decision.toLowerCase() == 'approved';
    final updatedApprovers = req.approvers.map((a) {
      if (a.approverId == currentUserId) {
        return RequestApproverRecord(
          id: a.id,
          requestId: a.requestId,
          approverId: a.approverId,
          approverName: a.approverName,
          approverRole: a.approverRole,
          approverDepartment: a.approverDepartment,
          stepOrder: a.stepOrder,
          status: isApprovedDecision ? 'Approved' : 'Rejected',
          decisionComments: comments.trim(),
          decidedAt: DateTime.now(),
          createdAt: a.createdAt,
        );
      }
      return a;
    }).toList();

    String nextStatus;
    if (!isApprovedDecision) {
      nextStatus = RequestStatus.rejected;
    } else {
      final allApproved = updatedApprovers.every((a) => a.isApproved);
      nextStatus = allApproved ? RequestStatus.approved : RequestStatus.underReview;
    }

    final updatedHistory = List<RequestHistoryRecord>.from(req.history)
      ..add(
        RequestHistoryRecord(
          id: 'hist-${req.id}-${req.history.length + 1}',
          requestId: req.id,
          actorId: currentUserId,
          actorName: currentUserName,
          actorRole: currentUserRole,
          action: isApprovedDecision ? (nextStatus == RequestStatus.approved ? 'Approved' : 'Approved Step') : 'Rejected',
          details: isApprovedDecision
              ? (nextStatus == RequestStatus.approved
                  ? 'Final approval granted. ${comments.trim()}'
                  : 'Approval step completed. ${comments.trim()}')
              : 'Request rejected: ${comments.trim()}',
          createdAt: DateTime.now(),
        ),
      );

    final updatedRecord = req.copyWith(
      status: nextStatus,
      approvers: updatedApprovers,
      history: updatedHistory,
      rejectionReason: !isApprovedDecision ? comments.trim() : req.rejectionReason,
      rejectedBy: !isApprovedDecision ? currentUserId : req.rejectedBy,
      rejectedAt: !isApprovedDecision ? DateTime.now() : req.rejectedAt,
      approvedAt: nextStatus == RequestStatus.approved ? DateTime.now() : req.approvedAt,
      updatedAt: DateTime.now(),
    );

    _mockRequests[idx] = updatedRecord;

    if (!isApprovedDecision) {
      NotificationService.safeDispatch(
        () => NotificationService.instance.notifyRequestRejected(
          requestId: updatedRecord.id,
          requestCode: updatedRecord.displayId,
          requesterUserId: updatedRecord.createdBy,
          approverName: currentUserName,
          requestTitle: updatedRecord.title,
          reason: comments.trim(),
          organizationId: updatedRecord.organizationId,
        ),
        context: 'RequestService.recordApprovalDecision (mock rejected)',
      );
    } else {
      final isCompleted = updatedRecord.isApproved || updatedRecord.isCompleted;
      NotificationService.safeDispatch(
        () => NotificationService.instance.notifyRequestApproved(
          requestId: updatedRecord.id,
          requestCode: updatedRecord.displayId,
          requesterUserId: updatedRecord.createdBy,
          approverName: currentUserName,
          requestTitle: updatedRecord.title,
          isCompleted: isCompleted,
          organizationId: updatedRecord.organizationId,
        ),
        context: 'RequestService.recordApprovalDecision (mock approved)',
      );

      if (!isCompleted && updatedRecord.approvalType == ApprovalType.sequential) {
        final pendingApprovers = updatedRecord.approvers
            .where((a) => a.isPending)
            .toList()
          ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
        if (pendingApprovers.isNotEmpty) {
          NotificationService.safeDispatch(
            () => NotificationService.instance.notifyRequestAssigned(
              requestId: updatedRecord.id,
              requestCode: updatedRecord.displayId,
              approverUserId: pendingApprovers.first.approverId,
              requestTitle: updatedRecord.title,
              organizationId: updatedRecord.organizationId,
            ),
            context: 'RequestService.recordApprovalDecision (mock next approver)',
          );
        }
      }
    }

    return updatedRecord;
  }

  // ===========================================================================
  // 6. FORWARD REQUEST
  // ===========================================================================

  Future<RequestRecord> forwardRequest({
    required String requestId,
    required String toUserId,
    required String toUserName,
    String notes = '',
    required String currentUserId,
    required String currentUserName,
    required String currentUserRole,
  }) async {
    final client = _client;
    final isLive = client != null && SupabaseConfig.isInitialized && !useMockOnly;

    if (toUserId == currentUserId) {
      throw ArgumentError('Cannot forward a request to yourself.');
    }

    if (isLive) {
      try {
        await client.rpc(
          'forward_request',
          params: {
            'p_request_id': requestId,
            'p_to_user_id': toUserId,
            'p_notes': notes.trim(),
          },
        );
        final updatedRecord = await getRequestDetails(requestId);
        NotificationService.safeDispatch(
          () => NotificationService.instance.notifyRequestForwarded(
            requestId: updatedRecord.id,
            requestCode: updatedRecord.displayId,
            delegatedToUserId: toUserId,
            forwardedByName: currentUserName,
            requestTitle: updatedRecord.title,
            organizationId: updatedRecord.organizationId,
          ),
          context: 'RequestService.forwardRequest',
        );
        return updatedRecord;
      } catch (e) {
        debugPrint('[RequestService] forwardRequest RPC error: $e');
        rethrow;
      }
    }

    // Mock
    final idx = _mockRequests.indexWhere((r) => r.id == requestId);
    if (idx == -1) throw StateError('Request not found: $requestId');

    final req = _mockRequests[idx];

    // Authorization check in mock mode:
    final isSubmitter = req.createdBy == currentUserId;
    final isApprover = req.approvers.any((a) => a.approverId == currentUserId);
    final isForwardee = req.forwards.any((f) => f.toUserId == currentUserId);
    final isManagerOrAdmin = currentUserRole.toLowerCase().contains('manager') ||
        currentUserRole.toLowerCase().contains('admin');
    if (!isSubmitter && !isApprover && !isForwardee && !isManagerOrAdmin) {
      throw StateError('Access Denied: You are not authorized to forward this request.');
    }

    final updatedForwards = List<RequestForwardRecord>.from(req.forwards)
      ..add(
        RequestForwardRecord(
          id: 'fwd-${req.id}-${req.forwards.length + 1}',
          requestId: req.id,
          fromUserId: currentUserId,
          fromUserName: currentUserName,
          toUserId: toUserId,
          toUserName: toUserName,
          notes: notes.trim(),
          createdAt: DateTime.now(),
        ),
      );

    final updatedHistory = List<RequestHistoryRecord>.from(req.history)
      ..add(
        RequestHistoryRecord(
          id: 'hist-${req.id}-${req.history.length + 1}',
          requestId: req.id,
          actorId: currentUserId,
          actorName: currentUserName,
          actorRole: currentUserRole,
          action: 'Forwarded',
          details: 'Forwarded to $toUserName. ${notes.trim()}',
          createdAt: DateTime.now(),
        ),
      );

    final updated = req.copyWith(
      forwards: updatedForwards,
      history: updatedHistory,
      updatedAt: DateTime.now(),
    );
    _mockRequests[idx] = updated;
    NotificationService.safeDispatch(
      () => NotificationService.instance.notifyRequestForwarded(
        requestId: updated.id,
        requestCode: updated.displayId,
        delegatedToUserId: toUserId,
        forwardedByName: currentUserName,
        requestTitle: updated.title,
        organizationId: updated.organizationId,
      ),
      context: 'RequestService.forwardRequest (mock)',
    );
    return updated;
  }

  // ===========================================================================
  // 7. COMPLETE REQUEST
  // ===========================================================================

  Future<RequestRecord> completeRequest({
    required String requestId,
    String notes = '',
    required String currentUserId,
    required String currentUserName,
    required String currentUserRole,
  }) async {
    final client = _client;
    final isLive = client != null && SupabaseConfig.isInitialized && !useMockOnly;

    if (isLive) {
      try {
        await client.rpc(
          'complete_request',
          params: {
            'p_request_id': requestId,
            'p_notes': notes.trim(),
          },
        );
        final updatedRecord = await getRequestDetails(requestId);
        NotificationService.safeDispatch(
          () => NotificationService.instance.notifyRequestApproved(
            requestId: updatedRecord.id,
            requestCode: updatedRecord.displayId,
            requesterUserId: updatedRecord.createdBy,
            approverName: currentUserName,
            requestTitle: updatedRecord.title,
            isCompleted: true,
            organizationId: updatedRecord.organizationId,
          ),
          context: 'RequestService.completeRequest',
        );
        return updatedRecord;
      } catch (e) {
        debugPrint('[RequestService] completeRequest RPC error: $e');
        rethrow;
      }
    }

    // Mock
    final idx = _mockRequests.indexWhere((r) => r.id == requestId);
    if (idx == -1) throw StateError('Request not found: $requestId');

    final req = _mockRequests[idx];
    if (req.status != RequestStatus.approved) {
      throw StateError('Only Approved requests can be marked Completed. Current status: ${req.status}');
    }

    // Caller authorization check in mock mode:
    // Rule: Original requester, scoped manager, or company admin.
    // Designated approvers do NOT have completion authority.
    final isSubmitter = req.createdBy == currentUserId;
    final isManagerOrAdmin = currentUserRole.toLowerCase().contains('manager') ||
        currentUserRole.toLowerCase().contains('admin');
    if (!isSubmitter && !isManagerOrAdmin) {
      throw StateError('Access Denied: You do not have authorization to mark this request as completed.');
    }

    final updatedHistory = List<RequestHistoryRecord>.from(req.history)
      ..add(
        RequestHistoryRecord(
          id: 'hist-${req.id}-${req.history.length + 1}',
          requestId: req.id,
          actorId: currentUserId,
          actorName: currentUserName,
          actorRole: currentUserRole,
          action: 'Completed',
          details: 'Work marked as Completed. ${notes.trim()}',
          createdAt: DateTime.now(),
        ),
      );

    final updated = req.copyWith(
      status: RequestStatus.completed,
      completedAt: DateTime.now(),
      completedBy: currentUserId,
      history: updatedHistory,
      updatedAt: DateTime.now(),
    );
    _mockRequests[idx] = updated;
    NotificationService.safeDispatch(
      () => NotificationService.instance.notifyRequestApproved(
        requestId: updated.id,
        requestCode: updated.displayId,
        requesterUserId: updated.createdBy,
        approverName: currentUserName,
        requestTitle: updated.title,
        isCompleted: true,
        organizationId: updated.organizationId,
      ),
      context: 'RequestService.completeRequest (mock)',
    );
    return updated;
  }

  // ===========================================================================
  // 8. ATTACHMENT DOWNLOAD / SIGNED URL
  // ===========================================================================

  /// Generates a time-limited signed URL for downloading a request attachment
  /// from the private 'documents' Supabase Storage bucket.
  Future<String> getAttachmentDownloadUrl(String filePath) async {
    final client = _client;
    final isLive = client != null && SupabaseConfig.isInitialized && !useMockOnly;

    if (filePath.trim().isEmpty) {
      throw ArgumentError('File path cannot be empty.');
    }

    if (isLive) {
      try {
        // Generates a 1-hour signed URL (3600 seconds)
        return await client.storage.from('documents').createSignedUrl(filePath, 3600);
      } catch (e) {
        debugPrint('[RequestService] getAttachmentDownloadUrl error: $e');
        rethrow;
      }
    }

    // Mock
    return 'https://mock-storage.actionflow.local/$filePath';
  }

  /// Downloads the raw binary bytes of a request attachment from Supabase Storage
  Future<Uint8List> getAttachmentBytes(String filePath) async {
    final client = _client;
    final isLive = client != null && SupabaseConfig.isInitialized && !useMockOnly;

    if (filePath.trim().isEmpty) {
      throw ArgumentError('File path cannot be empty.');
    }

    if (isLive) {
      try {
        final bytes = await client.storage.from('documents').download(filePath);
        return bytes;
      } catch (e) {
        debugPrint('[RequestService] getAttachmentBytes error: $e');
        rethrow;
      }
    }

    // Mock fallback
    return Uint8List(0);
  }

  /// Downloads a request attachment and prompts browser or platform filesystem to save it
  Future<bool> downloadAttachment({
    required RequestAttachmentRecord attachment,
  }) async {
    final bytes = await getAttachmentBytes(attachment.filePath);
    if (bytes.isEmpty) {
      throw StateError('Attachment content is empty.');
    }
    return await AppFilePicker.saveFile(
      fileName: attachment.fileName,
      bytes: bytes,
      mimeType: attachment.contentType.isNotEmpty
          ? attachment.contentType
          : 'application/octet-stream',
    );
  }

  // ===========================================================================
  // 8B. RESUBMIT REJECTED REQUEST
  // ===========================================================================

  /// Allows the original requester to respond to rejection comments and resubmit
  /// their request into the approval workflow.
  Future<RequestRecord> resubmitRequest({
    required String requestId,
    required String currentUserId,
    required String currentUserName,
    required String currentUserRole,
    String? comments,
    String? additionalNotes,
  }) async {
    final client = _client;
    final isLive = client != null && SupabaseConfig.isInitialized && !useMockOnly;

    if (isLive) {
      try {
        await client.rpc(
          'resubmit_request',
          params: {
            'p_request_id': requestId,
            'p_comments': comments?.trim() ?? '',
            'p_additional_notes': ?additionalNotes?.trim(),
          },
        );
        final updatedRecord = await getRequestDetails(requestId);
        return updatedRecord;
      } catch (e) {
        debugPrint('[RequestService] resubmitRequest RPC error: $e');
        rethrow;
      }
    }

    // Mock implementation
    final idx = _mockRequests.indexWhere((r) => r.id == requestId);
    if (idx == -1) throw StateError('Request not found: $requestId');

    final req = _mockRequests[idx];
    if (!req.isRejected) {
      throw StateError('Only rejected requests can be resubmitted. Current status: ${req.status}');
    }

    final updatedApprovers = req.approvers.map((a) => RequestApproverRecord(
      id: a.id,
      requestId: a.requestId,
      approverId: a.approverId,
      approverName: a.approverName,
      approverRole: a.approverRole,
      approverDepartment: a.approverDepartment,
      stepOrder: a.stepOrder,
      status: 'Pending',
      decisionComments: '',
      decidedAt: null,
      createdAt: a.createdAt,
    )).toList();

    final updatedHistory = List<RequestHistoryRecord>.from(req.history)
      ..add(
        RequestHistoryRecord(
          id: 'hist-${DateTime.now().millisecondsSinceEpoch}',
          requestId: requestId,
          actorId: currentUserId,
          actorName: currentUserName,
          actorRole: currentUserRole,
          action: 'Resubmitted',
          details: comments != null && comments.trim().isNotEmpty
              ? 'Requester responded and resubmitted: ${comments.trim()}'
              : 'Request resubmitted for approval.',
          createdAt: DateTime.now(),
        ),
      );

    final updatedRecord = req.copyWith(
      status: RequestStatus.pending,
      approvers: updatedApprovers,
      history: updatedHistory,
      clearRejection: true,
      additionalNotes: additionalNotes ?? req.additionalNotes,
      updatedAt: DateTime.now(),
    );

    _mockRequests[idx] = updatedRecord;
    return updatedRecord;
  }

  // ===========================================================================
  // 8B. PERMANENTLY DELETE APPROVED REQUEST
  // ===========================================================================

  /// Permanently deletes an Approved request, cleans up associated notifications,
  /// and queues exclusive physical attachments into public.storage_deletion_queue
  /// using the secure public.delete_approved_request RPC function.
  Future<RequestDeletionResult> deleteApprovedRequest({
    required String requestId,
  }) async {
    if (useMockOnly) {
      final idx = _mockRequests.indexWhere((r) => r.id == requestId);
      if (idx == -1) {
        throw Exception('Request not found: $requestId');
      }
      final req = _mockRequests[idx];
      if (!req.isApproved) {
        throw Exception('Validation error: Only Approved requests can be permanently deleted (current status: ${req.status})');
      }
      _mockRequests.removeAt(idx);
      final hasAttachments = req.attachments.isNotEmpty;
      return RequestDeletionResult(
        success: true,
        requestId: req.id,
        displayId: req.displayId,
        queuedStorageFilesCount: hasAttachments ? req.attachments.length : 0,
        deletedNotificationsCount: 1,
        storageCleanupStatus: hasAttachments ? 'queued' : 'none',
      );
    }

    final client = _client;
    if (client == null) {
      throw Exception('Supabase client is not initialized');
    }

    try {
      final dynamic response = await client.rpc(
        'delete_approved_request',
        params: {'p_request_id': requestId},
      );

      if (response is Map) {
        final Map<String, dynamic> respMap = Map<String, dynamic>.from(response);
        final result = RequestDeletionResult.fromJson(respMap);

        if (!result.success) {
          throw Exception('Failed to delete request: server returned success = false');
        }

        // If exclusive files were queued, asynchronously trigger the queue processing Edge Function.
        // We log any error explicitly without swallowing it silently.
        if (result.queuedStorageFilesCount > 0) {
          try {
            final funcRes = await client.functions.invoke(
              'process-storage-deletion-queue',
              body: {'batch_size': 50},
            );
            if (funcRes.status == 200) {
              debugPrint('[RequestService] Storage queue worker triggered successfully');
            } else {
              debugPrint('[RequestService] Storage queue worker returned status ${funcRes.status}: ${funcRes.data}');
            }
          } catch (funcErr) {
            // Logged clearly; the queue in PostgreSQL safely persists the pending state with retry
            debugPrint('[RequestService] Note: Asynchronous storage queue worker trigger error: $funcErr. Queue will be retried automatically.');
          }
        }

        return result;
      }

      throw Exception('Unexpected response format from delete_approved_request: $response');
    } catch (e) {
      debugPrint('[RequestService] Error deleting approved request: $e');
      rethrow;
    }
  }

  // ===========================================================================
  // 9. STAFF APPROVAL PERMISSION CHECK
  // ===========================================================================

  /// Returns true if the staff member is explicitly assigned as an approver on
  /// at least one request.
  Future<bool> hasStaffApprovalAuthority({
    required String userId,
    required String organizationId,
  }) async {
    final client = _client;
    final isLive = client != null && SupabaseConfig.isInitialized && !useMockOnly;

    if (isLive) {
      try {
        final dynamic res = await client
            .from('request_approvers')
            .select('id')
            .eq('organization_id', organizationId)
            .eq('approver_id', userId)
            .limit(1);

        if (res is List && res.isNotEmpty) {
          return true;
        }
        return false;
      } catch (e) {
        debugPrint('[RequestService] hasStaffApprovalAuthority error: $e');
        return false;
      }
    }

    // Mock check
    return _mockRequests.any((r) => r.approvers.any((a) => a.approverId == userId));
  }

  // ===========================================================================
  // 10. DASHBOARD REQUEST OVERVIEW COUNTS
  // ===========================================================================

  /// Aggregates request counts for the Manager Dashboard Request Overview section.
  /// Respects manager supervisory scope (departments/sites/organization) and prevents duplicate counts.
  Future<ManagerRequestOverviewCounts> getManagerRequestOverviewCounts({
    required String userId,
    required String organizationId,
    bool isCompanyAdmin = false,
    Set<String>? scopedDepartmentIds,
    Set<String>? scopedSiteIds,
    List<String>? scopedDepartmentNames,
    List<String>? scopedSiteNames,
  }) async {
    final client = _client;
    final isLive = client != null && SupabaseConfig.isInitialized && !useMockOnly;

    if (isLive) {
      try {
        // Hardened: RPC derives organization, role, and supervisory scope
        // strictly server-side from auth.uid() and public.manager_scopes.
        final dynamic res = await client.rpc('get_manager_request_metrics');

        if (res is Map) {
          final map = Map<String, dynamic>.from(res);
          return ManagerRequestOverviewCounts(
            total: (map['total'] as num?)?.toInt() ?? 0,
            pendingMyApproval: (map['pending_my_approval'] as num?)?.toInt() ?? 0,
            underReview: (map['under_review'] as num?)?.toInt() ?? 0,
            approved: (map['approved'] as num?)?.toInt() ?? 0,
            rejected: (map['rejected'] as num?)?.toInt() ?? 0,
            completed: (map['completed'] as num?)?.toInt() ?? 0,
          );
        }
      } catch (e) {
        debugPrint('[RequestService] getManagerRequestOverviewCounts RPC error: $e');
        rethrow;
      }
    }

    // Mock computation
    final inScopeMock = _mockRequests.where((r) {
      if (isCompanyAdmin) return true;
      final hasDeptScope = (scopedDepartmentIds != null && scopedDepartmentIds.isNotEmpty) ||
          (scopedDepartmentNames != null && scopedDepartmentNames.isNotEmpty);
      final hasSiteScope = (scopedSiteIds != null && scopedSiteIds.isNotEmpty) ||
          (scopedSiteNames != null && scopedSiteNames.isNotEmpty);

      if (!hasDeptScope && !hasSiteScope) return true;

      final matchesDept = (scopedDepartmentIds != null && scopedDepartmentIds.contains(r.departmentId)) ||
          (scopedDepartmentNames != null && scopedDepartmentNames.contains(r.departmentName));
      final matchesSite = (scopedSiteIds != null && scopedSiteIds.contains(r.siteId)) ||
          (scopedSiteNames != null && scopedSiteNames.contains(r.siteName));

      if (hasDeptScope && hasSiteScope) return matchesDept && matchesSite;
      return matchesDept || matchesSite;
    }).toList();

    int total = inScopeMock.length;
    int underReview = inScopeMock.where((r) => r.isUnderReview || r.isPending).length;
    int approved = inScopeMock.where((r) => r.isApproved).length;
    int rejected = inScopeMock.where((r) => r.isRejected).length;
    int completed = inScopeMock.where((r) => r.isCompleted).length;
    int pendingMyApproval = inScopeMock.where((r) => r.canUserApprove(userId)).length;

    return ManagerRequestOverviewCounts(
      total: total,
      pendingMyApproval: pendingMyApproval,
      underReview: underReview,
      approved: approved,
      rejected: rejected,
      completed: completed,
    );
  }

  /// Aggregates request counts for the Staff Dashboard Request Overview section.
  /// Only counts requests submitted by the authenticated Staff member, plus
  /// Pending My Approval if the staff member is a designated approver.
  Future<StaffRequestOverviewCounts> getStaffRequestOverviewCounts({
    required String userId,
    required String organizationId,
    bool hasApprovalAuthority = false,
  }) async {
    final client = _client;
    final isLive = client != null && SupabaseConfig.isInitialized && !useMockOnly;

    if (isLive) {
      try {
        // Hardened: RPC derives organization, caller identity, and approval authority
        // strictly server-side from auth.uid() and public.request_approvers.
        final dynamic res = await client.rpc('get_staff_request_metrics');

        if (res is Map) {
          final map = Map<String, dynamic>.from(res);
          return StaffRequestOverviewCounts(
            mySubmittedTotal: (map['my_submitted_total'] as num?)?.toInt() ?? 0,
            pendingApproval: (map['pending_approval'] as num?)?.toInt() ?? 0,
            underReview: (map['under_review'] as num?)?.toInt() ?? 0,
            approved: (map['approved'] as num?)?.toInt() ?? 0,
            rejected: (map['rejected'] as num?)?.toInt() ?? 0,
            completed: (map['completed'] as num?)?.toInt() ?? 0,
            pendingMyApproval: (map['pending_my_approval'] as num?)?.toInt(),
          );
        }
      } catch (e) {
        debugPrint('[RequestService] getStaffRequestOverviewCounts RPC error: $e');
        rethrow;
      }
    }

    // Mock computation
    final myRequests = _mockRequests.where((r) => r.createdBy == userId).toList();
    final total = myRequests.length;
    final pending = myRequests.where((r) => r.status.toLowerCase() == 'pending').length;
    final underReview = myRequests.where((r) => r.status.toLowerCase() == 'under review').length;
    final approved = myRequests.where((r) => r.isApproved).length;
    final rejected = myRequests.where((r) => r.isRejected).length;
    final completed = myRequests.where((r) => r.isCompleted).length;

    int? pendingMyApproval;
    if (hasApprovalAuthority) {
      pendingMyApproval = _mockRequests.where((r) => r.canUserApprove(userId)).length;
    }

    return StaffRequestOverviewCounts(
      mySubmittedTotal: total,
      pendingApproval: pending,
      underReview: underReview,
      approved: approved,
      rejected: rejected,
      completed: completed,
      pendingMyApproval: pendingMyApproval,
    );
  }

  /// Aggregates independent summary counts for the Request Approval screen.
  /// Counts all requests in the authorized scope, independent of which tab is active:
  /// - [myActionRequired]: Requests awaiting the caller's approval (respects sequential order)
  /// - [totalInScope]: Total requests in scope
  /// - [approved]: Total approved requests in scope
  /// - [rejected]: Total rejected requests in scope
  Future<RequestApprovalSummaryCounts> getApprovalSummaryCounts({
    required String userId,
    required String organizationId,
    required bool isManager,
    String? departmentId,
    String? siteId,
    DateTime? startDate,
    DateTime? endDate,
    String? requestType,
    String? priority,
  }) async {
    final client = _client;
    final isLive = client != null && SupabaseConfig.isInitialized && !useMockOnly;

    if (isLive) {
      try {
        var query = client
            .from('requests')
            .select(isManager ? '*, request_approvers (*)' : '*, request_approvers!inner (*)')
            .eq('organization_id', organizationId);

        if (!isManager) {
          query = query.eq('request_approvers.approver_id', userId);
        }

        if (requestType != null && requestType.isNotEmpty && requestType != 'All Types') {
          query = query.eq('request_type', requestType);
        }
        if (priority != null && priority.isNotEmpty && priority != 'All Priorities') {
          query = query.ilike('priority', priority);
        }
        if (departmentId != null && departmentId.isNotEmpty && departmentId != 'All Departments' && departmentId != 'all') {
          query = query.or('department_id.eq.$departmentId,department_name.ilike.$departmentId');
        }
        if (siteId != null && siteId.isNotEmpty && siteId != 'All Sites' && siteId != 'all') {
          query = query.or('site_id.eq.$siteId,site_name.ilike.$siteId');
        }
        if (startDate != null) {
          query = query.gte('required_by_date', startDate.toIso8601String().substring(0, 10));
        }
        if (endDate != null) {
          query = query.lte('required_by_date', endDate.toIso8601String().substring(0, 10));
        }

        final dynamic raw = await query;
        final items = (raw is List)
            ? raw.map((e) => RequestRecord.fromJson(Map<String, dynamic>.from(e as Map))).toList()
            : <RequestRecord>[];

        final Set<String> seenIds = {};
        int myActionRequired = 0;
        int underReview = 0;
        int totalInScope = 0;
        int approved = 0;
        int rejected = 0;

        for (final r in items) {
          if (seenIds.contains(r.id)) continue;
          seenIds.add(r.id);
          totalInScope++;
          if (r.canUserApprove(userId)) {
            myActionRequired++;
          }
          if (r.isUnderReview || r.isPending) {
            underReview++;
          }
          if (r.isApproved) {
            approved++;
          } else if (r.isRejected) {
            rejected++;
          }
        }

        return RequestApprovalSummaryCounts(
          myActionRequired: myActionRequired,
          underReview: underReview,
          totalInScope: totalInScope,
          approved: approved,
          rejected: rejected,
        );
      } catch (e) {
        debugPrint('[RequestService] getApprovalSummaryCounts error: $e');
        // Fall through to mock computation
      }
    }

    // Mock computation
    var inScope = isManager
        ? List<RequestRecord>.from(_mockRequests)
        : _mockRequests.where((r) => r.approvers.any((a) => a.approverId == userId)).toList();

    inScope = inScope.where((r) => r.organizationId.isEmpty || r.organizationId == organizationId).toList();

    if (requestType != null && requestType.isNotEmpty && requestType != 'All Types') {
      inScope = inScope.where((r) => r.requestType == requestType).toList();
    }
    if (priority != null && priority.isNotEmpty && priority != 'All Priorities') {
      inScope = inScope.where((r) => r.priority.toLowerCase() == priority.toLowerCase()).toList();
    }
    if (departmentId != null && departmentId.isNotEmpty && departmentId != 'All Departments' && departmentId != 'all') {
      inScope = inScope.where((r) =>
          r.departmentId == departmentId ||
          r.departmentName.toLowerCase() == departmentId.toLowerCase()).toList();
    }
    if (siteId != null && siteId.isNotEmpty && siteId != 'All Sites' && siteId != 'all') {
      inScope = inScope.where((r) =>
          r.siteId == siteId ||
          r.siteName.toLowerCase() == siteId.toLowerCase()).toList();
    }
    if (startDate != null) {
      inScope = inScope.where((r) {
        final d = DateTime.tryParse(r.requiredByDate);
        return d != null && !d.isBefore(startDate);
      }).toList();
    }
    if (endDate != null) {
      inScope = inScope.where((r) {
        final d = DateTime.tryParse(r.requiredByDate);
        return d != null && !d.isAfter(endDate);
      }).toList();
    }

    final Set<String> seenIds = {};
    int myActionRequired = 0;
    int underReview = 0;
    int totalInScope = 0;
    int approved = 0;
    int rejected = 0;

    for (final r in inScope) {
      if (seenIds.contains(r.id)) continue;
      seenIds.add(r.id);
      totalInScope++;
      if (r.canUserApprove(userId)) {
        myActionRequired++;
      }
      if (r.isUnderReview || r.isPending) {
        underReview++;
      }
      if (r.isApproved) {
        approved++;
      } else if (r.isRejected) {
        rejected++;
      }
    }

    return RequestApprovalSummaryCounts(
      myActionRequired: myActionRequired,
      underReview: underReview,
      totalInScope: totalInScope,
      approved: approved,
      rejected: rejected,
    );
  }
}
