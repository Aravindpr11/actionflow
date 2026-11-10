import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:action_flow/widgets/common/theme_toggle_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Screen allowing users to request password reset instructions via email.
///
/// Key behaviors:
/// - Trims and lowercases email before submission
/// - Shows real error messages from AuthService (including rate limits)
/// - Does NOT permanently disable the button after one request
/// - Allows re-submission after error
/// - Shows a clear "sent" confirmation only when the API call actually succeeds
/// - Does not silently swallow Supabase errors
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({
    super.key,
    this.initialEmail,
    @visibleForTesting this.resetPasswordOverride,
  });

  final String? initialEmail;

  /// Optional override for [AuthService.instance.resetPasswordForEmail].
  /// Used in widget tests to inject a fake without touching the singleton.
  final Future<AuthPasswordResetResult> Function(String email)?
  resetPasswordOverride;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  bool _isLoading = false;

  /// True only when the API call actually returned success.
  bool _isSubmitted = false;

  /// Set to a non-null value when the API call returned a real error.
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleSendResetLink() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim().toLowerCase();
    final AuthPasswordResetResult result;
    if (widget.resetPasswordOverride != null) {
      result = await widget.resetPasswordOverride!(email);
    } else {
      result = await AuthService.instance.resetPasswordForEmail(email);
    }

    if (!mounted) return;

    if (result.isSuccess) {
      setState(() {
        _isLoading = false;
        _isSubmitted = true;
        _errorMessage = null;
      });
    } else {
      // Show the real error so user knows what happened (rate limit, network, etc.)
      setState(() {
        _isLoading = false;
        _isSubmitted = false;
        _errorMessage =
            result.errorMessage ??
            'An unexpected error occurred. Please try again.';
      });
    }
  }

  /// Resets to the form so the user can request again.
  void _handleTryAgain() {
    setState(() {
      _isSubmitted = false;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
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
          onPressed: () => Navigator.of(context).maybePop(),
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
                  child: _isSubmitted
                      ? _buildConfirmationState()
                      : _buildRequestForm(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRequestForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.lock_reset_rounded,
                  color: Color(0xFF1565C0),
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Forgot Password?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Reset your account password',
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
          const SizedBox(height: 20),
          Divider(color: AppTheme.cardBorder(context)),
          const SizedBox(height: 16),
          Text(
            'Enter the email address associated with your ActionFlow account and we will send you password reset instructions.',
            style: TextStyle(
              fontSize: 13.5,
              color: AppTheme.textSecondary(context),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),

          // Error banner — shown when the API call fails (rate limit, network, etc.)
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFDC2626).withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Color(0xFFDC2626),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFFDC2626),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _errorMessage = null),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFFDC2626),
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _isLoading ? null : _handleSendResetLink(),
            style: TextStyle(
              color: AppTheme.textPrimary(context),
              fontSize: 14,
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Please enter your email address';
              }
              if (!val.contains('@') || !val.contains('.')) {
                return 'Please enter a valid email address';
              }
              return null;
            },
            decoration: InputDecoration(
              labelText: 'Email address *',
              labelStyle: TextStyle(
                color: AppTheme.textSecondary(context),
                fontSize: 13,
              ),
              prefixIcon: Icon(
                Icons.mail_outline_rounded,
                color: AppTheme.textSecondary(context),
                size: 20,
              ),
              filled: true,
              fillColor: AppTheme.inputFill(context),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppTheme.inputBorder(context)),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
                borderSide: BorderSide(color: Color(0xFF1565C0), width: 1.8),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              // Only disable during active loading — not permanently after one request
              onPressed: _isLoading ? null : _handleSendResetLink,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(
                _isLoading ? 'Sending Instructions...' : 'Send Reset Link',
                style: const TextStyle(
                  fontSize: 14,
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
          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back to Login'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF1565C0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmationState() {
    final email = _emailController.text.trim().toLowerCase();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF16A34A).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(
              Icons.mark_email_read_rounded,
              color: Color(0xFF16A34A),
              size: 48,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Password Reset Instructions Sent',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary(context),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'If an account exists for this email, password reset instructions have been sent to:',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            color: AppTheme.textSecondary(context),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.inputFill(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.cardBorder(context)),
          ),
          child: Text(
            email.isNotEmpty ? email : 'your registered email address',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary(context),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Check your inbox and follow the link to reset your password. '
          'If you do not see the email, please check your spam or junk folder.\n\n'
          'Note: Reset links expire after 1 hour. If your link has expired, '
          'please request a new one using the button below.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            color: AppTheme.textMuted(context),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 46,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.login_rounded, size: 18),
            label: const Text('Back to Login'),
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
        Center(
          child: TextButton(
            onPressed: _handleTryAgain,
            child: const Text("Didn't receive the email? Try again"),
          ),
        ),
      ],
    );
  }
}
