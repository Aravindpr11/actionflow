import 'package:action_flow/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

class DashboardHeaderBanner extends StatelessWidget {
  const DashboardHeaderBanner({
    super.key,
    required this.organizationName,
    required this.managerName,
    required this.onViewFullReports,
    this.currentDate,
    this.title = 'Manager Dashboard',
    this.subtitle = 'Action Management Overview',
  });

  final String organizationName;
  final String managerName;
  final VoidCallback onViewFullReports;
  final DateTime? currentDate;
  final String title;
  final String subtitle;

  static const List<String> _weekdayNames = [
    '',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static const List<String> _monthNames = [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String _formatCurrentDate(DateTime date) {
    final weekday = _weekdayNames[date.weekday];
    final month = _monthNames[date.month];
    return '$weekday, ${date.day} $month ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final now = currentDate ?? DateTime.now();
    final dateStr = _formatCurrentDate(now);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 650;

        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 22,
            vertical: isMobile ? 16 : 20,
          ),
          decoration: BoxDecoration(
            color: AppTheme.cardBg(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.cardBorder(context)),
            boxShadow: [
              BoxShadow(
                color: AppTheme.isDark(context)
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
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 12,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isMobile
                          ? constraints.maxWidth
                          : constraints.maxWidth * 0.65,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: isMobile ? 20 : 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary(context),
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: isMobile ? 12.5 : 13.5,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: onViewFullReports,
                    icon: const Icon(Icons.bar_chart_rounded, size: 18),
                    label: const Text('View Full Reports'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, thickness: 1),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _MetadataChip(
                    icon: Icons.business_rounded,
                    label: organizationName.isNotEmpty
                        ? organizationName
                        : 'ActionFlow Enterprise',
                    color: const Color(0xFF0284C7),
                  ),
                  _MetadataChip(
                    icon: Icons.person_rounded,
                    label: managerName.isNotEmpty
                        ? managerName
                        : 'Operations Manager',
                    color: const Color(0xFF16A34A),
                  ),
                  _MetadataChip(
                    icon: Icons.calendar_today_rounded,
                    label: dateStr,
                    color: const Color(0xFF7C3AED),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppTheme.isDark(context) ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: AppTheme.isDark(context) ? 0.3 : 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary(context),
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
