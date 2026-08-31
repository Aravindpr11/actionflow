import 'team.dart';

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
    this.department = '',
    this.division = '',
    this.site = '',
    this.company = '',
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
  final String department;
  final String division;
  final String site;
  final String company;

  String get typeLabel => type == PersonType.internalUser
      ? 'Internal ActionFlow User'
      : 'External Worker';

  String get roleLabel => role.label;

  Person copyWith({
    String? name,
    String? email,
    String? phone,
    String? designation,
    bool? isActive,
    String? department,
    String? division,
    String? site,
    String? company,
    UserRole? role,
    List<String>? teamIds,
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
      department: department ?? this.department,
      division: division ?? this.division,
      site: site ?? this.site,
      company: company ?? this.company,
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
    this.site = '',
  });

  final String personId;
  final String name;
  final PersonType type;
  final String email;
  final String phone;
  final String designation;
  final String site;

  String get typeLabel =>
      type == PersonType.internalUser ? 'Internal' : 'External';
}
