import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/services/report_service.dart';
import 'package:flutter/material.dart';

class DashboardKpiData {
  const DashboardKpiData({
    required this.label,
    required this.value,
    required this.subtext,
    required this.color,
    required this.bgColor,
    required this.icon,
  });

  final String label;
  final String value;
  final String subtext;
  final Color color;
  final Color bgColor;
  final IconData icon;
}

class DashboardKpiCards extends StatelessWidget {
  const DashboardKpiCards({
    super.key,
    required this.actions,
    this.onKpiTap,
    this.followUpCount,
    this.followUpSubtext,
    this.personalTaskCount,
    this.personalTaskSubtext,
  });

  final List<ActionRecord> actions;
  final ValueChanged<String>? onKpiTap;
  final int? followUpCount;
  final String? followUpSubtext;
  final int? personalTaskCount;
  final String? personalTaskSubtext;

  @override
  Widget build(BuildContext context) {
    final agg = ReportService.compute(actions);
    final total = agg.total;

    final inProgressCount = actions.where((a) {
      if (a.isClosed) return false;
      final s = a.status.trim().toLowerCase();
      if (s == 'in progress') return true;
      if (s != 'open' &&
          s != 'pending review' &&
          s != 'ready for review' &&
          s != 'closed' &&
          s != 'completed') {
        return true;
      }
      return a.percentComplete > 0 &&
          a.percentComplete < 100 &&
          !a.isReadyForReview;
    }).length;

    String pctOfTotal(int count) {
      if (total <= 0) return '0% of total';
      final p = (count / total * 100).round();
      return '$p% of total';
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Compute pending follow-ups from actions if not explicitly passed
    int computedFollowUps = 0;
    int computedFollowUpsToday = 0;
    for (final a in actions) {
      if (a.isClosed || a.isDeleted) continue;
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
            computedFollowUps++;
            if (norm.year == today.year && norm.month == today.month && norm.day == today.day) {
              computedFollowUpsToday++;
            }
          }
        }
      }

