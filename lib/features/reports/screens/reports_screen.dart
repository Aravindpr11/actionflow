import 'dart:math' as math;

import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/reports/models/report_filter_state.dart';
import 'package:action_flow/services/report_service.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public entry point
// ─────────────────────────────────────────────────────────────────────────────

/// Full Manager Reports & Analytics screen.
///
/// Receives the already-authorized [allActions] dataset from
/// [ManagerDashboardScreen] and performs all aggregations locally via
/// [ReportService] — no additional Supabase requests.
class ManagerReportsScreen extends StatefulWidget {
  const ManagerReportsScreen({
    super.key,
    required this.allActions,
    this.managerContext,
    this.userProfile,
    required this.onActionTap,
    required this.onExportExcel,
    required this.onRefresh,
    this.departmentOptions = const ['All Departments'],
    this.siteOptions = const ['All Sites'],
    this.divisionOptions = const [],
    this.assigneeOptions = const ['All People'],
  });

  final List<ActionRecord> allActions;
  final ManagerContext? managerContext;
  final UserProfile? userProfile;

  /// Opens the existing ActionDetailsScreen for [action].
  final void Function(ActionRecord action) onActionTap;

  /// Triggers Excel export with [filteredActions] and optional [activeFilters].
  final void Function(
    List<ActionRecord> filteredActions, [
    Map<String, String>? activeFilters,
  ])
  onExportExcel;

  /// Refreshes the parent action dataset.
  final VoidCallback onRefresh;

  final List<String> departmentOptions;
  final List<String> siteOptions;
  final List<String> divisionOptions;
  final List<String> assigneeOptions;

  @override
  State<ManagerReportsScreen> createState() => _ManagerReportsScreenState();
}

