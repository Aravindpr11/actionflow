import 'package:action_flow/features/auth/models/auth_models.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/users/models/team.dart';

/// Central singleton store for persistent mock user registrations and approval lifecycle
class MockAuthStore {
  MockAuthStore._() {
    _initSampleData();
  }

  static final MockAuthStore instance = MockAuthStore._();

  final List<SignupRequest> _registrations = [];

  List<SignupRequest> get registrations => List.unmodifiable(_registrations);

  void _initSampleData() {
    _registrations.clear();
    _registrations.addAll([
      SignupRequest(
        fullName: 'Elena Vlad',
        email: 'elena.vlad@company.com',
        phone: '+1 (555) 345-6789',
        designation: 'Senior Safety Lead',
        department: 'HSE / Safety',
        division: 'Operations & HSSE',
        site: 'Platform Alpha',
        team: 'HSE Team',
        supervisor: 'David Chen',
        requestedType: RequestedAccountType.manager,
        password: 'password123',
        status: AuthAccountStatus.pendingApproval,
        isEmailVerified: true,
        createdAt: DateTime.now().subtract(const Duration(hours: 4)),
      ),
      SignupRequest(
        fullName: 'Arjun Nair',
        email: 'arjun.nair@company.com',
        phone: '+1 (555) 456-7890',
        designation: 'Mechanical Field Tech',
        department: 'Maintenance',
        division: 'Operations & HSSE',
        site: 'North Rig #4',
        team: 'Operations Team',
        supervisor: 'Sarah Jenkins',
        requestedType: RequestedAccountType.staff,
        password: 'password123',
        status: AuthAccountStatus.pendingApproval,
        isEmailVerified: true,
        createdAt: DateTime.now().subtract(const Duration(hours: 8)),
      ),
      SignupRequest(
        fullName: 'Marcus Vance',
        email: 'marcus.vance@company.com',
        phone: '+1 (555) 567-8901',
        designation: 'Drilling Specialist',
        department: 'Drilling',
        division: 'Operations & HSSE',
        site: 'Platform Bravo',
        team: 'Operations Team',
        supervisor: 'David Chen',
        requestedType: RequestedAccountType.staff,
        password: 'password123',
        status: AuthAccountStatus.pendingVerification,
        isEmailVerified: false,
        createdAt: DateTime.now().subtract(const Duration(hours: 12)),
      ),
      SignupRequest(
        fullName: 'Tom Holloway',
        email: 'tom.holloway@external.com',
        phone: '+1 (555) 678-9012',
        designation: 'Third-Party Contractor Lead',
        department: 'Operations',
        division: 'Operations & HSSE',
        site: 'Central Logistics Base',
        team: 'Operations Team',
        supervisor: 'Elena Rostova',
        requestedType: RequestedAccountType.manager,
        password: 'password123',
        status: AuthAccountStatus.rejected,
        isEmailVerified: true,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        rejectionReason: 'Manager role requires minimum 12 months direct internal enterprise employment.',
        rejectedBy: 'System Administrator',
        rejectedAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ]);
  }

  /// Adds or updates a registration record in the persistent store
  void addRegistration(SignupRequest request) {
    final index = _registrations.indexWhere(
      (r) => r.email.toLowerCase() == request.email.toLowerCase(),
    );
    if (index >= 0) {
      _registrations[index] = request;
    } else {
      _registrations.insert(0, request);
    }
  }

  /// Finds a registration by email or username
  SignupRequest? getRegistrationByEmail(String emailOrUsername) {
    final query = emailOrUsername.trim().toLowerCase();
    if (query.isEmpty) return null;

    try {
      return _registrations.firstWhere(
        (r) =>
            r.email.toLowerCase() == query ||
            r.fullName.toLowerCase() == query ||
            r.email.toLowerCase().startsWith(query),
      );
    } catch (_) {
      return null;
    }
  }

  /// Transitions a user from pending verification to Pending Administrator Approval
  SignupRequest? verifyEmail(String email) {
    final index = _registrations.indexWhere(
      (r) => r.email.toLowerCase() == email.trim().toLowerCase(),
    );
    if (index < 0) return null;

    final updated = _registrations[index].copyWith(
      isEmailVerified: true,
      status: AuthAccountStatus.pendingApproval,
    );
    _registrations[index] = updated;
    return updated;
  }

  /// Approves a registration, sets status to Active, and registers the user in MockPeopleStore
  SignupRequest? approveRegistration(
    String email, {
    String approvedBy = 'System Administrator',
  }) {
    final index = _registrations.indexWhere(
      (r) => r.email.toLowerCase() == email.trim().toLowerCase(),
    );
    if (index < 0) return null;

    final reg = _registrations[index];
    final updated = reg.copyWith(
      status: AuthAccountStatus.active,
      approvedAt: DateTime.now(),
      approvedBy: approvedBy,
    );
    _registrations[index] = updated;

    // Synchronize with MockPeopleStore
    final existingPersonIdx = MockPeopleStore.instance.people.indexWhere(
      (p) => p.email.toLowerCase() == reg.email.toLowerCase(),
    );
    if (existingPersonIdx < 0) {
      final userProfile = updated.toUserProfile();
      MockPeopleStore.instance.people.add(
        Person(
          id: userProfile.id,
          name: reg.fullName,
          email: reg.email,
          phone: reg.phone,
          designation: reg.designation,
          department: reg.department,
          site: reg.site,
          type: PersonType.internalUser,
          isActive: true,
          role: reg.requestedType == RequestedAccountType.manager
              ? UserRole.departmentManager
              : UserRole.actionOwnerWorker,
          teamIds: reg.team.isNotEmpty ? [reg.team] : [],
        ),
      );
    } else {
      final existing = MockPeopleStore.instance.people[existingPersonIdx];
      MockPeopleStore.instance.people[existingPersonIdx] = existing.copyWith(
        isActive: true,
        role: reg.requestedType == RequestedAccountType.manager
            ? UserRole.departmentManager
            : UserRole.actionOwnerWorker,
      );
    }

    return updated;
  }

  /// Rejects a registration with a required audit reason
  SignupRequest? rejectRegistration(
    String email, {
    required String reason,
    String rejectedBy = 'System Administrator',
  }) {
    final index = _registrations.indexWhere(
      (r) => r.email.toLowerCase() == email.trim().toLowerCase(),
    );
    if (index < 0) return null;

    final updated = _registrations[index].copyWith(
      status: AuthAccountStatus.rejected,
      rejectionReason: reason,
      rejectedBy: rejectedBy,
      rejectedAt: DateTime.now(),
    );
    _registrations[index] = updated;
    return updated;
  }

  /// Returns pending account requests (awaiting email verification or admin approval)
  List<SignupRequest> getPendingRequests() {
    return _registrations
        .where(
          (r) =>
              r.status == AuthAccountStatus.pendingApproval ||
              r.status == AuthAccountStatus.pendingVerification,
        )
        .toList();
  }

  /// Returns approved and active accounts
  List<SignupRequest> getApprovedRequests() {
    return _registrations
        .where((r) => r.status == AuthAccountStatus.active)
        .toList();
  }

  /// Returns rejected account requests
  List<SignupRequest> getRejectedRequests() {
    return _registrations
        .where((r) => r.status == AuthAccountStatus.rejected)
        .toList();
  }

  /// Resets store to initial sample data
  void reset() {
    _initSampleData();
  }

  /// Clears all registration records (for testing)
  void clear() {
    _registrations.clear();
  }
}
