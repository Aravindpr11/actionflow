import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/profile/widgets/change_password_dialog.dart';
import 'package:action_flow/features/profile/widgets/edit_profile_dialog.dart';
import 'package:flutter/material.dart';

/// Reusable enterprise Profile card matching the approved ActionFlow visual language.
class ProfileViewCard extends StatelessWidget {
  const ProfileViewCard({
    super.key,
    required this.profile,
    required this.onProfileUpdated,
    this.title = 'User Profile',
    this.showPerformanceStats = false,
    this.performanceStats,
    this.allowDesignationEdit = true,
  });

  final UserProfile profile;
  final ValueChanged<UserProfile> onProfileUpdated;
  final String title;
  final bool showPerformanceStats;
  final Widget? performanceStats;
  final bool allowDesignationEdit;

  void _openEditDialog(BuildContext context) async {
    final updated = await EditProfileDialog.show(
      context,
      profile: profile,
      allowDesignationEdit: allowDesignationEdit,
    );
    if (updated != null) {
      onProfileUpdated(updated);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile updated successfully for ${updated.name}'),
            backgroundColor: const Color(0xFF1565C0),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _openChangePasswordDialog(BuildContext context) async {
    final changed = await ChangePasswordDialog.show(context);
    if (changed == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated successfully.'),
          backgroundColor: Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) ...[
          Row(
            children: [
              Icon(
                Icons.person_rounded,
                color: AppTheme.primaryAccent(context),
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        // Main Profile Header Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppTheme.cardBg(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.cardBorder(context)),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.2)
                    : const Color(0x060F172A),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Identity Row
              LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 500;

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Avatar
                      Container(
                        width: isCompact ? 56 : 68,
                        height: isCompact ? 56 : 68,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                            width: 2,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          profile.initials,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isCompact ? 20 : 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Name & Designation
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    profile.name,
                                    style: TextStyle(
                                      fontSize: isCompact ? 18 : 22,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary(context),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF16A34A)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    profile.accountStatus,
                                    style: const TextStyle(
                                      color: Color(0xFF16A34A),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${profile.designation} • ${profile.department}',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textSecondary(context),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Facility: ${profile.site}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textMuted(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isCompact) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _openChangePasswordDialog(context),
                          icon: const Icon(Icons.lock_reset_rounded, size: 16),
                          label: const Text('Change Password'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.textPrimary(context),
                            side: BorderSide(
                              color: AppTheme.inputBorder(context),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => _openEditDialog(context),
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('Edit Profile'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),

              // Mobile edit button fallback
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 500) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _openChangePasswordDialog(context),
                            icon: const Icon(
                              Icons.lock_reset_rounded,
                              size: 16,
                            ),
                            label: const Text('Change Password'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.textPrimary(context),
                              side: BorderSide(
                                color: AppTheme.inputBorder(context),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _openEditDialog(context),
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const Text('Edit Profile'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1565C0),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),
              Divider(color: AppTheme.dividerColor(context), height: 1),
              const SizedBox(height: 18),

              // Identity & Contact Details Grid
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 600;

                  final items = [
                    ('Employee ID', profile.id, Icons.badge_outlined),
                    ('Email Address', profile.email, Icons.email_outlined),
                    ('Phone Number', profile.phone, Icons.phone_outlined),
                    ('Assigned Role', profile.role, Icons.security_outlined),
                    ('Department', profile.department, Icons.business_outlined),
                    (
                      'Assigned Site / Facility',
                      profile.site,
                      Icons.location_on_outlined,
                    ),
                    if (profile.team.isNotEmpty)
                      ('Team / Squad', profile.team, Icons.groups_outlined),
                    if (profile.supervisor.isNotEmpty)
                      (
                        'Direct Supervisor',
                        profile.supervisor,
                        Icons.supervisor_account_outlined,
                      ),
                    if (profile.certifications.isNotEmpty)
                      (
                        'Safety Certification',
                        profile.certifications,
                        Icons.verified_outlined,
                      ),
                  ];

                  if (isWide) {
                    return Wrap(
                      spacing: 24,
                      runSpacing: 14,
                      children: items.map((item) {
                        return SizedBox(
                          width: (constraints.maxWidth - 32) / 2,
                          child: _buildDetailItem(
                            context,
                            label: item.$1,
                            value: item.$2,
                            icon: item.$3,
                          ),
                        );
                      }).toList(),
                    );
                  }

                  return Column(
                    children: items.map((item) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildDetailItem(
                          context,
                          label: item.$1,
                          value: item.$2,
                          icon: item.$3,
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),

        // Permissions & Scope Section
        if (profile.permissions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.cardBg(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.cardBorder(context)),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.2)
                      : const Color(0x060F172A),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.verified_user_rounded,
                      color: AppTheme.primaryAccent(context),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Access Permissions & Operational Scope',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: profile.permissions.map((perm) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.containerBg(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.cardBorder(context)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 15,
                            color: Color(0xFF16A34A),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            perm,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],

        // Performance Statistics if provided
        if (showPerformanceStats && performanceStats != null) ...[
          const SizedBox(height: 16),
          performanceStats!,
        ],
      ],
    );
  }

  Widget _buildDetailItem(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: AppTheme.primaryAccent(context).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: AppTheme.primaryAccent(context)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
