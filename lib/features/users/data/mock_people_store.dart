import '../models/person.dart';
import '../models/team.dart';

class MockPeopleStore {
  MockPeopleStore._();

  static final MockPeopleStore instance = MockPeopleStore._();

  final teams = const [
    Team(id: 'TEAM-HSE', name: 'HSE Team', department: 'HSE'),
    Team(id: 'TEAM-ACC', name: 'Accounts Team', department: 'Accounts'),
    Team(id: 'TEAM-OPS', name: 'Operations Team', department: 'Operations'),
    Team(id: 'TEAM-PUR', name: 'Purchase Team', department: 'Purchase'),
    Team(id: 'TEAM-HR', name: 'HR Team', department: 'HR'),
  ];

  final List<TeamNotification> notifications = [];

  final List<Person> people = [
    Person(
      id: 'a1000000-0000-0000-0000-000000000000',
      name: 'System Administrator',
      email: 'admin@actionflow.demo',
      phone: '+91 90000 10000',
      designation: 'System Administrator',
      department: 'Enterprise System Administration',
      site: 'Corporate HQ',
      type: PersonType.internalUser,
      isActive: true,
      role: UserRole.admin,
    ),
    Person(
      id: 'a1000000-0000-0000-0000-000000000001',
      name: 'R. Kumar',
      email: 'r.kumar@actionflow.demo',
      phone: '+91 90000 10001',
      designation: 'Maintenance Supervisor',
      department: 'Maintenance',
      departmentId: 'dept-maint-001',
      site: 'North Plant',
      type: PersonType.internalUser,
      isActive: true,
      role: UserRole.actionOwnerWorker,
      teamIds: ['TEAM-HSE', 'TEAM-OPS'],
    ),
    Person(
      id: 'a1000000-0000-0000-0000-000000000002',
      name: 'M. Ali',
      email: 'm.ali@actionflow.demo',
      phone: '+91 90000 10002',
      designation: 'HSE Coordinator',
      department: 'HSE',
      departmentId: 'dept-hse-001',
      site: 'Warehouse B',
      type: PersonType.internalUser,
      isActive: true,
      role: UserRole.departmentManager,
      teamIds: ['TEAM-HSE', 'TEAM-ACC'],
      managerScopes: const [
        ManagerScopeItem(
          departmentId: 'dept-hse-001',
          departmentName: 'HSE',
          siteId: 'site-whb-001',
          siteName: 'Warehouse B',
        ),
        ManagerScopeItem(
          departmentId: 'dept-ops-001',
          departmentName: 'Operations',
          siteId: 'site-np-001',
          siteName: 'North Plant',
        ),
        ManagerScopeItem(
          departmentId: 'dept-maint-001',
          departmentName: 'Maintenance',
          siteId: 'site-np-001',
          siteName: 'North Plant',
        ),
      ],
    ),
    Person(
      id: 'a1000000-0000-0000-0000-000000000003',
      name: 'S. Jones',
      email: 's.jones@actionflow.demo',
      phone: '+44 7000 10003',
      designation: 'Project Engineer',
      department: 'Projects',
      departmentId: 'dept-proj-001',
      site: 'Central Yard',
      type: PersonType.internalUser,
      isActive: true,
      role: UserRole.actionOwnerWorker,
      teamIds: ['TEAM-OPS'],
    ),
    Person(
      id: 'a1000000-0000-0000-0000-000000000004',
      name: 'N. Shah',
      email: 'n.shah@actionflow.demo',
      phone: '+91 90000 10004',
      designation: 'Facilities Lead',
      department: 'Operations',
      departmentId: 'dept-ops-001',
      site: 'Admin Block',
      type: PersonType.internalUser,
      isActive: true,
      role: UserRole.departmentManager,
      teamIds: ['TEAM-OPS'],
      managerScopes: const [
        ManagerScopeItem(
          departmentId: 'dept-ops-001',
          departmentName: 'Operations',
          siteId: 'site-adm-001',
          siteName: 'Admin Block',
        ),
        ManagerScopeItem(
          departmentId: 'dept-maint-001',
          departmentName: 'Maintenance',
          siteId: 'site-np-001',
          siteName: 'North Plant',
        ),
      ],
    ),
    Person(
      id: 'a1000000-0000-0000-0000-000000000006',
      name: 'Operations Manager',
      email: 'manager@actionflow.demo',
      phone: '+91 90000 10006',
      designation: 'Operations Manager',
      department: 'Operations',
      departmentId: 'dept-ops-001',
      site: 'North Plant',
      type: PersonType.internalUser,
      isActive: true,
      role: UserRole.departmentManager,
      managerScopes: const [
        ManagerScopeItem(
          departmentId: 'dept-ops-001',
          departmentName: 'Operations',
          siteId: 'site-np-001',
          siteName: 'North Plant',
        ),
        ManagerScopeItem(
          departmentId: 'dept-maint-001',
          departmentName: 'Maintenance',
          siteId: 'site-np-001',
          siteName: 'North Plant',
        ),
      ],
    ),
    Person(
      id: 'a1000000-0000-0000-0000-000000000005',
      name: 'T. Reed',
      email: 't.reed@actionflow.demo',
      phone: '+44 7000 10005',
      designation: 'Compliance Officer',
      department: 'HSE',
      departmentId: 'dept-hse-001',
      site: 'Storage Area',
      type: PersonType.internalUser,
      isActive: false,
      role: UserRole.actionOwnerWorker,
      teamIds: ['TEAM-HSE'],
    ),
    Person(
      id: 'b1000000-0000-0000-0000-000000000021',
      name: 'K. Patel',
      email: 'k.patel@safecontractors.demo',
      phone: '+91 90000 20001',
      designation: 'Electrical Technician',
      company: 'Safe Contractors Ltd',
      type: PersonType.externalWorker,
      isActive: true,
    ),
    Person(
      id: 'b1000000-0000-0000-0000-000000000022',
      name: 'A. Williams',
      email: 'a.williams@liftcare.demo',
      phone: '+44 7000 20002',
      designation: 'Equipment Inspector',
      company: 'LiftCare Services',
      type: PersonType.externalWorker,
      isActive: true,
    ),
    Person(
      id: 'b1000000-0000-0000-0000-000000000023',
      name: 'D. Green',
      email: 'd.green@siteworks.demo',
      phone: '+44 7000 20003',
      designation: 'Site Supervisor',
      company: 'SiteWorks Partners',
      type: PersonType.externalWorker,
      isActive: false,
    ),
  ];

