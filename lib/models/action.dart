/// Base model class for all data models
abstract class BaseModel {
  /// Convert model to JSON
  Map<String, dynamic> toJson();

  /// Create model from JSON
  /// This should be implemented by subclasses
  static BaseModel fromJson(Map<String, dynamic> json) {
    throw UnimplementedError('fromJson() has not been implemented.');
  }
}

/// Action model representing a work/task action
class Action extends BaseModel {
  final String id;
  final String title;
  final String description;
  final String assignedTo;
  final String status;
  final DateTime dueDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Action({
    required this.id,
    required this.title,
    required this.description,
    required this.assignedTo,
    required this.status,
    required this.dueDate,
    this.createdAt,
    this.updatedAt,
  });

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'assignedTo': assignedTo,
      'status': status,
      'dueDate': dueDate.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory Action.fromJson(Map<String, dynamic> json) {
    return Action(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      assignedTo: json['assignedTo'] as String,
      status: json['status'] as String,
      dueDate: DateTime.parse(json['dueDate'] as String),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
    );
  }
}
