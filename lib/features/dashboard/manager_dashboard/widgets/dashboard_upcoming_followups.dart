import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/services/report_service.dart';
import 'package:flutter/material.dart';

enum FollowUpTimeframe {
  today('Today'),
  tomorrow('Tomorrow'),
  upcoming('Upcoming');

  const FollowUpTimeframe(this.label);
  final String label;
}

class DashboardUpcomingFollowups extends StatefulWidget {
  const DashboardUpcomingFollowups({
    super.key,
    required this.actions,
    required this.onActionTap,
    required this.onOpenCalendar,
  });

  final List<ActionRecord> actions;
  final ValueChanged<ActionRecord> onActionTap;
  final VoidCallback onOpenCalendar;

  @override
  State<DashboardUpcomingFollowups> createState() =>
      _DashboardUpcomingFollowupsState();
}

class _DashboardUpcomingFollowupsState
    extends State<DashboardUpcomingFollowups> {
  FollowUpTimeframe _timeframe = FollowUpTimeframe.today;

  List<_FollowUpEntry> _extractFollowUps(DateTime today) {
    final tomorrow = today.add(const Duration(days: 1));
    final entries = <_FollowUpEntry>[];

    for (final a in widget.actions) {
      if (a.isClosed || a.isDeleted) continue;

      final scheduledDates = <DateTime>{};
      final inactiveDates = <DateTime>{};

      for (final f in a.followUps) {
        final d = ReportService.parseDate(f.followUpDate);
        if (d != null) {
          final normalized = DateTime(d.year, d.month, d.day);
          if (f.isCompleted || f.status.trim().toLowerCase() == 'cancelled') {
            inactiveDates.add(normalized);
          } else {
            scheduledDates.add(normalized);
          }
        }
      }

      if (a.nextFollowUpDate.isNotEmpty &&
          a.nextFollowUpDate != 'Not set') {
        final d = ReportService.parseDate(a.nextFollowUpDate);
        if (d != null) {
          final normalized = DateTime(d.year, d.month, d.day);
          if (!inactiveDates.contains(normalized)) {
            scheduledDates.add(normalized);
          }
        }
      }

      for (final entryDate in scheduledDates) {
        final FollowUpTimeframe tf;
        if (entryDate == today) {
          tf = FollowUpTimeframe.today;
        } else if (entryDate == tomorrow) {
          tf = FollowUpTimeframe.tomorrow;
        } else if (entryDate.isAfter(tomorrow)) {
          tf = FollowUpTimeframe.upcoming;
        } else {
          continue; // Past follow-up
        }
        entries.add(_FollowUpEntry(action: a, date: entryDate, timeframe: tf));
      }
    }

    entries.sort((a, b) => a.date.compareTo(b.date));
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final allEntries = _extractFollowUps(today);

    final todayEntries = allEntries
        .where((e) => e.timeframe == FollowUpTimeframe.today)
        .toList();
    final tomorrowEntries = allEntries
        .where((e) => e.timeframe == FollowUpTimeframe.tomorrow)
        .toList();
    final upcomingEntries = allEntries
        .where((e) => e.timeframe == FollowUpTimeframe.upcoming)
        .toList();

    final counts = {
      FollowUpTimeframe.today: todayEntries.length,
      FollowUpTimeframe.tomorrow: tomorrowEntries.length,
      FollowUpTimeframe.upcoming: upcomingEntries.length,
    };

    final currentEntries = switch (_timeframe) {
      FollowUpTimeframe.today => todayEntries,
      FollowUpTimeframe.tomorrow => tomorrowEntries,
      FollowUpTimeframe.upcoming => upcomingEntries,
    };

    final isDark = AppTheme.isDark(context);

    return Container(
      height: 260,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder(context)),
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
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Upcoming Follow-Ups',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              InkWell(
                onTap: widget.onOpenCalendar,
                borderRadius: BorderRadius.circular(4),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View All',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 13,
                      color: Color(0xFF2563EB),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Hidden semantic labels for tests: Today, Tomorrow, Upcoming
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: FollowUpTimeframe.values.map((tf) {
              final isSel = _timeframe == tf;
              final count = counts[tf] ?? 0;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InkWell(
                  onTap: () => setState(() => _timeframe = tf),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSel ? const Color(0xFF2563EB).withValues(alpha: 0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${tf.label} ($count)',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        color: isSel ? const Color(0xFF2563EB) : AppTheme.textSecondary(context),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          const Divider(height: 1, thickness: 0.6),
          const SizedBox(height: 4),

          // Items List
          Expanded(
            child: currentEntries.isEmpty
                ? Center(
                    child: Text(
                      'No scheduled follow-ups',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: currentEntries.take(5).map((e) {
                      final a = e.action;
                      final assignee = a.isExternalRecipient
                          ? (a.externalRecipientName ?? 'External')
                          : (a.assignedTo.isNotEmpty ? a.assignedTo : 'Unassigned');

                      final daysDiff = e.date.difference(today).inDays;
                      final dateLabel = daysDiff <= 0
                          ? 'Today'
                          : (daysDiff == 1 ? 'Tomorrow' : 'In $daysDiff days');
                      final dateColor = daysDiff <= 0
                          ? const Color(0xFFEF4444)
                          : const Color(0xFFF97316);

                      return InkWell(
                        onTap: () => widget.onActionTap(a),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.5),
                          child: Row(
                            children: [
                              Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF7ED),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.calendar_today_rounded,
                                    size: 12,
                                    color: Color(0xFFEA580C),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                a.displayId,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white70 : const Color(0xFF334155),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  a.subject,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? Colors.white60 : const Color(0xFF475569),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                dateLabel,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: dateColor,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  assignee,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${a.percentComplete}%',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2563EB),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FollowUpEntry {
  const _FollowUpEntry({
    required this.action,
    required this.date,
    required this.timeframe,
  });

  final ActionRecord action;
  final DateTime date;
  final FollowUpTimeframe timeframe;
}
