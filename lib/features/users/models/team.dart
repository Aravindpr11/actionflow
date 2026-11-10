class Team {
  const Team({required this.id, required this.name, required this.department});

  final String id;
  final String name;
  final String department;
}

enum UserRole { admin, departmentManager, actionOwnerWorker }

extension UserRoleLabel on UserRole {
  String get label {
    switch (this) {
      case UserRole.admin:
        return 'System Administrator';
      case UserRole.departmentManager:
        return 'Department Manager';
      case UserRole.actionOwnerWorker:
        return 'Action Owner / Staff';
    }
  }
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