  static String normalizePhone(String phone) {
    return phone.replaceAll(RegExp(r'\D'), '');
  }

  static bool isEmailMatch(String e1, String e2) {
    final a = e1.trim().toLowerCase();
    final b = e2.trim().toLowerCase();
    return a.isNotEmpty && b.isNotEmpty && a == b;
  }

  static bool isPhoneMatch(String p1, String p2) {
    final a = normalizePhone(p1);
    final b = normalizePhone(p2);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    if (a.length >= 10 && b.length >= 10 && (a.endsWith(b) || b.endsWith(a))) {
      return true;
    }
    return false;
  }

  Person? findDuplicate({
    required String email,
    required String phone,
    String? excludeId,
  }) {
    for (final person in people) {
      if (excludeId != null && person.id == excludeId) continue;
      if (isEmailMatch(person.email, email)) return person;
      if (isPhoneMatch(person.phone, phone)) return person;
    }
    return null;
  }

  void add(Person person) {
    final existingIndex = people.indexWhere((item) => item.id == person.id);
    if (existingIndex >= 0) {
      people[existingIndex] = person;
    } else {
      people.insert(0, person);
    }
  }

  void removePerson(String id) {
    people.removeWhere((item) => item.id == id);
  }

  void addWithTeamNotifications(Person person) {
    add(person);
    for (final teamId in person.teamIds) {
      final team = teams.firstWhere((item) => item.id == teamId);
      final managers = people.where(
        (item) =>
            item.isActive &&
            item.role == UserRole.departmentManager &&
            item.teamIds.contains(teamId),
      );
      for (final manager in managers) {
        notifications.add(
          TeamNotification(
            id: 'NTF-${notifications.length + 1}',
            managerId: manager.id,
            teamId: team.id,
            title: 'New team member joined',
            message:
                '${person.name} joined the ${team.department} ActionFlow team.',
          ),
        );
      }
    }
  }

  void addNotification(TeamNotification notification) {
    notifications.insert(0, notification);
  }

  void update(Person person) {
    final index = people.indexWhere((item) => item.id == person.id);
    if (index >= 0) people[index] = person;
  }
}
