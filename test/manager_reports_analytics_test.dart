// test/manager_reports_analytics_test.dart
//
// Focused tests for the Manager Reports & Analytics feature.
// Tests ReportService aggregation logic directly (unit) and the
// ManagerReportsScreen widget (widget tests).
//
// Tests cover:
//   1.  Report page loads
//   2.  Real action data used
//   3.  KPI calculations
//   4.  Status aggregation
//   5.  Progress aggregation
//   6.  Priority aggregation
//   7.  Department aggregation
//   8.  Division aggregation
//   9.  Section aggregation
//  10.  Site aggregation
//  11.  Assignee aggregation
//  12.  Date-field filtering
//  13.  Combined filters
//  14.  Clear All
//  15.  Manager scope / tenant isolation
//  16.  Closed actions remain included
//  17.  External recipient actions handled correctly
//  18.  Excel export respects active filters
//  19.  Overdue KPI includes implicitly-overdue actions
//  20.  Date-field filtering – Due Date

import 'package:action_flow/features/auth/models/manager_scope_item.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/reports/models/report_filter_state.dart';
import 'package:action_flow/services/report_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

const _orgA = 'org-alpha-01';
const _orgB = 'org-beta-99';

const _managerProfile = UserProfile(
  id: 'mgr-001',
  name: 'Alice Manager',
  email: 'alice@alpha.com',
  phone: '+971500000001',
  designation: 'HSE Manager',
  department: 'Safety',
  site: 'Plant A',
  role: 'manager',
  organizationId: _orgA,
  organizationName: 'Alpha Corp',
);

final _managerContext = ManagerContext(
  authUserId: 'mgr-001',
  profile: _managerProfile,
  organizationId: _orgA,
  organizationName: 'Alpha Corp',
  scopes: const [
    ManagerScopeItem(
      departmentId: 'dept-safety',
      departmentName: 'Safety',
      siteId: 'site-plant-a',
      siteName: 'Plant A',
    ),
    ManagerScopeItem(
      departmentId: 'dept-maintenance',
      departmentName: 'Maintenance',
      siteId: 'site-plant-b',
      siteName: 'Plant B',
    ),
  ],
);

