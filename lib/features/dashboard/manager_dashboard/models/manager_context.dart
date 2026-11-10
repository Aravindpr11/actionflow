import 'package:action_flow/features/auth/models/manager_scope_item.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';

/// Single source of truth for an authenticated Manager's organizational
/// authority and permitted Department + Site management scopes.
class ManagerContext {
  final String authUserId;
  final UserProfile profile;
  final String organizationId;
  final String organizationName;
  final List<ManagerScopeItem> scopes;
  final bool isActive;

  const ManagerContext({
    required this.authUserId,
    required this.profile,
    required this.organizationId,
    required this.organizationName,
    required this.scopes,
    this.isActive = true,
  });

  /// Set of unique department UUIDs the manager is authorized to supervise
  Set<String> get scopedDepartmentIds =>
      scopes.map((s) => s.departmentId).where((id) => id.isNotEmpty).toSet();

  /// Set of unique site UUIDs the manager is authorized to supervise
  Set<String> get scopedSiteIds =>
      scopes.map((s) => s.siteId).where((id) => id.isNotEmpty).toSet();

  /// Sorted list of unique department names
  List<String> get scopedDepartmentNames {
    final names = scopes.map((s) => s.departmentName).toSet().toList();
    names.sort();
    return names;
  }

  /// Sorted list of unique site names
  List<String> get scopedSiteNames {
    final names = scopes.map((s) => s.siteName).toSet().toList();
    names.sort();
    return names;
  }

  /// True if the manager has at least one active management scope
  bool get hasScopes => scopes.isNotEmpty;

  /// True if the user profile has a manager or administrative role
  bool get isManager =>
      profile.role.toLowerCase() == 'manager' ||
      profile.role.toLowerCase() == 'admin' ||
      profile.role.toLowerCase() == 'company_admin' ||
      profile.role.toLowerCase() == 'platform_admin';

  /// Active management scopes
  List<ManagerScopeItem> get activeScopes => scopes;

  /// Validates whether the manager has explicit supervisory authority over
  /// the given Department ID and Site ID combination.
  bool isScopePermitted(String departmentId, String siteId) {
    if (departmentId.isEmpty || siteId.isEmpty) return false;
    return scopes.any(
      (s) => s.departmentId == departmentId && s.siteId == siteId,
    );
  }

  /// Returns all permitted scopes for a specific department UUID
  List<ManagerScopeItem> scopesForDepartment(String departmentId) {
    return scopes.where((s) => s.departmentId == departmentId).toList();
  }

  /// Returns all permitted sites for a specific department name
  List<String> permittedSiteNamesForDepartmentName(String departmentName) {
    if (departmentName.isEmpty || departmentName == 'All Departments') {
      return scopedSiteNames;
    }
    final matched = scopes.where(
      (s) =>
          s.departmentName.trim().toLowerCase() ==
          departmentName.trim().toLowerCase(),
    );
    final names = matched.map((s) => s.siteName).toSet().toList();
    names.sort();
    return names;
  }

  /// Looks up a scope by department and site UUIDs
  ManagerScopeItem? findScopeByIds(String departmentId, String siteId) {
    try {
      return scopes.firstWhere(
        (s) => s.departmentId == departmentId && s.siteId == siteId,
      );
    } catch (_) {
      return null;
    }
  }

  /// Looks up a scope by department and site names
  ManagerScopeItem? findScopeByNames(String departmentName, String siteName) {
    try {
      return scopes.firstWhere(
        (s) =>
            s.departmentName.trim().toLowerCase() ==
                departmentName.trim().toLowerCase() &&
            s.siteName.trim().toLowerCase() == siteName.trim().toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }

  ManagerContext copyWith({
    String? authUserId,
    UserProfile? profile,
    String? organizationId,
    String? organizationName,
    List<ManagerScopeItem>? scopes,
    bool? isActive,
  }) {
    return ManagerContext(
      authUserId: authUserId ?? this.authUserId,
      profile: profile ?? this.profile,
      organizationId: organizationId ?? this.organizationId,
      organizationName: organizationName ?? this.organizationName,
      scopes: scopes ?? this.scopes,
      isActive: isActive ?? this.isActive,
    );
  }
}
