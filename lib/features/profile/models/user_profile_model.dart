import 'package:action_flow/models/organization.dart';

/// User profile model for ActionFlow users (Manager, Staff, Admin)
class UserProfile {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String designation;
  final String department;
  final String division;
  final String site;
  final String team;
  final String role;
  final String supervisor;
  final String certifications;
  final String accountStatus;
  final List<String> permissions;
  final String? avatarUrl;
  final String? organizationId;
  final String organizationName;
  final String? departmentId;
  final String? siteId;

  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.designation,
    required this.department,
    this.division = 'Operations & HSSE',
    required this.site,
    this.team = '',
    required this.role,
    this.supervisor = '',
    this.certifications = '',
    this.accountStatus = 'Active',
    this.permissions = const [],
    this.avatarUrl,
    this.organizationId = Organization.sobhaId,
    this.organizationName = Organization.sobhaName,
    this.departmentId,
    this.siteId,
  });

  String get initials {
    if (name.trim().isEmpty) return 'U';
    if (name == 'System Administrator') return 'AD';
    if (name == 'Manager') return 'M';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  UserProfile copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? designation,
    String? department,
    String? division,
    String? site,
    String? team,
    String? role,
    String? supervisor,
    String? certifications,
    String? accountStatus,
    List<String>? permissions,
    String? avatarUrl,
    String? organizationId,
    String? organizationName,
    String? departmentId,
    String? siteId,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      designation: designation ?? this.designation,
      department: department ?? this.department,
      division: division ?? this.division,
      site: site ?? this.site,
      team: team ?? this.team,
      role: role ?? this.role,
      supervisor: supervisor ?? this.supervisor,
      certifications: certifications ?? this.certifications,
      accountStatus: accountStatus ?? this.accountStatus,
      permissions: permissions ?? this.permissions,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      organizationId: organizationId ?? this.organizationId,
      organizationName: organizationName ?? this.organizationName,
      departmentId: departmentId ?? this.departmentId,
      siteId: siteId ?? this.siteId,
    );
  }

  /// Default mock profile for Manager
  static UserProfile mockManager() {
    return const UserProfile(
      id: 'MGR-1042',
      name: 'Manager',
      email: 'manager@actionflow.internal',
      phone: '+1 (555) 234-5678',
      designation: 'Operations Lead',
      department: 'Health & Safety',
      division: 'Operations & HSSE Governance',
      site: 'North Plant Facility',
      team: 'HSSE Audit & Compliance Team',
      role: 'Manager / Action Approver',
      supervisor: 'David Chen (Director of HSSE)',
      certifications: 'NEBOSH Diploma • ISO 45001 Lead Auditor',
      accountStatus: 'Active',
      permissions: [
        'Create & Assign Actions',
        'Approve Action Closures & Evidence',
        'Escalate SLA Breaches & Overdue Items',
        'Export Compliance & Audit Reports',
        'Manage Department Team Members',
      ],
    );
  }

  /// Default mock profile for Staff / Worker
  static UserProfile mockStaff() {
    return const UserProfile(
      id: 'EMP-2049',
      name: 'R. Kumar',
      email: 'r.kumar@actionflow.internal',
      phone: '+1 (555) 876-5432',
      designation: 'Field Operations',
      department: 'Operations / Maintenance',
      division: 'Plant Maintenance & Infrastructure',
      site: 'North Plant Facility',
      team: 'North Plant Operations Squad A',
      role: 'Action Assignee / Field Worker',
      supervisor: 'Sarah Jenkins (HSSE Manager)',
      certifications: 'Level 3 HSSE Site Qualified • Confined Space Certified',
      accountStatus: 'Active',
      permissions: [
        'View Assigned Actions',
        'Submit Action Progress & Evidence Updates',
        'Request Action Extensions & Reassignments',
        'Access Field Safety Documentation',
      ],
    );
  }

  /// Default mock profile for Admin
  static UserProfile mockAdmin() {
    return const UserProfile(
      id: 'ADM-0001',
      name: 'System Administrator',
      email: 'admin@actionflow.internal',
      phone: '+1 (555) 999-0001',
      designation: 'Enterprise System Administrator',
      department: 'IT & System Governance',
      division: 'Enterprise Security & Operations',
      site: 'Corporate Headquarters',
      team: 'Platform Governance & Security',
      role: 'System Administrator (Tier 1)',
      supervisor: 'Executive Board / CISO',
      certifications: 'CISSP • ISO 27001 Lead Implementer',
      accountStatus: 'Active',
      permissions: [
        'Full System Configuration Access',
        'User, Department & Site Governance',
        'Security Policy & 2FA Enforcement',
        'System Audit Log Inspection',
        'Emergency Broadcast Dispatch',
      ],
    );
  }
}
