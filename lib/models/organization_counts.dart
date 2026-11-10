import 'package:flutter/foundation.dart';

/// Real-time aggregate count metrics for a tenant organization.
@immutable
class OrganizationCounts {
  final int users;
  final int departments;
  final int sites;

  const OrganizationCounts({
    this.users = 0,
    this.departments = 0,
    this.sites = 0,
  });

  factory OrganizationCounts.fromJson(Map<String, dynamic> json) {
    return OrganizationCounts(
      users: (json['users'] as num?)?.toInt() ?? 0,
      departments: (json['departments'] as num?)?.toInt() ?? 0,
      sites: (json['sites'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'users': users,
    'departments': departments,
    'sites': sites,
  };

  OrganizationCounts copyWith({int? users, int? departments, int? sites}) {
    return OrganizationCounts(
      users: users ?? this.users,
      departments: departments ?? this.departments,
      sites: sites ?? this.sites,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrganizationCounts &&
          runtimeType == other.runtimeType &&
          users == other.users &&
          departments == other.departments &&
          sites == other.sites;

  @override
  int get hashCode => Object.hash(users, departments, sites);

  @override
  String toString() =>
      'OrganizationCounts(users: $users, departments: $departments, sites: $sites)';
}
