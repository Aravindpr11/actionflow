import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/core/theme/theme_controller.dart';
import 'package:action_flow/services/browser_notification_service.dart';
import 'package:action_flow/services/sound_service.dart';
import 'package:action_flow/widgets/notifications/browser_notification_dialogs.dart';
import 'package:flutter/material.dart';

/// Comprehensive Settings screen featuring Appearance, Notifications, and Portal Preferences.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Notification Preferences
  bool _actionDueReminders = true;
  bool _emailDigestEnabled = true;
  bool _overdueEscalations = true;
  bool _browserPushAlerts = false;
  String _digestFrequency = 'Daily Morning Digest';

  // System & Portal Preferences
  bool _compactTableDensity = false;
  bool _autoRefreshData = true;

  @override
  void initState() {
    super.initState();
    final bn = BrowserNotificationService.instance;
    _browserPushAlerts =
        bn.isSupported && bn.permissionStatus.isGranted && bn.isNotificationEnabled;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final currentMode = ThemeController.instance.themeMode;
        final isDark = ThemeController.instance.isDark;

        return Scaffold(
          backgroundColor: AppTheme.scaffoldBg(context),
          appBar: AppBar(
            backgroundColor: AppTheme.headerBg(context),
            foregroundColor: AppTheme.textPrimary(context),
            elevation: 0,
            title: Text(
              'Application Settings',
              style: TextStyle(
                color: AppTheme.textPrimary(context),
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Divider(
                height: 1,
                thickness: 1,
                color: AppTheme.cardBorder(context),
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            children: [
              // ==========================================
              // 1. APPEARANCE & THEME
              // ==========================================
              _buildSectionHeader(
                context,
                icon: Icons.palette_outlined,
                title: 'Appearance & Theme',
                subtitle: 'Customize the interface theme. Theme preferences are saved locally offline.',
              ),
              const SizedBox(height: 14),

              Card(
                color: AppTheme.cardBg(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: AppTheme.cardBorder(context)),
                ),
                elevation: 0,
                child: Column(
                  children: [
                    _buildThemeTile(
                      context,
                      title: 'Light Theme',
                      subtitle:
                          'Standard clean high-contrast light mode (Default)',
                      icon: Icons.light_mode_rounded,
                      iconColor: const Color(0xFFEAB308),
                      value: ThemeMode.light,
                      groupValue: currentMode,
                      onChanged: (mode) {
                        if (mode != null) {
                          ThemeController.instance.setThemeMode(mode);
                        }
                      },
                    ),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: AppTheme.cardBorder(context),
                    ),
                    _buildThemeTile(
                      context,
                      title: 'Dark Theme',
                      subtitle: 'Enterprise deep slate/navy palette for reduced eye strain',
                      icon: Icons.dark_mode_outlined,
                      iconColor: const Color(0xFF38BDF8),
                      value: ThemeMode.dark,
                      groupValue: currentMode,
                      onChanged: (mode) {
                        if (mode != null) {
                          ThemeController.instance.setThemeMode(mode);
                        }
                      },
                    ),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: AppTheme.cardBorder(context),
                    ),
                    _buildThemeTile(
                      context,
                      title: 'System Default',
                      subtitle: 'Automatically sync with your operating system settings',
                      icon: Icons.settings_brightness_outlined,
                      iconColor: const Color(0xFF8B5CF6),
                      value: ThemeMode.system,
                      groupValue: currentMode,
                      onChanged: (mode) {
                        if (mode != null) {
                          ThemeController.instance.setThemeMode(mode);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Active Mode Status Pill
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.cardBorder(context)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: AppTheme.primaryAccent(context),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Active mode: ${isDark ? "Dark Theme" : (currentMode == ThemeMode.light ? "Light Theme" : "System Default")} • Saved locally without network dependency.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ==========================================
              // 2. NOTIFICATIONS & REMINDERS
              // ==========================================
              _buildSectionHeader(
                context,
                icon: Icons.notifications_active_outlined,
                title: 'Notification & Reminder Preferences',
                subtitle: 'Manage in-app alert triggers and automated email dispatch schedules.',
              ),
              const SizedBox(height: 14),

              Card(
                color: AppTheme.cardBg(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: AppTheme.cardBorder(context)),
                ),
                elevation: 0,
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      title: Text(
                        'Action Due Reminders',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      subtitle: Text(
                        'Receive reminders 48 hours prior to action target completion date',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                      value: _actionDueReminders,
                      onChanged: (val) =>
                          setState(() => _actionDueReminders = val),
                    ),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: AppTheme.cardBorder(context),
                    ),
                    SwitchListTile.adaptive(
                      title: Text(
                        'Overdue Escalation Alerts',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      subtitle: Text(
                        'High-priority alerts when actions exceed target date SLA',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                      value: _overdueEscalations,
                      onChanged: (val) =>
                          setState(() => _overdueEscalations = val),
                    ),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: AppTheme.cardBorder(context),
                    ),
                    SwitchListTile.adaptive(
                      title: Text(
                        'Automated Email Digests',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      subtitle: Text(
                        'Receive periodic email summary of assigned and supervised actions',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                      value: _emailDigestEnabled,
                      onChanged: (val) =>
                          setState(() => _emailDigestEnabled = val),
                    ),
                    if (_emailDigestEnabled) ...[
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: AppTheme.cardBorder(context),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Digest Dispatch Frequency',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textPrimary(context),
                              ),
                            ),
                            const SizedBox(height: 6),
                            DropdownButton<String>(
                              isExpanded: true,
                              value: _digestFrequency,
                              dropdownColor: AppTheme.cardBg(context),
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppTheme.textPrimary(context),
                              ),
                              items: [
                                'Daily Morning Digest',
                                'Weekly Monday Summary',
                                'Bi-Weekly Compliance Digest',
                              ]
                                  .map(
                                    (f) => DropdownMenuItem(
                                      value: f,
                                      child: Text(f),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _digestFrequency = val);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: AppTheme.cardBorder(context),
                    ),
                    SwitchListTile.adaptive(
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Browser Desktop Notifications',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary(context),
                              ),
                            ),
                          ),
                          _buildPermissionBadge(context),
                        ],
                      ),
                      subtitle: Text(
                        'Show operating system desktop alerts when actions, requests, or updates arrive',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                      value: _browserPushAlerts,
                      onChanged: (val) async {
                        final bn = BrowserNotificationService.instance;
                        if (!bn.isSupported) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Browser notifications are not supported in this environment.'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        if (val) {
                          if (bn.permissionStatus.isDenied) {
                            BrowserNotificationDialogs.showBlockedInstructions(
                                context);
                            setState(() => _browserPushAlerts = false);
                            return;
                          }
                          if (bn.permissionStatus.isDefault) {
                            final res = await bn.requestPermission();
                            if (!context.mounted) return;
                            setState(() {
                              _browserPushAlerts = res.isGranted;
                            });
                            if (res.isGranted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Browser desktop notifications enabled!'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            } else if (res.isDenied) {
                              BrowserNotificationDialogs
                                  .showBlockedInstructions(context);
                            }
                            return;
                          }
                          bn.setNotificationEnabled(true);
                          setState(() => _browserPushAlerts = true);
                        } else {
                          bn.setNotificationEnabled(false);
                          setState(() => _browserPushAlerts = false);
                        }
                      },
                    ),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: AppTheme.cardBorder(context),
                    ),
                    SwitchListTile.adaptive(
                      title: Text(
                        'Notification Sound Alerts',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      subtitle: Text(
                        'Play a gentle chime when new actions, approvals, or escalations arrive',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                      value: SoundService.instance.isSoundEnabled,
                      onChanged: (val) {
                        setState(() {
                          SoundService.instance.setSoundEnabled(val);
                        });
                      },
                    ),
                    if (SoundService.instance.isSoundEnabled) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        child: Row(
                          children: [
                            Icon(Icons.volume_down_rounded,
                                size: 18,
                                color: AppTheme.textSecondary(context)),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 6),
                                ),
                                child: Slider(
                                  value: SoundService.instance.soundVolume,
                                  min: 0.1,
                                  max: 1.0,
                                  divisions: 9,
                                  label:
                                      '${(SoundService.instance.soundVolume * 100).round()}%',
                                  onChanged: (val) {
                                    setState(() {
                                      SoundService.instance.setSoundVolume(val);
                                    });
                                  },
                                ),
                              ),
                            ),
                            Icon(Icons.volume_up_rounded,
                                size: 18,
                                color: AppTheme.textSecondary(context)),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  SoundService.instance.playNotificationSound(),
                              icon: const Icon(Icons.play_arrow_rounded,
                                  size: 14),
                              label: const Text('Test Chime',
                                  style: TextStyle(fontSize: 11)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ==========================================
              // 3. DISPLAY & WORKSPACE PREFERENCES
              // ==========================================
              _buildSectionHeader(
                context,
                icon: Icons.table_view_outlined,
                title: 'Display & Table Density',
                subtitle: 'Configure workspace table compactness and auto-refresh settings.',
              ),
              const SizedBox(height: 14),

              Card(
                color: AppTheme.cardBg(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: AppTheme.cardBorder(context)),
                ),
                elevation: 0,
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      title: Text(
                        'Compact Table Rows',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      subtitle: Text(
                        'Show tighter rows in Action Register to fit more records per screen',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                      value: _compactTableDensity,
                      onChanged: (val) =>
                          setState(() => _compactTableDensity = val),
                    ),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: AppTheme.cardBorder(context),
                    ),
                    SwitchListTile.adaptive(
                      title: Text(
                        'Auto-Refresh Action Statuses',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      subtitle: Text(
                        'Automatically refresh action updates in real-time',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                      value: _autoRefreshData,
                      onChanged: (val) =>
                          setState(() => _autoRefreshData = val),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Save Settings Button
              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Settings and preferences saved successfully.',
                        ),
                        backgroundColor: Color(0xFF1565C0),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('Save Preferences'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppTheme.primaryAccent(context), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12.5,
            color: AppTheme.textSecondary(context),
          ),
        ),
      ],
    );
  }

  Widget _buildThemeTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required ThemeMode value,
    required ThemeMode groupValue,
    required ValueChanged<ThemeMode?> onChanged,
  }) {
    final isSelected = value == groupValue;

    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryAccent(context).withValues(alpha: 0.05)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w600,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? AppTheme.primaryAccent(context)
                      : AppTheme.inputBorder(context),
                  width: isSelected ? 6 : 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionBadge(BuildContext context) {
    final bn = BrowserNotificationService.instance;
    final status = bn.permissionStatus;

    final (color, label) = switch (status) {
      NotificationPermissionStatus.granted => (
          const Color(0xFF16A34A),
          'Granted'
        ),
      NotificationPermissionStatus.denied => (
          const Color(0xFFDC2626),
          'Blocked'
        ),
      NotificationPermissionStatus.defaultStatus => (
          const Color(0xFF64748B),
          'Not Requested'
        ),
      NotificationPermissionStatus.unsupported => (
          const Color(0xFF94A3B8),
          'Unsupported'
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
