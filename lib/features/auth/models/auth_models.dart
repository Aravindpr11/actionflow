import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/models/organization.dart';

export 'package:action_flow/models/organization.dart';

/// Requested account type during user registration
enum RequestedAccountType {
  staff(
    'Staff',
    'Direct staff registration for action assignments and field reporting.',
  ),
  manager(
    'Manager (Access Request)',
    'Manager access request requiring organizational administrative verification and approval.',
  );

  final String label;
  final String description;

  const RequestedAccountType(this.label, this.description);
}

/// Account verification and approval status for authentication workflow
enum AuthAccountStatus {
  pendingVerification(
    'Pending Email Verification',
    'Please verify your email address to proceed with account setup.',
  ),
  pendingApproval(
    'Pending Administrator Approval',
    'Your account has been verified and is awaiting administrator approval.',
  ),
  active(
    'Account Active',
    'Your account is verified and active. You can sign in to access your designated portal.',
  ),
  inactive(
    'Account Inactive',
    'Your account is currently inactive or suspended. Please contact your organization administrator.',
  ),
  rejected(
    'Access Request Rejected',
    'Your account registration or role access request was not approved by the organization administrator.',
  );

  final String label;
  final String description;

  const AuthAccountStatus(this.label, this.description);
}

/// Operational Department + Site scope item for Manager account requests
class ManagerScopeItemView {
  final String departmentName;
  final String siteName;
  final String? departmentId;
  final String? siteId;

  const ManagerScopeItemView({
    required this.departmentName,
    required this.siteName,
    this.departmentId,
    this.siteId,
  });

  String get displayName => '$departmentName / $siteName';
}

/// Signup request model capturing registration data and lifecycle status
class SignupRequest {
  final String id;
  final String authUserId;
  final String fullName;
  final String email;
  final String phone;
  final String? avatarUrl;
  final String designation;
  final String department;
  final String? departmentId;
  final String division;
  final String site;
  final String? siteId;
  final String team;
  final String? teamId;
  final String supervisor;
  final RequestedAccountType requestedType;
  final String? requestedRoleId;
  final List<ManagerScopeItemView> managerScopes;
  final String password;
  final DateTime createdAt;
  final AuthAccountStatus status;
  final bool isEmailVerified;
  final String? rejectionReason;
  final String? rejectedBy;
  final DateTime? rejectedAt;
  final DateTime? approvedAt;
  final String? approvedBy;
  final String? organizationId;
  final String organizationName;

  SignupRequest({
    this.id = '',
    this.authUserId = '',
    required this.fullName,
    required this.email,
    required this.phone,
    this.avatarUrl,
    required this.designation,
    required this.department,
    this.departmentId,
    this.division = 'Operations & HSSE',
    required this.site,
    this.siteId,
    this.team = '',
    this.teamId,
    this.supervisor = '',
    required this.requestedType,
    this.requestedRoleId,
    this.managerScopes = const [],
    this.password = '',
    DateTime? createdAt,
    AuthAccountStatus? status,
    this.isEmailVerified = false,
    this.rejectionReason,
    this.rejectedBy,
    this.rejectedAt,
    this.approvedAt,
    this.approvedBy,
    this.organizationId = Organization.sobhaId,
    this.organizationName = Organization.sobhaName,
  }) : createdAt = createdAt ?? DateTime.now(),
       status = status ?? AuthAccountStatus.pendingVerification;

  String get initials {
    if (fullName.trim().isEmpty) return 'U';
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  bool get isManager => requestedType == RequestedAccountType.manager;

  UserProfile toUserProfile() {
    final prefix = isManager ? 'MGR' : 'EMP';
    final idNum = (createdAt.millisecondsSinceEpoch % 9000) + 1000;
    return UserProfile(
      id: '$prefix-$idNum',
      name: fullName,
      email: email,
      phone: phone,
      designation: designation,
      department: department,
      division: division,
      site: site,
      team: team,
      role: isManager
          ? 'Manager / Action Approver'
          : 'Action Assignee / Field Worker',
      supervisor: supervisor,
      accountStatus: 'Active',
      permissions: isManager
          ? const [
              'Create & Assign Actions',
              'Approve Action Closures & Evidence',
              'Escalate SLA Breaches & Overdue Items',
              'Export Compliance & Audit Reports',
              'Manage Department Team Members',
            ]
          : const [
              'View Assigned Actions',
              'Submit Action Progress & Evidence Updates',
              'Request Action Extensions & Reassignments',
              'Access Field Safety Documentation',
            ],
      avatarUrl: avatarUrl,
      organizationId: organizationId,
      organizationName: organizationName,
    );
  }

  SignupRequest copyWith({
    String? id,
    String? authUserId,
    String? fullName,
    String? email,
    String? phone,
    String? avatarUrl,
    String? designation,
    String? department,
    String? departmentId,
    String? division,
    String? site,
    String? siteId,
    String? team,
    String? teamId,
    String? supervisor,
    RequestedAccountType? requestedType,
    String? requestedRoleId,
    List<ManagerScopeItemView>? managerScopes,
    String? password,
    DateTime? createdAt,
    AuthAccountStatus? status,
    bool? isEmailVerified,
    String? rejectionReason,
    String? rejectedBy,
    DateTime? rejectedAt,
    DateTime? approvedAt,
    String? approvedBy,
    String? organizationId,
    String? organizationName,
  }) {
    return SignupRequest(
      id: id ?? this.id,
      authUserId: authUserId ?? this.authUserId,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      designation: designation ?? this.designation,
      department: department ?? this.department,
      departmentId: departmentId ?? this.departmentId,
      division: division ?? this.division,
      site: site ?? this.site,
      siteId: siteId ?? this.siteId,
      team: team ?? this.team,
      teamId: teamId ?? this.teamId,
      supervisor: supervisor ?? this.supervisor,
      requestedType: requestedType ?? this.requestedType,
      requestedRoleId: requestedRoleId ?? this.requestedRoleId,
      managerScopes: managerScopes ?? this.managerScopes,
      password: password ?? this.password,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      rejectedBy: rejectedBy ?? this.rejectedBy,
      rejectedAt: rejectedAt ?? this.rejectedAt,
      approvedAt: approvedAt ?? this.approvedAt,
      approvedBy: approvedBy ?? this.approvedBy,
      organizationId: organizationId ?? this.organizationId,
      organizationName: organizationName ?? this.organizationName,
    );
  }
}