class _ManagerReportsScreenState extends State<ManagerReportsScreen>
    with SingleTickerProviderStateMixin {
  ReportFilterState _filters = ReportFilterState.none;
  late ReportAggregates _aggregates;
  late List<ActionRecord> _filteredActions;

  bool _filterPanelExpanded = false;
  late TabController _orgTabController;

  // For custom date range picker
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    _orgTabController = TabController(length: 5, vsync: this);
    _recompute();
  }

  @override
  void didUpdateWidget(ManagerReportsScreen old) {
    super.didUpdateWidget(old);
    if (old.allActions != widget.allActions) {
      _recompute();
    }
  }

  @override
  void dispose() {
    _orgTabController.dispose();
    super.dispose();
  }

  void _recompute() {
    _filteredActions = ReportService.applyFilters(
      widget.allActions,
      dateField: _filters.dateField,
      datePreset: _filters.datePreset,
      customStart: _filters.customStart,
      customEnd: _filters.customEnd,
      status: _filters.status,
      priority: _filters.priority,
      department: _filters.department,
      division: _filters.division,
      section: _filters.section,
      site: _filters.site,
      assignee: _filters.assignee,
    );
    _aggregates = ReportService.compute(_filteredActions);
  }

  void _updateFilter(ReportFilterState newFilters) {
    setState(() {
      _filters = newFilters;
      _recompute();
    });
  }

  void _clearAllFilters() {
    setState(() {
      _filters = ReportFilterState.none;
      _customRange = null;
      _recompute();
    });
  }

  // ─── Derived option lists from live dataset ───────────────────────────────

  List<String> get _sectionOptions {
    final set =
        widget.allActions
            .map((a) => a.section.trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return ['All Sections', ...set];
  }

  List<String> get _divisionOptions {
    final opts = widget.divisionOptions;
    if (opts.isNotEmpty) {
      final withAll = opts.contains('All Divisions')
          ? opts
          : ['All Divisions', ...opts];
      return withAll;
    }
    final set =
        widget.allActions
            .map((a) => a.division.trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return ['All Divisions', ...set];
  }

  List<String> get _assigneeOptions {
    final opts = widget.assigneeOptions;
    if (opts.isNotEmpty) {
      return opts.contains('All People') ? opts : ['All People', ...opts];
    }
    final set =
        widget.allActions
            .map(
              (a) => a.isExternalRecipient
                  ? (a.externalRecipientName ?? '').trim()
                  : a.assignedTo.trim(),
            )
            .where((s) => s.isNotEmpty && s != 'Unassigned')
            .toSet()
            .toList()
          ..sort();
    return ['All People', ...set];
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _ReportHeader(
            resultCount: _filteredActions.length,
            totalCount: widget.allActions.length,
            hasFilters: _filters.hasActiveFilters,
            onExport: () =>
                widget.onExportExcel(_filteredActions, _filters.asFilterMap),
            onRefresh: widget.onRefresh,
          ),

          const SizedBox(height: 16),

          // Filter panel
          _FilterPanel(
            expanded: _filterPanelExpanded,
            filters: _filters,
            onToggle: () =>
                setState(() => _filterPanelExpanded = !_filterPanelExpanded),
            onFiltersChanged: _updateFilter,
            onClearAll: _clearAllFilters,
            departmentOptions: widget.departmentOptions,
            siteOptions: widget.siteOptions,
            divisionOptions: _divisionOptions,
            sectionOptions: _sectionOptions,
            assigneeOptions: _assigneeOptions,
            customRange: _customRange,
            onCustomRangePicked: (range) {
              setState(() {
                _customRange = range;
                _filters = _filters.copyWith(
                  datePreset: 'Custom Range',
                  customStart: range?.start,
                  customEnd: range?.end,
                  clearCustomDates: range == null,
                );
                _recompute();
              });
            },
          ),

          // Active chips
          if (_filters.hasActiveFilters) ...[
            const SizedBox(height: 8),
            _ActiveChipsRow(
              chips: _filters.activeChips,
              onClearAll: _clearAllFilters,
            ),
          ],

          const SizedBox(height: 20),

          // KPI cards
          _KpiCardsRow(aggregates: _aggregates, isDark: isDark),

          const SizedBox(height: 20),

          // Status chart
          _SectionCard(
            title: 'Status Analysis',
            icon: Icons.donut_large_rounded,
            child: _StatusBarChart(
              byStatus: _aggregates.byStatus,
              total: _aggregates.total,
            ),
          ),

          const SizedBox(height: 16),

          // Progress + Priority side by side on wide, stacked on narrow
          LayoutBuilder(
            builder: (ctx, c) {
              final wide = c.maxWidth > 700;
              final progCard = _SectionCard(
                title: 'Progress Distribution',
                icon: Icons.bar_chart_rounded,
                child: _ProgressBarChart(
                  byBand: _aggregates.byProgressBand,
                  total: _aggregates.total,
                ),
              );
              final priCard = _SectionCard(
                title: 'Priority Analysis',
                icon: Icons.priority_high_rounded,
                child: _PriorityBarChart(
                  byPriority: _aggregates.byPriority,
                  total: _aggregates.total,
                ),
              );
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: progCard),
                    const SizedBox(width: 16),
                    Expanded(child: priCard),
                  ],
                );
              }
              return Column(
                children: [progCard, const SizedBox(height: 16), priCard],
              );
            },
          ),

          const SizedBox(height: 16),

          // Organisational analysis
          _SectionCard(
            title: 'Organisational Analysis',
            icon: Icons.account_tree_rounded,
            child: _OrganisationalAnalysisSection(
              aggregates: _aggregates,
              filteredActions: _filteredActions,
              onActionTap: widget.onActionTap,
              tabController: _orgTabController,
            ),
          ),

          const SizedBox(height: 16),

          // Timeline chart
          _SectionCard(
            title: 'Timeline Analysis (12-Month Trend)',
            icon: Icons.show_chart_rounded,
            child: _TimelineChart(
              timeline: _aggregates.monthlyTimeline,
              followUp: _aggregates.followUpTimeline,
            ),
          ),

          const SizedBox(height: 16),

          // Filtered action register
          _SectionCard(
            title: 'Filtered Action Register (${_filteredActions.length})',
            icon: Icons.table_chart_rounded,
            child: _FilteredActionTable(
              actions: _filteredActions,
              onActionTap: widget.onActionTap,
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _ReportHeader extends StatelessWidget {
  const _ReportHeader({
    required this.resultCount,
    required this.totalCount,
    required this.hasFilters,
    required this.onExport,
    required this.onRefresh,
  });

  final int resultCount;
  final int totalCount;
  final bool hasFilters;
  final VoidCallback onExport;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder(context)),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.18)
                : const Color(0x060F172A),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.bar_chart_rounded,
              color: Color(0xFF1565C0),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reports & Analytics',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasFilters
                      ? 'Showing $resultCount of $totalCount actions'
                      : 'All $totalCount actions',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'Refresh data',
            color: AppTheme.textSecondary(context),
          ),
          const SizedBox(width: 4),
          ElevatedButton.icon(
            onPressed: onExport,
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('Export Excel'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter Panel
// ─────────────────────────────────────────────────────────────────────────────

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.expanded,
    required this.filters,
    required this.onToggle,
    required this.onFiltersChanged,
    required this.onClearAll,
    required this.departmentOptions,
    required this.siteOptions,
    required this.divisionOptions,
    required this.sectionOptions,
    required this.assigneeOptions,
    required this.customRange,
    required this.onCustomRangePicked,
  });

  final bool expanded;
  final ReportFilterState filters;
  final VoidCallback onToggle;
  final void Function(ReportFilterState) onFiltersChanged;
  final VoidCallback onClearAll;
  final List<String> departmentOptions;
  final List<String> siteOptions;
  final List<String> divisionOptions;
  final List<String> sectionOptions;
  final List<String> assigneeOptions;
  final DateTimeRange? customRange;
  final void Function(DateTimeRange?) onCustomRangePicked;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        children: [
          // Header row
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_list_rounded,
                    size: 18,
                    color: filters.hasActiveFilters
                        ? const Color(0xFF1565C0)
                        : AppTheme.textSecondary(context),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Filters',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  if (filters.hasActiveFilters) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1565C0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${filters.activeChips.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.textSecondary(context),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // Expanded content
          if (expanded) ...[
            Divider(height: 1, color: AppTheme.cardBorder(context)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Date field + Date preset
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _FilterDropdown(
                        label: 'Date Field',
                        value: filters.dateField,
                        options: ['All Dates', ...ReportService.kDateFields],
                        onChanged: (v) =>
                            onFiltersChanged(filters.copyWith(dateField: v)),
                      ),
                      _FilterDropdown(
                        label: 'Date Range',
                        value: filters.datePreset,
                        options: ReportService.kDatePresets,
                        onChanged: (v) {
                          if (v == 'Custom Range') {
                            // Picker will be shown below
                            onFiltersChanged(filters.copyWith(datePreset: v));
                          } else {
                            onFiltersChanged(
                              filters.copyWith(
                                datePreset: v,
                                clearCustomDates: true,
                              ),
                            );
                          }
                        },
                      ),
                      _FilterDropdown(
                        label: 'Status',
                        value: filters.status,
                        options: const [
                          'All Status',
                          'Open',
                          'In Progress',
                          'Pending Review',
                          'Ready for Review',
                          'Overdue',
                          'Closed',
                        ],
                        onChanged: (v) =>
                            onFiltersChanged(filters.copyWith(status: v)),
                      ),
                      _FilterDropdown(
                        label: 'Priority',
                        value: filters.priority,
                        options: [
                          'All Priority',
                          ...ReportService.kPriorityOrder,
                        ],
                        onChanged: (v) =>
                            onFiltersChanged(filters.copyWith(priority: v)),
                      ),
                      _FilterDropdown(
                        label: 'Department',
                        value: filters.department,
                        options: departmentOptions.contains('All Departments')
                            ? departmentOptions
                            : ['All Departments', ...departmentOptions],
                        onChanged: (v) =>
                            onFiltersChanged(filters.copyWith(department: v)),
                      ),
                      _FilterDropdown(
                        label: 'Division',
                        value: filters.division,
                        options: divisionOptions,
                        onChanged: (v) =>
                            onFiltersChanged(filters.copyWith(division: v)),
                      ),
                      _FilterDropdown(
                        label: 'Section',
                        value: filters.section,
                        options: sectionOptions,
                        onChanged: (v) =>
                            onFiltersChanged(filters.copyWith(section: v)),
                      ),
                      _FilterDropdown(
                        label: 'Site',
                        value: filters.site,
                        options: siteOptions.contains('All Sites')
                            ? siteOptions
                            : ['All Sites', ...siteOptions],
                        onChanged: (v) =>
                            onFiltersChanged(filters.copyWith(site: v)),
                      ),
                      _FilterDropdown(
                        label: 'Assignee',
                        value: filters.assignee,
                        options: assigneeOptions,
                        onChanged: (v) =>
                            onFiltersChanged(filters.copyWith(assignee: v)),
                      ),
                    ],
                  ),

                  // Custom date range picker
                  if (filters.datePreset == 'Custom Range') ...[
                    const SizedBox(height: 12),
                    _CustomDateRangePicker(
                      currentRange: customRange,
                      onRangePicked: onCustomRangePicked,
                    ),
                  ],

                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: onClearAll,
                      icon: const Icon(Icons.clear_all_rounded, size: 16),
                      label: const Text('Clear All'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    // Ensure value is in options
    final safeValue = options.contains(value) ? value : options.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary(context),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          constraints: const BoxConstraints(minWidth: 160, maxWidth: 220),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          decoration: BoxDecoration(
            color: AppTheme.cardBg(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.cardBorder(context)),
          ),
          child: DropdownButton<String>(
            value: safeValue,
            items: options
                .map(
                  (o) => DropdownMenuItem(
                    value: o,
                    child: Text(o, style: const TextStyle(fontSize: 13)),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
            underline: const SizedBox(),
            isExpanded: true,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textPrimary(context),
            ),
            dropdownColor: AppTheme.cardBg(context),
          ),
        ),
      ],
    );
  }
}

