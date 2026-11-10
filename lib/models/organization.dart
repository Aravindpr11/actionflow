import 'package:flutter/foundation.dart';

/// Represents a tenant organization (company) in the ActionFlow multi-company architecture.
@immutable
class Organization {
  final String id;
  final String name;
  final String code;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Deterministic ID and slug for Organization #1 (Sobha)
  static const String sobhaId = '00000000-0000-0000-0000-000000000001';
  static const String sobhaCode = 'sobha';
  static const String sobhaName = 'Sobha';

  const Organization({
    required this.id,
    required this.name,
    required this.code,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  /// Factory constructor for the default Sobha organization
  factory Organization.sobha() {
    return const Organization(
      id: sobhaId,
      name: sobhaName,
      code: sobhaCode,
      isActive: true,
    );
  }

  /// Parses an organization record from database or JSON map
  factory Organization.fromJson(Map<String, dynamic> json) {
    return Organization(
      id: json['id']?.toString() ?? sobhaId,
      name: json['name']?.toString() ?? sobhaName,
      code: json['code']?.toString() ?? sobhaCode,
      isActive: json['is_active'] == null ? true : (json['is_active'] as bool),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  /// Serializes the organization to JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'code': code,
      'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  /// Returns a copy of the organization with updated fields
  Organization copyWith({
    String? id,
    String? name,
    String? code,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Organization(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Whether this organization represents the default anchor organization (Sobha)
  bool get isSobha => id == sobhaId || code.toLowerCase() == sobhaCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Organization &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          code == other.code &&
          isActive == other.isActive;

  @override
  int get hashCode => Object.hash(id, name, code, isActive);

  @override
  String toString() =>
      'Organization(id: $id, name: $name, code: $code, isActive: $isActive)';
}
