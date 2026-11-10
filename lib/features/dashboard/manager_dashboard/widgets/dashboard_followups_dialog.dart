import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/services/report_service.dart';
import 'package:flutter/material.dart';

enum FollowUpClassification {
  overdue('Overdue'),
  today('Due Today'),
  upcoming('Upcoming');

  const FollowUpClassification(this.label);
  final String label;
}

class FollowUpDetailItem {
  const FollowUpDetailItem({
    required this.action,
    required this.date,
    required this.timeframe,
    required this.notes,
    required this.status,
  });

  final ActionRecord action;
  final DateTime date;
  final FollowUpClassification timeframe;
  final String notes;
  final String status;
}

class DashboardFollowupsDialog extends StatefulWidget {
  const DashboardFollowupsDialog({
    super.key,
    required this.actions,
    required this.onActionTap,
    this.initialClassification,
  });

  final List<ActionRecord> actions;
  final ValueChanged<ActionRecord> onActionTap;
  final FollowUpClassification? initialClassification;

  static Future<void> show(
    BuildContext context, {
    required List<ActionRecord> actions,
    required ValueChanged<ActionRecord> onActionTap,
    FollowUpClassification? initialClassification,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => DashboardFollowupsDialog(
        actions: actions,
        onActionTap: onActionTap,
        initialClassification: initialClassification,
      ),
    );
  }

  @override
  State<DashboardFollowupsDialog> createState() =>
      _DashboardFollowupsDialogState();
}