class _CustomDateRangePicker extends StatelessWidget {
  const _CustomDateRangePicker({
    required this.currentRange,
    required this.onRangePicked,
  });

  final DateTimeRange? currentRange;
  final void Function(DateTimeRange?) onRangePicked;

  @override
  Widget build(BuildContext context) {
    final hasRange = currentRange != null;
    return Row(
      children: [
        const Icon(
          Icons.date_range_rounded,
          size: 16,
          color: Color(0xFF1565C0),
        ),
        const SizedBox(width: 8),
        Text(
          hasRange
              ? '${_fmt(currentRange!.start)} – ${_fmt(currentRange!.end)}'
              : 'Select custom date range',
          style: TextStyle(
            fontSize: 13,
            color: hasRange
                ? AppTheme.textPrimary(context)
                : AppTheme.textSecondary(context),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton(
          onPressed: () async {
            final now = DateTime.now();
            final range = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime(now.year + 2),
              initialDateRange: currentRange,
              builder: (ctx, child) => Theme(
                data: Theme.of(ctx).copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: Color(0xFF1565C0),
                  ),
                ),
                child: child!,
              ),
            );
            onRangePicked(range);
          },
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            side: const BorderSide(color: Color(0xFF1565C0)),
            foregroundColor: const Color(0xFF1565C0),
            textStyle: const TextStyle(fontSize: 12),
          ),
          child: Text(hasRange ? 'Change' : 'Pick Dates'),
        ),
        if (hasRange) ...[
          const SizedBox(width: 6),
          IconButton(
            onPressed: () => onRangePicked(null),
            icon: const Icon(Icons.close_rounded, size: 16),
            color: const Color(0xFFDC2626),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ],
    );
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Active Chips
// ─────────────────────────────────────────────────────────────────────────────

class _ActiveChipsRow extends StatelessWidget {
  const _ActiveChipsRow({required this.chips, required this.onClearAll});

  final List<({String label, String value})> chips;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...chips.map(
          (c) => Chip(
            label: Text(
              '${c.label}: ${c.value}',
              style: const TextStyle(fontSize: 11),
            ),
            backgroundColor: const Color(0xFF1565C0).withValues(alpha: 0.12),
            side: const BorderSide(color: Color(0xFF1565C0), width: 0.5),
            labelStyle: const TextStyle(color: Color(0xFF1565C0)),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            visualDensity: VisualDensity.compact,
          ),
        ),
        ActionChip(
          label: const Text('Clear All', style: TextStyle(fontSize: 11)),
          onPressed: onClearAll,
          backgroundColor: const Color(0xFFDC2626).withValues(alpha: 0.10),
          side: const BorderSide(color: Color(0xFFDC2626), width: 0.5),
          labelStyle: const TextStyle(color: Color(0xFFDC2626)),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KPI Cards
// ─────────────────────────────────────────────────────────────────────────────

class _KpiCardsRow extends StatelessWidget {
  const _KpiCardsRow({required this.aggregates, required this.isDark});

  final ReportAggregates aggregates;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cards = [
      (
        'Total Actions',
        '${aggregates.total}',
        const Color(0xFF1565C0),
        Icons.assignment_rounded,
      ),
      (
        'Open',
        '${aggregates.open}',
        const Color(0xFF16A34A),
        Icons.pending_actions_rounded,
      ),
      (
        'Overdue',
        '${aggregates.overdue}',
        const Color(0xFFEA580C),
        Icons.warning_amber_rounded,
      ),
      (
        'Ready for Review',
        '${aggregates.pendingReview}',
        const Color(0xFF7C3AED),
        Icons.rate_review_rounded,
      ),
      (
        'Closed',
        '${aggregates.closed}',
        const Color(0xFF059669),
        Icons.check_circle_rounded,
      ),
      (
        'Avg Completion',
        '${aggregates.avgCompletionPct.toStringAsFixed(1)}%',
        const Color(0xFF0284C7),
        Icons.percent_rounded,
      ),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: cards.map((c) {
        return _KpiCard(
          label: c.$1,
          value: c.$2,
          color: c.$3,
          icon: c.$4,
          isDark: isDark,
        );
      }).toList(),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    required this.isDark,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.15)
                : color.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: color,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary(context),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section card wrapper
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder(context)),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.15)
                : const Color(0x060F172A),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF1565C0)),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status bar chart (CustomPaint)
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBarChart extends StatelessWidget {
  const _StatusBarChart({required this.byStatus, required this.total});

  final Map<String, int> byStatus;
  final int total;

  static const _statusColors = {
    'Open': Color(0xFF16A34A),
    'In Progress': Color(0xFF0284C7),
    'Pending Review': Color(0xFF7C3AED),
    'Ready for Review': Color(0xFF7C3AED),
    'Overdue': Color(0xFFEA580C),
    'Closed': Color(0xFF059669),
  };

  Color _colorFor(String status) {
    for (final entry in _statusColors.entries) {
      if (status.toLowerCase().contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    return const Color(0xFF64748B);
  }

  @override
  Widget build(BuildContext context) {
    if (byStatus.isEmpty) {
      return const _EmptyChart();
    }
    final sorted = byStatus.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxVal = sorted.first.value;

    return Column(
      children: sorted.map((entry) {
        final pct = total > 0 ? entry.value / total : 0.0;
        final color = _colorFor(entry.key);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              SizedBox(
                width: 130,
                child: Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textPrimary(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 22,
                      decoration: BoxDecoration(
                        color: AppTheme.cardBorder(context),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: maxVal > 0 ? entry.value / maxVal : 0,
                      child: Container(
                        height: 22,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: Text(
                  '${entry.value} (${(pct * 100).toStringAsFixed(0)}%)',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Progress distribution chart
// ─────────────────────────────────────────────────────────────────────────────

class _ProgressBarChart extends StatelessWidget {
  const _ProgressBarChart({required this.byBand, required this.total});

  final Map<String, int> byBand;
  final int total;

  static const _bandColors = [
    Color(0xFFDC2626), // 0–24% red
    Color(0xFFEA580C), // 25–49% orange
    Color(0xFFD97706), // 50–74% amber
    Color(0xFF0284C7), // 75–99% blue
    Color(0xFF16A34A), // 100% green
  ];

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const _EmptyChart();
    final bands = ReportService.kProgressBands;
    final maxVal = byBand.values.fold(0, math.max);

    return Column(
      children: List.generate(bands.length, (i) {
        final band = bands[i];
        final count = byBand[band] ?? 0;
        final color = _bandColors[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                child: Text(
                  band,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 22,
                      decoration: BoxDecoration(
                        color: AppTheme.cardBorder(context),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: maxVal > 0 ? count / maxVal : 0,
                      child: Container(
                        height: 22,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 46,
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Priority analysis chart
// ─────────────────────────────────────────────────────────────────────────────

class _PriorityBarChart extends StatelessWidget {
  const _PriorityBarChart({required this.byPriority, required this.total});

  final Map<String, int> byPriority;
  final int total;

  static const _colors = {
    'Critical': Color(0xFFDC2626),
    'High': Color(0xFFEA580C),
    'Medium': Color(0xFF0284C7),
    'Low': Color(0xFF16A34A),
  };

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const _EmptyChart();
    final order = ReportService.kPriorityOrder;
    final maxVal = order.map((k) => byPriority[k] ?? 0).fold(0, math.max);

    return Column(
      children: order.map((p) {
        final count = byPriority[p] ?? 0;
        final color = _colors[p] ?? const Color(0xFF64748B);
        final pct = total > 0 ? count / total : 0.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              SizedBox(
                width: 68,
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        p,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 22,
                      decoration: BoxDecoration(
                        color: AppTheme.cardBorder(context),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: maxVal > 0 ? count / maxVal : 0,
                      child: Container(
                        height: 22,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: Text(
                  '$count (${(pct * 100).toStringAsFixed(0)}%)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Organisational Analysis Section (Redesigned with horizontal bars & drill-down)
// ─────────────────────────────────────────────────────────────────────────────

enum _OrgDimension {
  department('Department', 'Departments'),
  division('Division', 'Divisions'),
  section('Section', 'Sections'),
  site('Site', 'Sites'),
  assignee('Assignee', 'Assignees');

  const _OrgDimension(this.label, this.pluralLabel);
  final String label;
  final String pluralLabel;
}

class _OrganisationalAnalysisSection extends StatefulWidget {
  const _OrganisationalAnalysisSection({
    required this.aggregates,
    required this.filteredActions,
    required this.onActionTap,
    required this.tabController,
  });

  final ReportAggregates aggregates;
  final List<ActionRecord> filteredActions;
  final void Function(ActionRecord) onActionTap;
  final TabController tabController;

  @override
  State<_OrganisationalAnalysisSection> createState() =>
      _OrganisationalAnalysisSectionState();
}

class _OrganisationalAnalysisSectionState
    extends State<_OrganisationalAnalysisSection> {
  bool _sortByCount = true;
  bool _showAllCategories = false;
  String? _drilledCategory;

  @override
  void initState() {
    super.initState();
    widget.tabController.addListener(_handleTabChange);
  }

  @override
  void didUpdateWidget(_OrganisationalAnalysisSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabController != widget.tabController) {
      oldWidget.tabController.removeListener(_handleTabChange);
      widget.tabController.addListener(_handleTabChange);
    }
    if (_drilledCategory != null) {
      final stillExists = _getDrilledActions(
        _currentDimension,
        _drilledCategory!,
      ).isNotEmpty;
      if (!stillExists) {
        setState(() {
          _drilledCategory = null;
        });
      }
    }
  }

  @override
  void dispose() {
    widget.tabController.removeListener(_handleTabChange);
    super.dispose();
  }

  void _handleTabChange() {
    if (mounted) {
      setState(() {
        _drilledCategory = null;
        _showAllCategories = false;
      });
    }
  }

  _OrgDimension get _currentDimension {
    final idx = widget.tabController.index.clamp(
      0,
      _OrgDimension.values.length - 1,
    );
    return _OrgDimension.values[idx];
  }

  Map<String, int> _getDataForDimension(_OrgDimension dimension) {
    switch (dimension) {
      case _OrgDimension.department:
        return widget.aggregates.byDepartment;
      case _OrgDimension.division:
        return widget.aggregates.byDivision;
      case _OrgDimension.section:
        return widget.aggregates.bySection;
      case _OrgDimension.site:
        return widget.aggregates.bySite;
      case _OrgDimension.assignee:
        return widget.aggregates.byAssignee;
    }
  }

  List<ActionRecord> _getDrilledActions(
    _OrgDimension dimension,
    String category,
  ) {
    return widget.filteredActions.where((a) {
      switch (dimension) {
        case _OrgDimension.department:
          final d = a.department.isNotEmpty ? a.department : 'Unassigned';
          return d == category;
        case _OrgDimension.division:
          final d = a.division.isNotEmpty ? a.division : 'Unassigned';
          return d == category;
        case _OrgDimension.section:
          final s = a.section.isNotEmpty ? a.section : 'Unassigned';
          return s == category;
        case _OrgDimension.site:
          final s = a.site.isNotEmpty ? a.site : 'Unassigned';
          return s == category;
        case _OrgDimension.assignee:
          final p = a.isExternalRecipient
              ? (a.externalRecipientName?.isNotEmpty == true
                  ? '${a.externalRecipientName} (External)'
                  : 'External')
              : (a.assignedTo.isNotEmpty ? a.assignedTo : 'Unassigned');
          return p == category;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final dimension = _currentDimension;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // TabBar for the 5 dimensions
        TabBar(
          controller: widget.tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: const Color(0xFF1565C0),
          unselectedLabelColor: AppTheme.textSecondary(context),
          indicatorColor: const Color(0xFF1565C0),
          tabs: const [
            Tab(text: 'Department'),
            Tab(text: 'Division'),
            Tab(text: 'Section'),
            Tab(text: 'Site'),
            Tab(text: 'Assignee'),
          ],
        ),
        const SizedBox(height: 16),

        if (_drilledCategory != null)
          _buildDrilledView(context, isDark, dimension, _drilledCategory!)
        else
          _buildOverviewBars(context, isDark, dimension),
      ],
    );
  }

  Widget _buildOverviewBars(
    BuildContext context,
    bool isDark,
    _OrgDimension dimension,
  ) {
    final data = _getDataForDimension(dimension);
    final total = widget.filteredActions.length;

    final entries = data.entries.toList();
    if (entries.isEmpty || total == 0) {
      return _EmptyChart(
        message:
            'No data available for ${dimension.pluralLabel.toLowerCase()}.',
      );
    }

    if (_sortByCount) {
      entries.sort((a, b) {
        final cmp = b.value.compareTo(a.value);
        if (cmp != 0) return cmp;
        return a.key.compareTo(b.key);
      });
    } else {
      entries.sort(
        (a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()),
      );
    }

    final displayEntries = _showAllCategories || entries.length <= 15
        ? entries
        : entries.take(15).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Controls row
        Row(
          children: [
            Expanded(
              child: Text(
                '${entries.length} ${dimension.pluralLabel.toLowerCase()} • Click row to view breakdown',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary(context),
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => setState(() => _sortByCount = !_sortByCount),
              icon: Icon(
                _sortByCount
                    ? Icons.sort_rounded
                    : Icons.sort_by_alpha_rounded,
                size: 15,
              ),
              label: Text(
                _sortByCount ? 'Sort: Count' : 'Sort: Name (A–Z)',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF1565C0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Horizontal bars list
        ...displayEntries.map((entry) {
          final count = entry.value;
          final pct = total > 0 ? (count / total * 100) : 0.0;
          final fraction = total > 0 ? (count / total).clamp(0.0, 1.0) : 0.0;
          final displayFraction = count > 0 ? fraction.clamp(0.015, 1.0) : 0.0;
          final isUnassigned = entry.key == 'Unassigned';

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              key: ValueKey('org_category_${entry.key}'),
              onTap: () {
                setState(() {
                  _drilledCategory = entry.key;
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.03)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.cardBorder(context),
                    width: 0.8,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.key,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isUnassigned
                                  ? AppTheme.textSecondary(context)
                                  : (isDark
                                      ? const Color(0xFF90CAF9)
                                      : const Color(0xFF1565C0)),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF3B82F6).withValues(alpha: 0.18)
                                : const Color(0xFF1565C0).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '$count ${count == 1 ? "action" : "actions"}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? const Color(0xFF93C5FD)
                                  : const Color(0xFF1565C0),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 48,
                          child: Text(
                            '${pct.toStringAsFixed(1)}%',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: AppTheme.textSecondary(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    // Progress bar track and fill
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        height: 7,
                        width: double.infinity,
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFE2E8F0),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: displayFraction,
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF3B82F6)
                                  : const Color(0xFF1565C0),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),

        if (entries.length > 15) ...[
          const SizedBox(height: 4),
          Center(
            child: TextButton.icon(
              onPressed: () =>
                  setState(() => _showAllCategories = !_showAllCategories),
              icon: Icon(
                _showAllCategories
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 16,
              ),
              label: Text(
                _showAllCategories
                    ? 'Show fewer ${dimension.pluralLabel.toLowerCase()}'
                    : 'Show all ${entries.length} ${dimension.pluralLabel.toLowerCase()}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF1565C0),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDrilledView(
    BuildContext context,
    bool isDark,
    _OrgDimension dimension,
    String category,
  ) {
    final drilledActions = _getDrilledActions(dimension, category);
    final total = widget.filteredActions.length;
    final pct = total > 0 ? (drilledActions.length / total * 100) : 0.0;

    final openCount = drilledActions
        .where((a) => !a.isClosed && a.status.toLowerCase() == 'open')
        .length;
    final inProgressCount = drilledActions
        .where((a) => !a.isClosed && a.status.toLowerCase() == 'in progress')
        .length;
    final reviewCount = drilledActions
        .where(
          (a) =>
              !a.isClosed &&
              (a.status.toLowerCase() == 'pending review' ||
                  a.isReadyForReview),
        )
        .length;
    final closedCount = drilledActions.where((a) => a.isClosed).length;
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final overdueCount = drilledActions.where((a) {
      if (a.isClosed) return false;
      if (a.status.trim().toLowerCase() == 'overdue') return true;
      final targetDt = ReportService.parseDate(a.targetDate);
      return targetDt != null && targetDt.isBefore(today);
    }).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back Button & Category Breadcrumb
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _drilledCategory = null;
                });
              },
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: Text('Back to All ${dimension.pluralLabel}'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.subdirectory_arrow_right_rounded,
                  size: 16,
                  color: AppTheme.textSecondary(context),
                ),
                const SizedBox(width: 4),
                Text(
                  '${dimension.label}: ',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
                Flexible(
                  child: Text(
                    category,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 14),

        // KPI Pills / Metrics banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.03)
                : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppTheme.cardBorder(context),
              width: 0.8,
            ),
          ),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _metricPill(
                context,
                label: 'Total',
                value: '${drilledActions.length} (${pct.toStringAsFixed(1)}%)',
                color: const Color(0xFF1565C0),
              ),
              _metricPill(
                context,
                label: 'Open',
                value: '$openCount',
                color: const Color(0xFF16A34A),
              ),
              _metricPill(
                context,
                label: 'In Progress',
                value: '$inProgressCount',
                color: const Color(0xFF0284C7),
              ),
              if (reviewCount > 0)
                _metricPill(
                  context,
                  label: 'In Review',
                  value: '$reviewCount',
                  color: const Color(0xFF7C3AED),
                ),
              _metricPill(
                context,
                label: 'Closed',
                value: '$closedCount',
                color: const Color(0xFF059669),
              ),
              if (overdueCount > 0)
                _metricPill(
                  context,
                  label: 'Overdue',
                  value: '$overdueCount',
                  color: const Color(0xFFDC2626),
                ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Section header for detailed actions table
        Text(
          'Actions in "$category" (${drilledActions.length})',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary(context),
          ),
        ),
        const SizedBox(height: 8),

        // Detailed action table for the selected breakdown
        _FilteredActionTable(
          actions: drilledActions,
          onActionTap: widget.onActionTap,
        ),
      ],
    );
  }

  Widget _metricPill(
    BuildContext context, {
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary(context),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Timeline chart (CustomPaint)
// ─────────────────────────────────────────────────────────────────────────────

class _TimelineChart extends StatelessWidget {
  const _TimelineChart({required this.timeline, required this.followUp});

  final List<MonthlyTrendPoint> timeline;
  final List<MonthlyFollowUpPoint> followUp;

  @override
  Widget build(BuildContext context) {
    if (timeline.isEmpty) return const _EmptyChart();

    final hasAnyData = timeline.any(
      (t) => t.raised > 0 || t.closed > 0 || t.overdue > 0,
    );
    if (!hasAnyData && followUp.every((f) => f.count == 0)) {
      return const _EmptyChart(
        message: 'No timeline data in the 12-month window.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Legend
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            _LegendItem(color: const Color(0xFF1565C0), label: 'Raised'),
            _LegendItem(color: const Color(0xFF16A34A), label: 'Closed'),
            _LegendItem(color: const Color(0xFFEA580C), label: 'Overdue'),
            _LegendItem(color: const Color(0xFF7C3AED), label: 'Follow-Up'),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: CustomPaint(
            painter: _TimelinePainter(
              timeline: timeline,
              followUp: followUp,
              isDark: AppTheme.isDark(context),
            ),
            child: Container(),
          ),
        ),
        const SizedBox(height: 8),
        // Month labels
        Row(
          children: timeline.map((t) {
            return Expanded(
              child: Text(
                t.label.split(' ').first, // Just 'Jan', 'Feb', etc.
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppTheme.textSecondary(context),
          ),
        ),
      ],
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.timeline,
    required this.followUp,
    required this.isDark,
  });

  final List<MonthlyTrendPoint> timeline;
  final List<MonthlyFollowUpPoint> followUp;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (timeline.isEmpty) return;

    final n = timeline.length;
    final allVals = [
      ...timeline.map((t) => t.raised),
      ...timeline.map((t) => t.closed),
      ...timeline.map((t) => t.overdue),
      ...followUp.map((f) => f.count),
    ];
    final maxVal = allVals.fold(0, math.max);
    if (maxVal == 0) return;

    final gridColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    // Draw horizontal grid lines
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    for (int i = 0; i <= 4; i++) {
      final y = size.height * (1 - i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Helper to get point positions
    List<Offset> pts(List<int> values) {
      return List.generate(n, (i) {
        final x = n == 1 ? size.width / 2 : i * size.width / (n - 1);
        final y = size.height * (1 - values[i] / maxVal);
        return Offset(x, y);
      });
    }

    void drawLine(List<Offset> points, Color color) {
      if (points.isEmpty) return;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;

      // Fill area
      final fillPath = Path();
      fillPath.moveTo(points.first.dx, size.height);
      for (final p in points) {
        fillPath.lineTo(p.dx, p.dy);
      }
      fillPath.lineTo(points.last.dx, size.height);
      fillPath.close();
      canvas.drawPath(fillPath, Paint()..color = color.withValues(alpha: 0.08));

      // Line
      final linePath = Path();
      linePath.moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        linePath.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(linePath, paint);

      // Dots
      final dotPaint = Paint()..color = color;
      for (final p in points) {
        canvas.drawCircle(p, 3, dotPaint);
      }
    }

    drawLine(
      pts(timeline.map((t) => t.raised).toList()),
      const Color(0xFF1565C0),
    );
    drawLine(
      pts(timeline.map((t) => t.closed).toList()),
      const Color(0xFF16A34A),
    );
    drawLine(
      pts(timeline.map((t) => t.overdue).toList()),
      const Color(0xFFEA580C),
    );
    if (followUp.isNotEmpty) {
      drawLine(
        pts(followUp.map((f) => f.count).toList()),
        const Color(0xFF7C3AED),
      );
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.timeline != timeline ||
      old.followUp != followUp ||
      old.isDark != isDark;
}

// ─────────────────────────────────────────────────────────────────────────────
// Filtered action register table
// ─────────────────────────────────────────────────────────────────────────────

class _FilteredActionTable extends StatefulWidget {
  const _FilteredActionTable({
    required this.actions,
    required this.onActionTap,
  });

  final List<ActionRecord> actions;
  final void Function(ActionRecord) onActionTap;

  @override
  State<_FilteredActionTable> createState() => _FilteredActionTableState();
}

class _FilteredActionTableState extends State<_FilteredActionTable> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final rows = _showAll ? widget.actions : widget.actions.take(50).toList();
    if (rows.isEmpty) {
      return const _EmptyChart(
        message: 'No actions match the current filters.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 16,
            headingRowHeight: 36,
            dataRowMinHeight: 36,
            dataRowMaxHeight: 48,
            headingTextStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1565C0),
            ),
            columns: const [
              DataColumn(label: Text('Action ID')),
              DataColumn(label: Text('Subject')),
              DataColumn(label: Text('Assignee')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Priority')),
              DataColumn(label: Text('Department')),
              DataColumn(label: Text('Site')),
              DataColumn(label: Text('Progress')),
              DataColumn(label: Text('Due Date')),
            ],
            rows: rows.map((a) {
              final assigneeName = a.isExternalRecipient
                  ? '${a.externalRecipientName ?? 'External'} (Ext)'
                  : a.assignedTo;
              return DataRow(
                onSelectChanged: (_) => widget.onActionTap(a),
                cells: [
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1565C0).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        a.displayId,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1565C0),
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(
                        a.subject,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      assigneeName,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ),
                  DataCell(_StatusBadge(status: a.status)),
                  DataCell(_PriorityBadge(priority: a.priority)),
                  DataCell(
                    Text(
                      a.department,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      a.site,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${a.percentComplete}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: a.percentComplete >= 100
                            ? const Color(0xFF16A34A)
                            : AppTheme.textPrimary(context),
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      a.targetDate.isNotEmpty ? a.targetDate : '—',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        if (widget.actions.length > 50 && !_showAll) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _showAll = true),
              icon: const Icon(Icons.expand_more_rounded, size: 16),
              label: Text(
                'Show all ${widget.actions.length} actions',
                style: const TextStyle(fontSize: 12),
              ),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF1565C0),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  Color _color() {
    switch (status.toLowerCase()) {
      case 'closed':
        return const Color(0xFF059669);
      case 'open':
        return const Color(0xFF16A34A);
      case 'in progress':
        return const Color(0xFF0284C7);
      case 'pending review':
      case 'ready for review':
        return const Color(0xFF7C3AED);
      case 'overdue':
        return const Color(0xFFEA580C);
      default:
        return const Color(0xFF64748B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Text(
        status,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c),
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.priority});

  final String priority;

  Color _color() {
    switch (priority.toLowerCase()) {
      case 'critical':
        return const Color(0xFFDC2626);
      case 'high':
        return const Color(0xFFEA580C);
      case 'medium':
        return const Color(0xFF0284C7);
      case 'low':
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFF64748B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        priority,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty chart placeholder
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyChart extends StatelessWidget {
  const _EmptyChart({
    this.message = 'No data available for the selected filters.',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.bar_chart_outlined,
              size: 36,
              color: AppTheme.textSecondary(context).withValues(alpha: 0.4),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary(context),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
