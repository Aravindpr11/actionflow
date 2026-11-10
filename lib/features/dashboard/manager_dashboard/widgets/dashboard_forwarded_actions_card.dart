import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:flutter/material.dart';

class DashboardForwardedActionsCard extends StatelessWidget {
  const DashboardForwardedActionsCard({
    super.key,
    required this.actions,
    this.currentUserId,
    this.currentUserName,
    this.currentUserEmail,
    this.isManager = true,
    required this.onTapCard,
    required this.onTapForwardedByMe,
    required this.onTapForwardedToMe,
    this.isLoading = false,
    this.errorMessage,
  });

  final List<ActionRecord> actions;
  final String? currentUserId;
  final String? currentUserName;
  final String? currentUserEmail;
  final bool isManager;
  final VoidCallback onTapCard;
  final VoidCallback onTapForwardedByMe;
  final VoidCallback onTapForwardedToMe;
  final bool isLoading;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final forwardedByMeList = actions
        .where((a) => a.isForwardedBy(currentUserId, currentUserName, currentUserEmail))
        .toList();
    final forwardedToMeList = actions
        .where((a) => a.isForwardedTo(currentUserId, currentUserName, currentUserEmail))
        .toList();
    final totalForwardedList = actions.where((a) => a.isForwarded).toList();

    final forwardedByMeCount = forwardedByMeList.length;
    final forwardedToMeCount = forwardedToMeList.length;
    final totalForwardedCount = isManager
        ? totalForwardedList.length
        : forwardedToMeCount;

    final isDark = AppTheme.isDark(context);
    const accentColor = Color(0xFF7C3AED);

    return Container(
      key: ValueKey(isManager ? 'dashboard_forwarded_actions_card' : 'worker_forwarded_actions_card'),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? accentColor.withValues(alpha: 0.3)
              : const Color(0xFFDDD6FE),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.25)
                : const Color(0x060F172A),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTapCard,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Header Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(
                        Icons.shortcut_rounded,
                        color: accentColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                'Forwarded Actions',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.5,
                                  color: AppTheme.textPrimary(context),
                                  letterSpacing: -0.2,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$totalForwardedCount Total',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: accentColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isManager
                                ? 'Track collaborated actions, contributor assignments, and delegated sub-tasks'
                                : 'Actions forwarded to you for shared contribution or delegated sub-tasks',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 13,
                      color: AppTheme.textSecondary(context),
                    ),
                  ],
                ),

                if (isLoading) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(
                    minHeight: 2,
                    color: accentColor,
                  ),
                ] else if (errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    errorMessage!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red.shade600,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  // Interactive Quick Filter Chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildFilterChip(
                        context: context,
                        label: 'Forwarded to Me',
                        count: forwardedToMeCount,
                        icon: Icons.move_to_inbox_rounded,
                        color: const Color(0xFF0284C7),
                        onTap: onTapForwardedToMe,
                      ),
                      if (isManager || forwardedByMeCount > 0)
                        _buildFilterChip(
                          context: context,
                          label: 'Forwarded by Me',
                          count: forwardedByMeCount,
                          icon: Icons.outbox_rounded,
                          color: const Color(0xFF16A34A),
                          onTap: onTapForwardedByMe,
                        ),
                      _buildFilterChip(
                        context: context,
                        label: isManager ? 'All Forwarded' : 'View In Register',
                        count: isManager ? totalForwardedCount : null,
                        icon: Icons.hub_rounded,
                        color: accentColor,
                        onTap: onTapCard,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required BuildContext context,
    required String label,
    int? count,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = AppTheme.isDark(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isDark
              ? color.withValues(alpha: 0.12)
              : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: isDark ? 0.35 : 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

