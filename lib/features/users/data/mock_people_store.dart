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
      id: 'AFU-001',
      name: 'R. Kumar',
      email: 'r.kumar@actionflow.demo',
      phone: '+91 90000 10001',
      designation: 'Maintenance Supervisor',
      department: 'Maintenance',
      division: 'Operations',
      site: 'North Plant',
      type: PersonType.internalUser,
      isActive: true,
      role: UserRole.actionOwnerWorker,
      teamIds: ['TEAM-HSE', 'TEAM-OPS'],
    ),
    Person(
      id: 'AFU-002',
      name: 'M. Ali',
      email: 'm.ali@actionflow.demo',
      phone: '+91 90000 10002',
      designation: 'HSE Coordinator',
      department: 'HSE',
      division: 'Operations',
      site: 'Warehouse B',
      type: PersonType.internalUser,
      isActive: true,
      role: UserRole.departmentManager,
      teamIds: ['TEAM-HSE', 'TEAM-ACC'],
    ),
    Person(
      id: 'AFU-003',
      name: 'S. Jones',
      email: 's.jones@actionflow.demo',
      phone: '+44 7000 10003',
      designation: 'Project Engineer',
      department: 'Projects',
      division: 'Projects',
      site: 'Central Yard',
      type: PersonType.internalUser,
      isActive: true,
      role: UserRole.actionOwnerWorker,
      teamIds: ['TEAM-OPS'],
    ),
    Person(
      id: 'AFU-004',
      name: 'N. Shah',
      email: 'n.shah@actionflow.demo',
      phone: '+91 90000 10004',
      designation: 'Facilities Lead',
      department: 'Operations',
      division: 'Corporate',
      site: 'Admin Block',
      type: PersonType.internalUser,
      isActive: true,
      role: UserRole.departmentManager,
      teamIds: ['TEAM-OPS'],
    ),
    Person(
      id: 'AFU-005',
      name: 'T. Reed',
      email: 't.reed@actionflow.demo',
      phone: '+44 7000 10005',
      designation: 'Compliance Officer',
      department: 'HSE',
      division: 'Operations',
      site: 'Storage Area',
      type: PersonType.internalUser,
      isActive: false,
      role: UserRole.actionOwnerWorker,
      teamIds: ['TEAM-HSE'],
    ),
    Person(
      id: 'EXT-021',
      name: 'K. Patel',
      email: 'k.patel@safecontractors.demo',
      phone: '+91 90000 20001',
      designation: 'Electrical Technician',
      company: 'Safe Contractors Ltd',
      type: PersonType.externalWorker,
      isActive: true,
    ),
    Person(
      id: 'EXT-022',
      name: 'A. Williams',
      email: 'a.williams@liftcare.demo',
      phone: '+44 7000 20002',
      designation: 'Equipment Inspector',
      company: 'LiftCare Services',
      type: PersonType.externalWorker,
      isActive: true,
    ),
    Person(
      id: 'EXT-023',
      name: 'D. Green',
      email: 'd.green@siteworks.demo',
      phone: '+44 7000 20003',
      designation: 'Site Supervisor',
      company: 'SiteWorks Partners',
      type: PersonType.externalWorker,
      isActive: false,
    ),
  ];

  void add(Person person) => people.insert(0, person);

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

  void update(Person person) {
    final index = people.indexWhere((item) => item.id == person.id);
    if (index >= 0) people[index] = person;
  }
}
