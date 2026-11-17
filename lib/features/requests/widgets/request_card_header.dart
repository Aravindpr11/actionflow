import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/request_models.dart';

/// Reusable responsive header for Request cards in MyRequestsScreen and RequestApprovalScreen.
/// Adapts seamlessly across viewport widths:
/// - Desktop / Tablet (>= 580px): Left-aligns ID, Type, and Priority badges; right-aligns Status and Decision badges.
/// - Mobile (< 580px, e.g. 393px iPhone 16): Wraps badges fluidly without overflowing or clipping.
class RequestCardHeader extends StatelessWidget {
  const RequestCardHeader({
    super.key,
    required this.request,
    this.showDecisionNeeded = false,
  });

  final RequestRecord request;
  final bool showDecisionNeeded;

  @override
  Widget build(BuildContext context) {
    final typeColor = RequestType.getColor(request.requestType);
    final priorityColor = RequestPriority.getColor(request.priority);
    final statusColor = RequestStatus.getColor(request.status);

    final idBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
      ),
      child: Text(
        request.displayId,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: AppTheme.primaryColor,
        ),
      ),
    );

    final typeBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: typeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(RequestType.getIcon(request.requestType), size: 14, color: typeColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              request.requestType,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: typeColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    final priorityBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: priorityColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        request.priority,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: priorityColor,
        ),
      ),
    );

    Widget? decisionBadge;
    if (showDecisionNeeded) {
      decisionBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFDC2626),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_rounded, size: 13, color: Colors.white),
            SizedBox(width: 4),
            Flexible(
              child: Text(
                'Your Decision Needed',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    final statusBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(RequestStatus.getIcon(request.status), size: 14, color: statusColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              request.status,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // When space permits (>= 580px), present standard desktop row with right-aligned status
        if (constraints.maxWidth >= 580) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    idBadge,
                    typeBadge,
                    priorityBadge,
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ?decisionBadge,
                  statusBadge,
                ],
              ),
            ],
          );
        }

        // On mobile (< 580px, e.g. 393px iPhone 16), wrap fluidly without overflow
        return Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            idBadge,
            typeBadge,
            priorityBadge,
            ?decisionBadge,
            statusBadge,
          ],
        );
      },
    );
  }
}
