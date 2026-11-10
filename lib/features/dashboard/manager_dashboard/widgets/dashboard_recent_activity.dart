import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/services/report_service.dart';
import 'package:flutter/material.dart';

enum ActivityType {
  created('Created', Icons.add_rounded, Color(0xFFF59E0B), Color(0xFFFEF3C7)),
  progressUpdate(
    'Progress Update',
    Icons.arrow_upward_rounded,
    Color(0xFF0284C7),
    Color(0xFFE0F2FE),
  ),
  followUp(
    'Follow-Up Checkpoint',
    Icons.calendar_today_rounded,
    Color(0xFF06B6D4),
    Color(0xFFCFFAFE),
  ),
  review(
    'Ready for Review',
    Icons.rate_review_outlined,
    Color(0xFF8B5CF6),
    Color(0xFFEDE9FE),
  ),
  closure(
    'Closed & Verified',
    Icons.check_rounded,
    Color(0xFF10B981),
    Color(0xFFD1FAE5),
  );

  const ActivityType(this.label, this.icon, this.color, this.bgColor);
  final String label;
  final IconData icon;
  final Color color;
  final Color bgColor;
}

class DashboardActivityEvent {
  const DashboardActivityEvent({
    required this.action,
    required this.type,
    required this.title,
    required this.description,
    required this.author,
    required this.timestamp,
  });

  final ActionRecord action;
  final ActivityType type;
  final String title;
  final String description;
  final String author;
  final DateTime timestamp;
}

class DashboardRecentActivity extends StatelessWidget {
  const DashboardRecentActivity({
    super.key,
    required this.actions,
    required this.onActionTap,
    this.onViewAll,
  });

  final List<ActionRecord> actions;
  final ValueChanged<ActionRecord> onActionTap;
  final VoidCallback? onViewAll;

  List<DashboardActivityEvent> _extractEvents() {
    final events = <DashboardActivityEvent>[];

    for (final a in actions) {
      // 1. Action Creation Event
      final createdDt =
          ReportService.parseDate(a.dateRaised) ?? DateTime.now();
      events.add(
        DashboardActivityEvent(
          action: a,
          type: ActivityType.created,
          title: '${a.displayId} Action created',
          description: a.subject,
          author: a.assignedBy.isNotEmpty ? a.assignedBy : 'Manager',
          timestamp: createdDt,
        ),
      );

      // 2. Progress Updates
      for (final u in a.progressUpdates) {
        final uDt =
            u.createdAt ?? ReportService.parseDate(u.updateDate) ?? createdDt;
        events.add(
          DashboardActivityEvent(
            action: a,
            type: ActivityType.progressUpdate,
            title: '${a.displayId} Progress updated to ${u.progress}%',
            description: u.comments.isNotEmpty
                ? u.comments
                : 'Progress updated to ${u.progress}%: ${a.subject}',
            author: u.updatedByName.isNotEmpty
                ? u.updatedByName
                : (a.assignedTo.isNotEmpty ? a.assignedTo : 'Staff'),
            timestamp: uDt,
          ),
        );
      }

      // 3. Follow-Ups
      for (final f in a.followUps) {
        final fDt =
            f.createdAt ?? ReportService.parseDate(f.followUpDate) ?? createdDt;
        events.add(
          DashboardActivityEvent(
            action: a,
            type: ActivityType.followUp,
            title: '${a.displayId} Follow-up checkpoint created',
            description: f.notes.isNotEmpty
                ? f.notes
                : 'Follow-up checkpoint recorded for ${a.displayId}',
            author: f.createdByName.isNotEmpty ? f.createdByName : 'Manager',
            timestamp: fDt,
          ),
        );
      }

      // 4. Ready for Review
      if (a.isReadyForReview && !a.isClosed) {
        final rDt =
            ReportService.parseDate(a.latestUpdateDate) ?? createdDt;
        events.add(
          DashboardActivityEvent(
            action: a,
            type: ActivityType.review,
            title: '${a.displayId} Ready for manager review',
            description: '${a.subject} (${a.percentComplete}% complete)',
            author: a.assignedTo.isNotEmpty ? a.assignedTo : 'Staff',
            timestamp: rDt,
          ),
        );
      }

      // 5. Closed
      if (a.isClosed) {
        final cDt =
            a.closedAt ?? ReportService.parseDate(a.closeDate) ?? createdDt;
        events.add(
          DashboardActivityEvent(
            action: a,
            type: ActivityType.closure,
            title: '${a.displayId} Action closed',
            description: a.closureComment.isNotEmpty
                ? a.closureComment
                : 'Action verified and closed: ${a.subject}',
            author: (a.closedByName != null && a.closedByName!.isNotEmpty)
                ? a.closedByName!
                : 'Manager',
            timestamp: cDt,
          ),
        );
      }
    }

    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return events;
  }

  String _formatTimeAgo(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays <= 0) {
      if (diff.inHours <= 1) return 'Just now';
      return '${diff.inHours}h ago';
    }
    if (diff.inDays == 1) return '1 day ago';
    return '${diff.inDays} days ago';
  }

  @override
  Widget build(BuildContext context) {
    final events = _extractEvents();
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
                  'Recent Activity',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              InkWell(
                onTap: onViewAll,
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
          const SizedBox(height: 2),
          Text(
            'Real-time audit log of action updates, checkpoints, and closures',
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary(context),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          const Divider(height: 1, thickness: 0.6),
          const SizedBox(height: 4),

          // Events List
          Expanded(
            child: events.isEmpty
                ? Center(
                    child: Text(
                      'No recent activity recorded',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      children: events.take(5).map((e) {
                      final timeStr = _formatTimeAgo(e.timestamp);

                      return InkWell(
                        onTap: () => onActionTap(e.action),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.5),
                          child: Row(
                            children: [
                              Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? e.type.color.withValues(alpha: 0.2)
                                      : e.type.bgColor,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Icon(
                                    e.type.icon,
                                    size: 12,
                                    color: e.type.color,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      e.title,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      e.description,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: isDark ? Colors.white54 : const Color(0xFF64748B),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                timeStr,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
          ),
        ],
      ),
    );
  }
}
