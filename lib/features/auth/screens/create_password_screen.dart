import 'package:action_flow/core/routing/auth_router.dart';
import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:action_flow/widgets/common/theme_toggle_button.dart';
import 'package:flutter/material.dart';

/// Mode indicating the context in which the password is being created
enum PasswordScreenMode {
  /// First-time account activation via invitation link
  invite,

  /// Password reset / recovery via email link
  recovery,
}

/// ActionFlow-branded screen for creating an account password
/// during invitation activation or password recovery.
class CreatePasswordScreen extends StatefulWidget {
  const CreatePasswordScreen({
    super.key,
    required this.mode,
    this.profileData,
    this.email,
  });

  final PasswordScreenMode mode;
  final AuthProfileData? profileData;
  final String? email;

  @override
  State<CreatePasswordScreen> createState() => _CreatePasswordScreenState();
}

class _CreatePasswordScreenState extends State<CreatePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _hasMinLength => _passwordController.text.length >= 8;
  bool get _hasLetters =>
      RegExp(r'[A-Za-z]').hasMatch(_passwordController.text);
  bool get _hasNumbers => RegExp(r'[0-9]').hasMatch(_passwordController.text);
  bool get _passwordsMatch =>
      _passwordController.text.isNotEmpty &&
      _passwordController.text == _confirmController.text;

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final password = _passwordController.text.trim();
    final result = await AuthService.instance.updatePassword(password);

    if (!mounted) return;

    if (result.isSuccess) {
      AuthService.clearPasswordRecoveryState();
      AuthService.clearCapturedInitialAuthFlow();

      // 1. If profileData was already supplied, route to role portal
      var profileData = widget.profileData;

      // 2. Otherwise, attempt to load profile from active session
      if (profileData == null) {
        final currentSession = AuthService.instance.currentSession;
        if (currentSession != null) {
          try {
            profileData = await AuthService.instance.fetchProfile(
              currentSession.user.id,
            );
          } catch (_) {
            // Fallback to login if fetch fails
          }
        }
      }

      if (!mounted) return;

      if (profileData != null &&
          profileData.status.toLowerCase() == 'active' &&
          profileData.isActive) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.mode == PasswordScreenMode.invite
                  ? 'Account activated successfully! Welcome to ActionFlow.'
                  : 'Password updated successfully!',
            ),
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
        AuthRouter.navigateToRolePortal(context, profileData);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Password created successfully. Please sign in with your new credentials.',
            ),
            backgroundColor: Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
        AuthRouter.navigateToLogin(context);
      }
    } else {
      setState(() {
        _isSubmitting = false;
        _errorMessage =
            result.errorMessage ?? 'Unable to set password. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final userEmail =
        widget.email ??
        widget.profileData?.userProfile.email ??
        AuthService.instance.currentUser?.email ??
        '';
    final orgName = widget.profileData?.organization?.name ?? '';

    final isInvite = widget.mode == PasswordScreenMode.invite;
    final title = isInvite ? 'Activate Account' : 'Create New Password';
    final subtitle = isInvite
        ? 'Create a secure password to complete your account activation'
        : 'Set a new secure password for your ActionFlow account';

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: AppTheme.textPrimary(context),
          ),
          onPressed: () => AuthRouter.navigateToLogin(context),
          tooltip: 'Return to Login',
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: ThemeToggleButton(size: 36),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                color: AppTheme.cardBg(context),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: AppTheme.cardBorder(context)),
                ),
                child: Padding(
                  padding: EdgeInsets.all(
                    MediaQuery.sizeOf(context).width < 400 ? 20 : 32,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header Badge & Title
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1565C0)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                isInvite
                                    ? Icons.lock_open_rounded
                                    : Icons.lock_reset_rounded,
                                color: const Color(0xFF1565C0),
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary(context),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: AppTheme.textSecondary(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Divider(color: AppTheme.cardBorder(context)),
                        const SizedBox(height: 14),

                        // Account Information Snippet
                        if (userEmail.isNotEmpty || orgName.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppTheme.darkInputFill
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppTheme.cardBorder(context),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.account_circle_outlined,
                                  size: 20,
                                  color: AppTheme.primaryAccent(context),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (userEmail.isNotEmpty)
                                        Text(
                                          userEmail,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textPrimary(
                                              context,
                                            ),
                                          ),
                                        ),
                                      if (orgName.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Organization: $orgName',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: AppTheme.textSecondary(
                                              context,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Error Banner
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.red.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: Colors.red,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // New Password Field
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          enabled: !_isSubmitting,
                          textInputAction: TextInputAction.next,
                          style: TextStyle(
                            color: AppTheme.textPrimary(context),
                            fontSize: 14,
                          ),
                          onChanged: (_) => setState(() {}),
                          validator: (val) {
                            final v = val?.trim() ?? '';
                            if (v.isEmpty) {
                              return 'Please enter a password';
                            }
                            if (v.length < 8) {
                              return 'Password must be at least 8 characters';
                            }
                            if (!RegExp(r'[A-Za-z]').hasMatch(v) ||
                                !RegExp(r'[0-9]').hasMatch(v)) {
                              return 'Password must contain both letters and numbers';
                            }
                            return null;
                          },
                          decoration: InputDecoration(
                            labelText: 'New Password *',
                            labelStyle: TextStyle(
                              color: AppTheme.textSecondary(context),
                              fontSize: 13,
                            ),
                            prefixIcon: Icon(
                              Icons.lock_outline_rounded,
                              color: AppTheme.textSecondary(context),
                              size: 20,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: AppTheme.textSecondary(context),
                                size: 20,
                              ),
                              onPressed: () {
                                setState(
                                  () => _obscurePassword = !_obscurePassword,
                                );
                              },
                              tooltip: _obscurePassword
                                  ? 'Show password'
                                  : 'Hide password',
                            ),
                            filled: true,
                            fillColor: AppTheme.inputFill(context),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: AppTheme.inputBorder(context),
                              ),
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(10),
                              ),
                              borderSide: BorderSide(
                                color: Color(0xFF1565C0),
                                width: 1.8,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Confirm Password Field
                        TextFormField(
                          controller: _confirmController,
                          obscureText: _obscureConfirm,
                          enabled: !_isSubmitting,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _handleSubmit(),
                          style: TextStyle(
                            color: AppTheme.textPrimary(context),
                            fontSize: 14,
                          ),
                          onChanged: (_) => setState(() {}),
                          validator: (val) {
                            final v = val?.trim() ?? '';
                            if (v.isEmpty) {
                              return 'Please confirm your password';
                            }
                            if (v != _passwordController.text.trim()) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                          decoration: InputDecoration(
                            labelText: 'Confirm New Password *',
                            labelStyle: TextStyle(
                              color: AppTheme.textSecondary(context),
                              fontSize: 13,
                            ),
                            prefixIcon: Icon(
                              Icons.lock_clock_outlined,
                              color: AppTheme.textSecondary(context),
                              size: 20,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirm
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: AppTheme.textSecondary(context),
                                size: 20,
                              ),
                              onPressed: () {
                                setState(
                                  () => _obscureConfirm = !_obscureConfirm,
                                );
                              },
                              tooltip: _obscureConfirm
                                  ? 'Show password'
                                  : 'Hide password',
                            ),
                            filled: true,
                            fillColor: AppTheme.inputFill(context),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: AppTheme.inputBorder(context),
                              ),
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(10),
                              ),
                              borderSide: BorderSide(
                                color: Color(0xFF1565C0),
                                width: 1.8,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Password Policy Checklist
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppTheme.darkInputFill
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppTheme.cardBorder(context),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Password Security Requirements:',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary(context),
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildPolicyRow(
                                'At least 8 characters',
                                _hasMinLength,
                              ),
                              const SizedBox(height: 4),
                              _buildPolicyRow(
                                'Contains letters and numbers',
                                _hasLetters && _hasNumbers,
                              ),
                              const SizedBox(height: 4),
                              _buildPolicyRow(
                                'Passwords match',
                                _passwordsMatch,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Submit Button
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _handleSubmit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1565C0),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    isInvite
                                        ? 'Activate Account & Continue'
                                        : 'Update Password & Continue',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPolicyRow(String label, bool isSatisfied) {
    return Row(
      children: [
        Icon(
          isSatisfied
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
          size: 14,
          color: isSatisfied ? const Color(0xFF16A34A) : Colors.grey,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSatisfied ? FontWeight.w600 : FontWeight.normal,
            color: isSatisfied
                ? const Color(0xFF16A34A)
                : AppTheme.textSecondary(context),
          ),
        ),
      ],
    );
  }
}
