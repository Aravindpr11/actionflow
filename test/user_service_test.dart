import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/users/models/team.dart';
import 'package:action_flow/services/user_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserService Unit Tests', () {
    late UserService service;
    const testOrgId = 'sobha-const-001';

    setUp(() {
      service = UserService.instance;
    });

    test('UserService is a singleton instance', () {
      final s1 = UserService.instance;
      final s2 = UserService.instance;
      expect(identical(s1, s2), isTrue);
    });

    test('fetchUsers returns people directory with internal and external users in offline mode', () async {
      final users = await service.fetchUsers(testOrgId);
      expect(users, isNotEmpty);

      // Verify presence of internal users
      final hasInternal = users.any((u) => u.type == PersonType.internalUser);
      expect(hasInternal, isTrue);

      // Verify presence of external staff
      final hasExternal = users.any((u) => u.type == PersonType.externalWorker);
      expect(hasExternal, isTrue);

      // Verify all required directory fields are populated
      for (final u in users) {
        expect(u.id, isNotEmpty);
        expect(u.name, isNotEmpty);
        expect(u.email, isNotEmpty);
        expect(u.designation, isNotEmpty);
      }
    });

    test(
      'UserRole enum supports admin, departmentManager, and actionOwnerWorker',
      () {
        expect(UserRole.admin.label, 'System Administrator');
        expect(UserRole.departmentManager.label, 'Department Manager');
        expect(UserRole.actionOwnerWorker.label, 'Action Owner / Staff');
      },
    );

    test('Person model copyWith supports departmentId, siteId, roleId, organizationId', () {
      final person = Person(
        id: 'TEST-001',
        name: 'Test Person',
        email: 'test@actionflow.demo',
        phone: '+971 50 123 4567',
        designation: 'Safety Officer',
        type: PersonType.internalUser,
        isActive: true,
        role: UserRole.admin,
        department: 'HSE',
        site: 'Tower 1',
        departmentId: 'dept-uuid-001',
        siteId: 'site-uuid-001',
        roleId: 'role-uuid-001',
        organizationId: testOrgId,
      );

      expect(person.departmentId, 'dept-uuid-001');
      expect(person.siteId, 'site-uuid-001');
      expect(person.roleId, 'role-uuid-001');
      expect(person.organizationId, testOrgId);
      expect(person.role, UserRole.admin);

      final updated = person.copyWith(
        name: 'Updated Name',
        isActive: false,
        departmentId: 'dept-uuid-002',
        role: UserRole.departmentManager,
      );

      expect(updated.name, 'Updated Name');
      expect(updated.isActive, isFalse);
      expect(updated.departmentId, 'dept-uuid-002');
      expect(updated.siteId, 'site-uuid-001'); // Preserved
      expect(updated.role, UserRole.departmentManager);
    });

    test('updateUser updates in-memory store in offline mode', () async {
      final existing = MockPeopleStore.instance.people.first;
      final originalName = existing.name;
      final updatedName = '$originalName (Modified)';

      final modified = existing.copyWith(name: updatedName);
      await service.updateUser(organizationId: testOrgId, person: modified);

      final found = MockPeopleStore.instance.people.firstWhere(
        (p) => p.id == existing.id,
      );
      expect(found.name, updatedName);

      // Revert back
      await service.updateUser(organizationId: testOrgId, person: existing);
      final reverted = MockPeopleStore.instance.people.firstWhere(
        (p) => p.id == existing.id,
      );
      expect(reverted.name, originalName);
    });

    test('toggleUserStatus updates person active status', () async {
      final existing = MockPeopleStore.instance.people.first;
      final originalStatus = existing.isActive;

      await service.toggleUserStatus(
        organizationId: testOrgId,
        profileId: existing.id,
        isActive: !originalStatus,
      );

      final toggled = MockPeopleStore.instance.people.firstWhere(
        (p) => p.id == existing.id,
      );
      expect(toggled.isActive, !originalStatus);

      // Revert back
      await service.toggleUserStatus(
        organizationId: testOrgId,
        profileId: existing.id,
        isActive: originalStatus,
      );

      final restored = MockPeopleStore.instance.people.firstWhere(
        (p) => p.id == existing.id,
      );
      expect(restored.isActive, originalStatus);
    });

    test('createUser adds new external staff to store', () async {
      final uniqueId = 'EXT-TEST-${DateTime.now().millisecondsSinceEpoch}';
      final newPerson = Person(
        id: uniqueId,
        name: 'Contractor Specialist',
        email: 'contractor.$uniqueId@external.demo',
        phone: '+971 55 999 8888',
        designation: 'Scaffolding Inspector',
        type: PersonType.externalWorker,
        isActive: true,
        company: 'Apex Contracting LLC',
        site: 'Dubai Marina Tower',
      );

      await service.createUser(organizationId: testOrgId, person: newPerson);

      final found = MockPeopleStore.instance.people.firstWhere(
        (p) => p.id == uniqueId,
      );
      expect(found.name, 'Contractor Specialist');
      expect(found.company, 'Apex Contracting LLC');
      expect(found.type, PersonType.externalWorker);
    });
  });
}