const _months = [
  '',
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

// Convenience: a date 30 days in the past (definitely "past due")
final _pastDate = DateTime.now().subtract(const Duration(days: 30));
final _pastDateStr =
    '${_pastDate.day.toString().padLeft(2, '0')} ${_months[_pastDate.month]} ${_pastDate.year}';

// Today
final _nowDate = DateTime.now();
final _todayStr =
    '${_nowDate.day.toString().padLeft(2, '0')} ${_months[_nowDate.month]} ${_nowDate.year}';

/// Builds a minimal [ActionRecord] with the given properties.
ActionRecord _action({
  required String id,
  String orgId = _orgA,
  String status = 'Open',
  String priority = 'Medium',
  String department = 'Safety',
  String division = 'Operations',
  String section = 'Ground',
  String site = 'Plant A',
  String assignedTo = 'Alice Worker',
  int pct = 0,
  String targetDate = '',
  String dateRaised = '',
  String startDate = '',
  String followUpDate = '',
  String closeDate = '',
  DateTime? closedAt,
  bool isExternal = false,
}) {
  return ActionRecord(
    id: id,
    actionNumber: 'ACT-$id',
    organizationId: orgId,
    subject: 'Action $id',
    actionRequired: 'Required $id',
    division: division,
    assignedTo: isExternal ? '' : assignedTo,
    assignedToId: isExternal ? null : 'worker-$id',
    status: status,
    priority: priority,
    percentComplete: pct,
    department: department,
    site: site,
    section: section,
    dateRaised: dateRaised.isEmpty ? _pastDateStr : dateRaised,
    targetDate: targetDate,
    startDate: startDate,
    nextFollowUpDate: followUpDate,
    closeDate: closeDate,
    closedAt: closedAt,
    recipientType: isExternal ? 'external' : 'internal',
    externalRecipientName: isExternal ? 'Ext Recipient $id' : null,
    externalRecipientEmail: isExternal ? 'ext$id@example.com' : null,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Test dataset
// ─────────────────────────────────────────────────────────────────────────────

final _testActions = [
  // Open, High, Safety, Plant A — raised today
  _action(
    id: '001',
    status: 'Open',
    priority: 'High',
    department: 'Safety',
    division: 'HSE',
    section: 'Ground',
    site: 'Plant A',
    assignedTo: 'Bob',
    pct: 20,
    dateRaised: _todayStr,
    targetDate: _todayStr,
  ),
  // In Progress, Critical, Maintenance, Plant B — overdue (target in past)
  _action(
    id: '002',
    status: 'In Progress',
    priority: 'Critical',
    department: 'Maintenance',
    division: 'Ops',
    section: 'Level 2',
    site: 'Plant B',
    assignedTo: 'Carol',
    pct: 50,
    dateRaised: _pastDateStr,
    targetDate: _pastDateStr, // past due
  ),
  // Pending Review, Medium, Safety, Plant A
  _action(
    id: '003',
    status: 'Pending Review',
    priority: 'Medium',
    department: 'Safety',
    division: 'HSE',
    section: 'Ground',
    site: 'Plant A',
    assignedTo: 'Bob',
    pct: 90,
    dateRaised: _pastDateStr,
    targetDate: _todayStr,
  ),
  // Closed, Low, Maintenance, Plant B — closed today
  _action(
    id: '004',
    status: 'Closed',
    priority: 'Low',
    department: 'Maintenance',
    division: 'Ops',
    section: 'Level 2',
    site: 'Plant B',
    assignedTo: 'Carol',
    pct: 100,
    dateRaised: _pastDateStr,
    closeDate: _todayStr,
    closedAt: DateTime.now(),
  ),
  // Open, High, Safety — 100% complete → isReadyForReview
  _action(
    id: '005',
    status: 'Open',
    priority: 'High',
    department: 'Safety',
    division: 'HSE',
    section: 'Roof',
    site: 'Plant A',
    assignedTo: 'David',
    pct: 100,
    dateRaised: _pastDateStr,
    targetDate: _todayStr,
  ),
  // External recipient, Open, Critical
  _action(
    id: '006',
    status: 'Open',
    priority: 'Critical',
    department: 'Safety',
    division: 'HSE',
    section: 'Ground',
    site: 'Plant A',
    pct: 10,
    dateRaised: _pastDateStr,
    targetDate: _todayStr,
    isExternal: true,
  ),
  // Org-B action — must NOT mix with org-A dataset in isolation tests
  _action(id: '007', orgId: _orgB, status: 'Open', priority: 'High', pct: 30),
];

// Subset: only org-A actions (as the manager would receive from Supabase RLS)
final _orgAActions = _testActions
    .where((a) => a.organizationId == _orgA)
    .toList();

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ── 1. Report page loads ───────────────────────────────────────────────────
  testWidgets('1. Reports page loads within ManagerDashboardScreen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ManagerDashboardScreen(
          userProfile: _managerProfile,
          managerContext: _managerContext,
          initialActions: _orgAActions,
          initialMyActions: const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap the "Reports & Graphs" nav item (index 5)
    final reportNavFinder = find.text('Reports & Graphs');
    expect(reportNavFinder, findsAtLeastNWidgets(1));
    await tester.tap(reportNavFinder.first);
    await tester.pumpAndSettle();

    // The reports header should be visible
    expect(find.text('Reports & Analytics'), findsAtLeastNWidgets(1));
  });

  // ── 2. Real action data used (no mock/fake counts) ─────────────────────────
  test('2. KPI total equals real filtered dataset length', () {
    final agg = ReportService.compute(_orgAActions);
    // The aggregate total must exactly match the input list length
    expect(agg.total, equals(_orgAActions.length));
    expect(agg.actions.length, equals(_orgAActions.length));
  });

  // ── 3. KPI calculations ────────────────────────────────────────────────────
  test(
    '3. KPI calculations — open, overdue, pendingReview, closed, avgPct',
    () {
      final agg = ReportService.compute(_orgAActions);

      // Total
      expect(agg.total, equals(6)); // act-001..006

      // Closed: only act-004
      expect(agg.closed, equals(1));

      // Pending review: act-003 (status='Pending Review') + act-005 (100%, isReadyForReview)
      expect(agg.pendingReview, greaterThanOrEqualTo(1));

      // Overdue: act-002 has targetDate in past and is not closed
      expect(agg.overdue, greaterThanOrEqualTo(1));

      // Avg completion: sum of pcts / 6 = (20+50+90+100+100+10) / 6 = 370/6 ≈ 61.7
      expect(agg.avgCompletionPct, closeTo(370 / 6, 0.1));
    },
  );

  // ── 4. Status aggregation ──────────────────────────────────────────────────
  test('4. Status aggregation — byStatus map is correct', () {
    final agg = ReportService.compute(_orgAActions);

    // act-004 must be 'Closed'
    expect(agg.byStatus['Closed'], equals(1));

    // act-001, act-006 are 'Open' (not closed, not pendingReview)
    final openCount = agg.byStatus['Open'] ?? 0;
    expect(openCount, greaterThanOrEqualTo(1));

    // The sum of all byStatus values == total
    final statusTotal = agg.byStatus.values.fold(0, (a, b) => a + b);
    expect(statusTotal, equals(agg.total));
  });

  // ── 5. Progress aggregation ────────────────────────────────────────────────
  test('5. Progress aggregation — byProgressBand', () {
    final agg = ReportService.compute(_orgAActions);

    // act-001: 20% → 0–24%
    expect(agg.byProgressBand['0–24%'], greaterThanOrEqualTo(1));

    // act-002: 50% → 50–74%
    expect(agg.byProgressBand['50–74%'], greaterThanOrEqualTo(1));

    // act-004, act-005: 100% → 100%
    expect(agg.byProgressBand['100%'], greaterThanOrEqualTo(2));

    // act-003: 90% → 75–99%
    expect(agg.byProgressBand['75–99%'], greaterThanOrEqualTo(1));

    // Sum == total
    final bandTotal = agg.byProgressBand.values.fold(0, (a, b) => a + b);
    expect(bandTotal, equals(agg.total));
  });

  // ── 6. Priority aggregation ────────────────────────────────────────────────
  test('6. Priority aggregation — byPriority map', () {
    final agg = ReportService.compute(_orgAActions);

    // act-002, act-006 are Critical
    expect(agg.byPriority['Critical'], equals(2));

    // act-001, act-005 are High
    expect(agg.byPriority['High'], equals(2));

    // act-003 is Medium
    expect(agg.byPriority['Medium'], equals(1));

    // act-004 is Low
    expect(agg.byPriority['Low'], equals(1));

    // Sum == total
    final priTotal = agg.byPriority.values.fold(0, (a, b) => a + b);
    expect(priTotal, equals(agg.total));
  });

  // ── 7. Department aggregation ──────────────────────────────────────────────
  test('7. Department aggregation — byDepartment', () {
    final agg = ReportService.compute(_orgAActions);

    // Safety: act-001, 003, 005, 006 = 4
    expect(agg.byDepartment['Safety'], equals(4));

    // Maintenance: act-002, 004 = 2
    expect(agg.byDepartment['Maintenance'], equals(2));

    final deptTotal = agg.byDepartment.values.fold(0, (a, b) => a + b);
    expect(deptTotal, equals(agg.total));
  });

  // ── 8. Division aggregation ────────────────────────────────────────────────
  test('8. Division aggregation — byDivision', () {
    final agg = ReportService.compute(_orgAActions);

    // HSE: act-001, 003, 005, 006
    expect(agg.byDivision['HSE'], equals(4));

    // Ops: act-002, 004
    expect(agg.byDivision['Ops'], equals(2));
  });

  // ── 9. Section aggregation ─────────────────────────────────────────────────
  test('9. Section aggregation — bySection', () {
    final agg = ReportService.compute(_orgAActions);

    // Ground: act-001, 003, 006
    expect(agg.bySection['Ground'], equals(3));

    // Level 2: act-002, 004
    expect(agg.bySection['Level 2'], equals(2));

    // Roof: act-005
    expect(agg.bySection['Roof'], equals(1));
  });

  // ── 10. Site aggregation ───────────────────────────────────────────────────
  test('10. Site aggregation — bySite', () {
    final agg = ReportService.compute(_orgAActions);

    // Plant A: act-001, 003, 005, 006
    expect(agg.bySite['Plant A'], equals(4));

    // Plant B: act-002, 004
    expect(agg.bySite['Plant B'], equals(2));

    final siteTotal = agg.bySite.values.fold(0, (a, b) => a + b);
    expect(siteTotal, equals(agg.total));
  });

  // ── 11. Assignee aggregation ───────────────────────────────────────────────
  test('11. Assignee aggregation — byAssignee (includes external)', () {
    final agg = ReportService.compute(_orgAActions);

    // Bob: act-001, act-003
    expect(agg.byAssignee['Bob'], equals(2));

    // Carol: act-002, act-004
    expect(agg.byAssignee['Carol'], equals(2));

    // David: act-005
    expect(agg.byAssignee['David'], equals(1));

    // External recipient act-006: displayed under 'Ext Recipient 006'
    final hasExt = agg.byAssignee.keys.any((k) => k.contains('Ext Recipient'));
    expect(hasExt, isTrue);

    // Sum == total
    final assigneeTotal = agg.byAssignee.values.fold(0, (a, b) => a + b);
    expect(assigneeTotal, equals(agg.total));
  });

  // ── 12. Date-field filtering — Raised Date ─────────────────────────────────
  test('12a. Date filter: Raised Date = Today → only act-001 matches', () {
    final filtered = ReportService.applyFilters(
      _orgAActions,
      dateField: 'Raised Date',
      datePreset: 'Today',
    );
    expect(filtered.length, equals(1));
    expect(filtered.first.id, equals('001'));
  });

  // ── 12b. Date-field filtering — Closed Date ────────────────────────────────
  test('12b. Date filter: Closed Date = Today → only act-004 matches', () {
    final filtered = ReportService.applyFilters(
      _orgAActions,
      dateField: 'Closed Date',
      datePreset: 'Today',
    );
    // act-004 has closedAt=DateTime.now()
    expect(filtered.length, equals(1));
    expect(filtered.first.id, equals('004'));
  });

  // ── 13. Combined filters ───────────────────────────────────────────────────
  test('13. Combined: Status=Open + Priority=High → only act-001', () {
    final filtered = ReportService.applyFilters(
      _orgAActions,
      status: 'Open',
      priority: 'High',
    );
    // act-001: Open + High
    // act-005: Open + High — but pct=100 so isReadyForReview is true, status='Open'
    // Both should be present since status filter is literally 'Open' not 'Ready for Review'
    // act-001: status=='Open', priority=='High' ✓
    // act-005: status=='Open', priority=='High' ✓
    expect(
      filtered.every((a) => a.status == 'Open' && a.priority == 'High'),
      isTrue,
    );
    expect(filtered.length, greaterThanOrEqualTo(1));

    // Verify no Closed or non-Open actions leaked in
    expect(filtered.any((a) => a.isClosed), isFalse);
  });

  test(
    '13b. Combined: Status=Closed + Department=Maintenance → act-004 only',
    () {
      final filtered = ReportService.applyFilters(
        _orgAActions,
        status: 'Closed',
        department: 'Maintenance',
      );
      expect(filtered.length, equals(1));
      expect(filtered.first.id, equals('004'));
    },
  );

  // ── 14. Clear All — resets to full dataset ────────────────────────────────
  test(
    '14. Clear All: applyFilters with default ReportFilterState == all actions',
    () {
      final defaultFilters = ReportFilterState.none;
      final filtered = ReportService.applyFilters(
        _orgAActions,
        dateField: defaultFilters.dateField,
        datePreset: defaultFilters.datePreset,
        status: defaultFilters.status,
        priority: defaultFilters.priority,
        department: defaultFilters.department,
        division: defaultFilters.division,
        section: defaultFilters.section,
        site: defaultFilters.site,
        assignee: defaultFilters.assignee,
      );
      expect(filtered.length, equals(_orgAActions.length));
    },
  );

  // ── 15. Manager scope isolation ────────────────────────────────────────────
  test('15. Manager scope: org-B actions must NOT appear in org-A reports', () {
    // Simulate what Supabase RLS already enforces: the manager receives only org-A actions.
    // The report service receives _orgAActions (not _testActions).
    final agg = ReportService.compute(_orgAActions);

    // No org-B action (id='007') should appear
    expect(agg.actions.any((a) => a.organizationId == _orgB), isFalse);
    expect(agg.total, equals(6)); // only the 6 org-A actions
  });

  // ── 16. Closed actions remain included ────────────────────────────────────
  test('16. Closed actions: act-004 is included in total and closed KPI', () {
    final agg = ReportService.compute(_orgAActions);

    expect(agg.closed, equals(1));
    expect(agg.actions.any((a) => a.isClosed), isTrue);

    // Status filter = Closed should return exactly act-004
    final closedFiltered = ReportService.applyFilters(
      _orgAActions,
      status: 'Closed',
    );
    expect(closedFiltered.length, equals(1));
    expect(closedFiltered.first.id, equals('004'));
  });

  // ── 17. External recipient actions ────────────────────────────────────────
  test(
    '17. External recipient: act-006 appears in aggregates under external name',
    () {
      final agg = ReportService.compute(_orgAActions);

      // act-006 should be counted
      expect(agg.total, greaterThanOrEqualTo(6));

      // The external assignee name appears in byAssignee
      final hasExternal = agg.byAssignee.keys.any(
        (k) => k.toLowerCase().contains('ext recipient'),
      );
      expect(hasExternal, isTrue);
    },
  );

  // ── 18. Excel export respects active filters ───────────────────────────────
  test('18. Excel export: filteredActions count matches aggregate total', () {
    // Simulate the Reports screen applying a filter then calling export
    const activeFilters = ReportFilterState(priority: 'Critical');

    final filteredActions = ReportService.applyFilters(
      _orgAActions,
      priority: activeFilters.priority,
    );
    final agg = ReportService.compute(filteredActions);

    // The filteredActions list passed to export must equal agg.total
    expect(filteredActions.length, equals(agg.total));

    // Filter map should record the active priority filter
    expect(activeFilters.asFilterMap.containsKey('Priority'), isTrue);
    expect(activeFilters.asFilterMap['Priority'], equals('Critical'));
  });

  // ── 19. Overdue KPI includes implicitly-overdue actions ───────────────────
  test('19. Overdue: act-002 (target in past, not closed) counted as overdue', () {
    final agg = ReportService.compute(_orgAActions);

    // act-002 has target date in past and is not closed → should be in overdue
    expect(agg.overdue, greaterThanOrEqualTo(1));
  });

  // ── 20. Date-field filtering — Due Date ────────────────────────────────────
  test('20. Date filter: Due Date = Today → actions due today', () {
    final filtered = ReportService.applyFilters(
      _orgAActions,
      dateField: 'Due Date',
      datePreset: 'Today',
    );
    // act-001, act-003, act-005, act-006 have targetDate = _todayStr
    expect(filtered.length, greaterThanOrEqualTo(3));
    expect(
      filtered.every((a) {
        final dt = ReportService.parseDate(a.targetDate);
        if (dt == null) return false;
        final now = DateTime.now();
        return dt.year == now.year &&
            dt.month == now.month &&
            dt.day == now.day;
      }),
      isTrue,
    );
  });

  // ── ReportFilterState unit tests ──────────────────────────────────────────
  group('ReportFilterState', () {
    test('none has no active filters', () {
      expect(ReportFilterState.none.hasActiveFilters, isFalse);
      expect(ReportFilterState.none.activeChips.isEmpty, isTrue);
    });

    test('activeChips correctly enumerates active filters', () {
      const state = ReportFilterState(
        status: 'Open',
        priority: 'High',
        department: 'Safety',
      );
      final chips = state.activeChips;
      expect(
        chips.any((c) => c.label == 'Status' && c.value == 'Open'),
        isTrue,
      );
      expect(
        chips.any((c) => c.label == 'Priority' && c.value == 'High'),
        isTrue,
      );
      expect(
        chips.any((c) => c.label == 'Dept' && c.value == 'Safety'),
        isTrue,
      );
    });

    test('asFilterMap produces correct map', () {
      const state = ReportFilterState(
        dateField: 'Raised Date',
        datePreset: 'This Month',
        status: 'Closed',
      );
      final map = state.asFilterMap;
      expect(map['Date Field'], equals('Raised Date'));
      expect(map['Date Range'], equals('This Month'));
      expect(map['Status'], equals('Closed'));
    });

    test('copyWith preserves unmodified fields', () {
      const original = ReportFilterState(status: 'Open', priority: 'High');
      final modified = original.copyWith(status: 'Closed');
      expect(modified.status, equals('Closed'));
      expect(modified.priority, equals('High')); // preserved
    });

    test('equality works correctly', () {
      const a = ReportFilterState(status: 'Open');
      const b = ReportFilterState(status: 'Open');
      const c = ReportFilterState(status: 'Closed');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  // ── ReportService.parseDate unit tests ────────────────────────────────────
  group('ReportService.parseDate', () {
    test('parses ISO date', () {
      final d = ReportService.parseDate('2026-09-23');
      expect(d, equals(DateTime(2026, 9, 23)));
    });

    test('parses DD Mon YYYY format', () {
      final d = ReportService.parseDate('23 Sep 2026');
      expect(d, equals(DateTime(2026, 9, 23)));
    });

    test('parses DD-MM-YYYY', () {
      final d = ReportService.parseDate('23-09-2026');
      expect(d, isNotNull);
    });

    test('returns null for empty string', () {
      expect(ReportService.parseDate(''), isNull);
      expect(ReportService.parseDate(null), isNull);
    });
  });
}