class _DashboardFollowupsDialogState extends State<DashboardFollowupsDialog> {
  FollowUpClassification? _selectedClassification;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedClassification = widget.initialClassification;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<FollowUpDetailItem> _extractAllFollowUps(DateTime today) {
    final list = <FollowUpDetailItem>[];

    for (final a in widget.actions) {
      if (a.isClosed || a.isDeleted) continue;

      final scheduledDates = <({DateTime date, String notes, String status})>[];
      final existingDates = <DateTime>{};
      final inactiveDates = <DateTime>{};

      for (final f in a.followUps) {
        final d = ReportService.parseDate(f.followUpDate);
        if (d != null) {
          final normalized = DateTime(d.year, d.month, d.day);
          if (f.isCompleted || f.status.trim().toLowerCase() == 'cancelled') {
            inactiveDates.add(normalized);
          } else {
            existingDates.add(normalized);
            scheduledDates.add((
              date: normalized,
              notes: f.notes,
              status: f.status.isNotEmpty ? f.status : 'Scheduled',
            ));
          }
        }
      }

      if (a.nextFollowUpDate.isNotEmpty &&
          a.nextFollowUpDate != 'Not set') {
        final d = ReportService.parseDate(a.nextFollowUpDate);
        if (d != null) {
          final normalized = DateTime(d.year, d.month, d.day);
          if (!inactiveDates.contains(normalized) && !existingDates.contains(normalized)) {
            scheduledDates.add((
              date: normalized,
              notes: '',
              status: 'Scheduled',
            ));
          }
        }
      }

      for (final item in scheduledDates) {
        final FollowUpClassification tf;
        if (item.date.isBefore(today)) {
          tf = FollowUpClassification.overdue;
        } else if (item.date.isAtSameMomentAs(today)) {
          tf = FollowUpClassification.today;
        } else {
          tf = FollowUpClassification.upcoming;
        }

        list.add(FollowUpDetailItem(
          action: a,
          date: item.date,
          timeframe: tf,
          notes: item.notes,
          status: item.status,
        ));
      }
    }

    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final day = dt.day.toString().padLeft(2, '0');
    final mon = months[dt.month - 1];
    return '$day $mon ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final allItems = _extractAllFollowUps(today);

    final overdueCount = allItems
        .where((e) => e.timeframe == FollowUpClassification.overdue)
        .length;
    final todayCount = allItems
        .where((e) => e.timeframe == FollowUpClassification.today)
        .length;
    final upcomingCount = allItems
        .where((e) => e.timeframe == FollowUpClassification.upcoming)
        .length;

    var filtered = allItems;
    if (_selectedClassification != null) {
      filtered = filtered
          .where((e) => e.timeframe == _selectedClassification)
          .toList();
    }
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      filtered = filtered.where((e) {
        final a = e.action;
        return a.displayId.toLowerCase().contains(q) ||
            a.subject.toLowerCase().contains(q) ||
            a.assignedTo.toLowerCase().contains(q) ||
            (a.externalRecipientName ?? '').toLowerCase().contains(q) ||
            e.notes.toLowerCase().contains(q);
      }).toList();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = (screenWidth * 0.9).clamp(320.0, 960.0);

    return Dialog(
      backgroundColor: AppTheme.cardBg(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppTheme.cardBorder(context)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: dialogWidth,
        height: 640,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCCFBF1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.schedule_rounded,
                      color: Color(0xFF0D9488),
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Follow-ups Overview & Schedule',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Track all scheduled, due, and overdue action follow-up checkpoints',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Filter Tabs & Search Row
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 600;
                final filterChips = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _filterChip(
                      label: 'All (${allItems.length})',
                      isSelected: _selectedClassification == null,
                      color: const Color(0xFF0284C7),
                      onTap: () => setState(() => _selectedClassification = null),
                    ),
                    _filterChip(
                      label: 'Overdue ($overdueCount)',
                      isSelected: _selectedClassification ==
                          FollowUpClassification.overdue,
                      color: const Color(0xFFDC2626),
                      onTap: () => setState(() => _selectedClassification =
                          FollowUpClassification.overdue),
                    ),
                    _filterChip(
                      label: 'Due Today ($todayCount)',
                      isSelected:
                          _selectedClassification == FollowUpClassification.today,
                      color: const Color(0xFF2563EB),
                      onTap: () => setState(() => _selectedClassification =
                          FollowUpClassification.today),
                    ),
                    _filterChip(
                      label: 'Upcoming ($upcomingCount)',
                      isSelected: _selectedClassification ==
                          FollowUpClassification.upcoming,
                      color: const Color(0xFF0D9488),
                      onTap: () => setState(() => _selectedClassification =
                          FollowUpClassification.upcoming),
                    ),
                  ],
                );

                final searchBox = SizedBox(
                  width: isNarrow ? double.infinity : 240,
                  height: 38,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textPrimary(context),
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search Action or Assignee...',
                      hintStyle: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted(context),
                      ),
                      prefixIcon: const Icon(Icons.search_rounded, size: 16),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 0,
                        horizontal: 10,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: AppTheme.cardBorder(context),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: AppTheme.cardBorder(context),
                        ),
                      ),
                    ),
                  ),
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      filterChips,
                      const SizedBox(height: 10),
                      searchBox,
                    ],
                  );
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    filterChips,
                    searchBox,
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, thickness: 0.8),
            const SizedBox(height: 10),

            // Content List / Table
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.event_available_outlined,
                            size: 44,
                            color: AppTheme.textMuted(context),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'No follow-ups matching current selection',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1, thickness: 0.6),
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        final a = item.action;
                        final daysDiff = item.date.difference(today).inDays;

                        final String relativeText;
                        final Color tagColor;
                        final Color tagBg;

                        switch (item.timeframe) {
                          case FollowUpClassification.overdue:
                            final overdueDays = -daysDiff;
                            relativeText = overdueDays <= 1
                                ? '1 day overdue'
                                : '$overdueDays days overdue';
                            tagColor = const Color(0xFFDC2626);
                            tagBg = const Color(0xFFFEE2E2);
                            break;
                          case FollowUpClassification.today:
                            relativeText = 'Due Today';
                            tagColor = const Color(0xFF2563EB);
                            tagBg = const Color(0xFFDBEAFE);
                            break;
                          case FollowUpClassification.upcoming:
                            relativeText = daysDiff == 1
                                ? 'Tomorrow'
                                : 'In $daysDiff days';
                            tagColor = const Color(0xFF0D9488);
                            tagBg = const Color(0xFFCCFBF1);
                            break;
                        }

                        final assigneeName = a.isExternalRecipient
                            ? (a.externalRecipientName ?? 'External')
                            : (a.assignedTo.isNotEmpty
                                ? a.assignedTo
                                : 'Unassigned');

                        return InkWell(
                          onTap: () {
                            Navigator.of(context).pop();
                            widget.onActionTap(a);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 8,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Classification Tag
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? tagColor.withValues(alpha: 0.2)
                                        : tagBg,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    relativeText.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: tagColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Date
                                SizedBox(
                                  width: 95,
                                  child: Text(
                                    _formatDate(item.date),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white70
                                          : const Color(0xFF334155),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),

                                // Action ID Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF334155)
                                        : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: AppTheme.cardBorder(context),
                                    ),
                                  ),
                                  child: Text(
                                    a.displayId,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Subject & Notes
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        a.subject,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textPrimary(context),
                                        ),
                                      ),
                                      if (item.notes.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          item.notes,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textSecondary(context),
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),

                                // Assignee
                                SizedBox(
                                  width: 130,
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.person_outline_rounded,
                                        size: 14,
                                        color: Color(0xFF64748B),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          assigneeName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: AppTheme.textSecondary(context),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),

                                // Status Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF1E293B)
                                        : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    a.status,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textPrimary(context),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // View Action Button
                                OutlinedButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    widget.onActionTap(a);
                                  },
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    side: BorderSide(
                                      color: AppTheme.primaryColor.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                  ),
                                  child: const Text(
                                    'View Action',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = AppTheme.isDark(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? color.withValues(alpha: 0.3) : color.withValues(alpha: 0.12))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : AppTheme.cardBorder(context),
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? color : AppTheme.textSecondary(context),
          ),
        ),
      ),
    );
  }
}

