import 'package:flutter_test/flutter_test.dart';
import 'package:action_flow/features/calendar/models/calendar_task.dart';
import 'package:action_flow/services/calendar_task_service.dart';

void main() {
  group('CalendarTaskService PGRST205 Fallback & Offline Resilience Tests', () {
    test('1. CalendarTaskService creates and stores task in mock store when offline/uninitialized', () async {
      final service = CalendarTaskService();

      final task = CalendarTask(
        id: 'cal-task-01',
        userId: 'user-123',
        organizationId: '00000000-0000-0000-0000-000000000001',
        title: 'Safety audit walkthrough',
        description: 'Inspect Sector 4 emergency exits',
        dueDate: DateTime(2026, 11, 5, 10, 0),
        priority: 'high',
      );

      final created = await service.createTask(task);
      expect(created.id, isNotEmpty);
      expect(created.title, equals('Safety audit walkthrough'));

      final list = await service.getTasks(userId: 'user-123');
      expect(list.any((t) => t.title == 'Safety audit walkthrough'), isTrue);
    });

    test('2. CalendarTaskService updates, toggles, and deletes task in mock store', () async {
      final service = CalendarTaskService();

      final task = CalendarTask(
        id: 'cal-task-02',
        userId: 'user-456',
        title: 'Calibrate gas detector',
        dueDate: DateTime(2026, 11, 10, 14, 0),
        priority: 'medium',
        isCompleted: false,
      );

      final created = await service.createTask(task);

      // Toggle completion
      await service.toggleTaskCompletion(
        taskId: created.id,
        userId: 'user-456',
        isCompleted: true,
      );

      var list = await service.getTasks(userId: 'user-456');
      var updated = list.firstWhere((t) => t.id == created.id);
      expect(updated.isCompleted, isTrue);

      // Update description
      await service.updateTask(updated.copyWith(description: 'Calibrated with 50ppm gas'));
      list = await service.getTasks(userId: 'user-456');
      updated = list.firstWhere((t) => t.id == created.id);
      expect(updated.description, equals('Calibrated with 50ppm gas'));

      // Delete task
      await service.deleteTask(taskId: created.id, userId: 'user-456');
      list = await service.getTasks(userId: 'user-456');
      expect(list.any((t) => t.id == created.id), isFalse);
    });

    test('3. MockCalendarTaskStore correctly handles task isolation across different users', () async {
      final service = CalendarTaskService();

      final taskUserA = CalendarTask(
        id: 'task-a',
        userId: 'user-A',
        title: 'User A personal task',
        dueDate: DateTime.now(),
      );

      final taskUserB = CalendarTask(
        id: 'task-b',
        userId: 'user-B',
        title: 'User B personal task',
        dueDate: DateTime.now(),
      );

      await service.createTask(taskUserA);
      await service.createTask(taskUserB);

      final listA = await service.getTasks(userId: 'user-A');
      final listB = await service.getTasks(userId: 'user-B');

      expect(listA.any((t) => t.title == 'User A personal task'), isTrue);
      expect(listA.any((t) => t.title == 'User B personal task'), isFalse);

      expect(listB.any((t) => t.title == 'User B personal task'), isTrue);
      expect(listB.any((t) => t.title == 'User A personal task'), isFalse);
    });
  });
}

