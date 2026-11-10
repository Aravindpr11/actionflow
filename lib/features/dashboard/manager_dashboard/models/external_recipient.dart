class ExternalRecipient {
  const ExternalRecipient({
    required this.id,
    required this.organizationId,
    required this.fullName,
    required this.email,
    this.companyName = '',
    this.phone = '',
    this.createdBy = '',
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String organizationId;
  final String fullName;
  final String email;
  final String companyName;
  final String phone;
  final String createdBy;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ExternalRecipient copyWith({
    String? id,
    String? organizationId,
    String? fullName,
    String? email,
    String? companyName,
    String? phone,
    String? createdBy,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ExternalRecipient(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      companyName: companyName ?? this.companyName,
      phone: phone ?? this.phone,
      createdBy: createdBy ?? this.createdBy,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'organization_id': organizationId,
    'full_name': fullName,
    'email': email,
    'company_name': companyName,
    'phone': phone,
    'created_by': createdBy,
    'is_active': isActive,
    'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
  };

  factory ExternalRecipient.fromJson(Map<String, dynamic> json) {
    return ExternalRecipient(
      id: (json['id'] as String?) ?? '',
      organizationId: (json['organization_id'] as String?) ?? '',
      fullName: (json['full_name'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      companyName: (json['company_name'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
      createdBy: (json['created_by'] as String?) ?? '',
      isActive: json['is_active'] != false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }
}
