/// Model representing an Organizational Division in ActionFlow.
/// Divisions are tenant-scoped top-level business classifications.
class Division {
  final String id;
  final String organizationId;
  final String name;
  final String code;
  final String description;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int actionCount;

  const Division({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.code,
    this.description = '',
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.actionCount = 0,
  });

  factory Division.fromSupabase(Map<String, dynamic> data) {
    return Division(
      id: (data['id'] as String?) ?? '',
      organizationId: (data['organization_id'] as String?) ?? '',
      name: (data['name'] as String?) ?? '',
      code: (data['code'] as String?) ?? '',
      description: (data['description'] as String?) ?? '',
      isActive: data['is_active'] != false,
      createdAt: data['created_at'] != null
          ? DateTime.tryParse(data['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: data['updated_at'] != null
          ? DateTime.tryParse(data['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      actionCount: (data['action_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'organization_id': organizationId,
    'name': name,
    'code': code,
    'description': description,
    'is_active': isActive,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'action_count': actionCount,
  };

  Map<String, dynamic> toInsertMap() {
    final map = <String, dynamic>{
      'name': name.trim(),
      'code': code.trim().toUpperCase(),
      'description': description.trim(),
      'is_active': isActive,
    };
    if (organizationId.isNotEmpty) {
      map['organization_id'] = organizationId;
    }
    return map;
  }

  Map<String, dynamic> toUpdateMap() => {
    'name': name.trim(),
    'code': code.trim().toUpperCase(),
    'description': description.trim(),
    'is_active': isActive,
    'updated_at': DateTime.now().toIso8601String(),
  };

  Division copyWith({
    String? id,
    String? organizationId,
    String? name,
    String? code,
    String? description,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? actionCount,
  }) {
    return Division(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      name: name ?? this.name,
      code: code ?? this.code,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      actionCount: actionCount ?? this.actionCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Division && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
