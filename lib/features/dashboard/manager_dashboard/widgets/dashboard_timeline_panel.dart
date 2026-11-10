import 'dart:math' as math;
import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/services/report_service.dart';
import 'package:flutter/material.dart';

class DashboardTimelinePanel extends StatelessWidget {
  const DashboardTimelinePanel({super.key, required this.actions});

  final List<ActionRecord> actions;

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final now = DateTime.now();

    // Generate 7 sample dates across the last 30 days
    final List<DateTime> sampleDates = List.generate(7, (i) {
      final daysAgo = (6 - i) * 5;
      return now.subtract(Duration(days: daysAgo));
    });

    // Group due and completed counts around each 5-day bucket
    final List<int> dueCounts = [];
    final List<int> completedCounts = [];

    for (int i = 0; i < sampleDates.length; i++) {
      final d = sampleDates[i];
      final bucketStart = d.subtract(const Duration(days: 2));
      final bucketEnd = d.add(const Duration(days: 2, hours: 23));

      final due = actions.where((a) {
        final target = a.targetDateTime ?? ReportService.parseDate(a.targetDate);
        if (target == null) return false;
        return target.isAfter(bucketStart) && target.isBefore(bucketEnd);
      }).length;

      final completed = actions.where((a) {
        if (!a.isClosed) return false;
        final closed = a.closedAt ?? ReportService.parseDate(a.closeDate);
        if (closed == null) return false;
        return closed.isAfter(bucketStart) && closed.isBefore(bucketEnd);
      }).length;

      dueCounts.add(due);
      completedCounts.add(completed);
    }

    final maxVal = math.max(
      8,
      [...dueCounts, ...completedCounts].fold<int>(0, (m, v) => math.max(m, v)),
    );
    final yMax = ((maxVal + 1) ~/ 2) * 2;

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
          // Header & Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Actions Due vs Completed (Last 30 Days)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LegendDot(
                    color: const Color(0xFF0284C7),
                    label: 'Actions Due',
                    isDark: isDark,
                  ),
                  const SizedBox(width: 10),
                  _LegendDot(
                    color: const Color(0xFF10B981),
                    label: 'Actions Completed',
                    isDark: isDark,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Line Chart Area
          Expanded(
            child: Row(
              children: [
                // Y-Axis labels
                SizedBox(
                  width: 18,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$yMax', style: TextStyle(fontSize: 9.5, color: isDark ? Colors.white38 : const Color(0xFF94A3B8))),
                      Text('${(yMax * 3) ~/ 4}', style: TextStyle(fontSize: 9.5, color: isDark ? Colors.white38 : const Color(0xFF94A3B8))),
                      Text('${yMax ~/ 2}', style: TextStyle(fontSize: 9.5, color: isDark ? Colors.white38 : const Color(0xFF94A3B8))),
                      Text('${yMax ~/ 4}', style: TextStyle(fontSize: 9.5, color: isDark ? Colors.white38 : const Color(0xFF94A3B8))),
                      Text('0', style: TextStyle(fontSize: 9.5, color: isDark ? Colors.white38 : const Color(0xFF94A3B8))),
                    ],
                  ),
                ),
                const SizedBox(width: 4),

                // Chart Painter & X Labels
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _DualLineChartPainter(
                            duePoints: dueCounts,
                            completedPoints: completedCounts,
                            yMax: yMax,
                            isDark: isDark,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final List<DateTime> displayedDates;
                          if (constraints.maxWidth < 280) {
                            displayedDates = [sampleDates.first, sampleDates.last];
                          } else if (constraints.maxWidth < 450) {
                            displayedDates = [
                              sampleDates.first,
                              sampleDates[sampleDates.length ~/ 2],
                              sampleDates.last,
                            ];
                          } else {
                            displayedDates = sampleDates;
                          }
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: displayedDates.map((d) {
                              final label = '${d.day} ${_monthName(d.month)}';
                              return Text(
                                label,
                                style: TextStyle(
                                  fontSize: 9.0,
                                  color: isDark ? Colors.white54 : const Color(0xFF64748B),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _monthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return months[(month - 1).clamp(0, 11)];
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    required this.isDark,
  });

  final Color color;
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            color: isDark ? Colors.white70 : const Color(0xFF475569),
          ),
        ),
      ],
    );
  }
}

class _DualLineChartPainter extends CustomPainter {
  _DualLineChartPainter({
    required this.duePoints,
    required this.completedPoints,
    required this.yMax,
    required this.isDark,
  });

  final List<int> duePoints;
  final List<int> completedPoints;
  final int yMax;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Grid lines
    final gridPaint = Paint()
      ..color = isDark ? Colors.white10 : const Color(0xFFF1F5F9)
      ..strokeWidth = 1.0;

    for (int i = 0; i <= 4; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (duePoints.length < 2) return;

    final stepX = size.width / (duePoints.length - 1);

    // 1. Draw Due Line (Blue)
    _drawLine(
      canvas,
      size,
      duePoints,
      stepX,
      const Color(0xFF0284C7),
    );

    // 2. Draw Completed Line (Green)
    _drawLine(
      canvas,
      size,
      completedPoints,
      stepX,
      const Color(0xFF10B981),
    );
  }

  void _drawLine(
    Canvas canvas,
    Size size,
    List<int> points,
    double stepX,
    Color color,
  ) {
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final dotInnerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path();
    final List<Offset> offsets = [];

    for (int i = 0; i < points.length; i++) {
      final x = i * stepX;
      final ratio = yMax > 0 ? (points[i] / yMax).clamp(0.0, 1.0) : 0.0;
      final y = size.height - (ratio * (size.height - 8)) - 4;
      final pt = Offset(x, y);
      offsets.add(pt);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, linePaint);

    for (final pt in offsets) {
      canvas.drawCircle(pt, 3.5, dotPaint);
      canvas.drawCircle(pt, 1.8, dotInnerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DualLineChartPainter oldDelegate) => true;
}
