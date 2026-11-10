import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/auth/models/auth_models.dart';
import 'package:action_flow/features/auth/screens/account_status_screen.dart';
import 'package:action_flow/features/auth/screens/email_verification_screen.dart';
import 'package:action_flow/widgets/common/theme_toggle_button.dart';
import 'package:flutter/material.dart';

/// Screen displayed immediately upon successful submission of user registration
class SignupSuccessScreen extends StatelessWidget {
  const SignupSuccessScreen({super.key, required this.request});

  final SignupRequest request;

  @override
  Widget build(BuildContext context) {
    final isManager = request.requestedType == RequestedAccountType.manager;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
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
                      // Success Emblem
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16A34A).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.check_circle_outline_rounded,
                            color: Color(0xFF16A34A),
                            size: 52,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Title
                      Text(
                        'Account Registration Submitted',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Role subtitle & description
                      Text(
                        isManager
                            ? 'Your Manager access request has been successfully recorded and is awaiting email verification and Organization Administrator approval.'
                            : 'Your Staff account registration has been successfully recorded and is awaiting email verification and Administrator approval.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: AppTheme.textSecondary(context),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Registration Summary Card
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
                            _summaryRow(context, 'Full Name', request.fullName),
                            const SizedBox(height: 8),
                            _summaryRow(context, 'Email', request.email),
                            const SizedBox(height: 8),
                            _summaryRow(
                              context,
                              'Requested Role',
                              request.requestedType.label,
                            ),
                            const SizedBox(height: 8),
                            _summaryRow(
                              context,
                              'Department',
                              request.department,
                            ),
                            const SizedBox(height: 8),
                            _summaryRow(context, 'Site', request.site),
                            if (request.designation.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _summaryRow(
                                context,
                                'Designation',
                                request.designation,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Workflow Next Steps Guidance
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1565C0)
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF1565C0)
                                .withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              color: Color(0xFF1565C0),
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isManager
                                        ? 'Next Steps for Manager Access:'
                                        : 'Next Steps for Account Activation:',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1565C0),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isManager
                                        ? '1. Verify your email address.\n2. An Organization Administrator will review your department assignments and approve your Manager portal access.'
                                        : '1. Verify your email address using the link sent to your inbox.\n2. An Administrator will review and activate your Staff account.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary(context),
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Actions
                      SizedBox(
                        height: 46,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => EmailVerificationScreen(
                                  email: request.email,
                                  signupRequest: request,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.mark_email_read_rounded,
                            size: 18,
                          ),
                          label: const Text(
                            'Verify Email Address',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 46,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => AccountStatusScreen(
                                  status: request.status,
                                  userEmail: request.email,
                                  userName: request.fullName,
                                  requestedType: request.requestedType,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.track_changes_rounded,
                            size: 18,
                          ),
                          label: const Text(
                            'Check Account Status',
                            style: TextStyle(
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
                      const SizedBox(height: 16),
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

  Widget _summaryRow(BuildContext context, String label, String value) {
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
}
