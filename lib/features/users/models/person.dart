import '../../auth/models/manager_scope_item.dart';
import 'team.dart';

export '../../auth/models/manager_scope_item.dart';

enum PersonType { internalUser, externalWorker }

class Person {
  Person({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.designation,
    required this.type,
    required this.isActive,
    this.role = UserRole.actionOwnerWorker,
    this.teamIds = const [],
    this.teamNames = const [],
    this.managerScopes = const [],
    this.department = '',
    this.site = '',
    this.company = '',
    this.notes = '',
    this.departmentId,
    this.siteId,
    this.roleId,
    this.organizationId,
  });

  final String id;
  final String name;
  final String email;
  final String phone;
  final String designation;
  final PersonType type;
  final bool isActive;
  final UserRole role;
  final List<String> teamIds;
  final List<String> teamNames;
  final List<ManagerScopeItem> managerScopes;

  /// Effective scopes for this person: managerScopes if Manager,
  /// with fallback to primary department + site if scopes list is empty.
  List<ManagerScopeItem> get scopes {
    if (role == UserRole.departmentManager) {
      if (managerScopes.isNotEmpty) return managerScopes;
      if (departmentId != null && departmentId!.isNotEmpty) {
        return [
          ManagerScopeItem(
            departmentId: departmentId!,
            departmentName: department,
            siteId: siteId ?? '',
            siteName: site,
          ),
        ];
      }
      return const [];
    } else {
      if (departmentId != null && departmentId!.isNotEmpty) {
        return [
          ManagerScopeItem(
            departmentId: departmentId!,
            departmentName: department,
            siteId: siteId ?? '',
            siteName: site,
          ),
        ];
      }
      return const [];
    }
  }

  /// Whether the user has operational authorization for the given (departmentId, siteId) scope.
  bool isScopePermitted(String? deptId, String? stId) {
    if (deptId == null || deptId.isEmpty) return false;
    for (final s in scopes) {
      if (s.departmentId == deptId && (stId == null || stId.isEmpty || s.siteId == stId)) {
        return true;
      }
    }
    return (departmentId == deptId && (stId == null || stId.isEmpty || siteId == stId));
  }
  final String department;
  final String site;
  final String company;
  final String notes;
  final String? departmentId;
  final String? siteId;
  final String? roleId;
  final String? organizationId;

  String get typeLabel => type == PersonType.internalUser
      ? 'Internal ActionFlow User'
      : 'External User';

  String get roleLabel => role.label;

  Person copyWith({
    String? name,
    String? email,
    String? phone,
    String? designation,
    bool? isActive,
    String? department,
    String? site,
    String? company,
    String? notes,
    UserRole? role,
    List<String>? teamIds,
    List<String>? teamNames,
    List<ManagerScopeItem>? managerScopes,
    String? departmentId,
    String? siteId,
    String? roleId,
    String? organizationId,
  }) {
    return Person(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      designation: designation ?? this.designation,
      type: type,
      isActive: isActive ?? this.isActive,
      role: role ?? this.role,
      teamIds: teamIds ?? this.teamIds,
      teamNames: teamNames ?? this.teamNames,
      managerScopes: managerScopes ?? this.managerScopes,
      department: department ?? this.department,
      site: site ?? this.site,
      company: company ?? this.company,
      notes: notes ?? this.notes,
      departmentId: departmentId ?? this.departmentId,
      siteId: siteId ?? this.siteId,
      roleId: roleId ?? this.roleId,
      organizationId: organizationId ?? this.organizationId,
    );
  }
}

class ActionPersonReference {
  const ActionPersonReference({
    required this.personId,
    required this.name,
    required this.type,
    this.email = '',
    this.phone = '',
    this.designation = '',
    this.department = '',
    this.site = '',
    this.company = '',
    this.notes = '',
    this.role = '',
    this.teamIds = const [],
    this.departmentId,
    this.siteId,
  });

  final String personId;
  final String name;
  final PersonType type;
  final String email;
  final String phone;
  final String designation;
  final String department;
  final String site;
  final String company;
  final String notes;
  final String role;
  final List<String> teamIds;
  final String? departmentId;
  final String? siteId;

  String get typeLabel =>
      type == PersonType.internalUser ? 'Internal' : 'External';

  bool get isValidUuid => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(personId.trim());

  bool get isManager {
    final r = role.toLowerCase().trim();
    if (r.isNotEmpty) {
      return r == 'manager' ||
          r == 'departmentmanager' ||
          r == 'department_manager' ||
          r == 'company_admin' ||
          r == 'platform_admin' ||
          r == 'admin';
    }
    final d = designation.toLowerCase().trim();
    return d.contains('manager') || d.contains('admin') || d.contains('director');
  }

  bool get isStaff {
    final r = role.toLowerCase().trim();
    if (r.isNotEmpty) {
      return r == 'staff' ||
          r == 'worker' ||
          r == 'actionownerworker' ||
          r == 'action_owner_worker';
    }
    return !isManager;
  }

  ActionPersonReference copyWith({
    String? personId,
    String? name,
    PersonType? type,
    String? email,
    String? phone,
    String? designation,
    String? department,
    String? site,
    String? company,
    String? notes,
    String? role,
    List<String>? teamIds,
    String? departmentId,
    String? siteId,
  }) {
    return ActionPersonReference(
      personId: personId ?? this.personId,
      name: name ?? this.name,
      type: type ?? this.type,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      designation: designation ?? this.designation,
      department: department ?? this.department,
      site: site ?? this.site,
      company: company ?? this.company,
      notes: notes ?? this.notes,
      role: role ?? this.role,
      teamIds: teamIds ?? this.teamIds,
      departmentId: departmentId ?? this.departmentId,
      siteId: siteId ?? this.siteId,
    );
  }

  Map<String, dynamic> toJson() => {
    'person_id': personId,
    'name': name,
    'type': type == PersonType.externalWorker ? 'external' : 'internal',
    'email': email,
    'phone': phone,
    'designation': designation,
    'department': department,
    'site': site,
    'company': company,
    'notes': notes,
    'role': role,
    'team_ids': teamIds,
    if (departmentId != null) 'department_id': departmentId,
    if (siteId != null) 'site_id': siteId,
  };

  factory ActionPersonReference.fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] as String?) ?? 'internal';
    final rawTeams = json['team_ids'] ?? json['teamIds'];
    final parsedTeams = rawTeams is List
        ? rawTeams.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
        : const <String>[];
    return ActionPersonReference(
      personId: (json['person_id'] as String?) ??
          (json['personId'] as String?) ??
          '',
      name: (json['name'] as String?) ?? '',
      type: (rawType == 'external' || rawType == PersonType.externalWorker.name)
          ? PersonType.externalWorker
          : PersonType.internalUser,
      email: (json['email'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
      designation: (json['designation'] as String?) ?? '',
      department: (json['department'] as String?) ?? '',
      site: (json['site'] as String?) ?? '',
      company: (json['company'] as String?) ?? '',
      notes: (json['notes'] as String?) ?? '',
      role: (json['role'] as String?) ?? '',
      teamIds: parsedTeams,
      departmentId: (json['department_id'] as String?) ?? (json['departmentId'] as String?),
      siteId: (json['site_id'] as String?) ?? (json['siteId'] as String?),
    );
  }
}
