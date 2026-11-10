import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/core/routing/auth_router.dart';
import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/auth/data/mock_auth_store.dart';
import 'package:action_flow/features/auth/models/auth_models.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:action_flow/widgets/common/theme_toggle_button.dart';
import 'package:flutter/material.dart';

/// Reusable screen displaying account verification and organizational approval status
class AccountStatusScreen extends StatefulWidget {
  const AccountStatusScreen({
    super.key,
    required this.status,
    this.userEmail = '',
    this.userName = '',
    this.requestedType = RequestedAccountType.staff,
    this.registration,
  });

  final AuthAccountStatus status;
  final String userEmail;
  final String userName;
  final RequestedAccountType requestedType;
  final SignupRequest? registration;

  @override
  State<AccountStatusScreen> createState() => _AccountStatusScreenState();
}

class _AccountStatusScreenState extends State<AccountStatusScreen> {
  late AuthAccountStatus _currentStatus;
  SignupRequest? _registration;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.status;
    _registration =
        widget.registration ??
        (widget.userEmail.isNotEmpty
            ? MockAuthStore.instance.getRegistrationByEmail(widget.userEmail)
            : null);
    if (_registration != null) {
      _currentStatus = _registration!.status;
    }
  }

  Future<void> _handleRefresh() async {
    setState(() {
      _isRefreshing = true;
    });

    if (SupabaseConfig.isInitialized && widget.userEmail.isNotEmpty) {
      try {
        final client = SupabaseConfig.clientOrNull;
        if (client != null) {
          final emailClean = widget.userEmail.trim();
          final currentAuthUser = client.auth.currentUser;

          // 1. Authoritative check: Query public.account_requests first
          dynamic reqRow;
          if (currentAuthUser != null) {
            reqRow = await client
                .from('account_requests')
                .select('id, status, is_email_verified, rejection_reason')
                .eq('auth_user_id', currentAuthUser.id)
                .maybeSingle();
          }

          if (reqRow == null && emailClean.isNotEmpty) {
            reqRow = await client
                .from('account_requests')
                .select('id, status, is_email_verified, rejection_reason')
                .eq('email', emailClean)
                .maybeSingle();
          }

          if (reqRow is Map) {
            final st =
                (reqRow['status'] as String?)?.toLowerCase().trim() ?? '';
            final isVerified = reqRow['is_email_verified'] == true;
            AuthAccountStatus resolvedStatus;
            if (st == 'approved') {
              resolvedStatus = AuthAccountStatus.active;
            } else if (st == 'rejected') {
              resolvedStatus = AuthAccountStatus.rejected;
            } else if (isVerified || st == 'pending_admin_approval') {
              resolvedStatus = AuthAccountStatus.pendingApproval;
            } else {
              resolvedStatus = AuthAccountStatus.pendingVerification;
            }

            if (!mounted) return;
            setState(() {
              _currentStatus = resolvedStatus;
              _isRefreshing = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  resolvedStatus == AuthAccountStatus.active
                      ? 'Account approved! You can now proceed to your dashboard.'
                      : 'Account status: ${_currentStatus.label}',
                ),
                backgroundColor: resolvedStatus == AuthAccountStatus.active
                    ? const Color(0xFF16A34A)
                    : null,
                duration: const Duration(seconds: 3),
              ),
            );
            return;
          }

          // 2. Direct invited or admin accounts with no account_request record
          final dynamic profileRow = await client
              .from('profiles')
              .select('id, status, is_active')
              .eq('email', emailClean)
              .maybeSingle();

          if (profileRow is Map) {
            final isActive =
                profileRow['is_active'] == true &&
                profileRow['status'] == 'active';
            if (isActive) {
              if (!mounted) return;
              setState(() {
                _currentStatus = AuthAccountStatus.active;
                _isRefreshing = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Account approved! You can now proceed to your dashboard.',
                  ),
                  backgroundColor: Color(0xFF16A34A),
                  duration: Duration(seconds: 3),
                ),
              );
              return;
            }
          }
        }
      } catch (e) {
        debugPrint('Error refreshing account status from Supabase: $e');
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    if (widget.userEmail.isNotEmpty) {
      final updated = MockAuthStore.instance.getRegistrationByEmail(
        widget.userEmail,
      );
      if (updated != null) {
        setState(() {
          _registration = updated;
          _currentStatus = updated.status;
          _isRefreshing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Account status updated: ${_currentStatus.label}'),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
    }

    setState(() {
      _isRefreshing = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Account status refreshed.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Color _getStatusColor(AuthAccountStatus status) {
    switch (status) {
      case AuthAccountStatus.pendingVerification:
        return const Color(0xFF0284C7);
      case AuthAccountStatus.pendingApproval:
        return const Color(0xFF7C3AED);
      case AuthAccountStatus.active:
        return const Color(0xFF16A34A);
      case AuthAccountStatus.inactive:
        return const Color(0xFFD97706);
      case AuthAccountStatus.rejected:
        return const Color(0xFFDC2626);
    }
  }

  IconData _getStatusIcon(AuthAccountStatus status) {
    switch (status) {
      case AuthAccountStatus.pendingVerification:
        return Icons.mark_email_unread_rounded;
      case AuthAccountStatus.pendingApproval:
        return Icons.verified_user_outlined;
      case AuthAccountStatus.active:
        return Icons.check_circle_rounded;
      case AuthAccountStatus.inactive:
        return Icons.pause_circle_outline_rounded;
      case AuthAccountStatus.rejected:
        return Icons.cancel_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(_currentStatus);
    final statusIcon = _getStatusIcon(_currentStatus);
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
          onPressed: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          tooltip: 'Back to Login',
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
              constraints: const BoxConstraints(maxWidth: 540),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Status Icon Badge
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(
                              alpha: isDark ? 0.2 : 0.1,
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: statusColor.withValues(
                                alpha: isDark ? 0.4 : 0.25,
                              ),
                              width: 1.5,
                            ),
                          ),
                          child: Icon(statusIcon, color: statusColor, size: 48),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Status Title & Role Badge
                      Text(
                        _currentStatus.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1565C0)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFF1565C0)
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            widget.requestedType.label,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1565C0),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Description
                      Text(
                        _currentStatus.description,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: AppTheme.textSecondary(context),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Account Details Snapshot
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.inputFill(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.cardBorder(context),
                          ),
                        ),
                        child: Column(
                          children: [
                            if ((_registration?.fullName ?? widget.userName)
                                .isNotEmpty)
                              _buildMetaRow(
                                'Applicant Name',
                                _registration?.fullName ?? widget.userName,
                              ),
                            if ((_registration?.email ?? widget.userEmail)
                                .isNotEmpty) ...[
                              if ((_registration?.fullName ?? widget.userName)
                                  .isNotEmpty)
                                const SizedBox(height: 8),
                              _buildMetaRow(
                                'Account Email',
                                _registration?.email ?? widget.userEmail,
                              ),
                            ],
                            const SizedBox(height: 8),
                            _buildMetaRow(
                              'Account Type',
                              (_registration?.requestedType ??
                                          widget.requestedType) ==
                                      RequestedAccountType.manager
                                  ? 'Manager (Approval Required)'
                                  : 'Staff (Approval Required)',
                            ),
                            const SizedBox(height: 8),
                            _buildMetaRow('Status', _currentStatus.name),
                          ],
                        ),
                      ),
                      if (_currentStatus == AuthAccountStatus.rejected) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    color: Color(0xFFDC2626),
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Application Decision Details',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF991B1B),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Reason: ${_registration?.rejectionReason ?? "Registration was not approved by administration."}',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF7F1D1D),
                                  height: 1.4,
                                ),
                              ),
                              if (_registration?.rejectedBy != null ||
                                  _registration?.rejectedAt != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Reviewed by ${_registration?.rejectedBy ?? "Administrator"}'
                                  '${_registration?.rejectedAt != null ? " on ${_registration!.rejectedAt!.year}-${_registration!.rejectedAt!.month.toString().padLeft(2, '0')}-${_registration!.rejectedAt!.day.toString().padLeft(2, '0')}" : ""}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                    color: Color(0xFF991B1B),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),

                      // Lifecycle Stepper Visual
                      _buildLifecycleStepper(),
                      const SizedBox(height: 24),

                      // Action Buttons
                      if (_currentStatus == AuthAccountStatus.active)
                        SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              if (SupabaseConfig.isInitialized) {
                                final client = SupabaseConfig.clientOrNull;
                                final currentAuthUser =
                                    client?.auth.currentUser;
                                if (currentAuthUser != null) {
                                  final res = await AuthService.instance
                                      .fetchProfileResult(currentAuthUser.id);
                                  if (!mounted) return;
                                  if (res is ProfileFetchSuccess) {
                                    if (!context.mounted) return;
                                    AuthRouter.navigateToRolePortal(
                                      context,
                                      res.profileData,
                                    );
                                    return;
                                  }
                                }
                                if (!context.mounted) return;
                                AuthRouter.navigateToLogin(context);
                                return;
                              }

                              final role =
                                  _registration?.requestedType ??
                                  widget.requestedType;
                              final profile = _registration?.toUserProfile();
                              if (role == RequestedAccountType.manager) {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (_) => ManagerDashboardScreen(
                                      userProfile: profile,
                                    ),
                                  ),
                                );
                              } else {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (_) => WorkerDashboardScreen(
                                      userProfile: profile,
                                    ),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                            ),
                            label: const Text(
                              'Proceed to Dashboard',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF16A34A),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                          ),
                        )
                      else ...[
                        SizedBox(
                          height: 46,
                          child: OutlinedButton.icon(
                            onPressed: _isRefreshing ? null : _handleRefresh,
                            icon: _isRefreshing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh_rounded, size: 17),
                            label: Text(
                              _isRefreshing
                                  ? 'Checking Status...'
                                  : 'Refresh Status',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF1565C0),
                              side: const BorderSide(color: Color(0xFF1565C0)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.of(context)
                                .popUntil((route) => route.isFirst);
                          },
                          icon: const Icon(Icons.arrow_back_rounded, size: 16),
                          label: const Text('Back to Login'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.textSecondary(context),
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
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context)),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary(context),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildLifecycleStepper() {
    int currentStep = 1; // 1: Registered, 2: Verified, 3: Approved, 4: Active
    if (_currentStatus == AuthAccountStatus.pendingApproval) {
      currentStep = 2;
    } else if (_currentStatus == AuthAccountStatus.active) {
      currentStep = 4;
    } else if (_currentStatus == AuthAccountStatus.rejected) {
      currentStep = 2;
    }

    const steps = [
      'Registration',
      'Email Verified',
      'Admin Approval',
      'Portal Access',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Onboarding Progress',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppTheme.textMuted(context),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: List.generate(steps.length, (index) {
            final isDone = index < currentStep;
            final isCurrent = index == currentStep - 1;
            final isRejected =
                _currentStatus == AuthAccountStatus.rejected && index == 2;

            final color = isRejected
                ? const Color(0xFFDC2626)
                : (isDone
                      ? const Color(0xFF16A34A)
                      : (isCurrent
                            ? const Color(0xFF1565C0)
                            : const Color(0xFF94A3B8)));

            return Expanded(
              child: Column(
                children: [
                  Row(
                    children: [
                      if (index > 0)
                        Expanded(
                          child: Container(
                            height: 2,
                            color: index <= currentStep - 1
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFCBD5E1),
                          ),
                        ),
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: isRejected
                              ? const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 13,
                                )
                              : (isDone
                                    ? const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 13,
                                      )
                                    : Text(
                                        '${index + 1}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )),
                        ),
                      ),
                      if (index < steps.length - 1)
                        Expanded(
                          child: Container(
                            height: 2,
                            color: index < currentStep - 1
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFCBD5E1),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    steps[index],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                      color: isRejected
                          ? const Color(0xFFDC2626)
                          : (isCurrent
                                ? AppTheme.textPrimary(context)
                                : AppTheme.textMuted(context)),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }
}
