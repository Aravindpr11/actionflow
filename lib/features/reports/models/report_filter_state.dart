/// Immutable value object that holds the active report filter state.
///
/// Passed from [ManagerReportsScreen] down to [ReportService.applyFilters]
/// and from [_buildActiveContent] to the Excel export method.
class ReportFilterState {
  const ReportFilterState({
    this.dateField = 'All Dates',
    this.datePreset = 'All Time',
    this.customStart,
    this.customEnd,
    this.status = 'All Status',
    this.priority = 'All Priority',
    this.department = 'All Departments',
    this.division = 'All Divisions',
    this.section = 'All Sections',
    this.site = 'All Sites',
    this.assignee = 'All People',
  });

  // ─── Date filters ─────────────────────────────────────────────────────────
  /// Which date field the date filter applies to.
  final String dateField; // 'All Dates' | 'Raised Date' | 'Start Date' | 'Due Date' | 'Follow-Up Date' | 'Closed Date'

  /// The date range preset.
  final String datePreset; // 'All Time' | 'Today' | 'This Week' | 'This Month' | 'Custom Range'

  /// Custom range start (only used when [datePreset] == 'Custom Range').
  final DateTime? customStart;

  /// Custom range end (only used when [datePreset] == 'Custom Range').
  final DateTime? customEnd;

  // ─── Categorical filters ──────────────────────────────────────────────────
  final String status;
  final String priority;
  final String department;
  final String division;
  final String section;
  final String site;
  final String assignee;

  // ─── Derived helpers ──────────────────────────────────────────────────────

  bool get hasActiveFilters =>
      dateField != 'All Dates' ||
      (datePreset != 'All Time' && datePreset.isNotEmpty) ||
      status != 'All Status' ||
      priority != 'All Priority' ||
      department != 'All Departments' ||
      division != 'All Divisions' ||
      section != 'All Sections' ||
      site != 'All Sites' ||
      assignee != 'All People';

  /// Returns active filter chips as (label, value) pairs.
  List<({String label, String value})> get activeChips {
    final chips = <({String label, String value})>[];
    if (dateField != 'All Dates') {
      chips.add((label: 'Date Field', value: dateField));
    }
    if (datePreset != 'All Time' && datePreset.isNotEmpty) {
      if (datePreset == 'Custom Range' &&
          customStart != null &&
          customEnd != null) {
        final s = customStart!;
        final e = customEnd!;
        chips.add((
          label: 'Date Range',
          value:
              '${s.day.toString().padLeft(2, '0')}/${s.month.toString().padLeft(2, '0')}/${s.year}'
              ' – '
              '${e.day.toString().padLeft(2, '0')}/${e.month.toString().padLeft(2, '0')}/${e.year}',
        ));
      } else {
        chips.add((label: 'Date', value: datePreset));
      }
    }
    if (status != 'All Status') chips.add((label: 'Status', value: status));
    if (priority != 'All Priority') {
      chips.add((label: 'Priority', value: priority));
    }
    if (department != 'All Departments') {
      chips.add((label: 'Dept', value: department));
    }
    if (division != 'All Divisions') {
      chips.add((label: 'Division', value: division));
    }
    if (section != 'All Sections') {
      chips.add((label: 'Section', value: section));
    }
    if (site != 'All Sites') chips.add((label: 'Site', value: site));
    if (assignee != 'All People') {
      chips.add((label: 'Assignee', value: assignee));
    }
    return chips;
  }

  /// Returns the filter state as a flat map suitable for Excel export metadata.
  Map<String, String> get asFilterMap {
    final m = <String, String>{};
    if (dateField != 'All Dates') m['Date Field'] = dateField;
    if (datePreset != 'All Time' && datePreset.isNotEmpty) {
      m['Date Range'] = datePreset;
      if (datePreset == 'Custom Range' &&
          customStart != null &&
          customEnd != null) {
        final s = customStart!;
        final e = customEnd!;
        m['Custom Start'] =
            '${s.day.toString().padLeft(2, '0')}/${s.month.toString().padLeft(2, '0')}/${s.year}';
        m['Custom End'] =
            '${e.day.toString().padLeft(2, '0')}/${e.month.toString().padLeft(2, '0')}/${e.year}';
      }
    }
    if (status != 'All Status') m['Status'] = status;
    if (priority != 'All Priority') m['Priority'] = priority;
    if (department != 'All Departments') m['Department'] = department;
    if (division != 'All Divisions') m['Division'] = division;
    if (section != 'All Sections') m['Section'] = section;
    if (site != 'All Sites') m['Site'] = site;
    if (assignee != 'All People') m['Assignee'] = assignee;
    return m;
  }

  // ─── copyWith ─────────────────────────────────────────────────────────────
  ReportFilterState copyWith({
    String? dateField,
    String? datePreset,
    DateTime? customStart,
    DateTime? customEnd,
    bool clearCustomDates = false,
    String? status,
    String? priority,
    String? department,
    String? division,
    String? section,
    String? site,
    String? assignee,
  }) {
    return ReportFilterState(
      dateField: dateField ?? this.dateField,
      datePreset: datePreset ?? this.datePreset,
      customStart: clearCustomDates ? null : (customStart ?? this.customStart),
      customEnd: clearCustomDates ? null : (customEnd ?? this.customEnd),
      status: status ?? this.status,
      priority: priority ?? this.priority,
      department: department ?? this.department,
      division: division ?? this.division,
      section: section ?? this.section,
      site: site ?? this.site,
      assignee: assignee ?? this.assignee,
    );
  }

  /// Resets all filters to their defaults.
  static const ReportFilterState none = ReportFilterState();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReportFilterState &&
          other.dateField == dateField &&
          other.datePreset == datePreset &&
          other.customStart == customStart &&
          other.customEnd == customEnd &&
          other.status == status &&
          other.priority == priority &&
          other.department == department &&
          other.division == division &&
          other.section == section &&
          other.site == site &&
          other.assignee == assignee;

  @override
  int get hashCode => Object.hash(
    dateField,
    datePreset,
    customStart,
    customEnd,
    status,
    priority,
    department,
    division,
    section,
    site,
    assignee,
  );
}
