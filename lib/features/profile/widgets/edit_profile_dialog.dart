import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/profile/widgets/change_password_dialog.dart';
import 'package:flutter/material.dart';

/// Reusable modal dialog for editing permitted personal profile details
/// while strictly displaying organizational & governance fields as read-only.
class EditProfileDialog extends StatefulWidget {
  const EditProfileDialog({
    super.key,
    required this.profile,
    required this.onSave,
    this.allowDesignationEdit = true,
  });

  final UserProfile profile;
  final ValueChanged<UserProfile> onSave;
  final bool allowDesignationEdit;

  /// Helper static method to show the dialog
  static Future<UserProfile?> show(
    BuildContext context, {
    required UserProfile profile,
    bool allowDesignationEdit = true,
  }) {
    return showDialog<UserProfile>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => EditProfileDialog(
        profile: profile,
        allowDesignationEdit: allowDesignationEdit,
        onSave: (updated) => Navigator.of(ctx).pop(updated),
      ),
    );
  }

  @override
  State<EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<EditProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _designationController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _phoneController = TextEditingController(text: widget.profile.phone);
    _designationController = TextEditingController(
      text: widget.profile.designation,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _designationController.dispose();
    super.dispose();
  }

  void _handleSave() {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final updated = widget.profile.copyWith(
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      designation: widget.allowDesignationEdit
          ? _designationController.text.trim()
          : widget.profile.designation,
    );

    widget.onSave(updated);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    return Dialog(
      backgroundColor: AppTheme.cardBg(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppTheme.cardBorder(context)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Modal Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppTheme.cardBorder(context)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAccent(context)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.manage_accounts_rounded,
                      color: AppTheme.primaryAccent(context),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Profile Information',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Update your personal contact details',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: AppTheme.textSecondary(context),
                      size: 20,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Scrollable Form Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar & Identity Pill
                      Center(
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            CircleAvatar(
                              radius: 36,
                              backgroundColor: const Color(0xFF1565C0),
                              child: Text(
                                widget.profile.initials,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: AppTheme.cardBg(context),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppTheme.cardBorder(context),
                                  width: 2,
                                ),
                              ),
                              child: Icon(
                                Icons.camera_alt_rounded,
                                size: 14,
                                color: AppTheme.primaryAccent(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          widget.profile.email,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Section: Editable Personal Fields
                      Row(
                        children: [
                          Icon(
                            Icons.edit_note_rounded,
                            size: 18,
                            color: AppTheme.primaryAccent(context),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Personal Information (Editable)',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Full Name Field
                      _buildFormField(
                        context,
                        label: 'Full Name *',
                        controller: _nameController,
                        hintText: 'Enter your full legal name',
                        icon: Icons.person_outline_rounded,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Full name cannot be blank';
                          }
                          if (value.trim().length < 2) {
                            return 'Name must be at least 2 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Phone Number Field
                      _buildFormField(
                        context,
                        label: 'Phone Number *',
                        controller: _phoneController,
                        hintText: '+1 (555) 000-0000',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Phone number is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Designation Field (if allowed)
                      if (widget.allowDesignationEdit) ...[
                        _buildFormField(
                          context,
                          label: 'Designation / Job Title',
                          controller: _designationController,
                          hintText: 'Enter current job title',
                          icon: Icons.badge_outlined,
                        ),
                        const SizedBox(height: 20),
                      ],

                      Divider(
                        color: AppTheme.dividerColor(context),
                        height: 24,
                      ),

                      // Section: Protected Read-Only Governance Fields
                      Row(
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 16,
                            color: AppTheme.textMuted(context),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Organizational Governance (Read-Only)',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textSecondary(context),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF334155)
                                  : const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'PROTECTED',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textSecondary(context),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Read-Only Attributes Grid
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.containerBg(context),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppTheme.cardBorder(context),
                          ),
                        ),
                        child: Column(
                          children: [
                            _buildReadOnlyRow(
                              context,
                              label: 'Employee ID',
                              value: widget.profile.id,
                              icon: Icons.fingerprint_rounded,
                            ),
                            const SizedBox(height: 10),
                            _buildReadOnlyRow(
                              context,
                              label: 'Assigned Role',
                              value: widget.profile.role,
                              icon: Icons.shield_outlined,
                            ),
                            if (!widget.allowDesignationEdit) ...[
                              const SizedBox(height: 10),
                              _buildReadOnlyRow(
                                context,
                                label: 'Designation / Role Title',
                                value: widget.profile.designation,
                                icon: Icons.badge_outlined,
                              ),
                            ],
                            const SizedBox(height: 10),
                            _buildReadOnlyRow(
                              context,
                              label: 'Department',
                              value: widget.profile.department,
                              icon: Icons.business_outlined,
                            ),
                            const SizedBox(height: 10),
                            _buildReadOnlyRow(
                              context,
                              label: 'Assigned Facility / Site',
                              value: widget.profile.site,
                              icon: Icons.location_on_outlined,
                            ),
                            if (widget.profile.supervisor.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              _buildReadOnlyRow(
                                context,
                                label: 'Direct Supervisor',
                                value: widget.profile.supervisor,
                                icon: Icons.supervisor_account_outlined,
                              ),
                            ],
                            const SizedBox(height: 10),
                            _buildReadOnlyRow(
                              context,
                              label: 'Account Status',
                              value: widget.profile.accountStatus,
                              icon: Icons.verified_user_outlined,
                              isStatus: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Change Account Password Button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final changed = await ChangePasswordDialog.show(
                              context,
                            );
                            if (changed == true && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Password updated successfully.',
                                  ),
                                  backgroundColor: Color(0xFF16A34A),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.lock_reset_rounded, size: 16),
                          label: const Text('Change Account Password'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.textPrimary(context),
                            side: BorderSide(
                              color: AppTheme.inputBorder(context),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Read-only notice
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 15,
                            color: AppTheme.textMuted(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Role, department, and site assignments are governed by the enterprise ActionFlow administrator.',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textMuted(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Modal Footer Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppTheme.cardBorder(context)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textPrimary(context),
                      side: BorderSide(color: AppTheme.inputBorder(context)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 11,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 11,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_rounded, size: 17),
                              SizedBox(width: 6),
                              Text(
                                'Save Changes',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormField(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary(context),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          style: TextStyle(
            fontSize: 13.5,
            color: AppTheme.textPrimary(context),
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(
              fontSize: 13,
              color: AppTheme.textMuted(context),
            ),
            prefixIcon: Icon(
              icon,
              size: 18,
              color: AppTheme.textSecondary(context),
            ),
            filled: true,
            fillColor: AppTheme.inputFill(context),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppTheme.inputBorder(context)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppTheme.inputBorder(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: Color(0xFF1565C0),
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFDC2626)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyRow(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    bool isStatus = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: AppTheme.textMuted(context)),
        const SizedBox(width: 8),
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary(context),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: isStatus
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF16A34A),
                      ),
                    ),
                  ),
                )
              : Text(
                  value,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
        ),
      ],
    );
  }
}
