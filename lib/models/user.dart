/// User model representing an application user
class User {
  final String id;
  final String email;
  final String name;
  final String role; // 'manager' or 'worker'
  final String? profilePicture;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isActive;

  User({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.profilePicture,
    this.createdAt,
    this.updatedAt,
    this.isActive = true,
  });

  /// Convert user to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'role': role,
      'profilePicture': profilePicture,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'isActive': isActive,
    };
  }

  /// Create user from JSON
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String,
      role: json['role'] as String,
      profilePicture: json['profilePicture'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      isActive: json['isActive'] as bool? ?? true,
    );
  }

  /// Create a copy of user with some fields replaced
  User copyWith({
    String? id,
    String? email,
    String? name,
    String? role,
    String? profilePicture,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      role: role ?? this.role,
      profilePicture: profilePicture ?? this.profilePicture,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
    );
  }
}
