import 'package:action_flow/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

class DashboardQuickActions extends StatelessWidget {
  const DashboardQuickActions({
    super.key,
    required this.onAddAction,
    required this.onActionRegister,
    required this.onMyActions,
    required this.onReports,
    required this.onCalendar,
  });

  final VoidCallback onAddAction;
  final VoidCallback onActionRegister;
  final VoidCallback onMyActions;
  final VoidCallback onReports;
  final VoidCallback onCalendar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder(context)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.isDark(context)
                ? Colors.black.withValues(alpha: 0.2)
                : const Color(0x060F172A),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 650;

          return Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.bolt_rounded,
                    color: Color(0xFFEAB308),
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                ],
              ),
              if (!isNarrow) const SizedBox(width: 6),
              ElevatedButton.icon(
                onPressed: onAddAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                ),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 17),
                label: const Text(
                  'Add Action',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onActionRegister,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0284C7),
                  side: BorderSide(
                    color: const Color(
                      0xFF0284C7,
                    ).withValues(alpha: AppTheme.isDark(context) ? 0.5 : 0.3),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                ),
                icon: const Icon(Icons.table_chart_rounded, size: 16),
                label: const Text(
                  'Action Register',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onMyActions,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF16A34A),
                  side: BorderSide(
                    color: const Color(
                      0xFF16A34A,
                    ).withValues(alpha: AppTheme.isDark(context) ? 0.5 : 0.3),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                ),
                icon: const Icon(Icons.assignment_turned_in_rounded, size: 16),
                label: const Text(
                  'My Actions',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onReports,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF7C3AED),
                  side: BorderSide(
                    color: const Color(
                      0xFF7C3AED,
                    ).withValues(alpha: AppTheme.isDark(context) ? 0.5 : 0.3),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                ),
                icon: const Icon(Icons.bar_chart_rounded, size: 16),
                label: const Text(
                  'Reports & Graphs',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onCalendar,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEA580C),
                  side: BorderSide(
                    color: const Color(
                      0xFFEA580C,
                    ).withValues(alpha: AppTheme.isDark(context) ? 0.5 : 0.3),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                ),
                icon: const Icon(Icons.calendar_month_rounded, size: 16),
                label: const Text(
                  'Calendar',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
