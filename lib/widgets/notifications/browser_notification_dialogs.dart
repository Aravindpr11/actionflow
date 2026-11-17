import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class BrowserNotificationDialogs {
  /// Displays step-by-step instructions for allowing notifications when previously blocked in browser settings.
  static void showBlockedInstructions(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardBg(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppTheme.cardBorder(context)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFD97706).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.notifications_off_rounded,
                color: Color(0xFFD97706),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Browser Notifications Blocked',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notifications are currently blocked by your browser settings for https://app.actionflow.cc.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary(context),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'How to enable notifications:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 10),
                _buildInstructionStep(
                  context,
                  step: '1',
                  title: 'Click the Site Settings / Padlock icon',
                  description:
                      'In your browser address bar next to "https://app.actionflow.cc", click the lock (🔒), tune (🎛️), or site information icon.',
                ),
                const SizedBox(height: 8),
                _buildInstructionStep(
                  context,
                  step: '2',
                  title: 'Find "Notifications" in permissions',
                  description:
                      'Locate the "Notifications" permission line in the site settings popup or dropdown menu.',
                ),
                const SizedBox(height: 8),
                _buildInstructionStep(
                  context,
                  step: '3',
                  title: 'Change setting to "Allow"',
                  description:
                      'Switch the toggle or select "Allow" from the permission dropdown.',
                ),
                const SizedBox(height: 8),
                _buildInstructionStep(
                  context,
                  step: '4',
                  title: 'Reload the web page',
                  description:
                      'Refresh the ActionFlow tab (Ctrl+R or Cmd+R) for the updated browser permission to take effect.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it, Close'),
          ),
        ],
      ),
    );
  }

  static Widget _buildInstructionStep(
    BuildContext context, {
    required String step,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF1565C0).withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Text(
            step,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1565C0),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.textSecondary(context),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
