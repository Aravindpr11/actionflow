import 'package:flutter/material.dart';

import '../features/dashboard/manager_dashboard/models/action_record.dart';
import '../features/requests/models/request_models.dart';
import '../features/requests/services/request_service.dart';
import 'action_service.dart';

/// Distinguishes the type of record returned by global search.
enum SearchResultType {
  action,
  request,
}

/// Normalized search result representation for ActionFlow autocomplete dropdown.
class SearchResultItem {
  final String id;
  final String referenceNumber; // e.g., 'ACT-1001' or 'REQ-1004'
  final String title;
  final String subtitle;
  final String? description;
  final SearchResultType type;
  final String status;
  final Color statusColor;
  final dynamic rawRecord; // ActionRecord or RequestRecord

  const SearchResultItem({
    required this.id,
    required this.referenceNumber,
    required this.title,
    required this.subtitle,
    this.description,
    required this.type,
    required this.status,
    required this.statusColor,
    this.rawRecord,
  });

  bool get isAction => type == SearchResultType.action;
  bool get isRequest => type == SearchResultType.request;
}

/// Service providing unified, role-aware, organization-isolated search across Actions and Requests.
class GlobalSearchService {
  static final GlobalSearchService instance = GlobalSearchService._();
  GlobalSearchService._();

