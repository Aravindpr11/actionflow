import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/services/report_service.dart';
import 'package:flutter/material.dart';

enum AttentionCategory {
  overdue(
    'Overdue',
    Icons.error_outline_rounded,
    Color(0xFFDC2626),
    Color(0xFFFEF2F2),
    Color(0xFFFEE2E2),
  ),
  dueSoon(
    'Due Soon',
    Icons.schedule_rounded,
    Color(0xFFEA580C),
    Color(0xFFFFF7ED),
    Color(0xFFFFEDD5),
  ),
  followUpsToday(
    'Follow-Ups Today',
    Icons.calendar_today_rounded,
    Color(0xFF2563EB),
    Color(0xFFEFF6FF),
    Color(0xFFDBEAFE),
  ),
  readyForReview(
    'Ready for Review',
    Icons.rate_review_outlined,
    Color(0xFF7C3AED),
    Color(0xFFFAF5FF),
    Color(0xFFF3E8FF),
  ),
  recentlyClosed(
    'Recently Closed',
    Icons.check_circle_outline_rounded,
    Color(0xFF16A34A),
    Color(0xFFF0FDF4),
    Color(0xFFDCFCE7),
  );

  const AttentionCategory(
    this.label,
    this.icon,
    this.color,
    this.lightBg,
    this.borderColor,
  );
  final String label;
  final IconData icon;
  final Color color;
  final Color lightBg;
  final Color borderColor;
}

class DashboardAttentionSection extends StatefulWidget {
  const DashboardAttentionSection({
    super.key,
    required this.actions,
    required this.onActionTap,
    this.initialCategory = AttentionCategory.overdue,
    this.onViewAll,
  });

  final List<ActionRecord> actions;
  final ValueChanged<ActionRecord> onActionTap;
  final AttentionCategory initialCategory;
  final VoidCallback? onViewAll;

  @override
  State<DashboardAttentionSection> createState() =>
      _DashboardAttentionSectionState();
}

