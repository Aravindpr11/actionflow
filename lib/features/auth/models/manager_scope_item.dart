/// Represents an individual Department + Site management scope combination.
/// A Manager has one or more discrete (Department ID + Site ID) assignments,
/// which map to `account_request_scopes` during registration.
class ManagerScopeItem {
  final String? id;
  final String departmentId;
  final String departmentName;
  final String siteId;
  final String siteName;

  const ManagerScopeItem({
    this.id,
    required this.departmentId,
    required this.departmentName,
    required this.siteId,
    required this.siteName,
  });

  String get displayName => '$departmentName / $siteName';
  String get label => '$departmentName / $siteName';

  Map<String, dynamic> toSyncJson() => {
    'department_id': departmentId,
    'site_id': siteId,
  };

  ManagerScopeItem copyWith({
    String? id,
    String? departmentId,
    String? departmentName,
    String? siteId,
    String? siteName,
  }) {
    return ManagerScopeItem(
      id: id ?? this.id,
      departmentId: departmentId ?? this.departmentId,
      departmentName: departmentName ?? this.departmentName,
      siteId: siteId ?? this.siteId,
      siteName: siteName ?? this.siteName,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ManagerScopeItem &&
          runtimeType == other.runtimeType &&
          departmentId == other.departmentId &&
          siteId == other.siteId;

  @override
  int get hashCode => Object.hash(departmentId, siteId);

  @override
  String toString() => 'ManagerScopeItem($departmentName / $siteName)';
}

/// Standard department option for organization scope selection
class DepartmentOption {
  final String id;
  final String name;
  final String code;

  const DepartmentOption({
    required this.id,
    required this.name,
    required this.code,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DepartmentOption &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Standard site option for organization scope selection
class SiteOption {
  final String id;
  final String name;
  final String code;

  const SiteOption({required this.id, required this.name, required this.code});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SiteOption && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Default standard departments aligned with the ActionFlow organizational foundation
const List<DepartmentOption> defaultDepartments = [
  DepartmentOption(id: 'dept-hse', name: 'HSE / Safety', code: 'HSE'),
  DepartmentOption(id: 'dept-ops', name: 'Operations', code: 'OPS'),
  DepartmentOption(id: 'dept-maint', name: 'Maintenance', code: 'MAINT'),
  DepartmentOption(id: 'dept-proj', name: 'Projects', code: 'PROJ'),
  DepartmentOption(id: 'dept-qa', name: 'Quality Assurance', code: 'QA'),
  DepartmentOption(id: 'dept-log', name: 'Logistics', code: 'LOG'),
  DepartmentOption(id: 'dept-acc', name: 'Accounts', code: 'ACC'),
  DepartmentOption(id: 'dept-hr', name: 'Human Resources', code: 'HR'),
];

/// Default standard sites aligned with the ActionFlow organizational foundation
const List<SiteOption> defaultSites = [
  SiteOption(id: 'site-plt-a', name: 'Platform Alpha', code: 'PLT-A'),
  SiteOption(id: 'site-plt-b', name: 'Platform Bravo', code: 'PLT-B'),
  SiteOption(id: 'site-np-01', name: 'North Plant', code: 'NP-01'),
  SiteOption(id: 'site-cy-main', name: 'Central Yard', code: 'CY-MAIN'),
  SiteOption(id: 'site-wh-b', name: 'Warehouse B', code: 'WH-B'),
  SiteOption(id: 'site-rig-04', name: 'Offshore Rig #4', code: 'RIG-04'),
  SiteOption(id: 'site-hq', name: 'Corporate Headquarters', code: 'HQ'),
];

/// Standard team option within a department
class TeamOption {
  final String id;
  final String name;
  final String departmentId;
  final bool isActive;

  const TeamOption({
    required this.id,
    required this.name,
    required this.departmentId,
    this.isActive = true,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TeamOption && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Default standard teams aligned with the ActionFlow organizational foundation
const List<TeamOption> defaultTeams = [
  TeamOption(
    id: 'team-hse-audit',
    name: 'HSSE Audit & Compliance Team',
    departmentId: 'dept-hse',
  ),
  TeamOption(
    id: 'team-hse-field',
    name: 'Field Safety & Emergency Response',
    departmentId: 'dept-hse',
  ),
  TeamOption(
    id: 'team-ops-a',
    name: 'Operations Squad A',
    departmentId: 'dept-ops',
  ),
  TeamOption(
    id: 'team-ops-b',
    name: 'Operations Squad B',
    departmentId: 'dept-ops',
  ),
  TeamOption(
    id: 'team-maint-mech',
    name: 'Mechanical Maintenance Unit',
    departmentId: 'dept-maint',
  ),
  TeamOption(
    id: 'team-maint-elec',
    name: 'Electrical & Instrumentation',
    departmentId: 'dept-maint',
  ),
  TeamOption(
    id: 'team-proj-eng',
    name: 'Engineering & Project Delivery',
    departmentId: 'dept-proj',
  ),
  TeamOption(
    id: 'team-qa-qc',
    name: 'Quality Control & Inspection',
    departmentId: 'dept-qa',
  ),
  TeamOption(
    id: 'team-acc-finance',
    name: 'Financial Audit & Accounts Team',
    departmentId: 'dept-acc',
  ),
  TeamOption(
    id: 'team-hr-ops',
    name: 'HR Operations & Personnel',
    departmentId: 'dept-hr',
  ),
];

/// Data model representing a validated Staff registration request
class StaffRegistrationData {
  final String fullName;
  final String email;
  final String phone;
  final String designation;
  final String departmentId;
  final String departmentName;
  final String siteId;
  final String siteName;
  final String? teamId;
  final String? teamName;
  final String password;

  const StaffRegistrationData({
    required this.fullName,
    required this.email,
    this.phone = '',
    required this.designation,
    required this.departmentId,
    required this.departmentName,
    required this.siteId,
    required this.siteName,
    this.teamId,
    this.teamName,
    required this.password,
  });
}
