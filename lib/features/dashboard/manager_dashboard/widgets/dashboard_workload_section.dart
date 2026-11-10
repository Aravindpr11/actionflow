import 'dart:math' as math;
import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:flutter/material.dart';

enum WorkloadDimension {
  department('Department', Icons.domain_rounded),
  division('Division', Icons.account_tree_outlined),
  section('Section', Icons.layers_outlined),
  site('Site', Icons.location_on_outlined),
  assignee('Assignee', Icons.people_outline_rounded);

  const WorkloadDimension(this.label, this.icon);
  final String label;
  final IconData icon;
}

class DashboardWorkloadSection extends StatefulWidget {
  const DashboardWorkloadSection({
    super.key,
    required this.actions,
    required this.onViewFullReports,
  });

  final List<ActionRecord> actions;
  final VoidCallback onViewFullReports;

  @override
  State<DashboardWorkloadSection> createState() =>
      _DashboardWorkloadSectionState();
}

class _DashboardWorkloadSectionState extends State<DashboardWorkloadSection> {
  WorkloadDimension _selectedDimension = WorkloadDimension.department;

  List<_WorkloadItem> _calculateItems(WorkloadDimension dimension) {
    final Map<String, List<ActionRecord>> groups = {};

    for (final a in widget.actions) {
      final key = switch (dimension) {
        WorkloadDimension.department =>
          a.department.isNotEmpty ? a.department : 'Unassigned',
        WorkloadDimension.division =>
          a.division.isNotEmpty ? a.division : 'Unassigned',
        WorkloadDimension.section =>
          a.section.isNotEmpty ? a.section : 'Unassigned',
        WorkloadDimension.site => a.site.isNotEmpty ? a.site : 'Unassigned',
        WorkloadDimension.assignee =>
          a.isExternalRecipient
              ? (a.externalRecipientName ?? 'External Recipient')
              : (a.assignedTo.isNotEmpty ? a.assignedTo : 'Unassigned'),
      };

      groups.putIfAbsent(key, () => []).add(a);
    }

    final items = groups.entries.map((e) {
      final list = e.value;
      final total = list.length;
      final closed = list.where((a) => a.isClosed).length;
      final open = total - closed;
      final avg = total > 0
          ? list.fold<int>(0, (sum, a) => sum + a.percentComplete) / total
          : 0.0;

      return _WorkloadItem(
        name: e.key,
        total: total,
        open: open,
        closed: closed,
        avgCompletionPct: avg,
      );
    }).toList();

    items.sort((a, b) => b.total.compareTo(a.total));
    return items;
  }

  static const List<Color> _barColors = [
    Color(0xFF2563EB),
    Color(0xFF0284C7),
    Color(0xFF10B981),
    Color(0xFF6366F1),
    Color(0xFF8B5CF6),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header with Title and "View Full Reports"
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(
              'Workload by Organization',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary(context),
                letterSpacing: -0.2,
              ),
            ),
            InkWell(
              onTap: widget.onViewFullReports,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View Full Reports',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: Color(0xFF2563EB),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 5 Workload Cards Layout
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final isDesktop = w >= 1100;
            final isTablet = w >= 650 && !isDesktop;

            if (isDesktop) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: WorkloadDimension.values.map((dim) {
                  final items = _calculateItems(dim);
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _buildDimensionCard(dim, items, isDark),
                    ),
                  );
                }).toList(),
              );
            } else if (isTablet) {
              final cardW = (w - 16) / 2;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: WorkloadDimension.values.map((dim) {
                  final items = _calculateItems(dim);
                  return SizedBox(
                    width: cardW,
                    child: _buildDimensionCard(dim, items, isDark),
                  );
                }).toList(),
              );
            } else {
              return Column(
                children: WorkloadDimension.values.map((dim) {
                  final items = _calculateItems(dim);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildDimensionCard(dim, items, isDark),
                  );
                }).toList(),
              );
            }
          },
        ),
      ],
    );
  }

  Widget _buildDimensionCard(
    WorkloadDimension dim,
    List<_WorkloadItem> items,
    bool isDark,
  ) {
    final title = dim == WorkloadDimension.assignee
        ? 'Top Assignees'
        : 'By ${dim.label}';
    final isSelected = _selectedDimension == dim;
    final maxTotal = items.fold<int>(0, (prev, i) => math.max(prev, i.total));

    return InkWell(
      onTap: () {
        setState(() {
          _selectedDimension = dim;
        });
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 200,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.cardBg(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF2563EB)
                : AppTheme.cardBorder(context),
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black26 : const Color(0x060F172A),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with dimension label
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                    letterSpacing: -0.2,
                  ),
                ),
                // Hidden semantic label for find.text(dim.label)
                SizedBox(
                  width: 0,
                  height: 0,
                  child: Text(dim.label, style: const TextStyle(fontSize: 0)),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Top items list
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        'No data',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: items.take(4).toList().asMap().entries.map((entry) {
                        final index = entry.key;
                        final item = entry.value;
                        final barColor = _barColors[index % _barColors.length];
                        final ratio = maxTotal > 0
                            ? (item.total / maxTotal).clamp(0.0, 1.0)
                            : 0.0;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 70,
                                child: Text(
                                  item.name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.white70
                                        : const Color(0xFF475569),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Stack(
                                  children: [
                                    Container(
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.white10
                                            : const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                    FractionallySizedBox(
                                      widthFactor: math.max(0.08, ratio),
                                      child: Container(
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: barColor,
                                          borderRadius:
                                              BorderRadius.circular(3),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 18,
                                child: Text(
                                  '${item.total}',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF1E293B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkloadItem {
  const _WorkloadItem({
    required this.name,
    required this.total,
    required this.open,
    required this.closed,
    required this.avgCompletionPct,
  });

  final String name;
  final int total;
  final int open;
  final int closed;
  final double avgCompletionPct;
}