class _DashboardAttentionSectionState extends State<DashboardAttentionSection> {
  AttentionCategory? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
  }

  List<ActionRecord> _getOverdueActions(DateTime today) {
    final list = widget.actions.where((a) {
      if (a.isClosed) return false;
      if (a.isReadyForReview || a.percentComplete >= 100) return false;
      final dt = a.targetDateTime ?? ReportService.parseDate(a.targetDate);
      final isOverdue =
          a.status.toLowerCase() == 'overdue' ||
          (dt != null && dt.isBefore(today));
      return isOverdue;
    }).toList();

    list.sort((a, b) {
      final dtA =
          a.targetDateTime ??
          ReportService.parseDate(a.targetDate) ??
          DateTime(2099);
      final dtB =
          b.targetDateTime ??
          ReportService.parseDate(b.targetDate) ??
          DateTime(2099);
      return dtA.compareTo(dtB);
    });
    return list;
  }

  List<ActionRecord> _getDueSoonActions(DateTime today) {
    final list = widget.actions.where((a) {
      if (a.isClosed) return false;
      // Do not duplicate actions ready for review or overdue
      if (a.isReadyForReview || a.percentComplete >= 100) return false;
      final dt = a.targetDateTime ?? ReportService.parseDate(a.targetDate);
      if (dt == null) return false;
      final isOverdue =
          a.status.toLowerCase() == 'overdue' || dt.isBefore(today);
      if (isOverdue) return false;
      final diff = dt.difference(today).inDays;
      return diff >= 0 && diff <= 7;
    }).toList();

    list.sort((a, b) {
      final dtA =
          a.targetDateTime ??
          ReportService.parseDate(a.targetDate) ??
          DateTime(2099);
      final dtB =
          b.targetDateTime ??
          ReportService.parseDate(b.targetDate) ??
          DateTime(2099);
      return dtA.compareTo(dtB);
    });
    return list;
  }

  List<ActionRecord> _getFollowUpsToday(DateTime today) {
    final list = widget.actions.where((a) {
      if (a.isClosed || a.isDeleted) return false;

      final existingDates = <DateTime>{};
      final inactiveDates = <DateTime>{};

      for (final f in a.followUps) {
        final d = ReportService.parseDate(f.followUpDate);
        if (d != null) {
          final norm = DateTime(d.year, d.month, d.day);
          if (f.isCompleted || f.status.trim().toLowerCase() == 'cancelled') {
            inactiveDates.add(norm);
          } else {
            existingDates.add(norm);
          }
        }
      }

      if (existingDates.contains(today)) return true;
      if (inactiveDates.contains(today)) return false;

      // Check nextFollowUpDate field if set and not "Not set"
      if (a.nextFollowUpDate.isNotEmpty && a.nextFollowUpDate != 'Not set') {
        final d = ReportService.parseDate(a.nextFollowUpDate);
        if (d != null) {
          final norm = DateTime(d.year, d.month, d.day);
          if (norm == today) {
            return true;
          }
        }
      }

      return false;
    }).toList();
    return list;
  }

  String _buildFollowUpTodaySubtitle(ActionRecord action, DateTime today) {
    ActionFollowUpRecord? match;
    for (final f in action.followUps) {
      if (f.isCompleted || f.status.trim().toLowerCase() == 'cancelled') continue;
      final d = ReportService.parseDate(f.followUpDate);
      if (d != null && d.year == today.year && d.month == today.month && d.day == today.day) {
        match = f;
        break;
      }
    }

    final person = action.assignedTo.isNotEmpty
        ? action.assignedTo
        : (action.primaryAssignee?.name ?? '');

    final parts = <String>['Follow-up today'];
    if (match != null && match.notes.trim().isNotEmpty) {
      parts.add(match.notes.trim());
    }
    if (person.isNotEmpty && person != 'Unassigned') {
      parts.add(person);
    }
    return parts.join(' • ');
  }

  List<ActionRecord> _getReadyForReviewActions() {
    final list = widget.actions.where((a) {
      if (a.isClosed) return false;
      final statusLower = a.status.trim().toLowerCase();
      return a.isReadyForReview ||
          statusLower == 'pending review' ||
          statusLower == 'ready for review' ||
          a.percentComplete >= 100;
    }).toList();

    list.sort((a, b) => b.percentComplete.compareTo(a.percentComplete));
    return list;
  }

  List<ActionRecord> _getRecentlyClosedActions() {
    final list = widget.actions.where((a) => a.isClosed).toList();
    list.sort((a, b) {
      final dtA =
          a.closedAt ?? ReportService.parseDate(a.closeDate) ?? DateTime(2000);
      final dtB =
          b.closedAt ?? ReportService.parseDate(b.closeDate) ?? DateTime(2000);
      return dtB.compareTo(dtA);
    });
    return list;
  }

  String _formatActionTimeInfo(AttentionCategory category, ActionRecord action, DateTime today) {
    switch (category) {
      case AttentionCategory.overdue:
        final dt = action.targetDateTime ?? ReportService.parseDate(action.targetDate);
        if (dt == null) return 'Overdue';
        final days = today.difference(dt).inDays;
        return days <= 1 ? '1 day overdue' : '$days days overdue';
      case AttentionCategory.dueSoon:
        final dt = action.targetDateTime ?? ReportService.parseDate(action.targetDate);
        if (dt == null) return 'Due soon';
        final days = dt.difference(today).inDays;
        return days == 0 ? 'Due today' : (days == 1 ? 'Due tomorrow' : 'Due in $days days');
      case AttentionCategory.followUpsToday:
        return 'Follow-up today';
      case AttentionCategory.readyForReview:
        return '${action.percentComplete}% complete';
      case AttentionCategory.recentlyClosed:
        final dt = action.closedAt ?? ReportService.parseDate(action.closeDate);
        if (dt == null) return 'Closed';
        final days = today.difference(dt).inDays;
        return days <= 0 ? 'Closed today' : (days == 1 ? 'Closed 1 day ago' : 'Closed $days days ago');
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final overdueList = _getOverdueActions(today);
    final dueSoonList = _getDueSoonActions(today);
    final followUpList = _getFollowUpsToday(today);
    final reviewList = _getReadyForReviewActions();
    final closedList = _getRecentlyClosedActions();

    final categoryData = {
      AttentionCategory.overdue: overdueList,
      AttentionCategory.dueSoon: dueSoonList,
      AttentionCategory.followUpsToday: followUpList,
      AttentionCategory.readyForReview: reviewList,
      AttentionCategory.recentlyClosed: closedList,
    };

    final isDark = AppTheme.isDark(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder(context)),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.25)
                : const Color(0x060F172A),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Color(0xFFDC2626),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.priority_high_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Needs Your Attention',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(context),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Actions requiring immediate supervision, review, or follow-up action',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.onViewAll != null)
                  InkWell(
                    onTap: widget.onViewAll,
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'View All',
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
          ),

          // 5 Compact Cards Row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 1050;
                final isMedium = constraints.maxWidth >= 600 && !isWide;

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: AttentionCategory.values.map((cat) {
                      final items = categoryData[cat] ?? [];
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _buildCategoryCard(
                            context,
                            cat,
                            items,
                            today,
                            isDark,
                          ),
                        ),
                      );
                    }).toList(),
                  );
                } else if (isMedium) {
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: AttentionCategory.values.map((cat) {
                      final items = categoryData[cat] ?? [];
                      final width = (constraints.maxWidth - 12) / 2;
                      return SizedBox(
                        width: width,
                        child: _buildCategoryCard(
                          context,
                          cat,
                          items,
                          today,
                          isDark,
                        ),
                      );
                    }).toList(),
                  );
                } else {
                  return Column(
                    children: AttentionCategory.values.map((cat) {
                      final items = categoryData[cat] ?? [];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildCategoryCard(
                          context,
                          cat,
                          items,
                          today,
                          isDark,
                        ),
                      );
                    }).toList(),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(
    BuildContext context,
    AttentionCategory cat,
    List<ActionRecord> items,
    DateTime today,
    bool isDark,
  ) {
    final count = items.length;
    final isSelected = _selectedCategory == cat;

    final bgColor = isDark
        ? cat.color.withValues(alpha: 0.12)
        : cat.lightBg;
    final borderColor = isSelected
        ? cat.color
        : (isDark ? cat.color.withValues(alpha: 0.25) : cat.borderColor);

    return InkWell(
      onTap: () {
        setState(() {
          _selectedCategory = cat;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Row: Icon, Category Name, Count, Chevron
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: cat.color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(cat.icon, size: 16, color: cat.color),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cat.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: cat.color,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, thickness: 0.7),
            const SizedBox(height: 8),

            // Action Items or Compact Empty State
            if (items.isEmpty)
              _buildEmptyState(context, cat)
            else
              ...items.take(3).map((action) {
                final tagText = _formatActionTimeInfo(cat, action, today);
                final displayId = action.actionNumber.isNotEmpty
                    ? action.actionNumber
                    : action.id;

                final isTwoLine = cat == AttentionCategory.readyForReview ||
                    cat == AttentionCategory.recentlyClosed ||
                    cat == AttentionCategory.followUpsToday;

                return InkWell(
                  onTap: () => widget.onActionTap(action),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3.5),
                    child: isTwoLine
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    displayId,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.white70
                                          : const Color(0xFF334155),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      action.subject,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? Colors.white60
                                            : const Color(0xFF475569),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              if (cat == AttentionCategory.followUpsToday)
                                Row(
                                  children: [
                                    Icon(
                                      Icons.schedule_rounded,
                                      size: 11,
                                      color: cat.color,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        _buildFollowUpTodaySubtitle(action, today),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                          color: cat.color,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Text(
                                  tagText,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: cat == AttentionCategory.readyForReview
                                        ? const Color(0xFF2563EB)
                                        : (isDark
                                            ? Colors.white54
                                            : const Color(0xFF64748B)),
                                  ),
                                ),
                            ],
                          )
                        : Row(
                            children: [
                              Text(
                                displayId,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.white70
                                      : const Color(0xFF334155),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  action.subject,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.white60
                                        : const Color(0xFF475569),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                flex: 2,
                                child: Text(
                                  tagText,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w500,
                                    color: cat.color,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AttentionCategory cat) {
    if (cat == AttentionCategory.overdue) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Clear of Overdue',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cat.color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'No overdue actions! All actions are on schedule.',
              style: TextStyle(
                fontSize: 10.5,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 14,
            color: cat.color.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'No actions in ${cat.label.toLowerCase()}',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