  /// Resolves status color for Action records.
  Color _getActionStatusColor(String status) {
    switch (status.trim().toLowerCase()) {
      case 'completed':
      case 'closed':
      case 'verified':
        return const Color(0xFF16A34A);
      case 'in progress':
      case 'active':
        return const Color(0xFF0284C7);
      case 'overdue':
        return const Color(0xFFDC2626);
      case 'pending review':
      case 'ready for review':
      case 'under review':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF64748B);
    }
  }

  /// Searches Actions and Requests based on query string and user permissions.
  ///
  /// - Fast path: Searches [cachedActions] in-memory if provided.
  /// - Network path: Queries Supabase Actions and Requests respecting RLS and tenant isolation.
  Future<List<SearchResultItem>> search({
    required String query,
    required String organizationId,
    required String currentUserId,
    required String currentUserRole,
    List<ActionRecord>? cachedActions,
    bool includeActions = true,
    bool includeRequests = true,
    int limit = 10,
  }) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) {
      return const <SearchResultItem>[];
    }

    final List<SearchResultItem> actionResults = [];
    final List<SearchResultItem> requestResults = [];

    // 1. Search Actions
    if (includeActions) {
      try {
        List<ActionRecord> actionsToSearch = [];

        final isManager = currentUserRole.toLowerCase().contains('manager') ||
            currentUserRole.toLowerCase().contains('admin');

        if (cachedActions != null && cachedActions.isNotEmpty) {
          // Defensively scope in-memory actions to prevent any cross-tenant or cross-user leakage
          actionsToSearch = cachedActions.where((act) {
            // 1. Organization isolation
            if (organizationId.trim().isNotEmpty &&
                act.organizationId.trim().isNotEmpty &&
                act.organizationId.trim().toLowerCase() !=
                    organizationId.trim().toLowerCase()) {
              return false;
            }
            // 2. Staff user isolation
            if (!isManager && currentUserId.trim().isNotEmpty) {
              final uid = currentUserId.trim().toLowerCase();
              final isAssigned = (act.assignedToId?.trim().toLowerCase() == uid) ||
                  (act.createdById.trim().toLowerCase() == uid) ||
                  act.assignees.any((a) => a.profileId.trim().toLowerCase() == uid) ||
                  act.additionalPeople.any((p) => p.personId.trim().toLowerCase() == uid) ||
                  act.contributors.any((c) => c.profileId.trim().toLowerCase() == uid);
              if (!isAssigned) return false;
            }
            return true;
          }).toList();
        } else {
          // Fetch from ActionService respecting role
          if (isManager) {
            actionsToSearch = await ActionService.instance.fetchManagerActions(
              organizationId: organizationId,
              searchQuery: cleanQuery,
            );
          } else {
            actionsToSearch = await ActionService.instance.fetchMyActions(
              organizationId: organizationId,
              userId: currentUserId,
              searchQuery: cleanQuery,
            );
          }
        }

        for (final act in actionsToSearch) {
          final ref = act.displayId.toLowerCase();
          final subject = act.subject.toLowerCase();
          final desc = act.actionRequired.toLowerCase();
          final assignee = act.assignedTo.toLowerCase();
          final dept = act.department.toLowerCase();
          final site = act.site.toLowerCase();
          final status = act.status.toLowerCase();

          if (ref.contains(cleanQuery) ||
              subject.contains(cleanQuery) ||
              desc.contains(cleanQuery) ||
              assignee.contains(cleanQuery) ||
              dept.contains(cleanQuery) ||
              site.contains(cleanQuery) ||
              status.contains(cleanQuery)) {
            final deptInfo = act.department.isNotEmpty ? act.department : 'General';
            final siteInfo = act.site.isNotEmpty ? ' • ${act.site}' : '';
            final assignInfo = act.assignedTo.isNotEmpty ? ' • ${act.assignedTo}' : '';

            actionResults.add(
              SearchResultItem(
                id: act.id,
                referenceNumber: act.displayId,
                title: act.subject,
                subtitle: '$deptInfo$siteInfo$assignInfo',
                description: act.actionRequired,
                type: SearchResultType.action,
                status: act.status,
                statusColor: _getActionStatusColor(act.status),
                rawRecord: act,
              ),
            );
          }

          if (actionResults.length >= limit) break;
        }
      } catch (e, st) {
        debugPrint('[GlobalSearchService] Error searching actions: $e\n$st');
      }
    }

    // 2. Search Requests
    if (includeRequests) {
      try {
        final isManager = currentUserRole.toLowerCase().contains('manager') ||
            currentUserRole.toLowerCase().contains('admin');

        List<RequestRecord> requests = [];

        if (isManager) {
          // Managers see approval requests & my requests in their scope
          final approvalRes = await RequestService.instance.getApprovalRequests(
            userId: currentUserId,
            organizationId: organizationId,
            isManager: true,
            tabIndex: 4, // All requests in scope
            searchQuery: cleanQuery,
            pageSize: limit,
          );
          requests.addAll(approvalRes.items);
        } else {
          // Staff see my requests and requests assigned to them for approval
          final myRes = await RequestService.instance.getMyRequests(
            userId: currentUserId,
            organizationId: organizationId,
            searchQuery: cleanQuery,
            pageSize: limit,
          );
          requests.addAll(myRes.items);

          final assignedRes = await RequestService.instance.getApprovalRequests(
            userId: currentUserId,
            organizationId: organizationId,
            isManager: false,
            searchQuery: cleanQuery,
            pageSize: limit,
          );
          for (final req in assignedRes.items) {
            if (!requests.any((r) => r.id == req.id)) {
              requests.add(req);
            }
          }
        }

        for (final req in requests) {
          final ref = req.displayId.toLowerCase();
          final title = req.title.toLowerCase();
          final desc = req.description.toLowerCase();
          final type = req.requestType.toLowerCase();
          final requester = req.createdByName.toLowerCase();
          final dept = req.departmentName.toLowerCase();
          final site = req.siteName.toLowerCase();
          final status = req.status.toLowerCase();

          if (ref.contains(cleanQuery) ||
              title.contains(cleanQuery) ||
              desc.contains(cleanQuery) ||
              type.contains(cleanQuery) ||
              requester.contains(cleanQuery) ||
              dept.contains(cleanQuery) ||
              site.contains(cleanQuery) ||
              status.contains(cleanQuery)) {
            final typeInfo = req.requestType.isNotEmpty ? req.requestType : 'Request';
            final deptInfo = req.departmentName.isNotEmpty ? ' • ${req.departmentName}' : '';
            final byInfo = req.createdByName.isNotEmpty ? ' • By: ${req.createdByName}' : '';

            requestResults.add(
              SearchResultItem(
                id: req.id,
                referenceNumber: req.displayId,
                title: req.title,
                subtitle: '$typeInfo$deptInfo$byInfo',
                description: req.description,
                type: SearchResultType.request,
                status: req.status,
                statusColor: RequestStatus.getColor(req.status),
                rawRecord: req,
              ),
            );
          }

          if (requestResults.length >= limit) break;
        }
      } catch (e, st) {
        debugPrint('[GlobalSearchService] Error searching requests: $e\n$st');
      }
    }

    // Combine results, prioritizing exact reference prefix matches (e.g. 'act' or 'req')
    final List<SearchResultItem> combined = [];

    // Exact reference match first
    final exactRefMatches = [...actionResults, ...requestResults].where(
      (r) => r.referenceNumber.toLowerCase().startsWith(cleanQuery),
    );
    combined.addAll(exactRefMatches);

    // Title matches next
    for (final r in [...actionResults, ...requestResults]) {
      if (!combined.contains(r) && r.title.toLowerCase().contains(cleanQuery)) {
        combined.add(r);
      }
    }

    // Remaining matches
    for (final r in [...actionResults, ...requestResults]) {
      if (!combined.contains(r)) {
        combined.add(r);
      }
    }

    if (combined.length > limit) {
      return combined.sublist(0, limit);
    }
    return combined;
  }
}