      if (a.nextFollowUpDate.isNotEmpty && a.nextFollowUpDate != 'Not set') {
        final d = ReportService.parseDate(a.nextFollowUpDate);
        if (d != null) {
          final norm = DateTime(d.year, d.month, d.day);
          if (!inactiveDates.contains(norm) && !existingDates.contains(norm)) {
            computedFollowUps++;
            if (norm.year == today.year && norm.month == today.month && norm.day == today.day) {
              computedFollowUpsToday++;
            }
          }
        }
      }
    }

    final effectiveFollowUpCount = followUpCount ?? computedFollowUps;
    final effectiveFollowUpSubtext = followUpSubtext ??
        (computedFollowUpsToday > 0
            ? '$computedFollowUpsToday due today'
            : (effectiveFollowUpCount > 0 ? '$effectiveFollowUpCount pending' : 'No follow-ups'));

    final effectivePersonalTaskCount = personalTaskCount ?? 0;
    final effectivePersonalTaskSubtext = personalTaskSubtext ??
        (effectivePersonalTaskCount > 0 ? '$effectivePersonalTaskCount active' : 'No pending tasks');

    final cards = [
      DashboardKpiData(
        label: 'Total Actions',
        value: total.toString(),
        subtext: 'All actions',
        color: const Color(0xFF0284C7),
        bgColor: const Color(0xFFE0F2FE),
        icon: Icons.layers_outlined,
      ),
      DashboardKpiData(
        label: 'Open',
        value: agg.open.toString(),
        subtext: pctOfTotal(agg.open),
        color: const Color(0xFF16A34A),
        bgColor: const Color(0xFFDCFCE7),
        icon: Icons.pending_actions_rounded,
      ),
      DashboardKpiData(
        label: 'In Progress',
        value: inProgressCount.toString(),
        subtext: pctOfTotal(inProgressCount),
        color: const Color(0xFF2563EB),
        bgColor: const Color(0xFFDBEAFE),
        icon: Icons.sync_rounded,
      ),
      DashboardKpiData(
        label: 'Overdue',
        value: agg.overdue.toString(),
        subtext: pctOfTotal(agg.overdue),
        color: const Color(0xFFDC2626),
        bgColor: const Color(0xFFFEE2E2),
        icon: Icons.warning_amber_rounded,
      ),
      DashboardKpiData(
        label: 'Ready for Review',
        value: agg.pendingReview.toString(),
        subtext: pctOfTotal(agg.pendingReview),
        color: const Color(0xFF7C3AED),
        bgColor: const Color(0xFFF3E8FF),
        icon: Icons.rate_review_outlined,
      ),
      DashboardKpiData(
        label: 'Closed',
        value: agg.closed.toString(),
        subtext: pctOfTotal(agg.closed),
        color: const Color(0xFF059669),
        bgColor: const Color(0xFFD1FAE5),
        icon: Icons.check_circle_rounded,
      ),
      DashboardKpiData(
        label: 'Average Completion %',
        value: '${agg.avgCompletionPct.round()}%',
        subtext: 'Overall progress',
        color: const Color(0xFFEA580C),
        bgColor: const Color(0xFFFFEDD5),
        icon: Icons.bar_chart_rounded,
      ),
      DashboardKpiData(
        label: 'Follow-ups',
        value: effectiveFollowUpCount.toString(),
        subtext: effectiveFollowUpSubtext,
        color: const Color(0xFF0D9488),
        bgColor: const Color(0xFFCCFBF1),
        icon: Icons.schedule_rounded,
      ),
      DashboardKpiData(
        label: 'Personal Tasks',
        value: effectivePersonalTaskCount.toString(),
        subtext: effectivePersonalTaskSubtext,
        color: const Color(0xFF6366F1),
        bgColor: const Color(0xFFEEF2FF),
        icon: Icons.checklist_rounded,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;

        if (w >= 1400) {
          return Row(
            children: cards.map((data) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _KpiCard(
                    data: data,
                    onTap: () => onKpiTap?.call(data.label),
                  ),
                ),
              );
            }).toList(),
          );
        } else if (w >= 850) {
          final cols = w >= 1150 ? 5 : 4;
          final cardWidth = (w - ((cols - 1) * 12)) / cols;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: cards.map((data) {
              return SizedBox(
                width: cardWidth,
                child: _KpiCard(
                  data: data,
                  onTap: () => onKpiTap?.call(data.label),
                ),
              );
            }).toList(),
          );
        } else if (w >= 580) {
          final cardWidth = (w - (2 * 12)) / 3;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: cards.map((data) {
              return SizedBox(
                width: cardWidth,
                child: _KpiCard(
                  data: data,
                  onTap: () => onKpiTap?.call(data.label),
                ),
              );
            }).toList(),
          );
        } else if (w >= 380) {
          final cardWidth = (w - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: cards.map((data) {
              return SizedBox(
                width: cardWidth,
                child: _KpiCard(
                  data: data,
                  onTap: () => onKpiTap?.call(data.label),
                ),
              );
            }).toList(),
          );
        } else {
          return Column(
            children: cards.map((data) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _KpiCard(
                  data: data,
                  onTap: () => onKpiTap?.call(data.label),
                ),
              );
            }).toList(),
          );
        }
      },
    );
  }
}

class _KpiCard extends StatefulWidget {
  const _KpiCard({required this.data, required this.onTap});

  final DashboardKpiData data;
  final VoidCallback onTap;

  @override
  State<_KpiCard> createState() => _KpiCardState();
}

class _KpiCardState extends State<_KpiCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final isDark = AppTheme.isDark(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.cardBg(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isHovered
                  ? d.color.withValues(alpha: 0.6)
                  : AppTheme.cardBorder(context),
              width: _isHovered ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: _isHovered
                    ? d.color.withValues(alpha: 0.12)
                    : (isDark
                        ? Colors.black.withValues(alpha: 0.2)
                        : const Color(0x060F172A)),
                blurRadius: _isHovered ? 8 : 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark
                      ? d.color.withValues(alpha: 0.18)
                      : d.bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Icon(d.icon, color: d.color, size: 20),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      d.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      d.value,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      d.subtext,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppTheme.textSecondary(context).withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
