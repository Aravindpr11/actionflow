class Team {
  const Team({required this.id, required this.name, required this.department});

  final String id;
  final String name;
  final String department;
}

enum UserRole { departmentManager, actionOwnerWorker }

extension UserRoleLabel on UserRole {
  String get label => this == UserRole.departmentManager
      ? 'Department Manager'
      : 'Action Owner / Worker';
}

class TeamNotification {
  const TeamNotification({
    required this.id,
    required this.managerId,
    required this.teamId,
    required this.title,
    required this.message,
  });

  final String id;
  final String managerId;
  final String teamId;
  final String title;
  final String message;
}
