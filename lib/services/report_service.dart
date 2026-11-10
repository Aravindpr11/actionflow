import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';

/// Immutable aggregated report data computed from a filtered list of [ActionRecord]s.
class ReportAggregates {
  const ReportAggregates({
    required this.total,
    required this.open,
    required this.overdue,
    required this.pendingReview,
    required this.closed,
    required this.avgCompletionPct,
    required this.byStatus,
    required this.byProgressBand,
    required this.byPriority,
    required this.byDepartment,
    required this.byDivision,
    required this.bySection,
    required this.bySite,
    required this.byAssignee,
    required this.monthlyTimeline,
    required this.followUpTimeline,
    required this.actions,
  });

  // ─── KPIs ────────────────────────────────────────────────────────────────
  final int total;
  final int open;
  final int overdue;
  final int pendingReview;
  final int closed;
  final double avgCompletionPct;

  // ─── Breakdowns ──────────────────────────────────────────────────────────
  final Map<String, int> byStatus;
  final Map<String, int> byProgressBand;
  final Map<String, int> byPriority;
  final Map<String, int> byDepartment;
  final Map<String, int> byDivision;
  final Map<String, int> bySection;
  final Map<String, int> bySite;
  final Map<String, int> byAssignee;

  // ─── Timelines ───────────────────────────────────────────────────────────
  /// Rolling 12-month trend: actions raised, closed, overdue per month.
  final List<MonthlyTrendPoint> monthlyTimeline;

  /// Rolling 12-month follow-up activity count per month.
  final List<MonthlyFollowUpPoint> followUpTimeline;

  // ─── Raw filtered list for drill-down ────────────────────────────────────
  final List<ActionRecord> actions;

  /// Empty aggregates used as initial state.
  static const ReportAggregates empty = ReportAggregates(
    total: 0,
    open: 0,
    overdue: 0,
    pendingReview: 0,
    closed: 0,
    avgCompletionPct: 0,
    byStatus: {},
    byProgressBand: {},
    byPriority: {},
    byDepartment: {},
    byDivision: {},
    bySection: {},
    bySite: {},
    byAssignee: {},
    monthlyTimeline: [],
    followUpTimeline: [],
    actions: [],
  );
}

/// One point in the monthly raised/closed/overdue timeline.
class MonthlyTrendPoint {
  const MonthlyTrendPoint({
    required this.year,
    required this.month,
    required this.label,
    required this.raised,
    required this.closed,
    required this.overdue,
  });

  final int year;
  final int month;
  final String label; // e.g. 'Sep 2026'
  final int raised;
  final int closed;
  final int overdue;
}

/// One point in the monthly follow-up timeline.
class MonthlyFollowUpPoint {
  const MonthlyFollowUpPoint({
    required this.year,
    required this.month,
    required this.label,
    required this.count,
  });

  final int year;
  final int month;
  final String label;
  final int count;
}

/// Pure-Dart report aggregation service.
///
/// Call [ReportService.compute] with a filtered [List<ActionRecord>] to get
/// [ReportAggregates] — all calculations are performed locally, no Supabase
/// calls are made.
class ReportService {
  const ReportService._();

  static const _monthNames = [
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

  static const List<String> kProgressBands = [
    '0–24%',
    '25–49%',
    '50–74%',
    '75–99%',
    '100%',
  ];

  static const List<String> kPriorityOrder = [
    'Critical',
    'High',
    'Medium',
    'Low',
  ];

  static const List<String> kDateFields = [
    'Raised Date',
    'Start Date',
    'Due Date',
    'Follow-Up Date',
    'Closed Date',
  ];

  static const List<String> kDatePresets = [
    'All Time',
    'Today',
    'This Week',
    'This Month',
    'Custom Range',
  ];

  // ─── Date helpers ─────────────────────────────────────────────────────────

  /// Parses a date string in multiple formats (ISO, DD Mon YYYY, etc.)
  /// into a date-only [DateTime] or null if unparseable.
  static DateTime? parseDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final str = raw.trim();

    // Try direct ISO parse first
    final direct = DateTime.tryParse(str);
    if (direct != null) {
      final local = direct.isUtc ? direct.toLocal() : direct;
      return DateTime(local.year, local.month, local.day);
    }

    // Handle DD Mon YYYY / DD-MM-YYYY / YYYY-MM-DD etc.
    try {
      final parts = str.split(RegExp(r'[\s\-/]+'));
      if (parts.length >= 3) {
        if (parts[0].length == 4) {
          final y = int.tryParse(parts[0]);
          final m = int.tryParse(parts[1]);
          final d = int.tryParse(parts[2]);
          if (y != null && m != null && d != null) return DateTime(y, m, d);
        }

        final day = int.tryParse(parts[0]);
        final year = int.tryParse(parts[2]);
        const months = {
          'jan': 1,
          'january': 1,
          'feb': 2,
          'february': 2,
          'mar': 3,
          'march': 3,
          'apr': 4,
          'april': 4,
          'may': 5,
          'jun': 6,
          'june': 6,
          'jul': 7,
          'july': 7,
          'aug': 8,
          'august': 8,
          'sep': 9,
          'september': 9,
          'oct': 10,
          'october': 10,
          'nov': 11,
          'november': 11,
          'dec': 12,
          'december': 12,
        };
        final month = months[parts[1].toLowerCase()] ?? int.tryParse(parts[1]);
        if (day != null && month != null && year != null) {
          return DateTime(year, month, day);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Returns the relevant dates for [action] under [dateField].
  static List<DateTime> datesForField(ActionRecord action, String dateField) {
    switch (dateField) {
      case 'Raised Date':
        final d = parseDate(action.dateRaised);
        return d != null ? [d] : [];
      case 'Start Date':
        final d = parseDate(action.startDate);
        return d != null ? [d] : [];
      case 'Due Date':
        final d = parseDate(action.targetDate);
        return d != null ? [d] : [];
      case 'Follow-Up Date':
        final set = <DateTime>{};
        final d1 = parseDate(action.nextFollowUpDate);
        if (d1 != null) set.add(d1);
        final d2 = parseDate(action.lastFollowUpDate);
        if (d2 != null) set.add(d2);
        for (final f in action.followUps) {
          final df = parseDate(f.followUpDate);
          if (df != null) set.add(df);
          if (f.createdAt != null) {
            final fc = f.createdAt!.isUtc
                ? f.createdAt!.toLocal()
                : f.createdAt!;
            set.add(DateTime(fc.year, fc.month, fc.day));
          }
        }
        return set.toList();
      case 'Closed Date':
        final set = <DateTime>{};
        if (action.closedAt != null) {
          final c = action.closedAt!.isUtc
              ? action.closedAt!.toLocal()
              : action.closedAt!;
          set.add(DateTime(c.year, c.month, c.day));
        }
        final d = parseDate(action.closeDate);
        if (d != null) set.add(d);
        return set.toList();
      default:
        // All Dates — union of all known dates
        final set = <DateTime>{};
        void add(DateTime? d) {
          if (d != null) set.add(d);
        }
        add(parseDate(action.dateRaised));
        add(parseDate(action.startDate));
        add(parseDate(action.targetDate));
        add(parseDate(action.nextFollowUpDate));
        add(parseDate(action.lastFollowUpDate));
        if (action.closedAt != null) {
          final c = action.closedAt!.isUtc
              ? action.closedAt!.toLocal()
              : action.closedAt!;
          set.add(DateTime(c.year, c.month, c.day));
        }
        add(parseDate(action.closeDate));
        for (final f in action.followUps) {
          add(parseDate(f.followUpDate));
        }
        return set.toList();
    }
  }

  /// Returns true if [d] falls within [preset] (optionally constrained by
  /// [customStart]/[customEnd] when preset == 'Custom Range').
  static bool matchesPeriod(
    DateTime d,
    String preset, {
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (preset) {
      case 'All Time':
      case '':
        return true;
      case 'Today':
        return d == today;
      case 'This Week':
        final monday = today.subtract(Duration(days: today.weekday - 1));
        final sunday = monday.add(const Duration(days: 6));
        return !d.isBefore(monday) && !d.isAfter(sunday);
      case 'This Month':
        return d.year == today.year && d.month == today.month;
      case 'Custom Range':
        if (customStart != null) {
          final cs = DateTime(
            customStart.year,
            customStart.month,
            customStart.day,
          );
          if (d.isBefore(cs)) return false;
        }
        if (customEnd != null) {
          final ce = DateTime(
            customEnd.year,
            customEnd.month,
            customEnd.day,
            23,
            59,
            59,
          );
          if (d.isAfter(ce)) return false;
        }
        return true;
      default:
        return true;
    }
  }

  /// Returns true if [action] satisfies the date filter combination.
  static bool matchesDateFilter(
    ActionRecord action,
    String dateField,
    String datePreset, {
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    if (datePreset == 'All Time' && dateField == 'All Dates') return true;

    final dates = datesForField(action, dateField);
    if (dates.isEmpty) {
      // If a specific date field was requested but no dates available → exclude
      if (dateField != 'All Dates') return false;
      return true;
    }
    if (datePreset == 'All Time') return true;

    return dates.any(
      (d) => matchesPeriod(
        d,
        datePreset,
        customStart: customStart,
        customEnd: customEnd,
      ),
    );
  }

  // ─── Filter helper ────────────────────────────────────────────────────────

  /// Applies report filter state to [allActions] and returns the matching subset.
  static List<ActionRecord> applyFilters(
    List<ActionRecord> allActions, {
    String dateField = 'All Dates',
    String datePreset = 'All Time',
    DateTime? customStart,
    DateTime? customEnd,
    String status = 'All Status',
    String priority = 'All Priority',
    String department = 'All Departments',
    String division = 'All Divisions',
    String section = 'All Sections',
    String site = 'All Sites',
    String assignee = 'All People',
  }) {
    return allActions.where((a) {
      // Status
      if (status != 'All Status') {
        if (status == 'Closed') {
          if (!a.isClosed) return false;
        } else if (status == 'Ready for Review') {
          if (!a.isReadyForReview) return false;
        } else if (status == 'Pending Review') {
          if (a.status.toLowerCase() != 'pending review' &&
              !a.isReadyForReview) {
            return false;
          }
        } else {
          if (a.status.toLowerCase() != status.toLowerCase()) return false;
        }
      }

      // Priority
      if (priority != 'All Priority') {
        if (a.priority.toLowerCase() != priority.toLowerCase()) return false;
      }

      // Org dimensions
      if (department != 'All Departments') {
        if (a.department.toLowerCase() != department.toLowerCase()) {
          return false;
        }
      }
      if (division != 'All Divisions') {
        if (a.division.toLowerCase() != division.toLowerCase()) return false;
      }
      if (section != 'All Sections') {
        if (a.section.toLowerCase() != section.toLowerCase()) return false;
      }
      if (site != 'All Sites') {
        if (a.site.toLowerCase() != site.toLowerCase()) return false;
      }

      // Assignee
      if (assignee != 'All People') {
        final name = a.isExternalRecipient
            ? (a.externalRecipientName ?? '').toLowerCase()
            : a.assignedTo.toLowerCase();
        if (!name.contains(assignee.toLowerCase())) return false;
      }

      // Date filter
      if (!matchesDateFilter(
        a,
        dateField,
        datePreset,
        customStart: customStart,
        customEnd: customEnd,
      )) {
        return false;
      }

      return true;
    }).toList();
  }

  // ─── Core aggregation ─────────────────────────────────────────────────────

  /// Computes [ReportAggregates] from the already-filtered [actions] list.
  ///
  /// This is pure local computation — no Supabase calls are made.
  static ReportAggregates compute(List<ActionRecord> actions) {
    if (actions.isEmpty) {
      return ReportAggregates.empty.copyWith(actions: actions);
    }

    // KPI accumulators
    int open = 0;
    int overdue = 0;
    int pendingReview = 0;
    int closed = 0;
    int totalPct = 0;

    final byStatus = <String, int>{};
    final byPriority = <String, int>{};
    final byDept = <String, int>{};
    final byDiv = <String, int>{};
    final bySect = <String, int>{};
    final bySite = <String, int>{};
    final byAssignee = <String, int>{};

    // Timeline: keyed by 'YYYY-MM'
    final raisedByMonth = <String, int>{};
    final closedByMonth = <String, int>{};
    final overdueByMonth = <String, int>{};
    final followUpByMonth = <String, int>{};

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Build 12-month rolling window
    final months = <String>[];
    for (int i = 11; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i, 1);
      months.add(_monthKey(m.year, m.month));
    }
    for (final k in months) {
      raisedByMonth[k] = 0;
      closedByMonth[k] = 0;
      overdueByMonth[k] = 0;
      followUpByMonth[k] = 0;
    }

    for (final a in actions) {
      final statusLower = a.status.trim().toLowerCase();
      totalPct += a.percentComplete;

      // KPIs
      if (a.isClosed) {
        closed++;
      } else {
        if (statusLower == 'open') {
          open++;
        } else if (statusLower == 'pending review' || a.isReadyForReview) {
          pendingReview++;
        }

        final targetDt = parseDate(a.targetDate);
        if (statusLower == 'overdue' ||
            (targetDt != null && targetDt.isBefore(today))) {
          overdue++;
        }
      }

      // Status breakdown (normalise)
      final displayStatus = _displayStatus(a);
      byStatus[displayStatus] = (byStatus[displayStatus] ?? 0) + 1;

      // Priority breakdown
      final p = a.priority.isNotEmpty ? a.priority : 'Unknown';
      byPriority[p] = (byPriority[p] ?? 0) + 1;

      // Org breakdowns
      final dept = a.department.isNotEmpty ? a.department : 'Unassigned';
      byDept[dept] = (byDept[dept] ?? 0) + 1;

      final div = a.division.isNotEmpty ? a.division : 'Unassigned';
      byDiv[div] = (byDiv[div] ?? 0) + 1;

      final sect = a.section.isNotEmpty ? a.section : 'Unassigned';
      bySect[sect] = (bySect[sect] ?? 0) + 1;

      final site = a.site.isNotEmpty ? a.site : 'Unassigned';
      bySite[site] = (bySite[site] ?? 0) + 1;

      final assigneeName = a.isExternalRecipient
          ? (a.externalRecipientName ?? 'External').trim()
          : a.assignedTo.trim().isEmpty
          ? 'Unassigned'
          : a.assignedTo.trim();
      byAssignee[assigneeName] = (byAssignee[assigneeName] ?? 0) + 1;

      // Raised timeline
      final raisedDt = parseDate(a.dateRaised);
      if (raisedDt != null) {
        final key = _monthKey(raisedDt.year, raisedDt.month);
        if (raisedByMonth.containsKey(key)) {
          raisedByMonth[key] = raisedByMonth[key]! + 1;
        }
      }

      // Closed timeline
      if (a.isClosed) {
        DateTime? closedDt = a.closedAt;
        if (closedDt == null && a.closeDate.isNotEmpty) {
          closedDt = parseDate(a.closeDate);
        }
        if (closedDt != null) {
          final local = closedDt.isUtc ? closedDt.toLocal() : closedDt;
          final key = _monthKey(local.year, local.month);
          if (closedByMonth.containsKey(key)) {
            closedByMonth[key] = closedByMonth[key]! + 1;
          }
        }
      }

      // Overdue timeline (count overdue actions by their target month)
      if (!a.isClosed) {
        final targetDt = parseDate(a.targetDate);
        if (targetDt != null && targetDt.isBefore(today)) {
          final key = _monthKey(targetDt.year, targetDt.month);
          if (overdueByMonth.containsKey(key)) {
            overdueByMonth[key] = overdueByMonth[key]! + 1;
          }
        }
      }

      // Follow-up timeline
      final fuDates = datesForField(a, 'Follow-Up Date');
      for (final fd in fuDates) {
        final key = _monthKey(fd.year, fd.month);
        if (followUpByMonth.containsKey(key)) {
          followUpByMonth[key] = followUpByMonth[key]! + 1;
        }
      }
    }

    // Progress bands
    final byProgressBand = <String, int>{for (final b in kProgressBands) b: 0};
    for (final a in actions) {
      final pct = a.percentComplete;
      if (pct >= 100) {
        byProgressBand['100%'] = byProgressBand['100%']! + 1;
      } else if (pct >= 75) {
        byProgressBand['75–99%'] = byProgressBand['75–99%']! + 1;
      } else if (pct >= 50) {
        byProgressBand['50–74%'] = byProgressBand['50–74%']! + 1;
      } else if (pct >= 25) {
        byProgressBand['25–49%'] = byProgressBand['25–49%']! + 1;
      } else {
        byProgressBand['0–24%'] = byProgressBand['0–24%']! + 1;
      }
    }

    // Build timeline lists
    final monthlyTimeline = months.map((key) {
      final parts = key.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      return MonthlyTrendPoint(
        year: year,
        month: month,
        label: '${_monthNames[month]} $year',
        raised: raisedByMonth[key] ?? 0,
        closed: closedByMonth[key] ?? 0,
        overdue: overdueByMonth[key] ?? 0,
      );
    }).toList();

    final followUpTimeline = months.map((key) {
      final parts = key.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      return MonthlyFollowUpPoint(
        year: year,
        month: month,
        label: '${_monthNames[month]} $year',
        count: followUpByMonth[key] ?? 0,
      );
    }).toList();

    final total = actions.length;
    final avgPct = total > 0 ? totalPct / total : 0.0;

    return ReportAggregates(
      total: total,
      open: open,
      overdue: overdue,
      pendingReview: pendingReview,
      closed: closed,
      avgCompletionPct: avgPct,
      byStatus: byStatus,
      byProgressBand: byProgressBand,
      byPriority: byPriority,
      byDepartment: byDept,
      byDivision: byDiv,
      bySection: bySect,
      bySite: bySite,
      byAssignee: byAssignee,
      monthlyTimeline: monthlyTimeline,
      followUpTimeline: followUpTimeline,
      actions: actions,
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  static String _monthKey(int year, int month) =>
      '$year-${month.toString().padLeft(2, '0')}';

  /// Normalised display status for chart grouping.
  static String _displayStatus(ActionRecord a) {
    if (a.isClosed) return 'Closed';
    if (a.isReadyForReview && a.status.toLowerCase() != 'pending review') {
      return 'Pending Review';
    }
    final s = a.status.trim();
    return s.isEmpty ? 'Open' : s;
  }
}

extension _ReportAggregatesX on ReportAggregates {
  ReportAggregates copyWith({List<ActionRecord>? actions}) {
    return ReportAggregates(
      total: total,
      open: open,
      overdue: overdue,
      pendingReview: pendingReview,
      closed: closed,
      avgCompletionPct: avgCompletionPct,
      byStatus: byStatus,
      byProgressBand: byProgressBand,
      byPriority: byPriority,
      byDepartment: byDepartment,
      byDivision: byDivision,
      bySection: bySection,
      bySite: bySite,
      byAssignee: byAssignee,
      monthlyTimeline: monthlyTimeline,
      followUpTimeline: followUpTimeline,
      actions: actions ?? this.actions,
    );
  }
}
