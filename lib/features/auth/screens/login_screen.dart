import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/auth/data/mock_auth_store.dart';
import 'package:action_flow/features/auth/models/auth_models.dart';
import 'package:action_flow/features/auth/screens/account_status_screen.dart';
import 'package:action_flow/features/auth/screens/account_type_selection_screen.dart';
import 'package:action_flow/features/auth/screens/email_verification_screen.dart';
import 'package:action_flow/features/auth/screens/forgot_password_screen.dart';
import 'package:action_flow/features/dashboard/admin_dashboard/screens/admin_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/platform_admin_dashboard/screens/platform_admin_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:action_flow/widgets/common/action_flow_logo.dart';
import 'package:action_flow/widgets/common/theme_toggle_button.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.initialErrorMessage});

  final String? initialErrorMessage;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _rememberMe = true;
  bool _isLoading = false;
  String? _bannerError;

  @override
  void initState() {
    super.initState();
    _bannerError = widget.initialErrorMessage;
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    // 1. Real Supabase Auth login if Supabase is initialized
    if (SupabaseConfig.isInitialized) {
      try {
        final result = await AuthService.instance.signIn(
          email: username,
          password: password,
        );

        if (!mounted) return;

        if (result.isSuccess) {
          if (result.profileData != null) {
            final profileData = result.profileData!;
            final profile = profileData.userProfile;
            final status = profileData.status.toLowerCase();
            final isActive = profileData.isActive;
            final role = profileData.roleCode.toLowerCase();
            final isPrimaryAdmin = profileData.isPrimaryAdmin;

            if (status == 'active' && isActive) {
              if (profileData.isPlatformAdmin) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => const PlatformAdminDashboardScreen(),
                  ),
                );
                return;
              } else if (role == 'admin' || isPrimaryAdmin) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => AdminDashboardScreen(adminProfile: profile),
                  ),
                );
                return;
              } else if (role == 'manager') {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) =>
                        ManagerDashboardScreen(userProfile: profile),
                  ),
                );
                return;
              } else {
                // Staff
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => WorkerDashboardScreen(userProfile: profile),
                  ),
                );
                return;
              }
            } else if (status == 'pending_approval') {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Your account is awaiting administrator approval.',
                  ),
                  backgroundColor: Color(0xFF7C3AED),
                ),
              );
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AccountStatusScreen(
                    status: AuthAccountStatus.pendingApproval,
                    userEmail: profile.email,
                    userName: profile.name,
                    requestedType: role == 'manager'
                        ? RequestedAccountType.manager
                        : RequestedAccountType.staff,
                  ),
                ),
              );
              return;
            } else {
              // Inactive or suspended
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Your account is currently inactive. Please contact your administrator.',
                  ),
                  backgroundColor: Color(0xFFD97706),
                ),
              );
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AccountStatusScreen(
                    status: AuthAccountStatus.inactive,
                    userEmail: profile.email,
                    userName: profile.name,
                    requestedType: role == 'manager'
                        ? RequestedAccountType.manager
                        : RequestedAccountType.staff,
                  ),
                ),
              );
              return;
            }
          } else if (result.accountRequest != null) {
            final req = result.accountRequest!;
            final reqStatus = req.status.toLowerCase();
            final isManager = req.requestedRoleCode == 'manager';

            if (reqStatus == 'pending_email_verification') {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please verify your email before signing in.'),
                  backgroundColor: Color(0xFF0284C7),
                ),
              );
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EmailVerificationScreen(email: req.email),
                ),
              );
              return;
            } else if (reqStatus == 'rejected') {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Your account request was not approved. Please contact your administrator.',
                  ),
                  backgroundColor: Color(0xFFDC2626),
                ),
              );
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AccountStatusScreen(
                    status: AuthAccountStatus.rejected,
                    userEmail: req.email,
                    userName: req.fullName,
                    requestedType: isManager
                        ? RequestedAccountType.manager
                        : RequestedAccountType.staff,
                  ),
                ),
              );
              return;
            } else {
              // pending_admin_approval or other
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Your account is awaiting administrator approval.',
                  ),
                  backgroundColor: Color(0xFF7C3AED),
                ),
              );
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AccountStatusScreen(
                    status: AuthAccountStatus.pendingApproval,
                    userEmail: req.email,
                    userName: req.fullName,
                    requestedType: isManager
                        ? RequestedAccountType.manager
                        : RequestedAccountType.staff,
                  ),
                ),
              );
              return;
            }
          }
        }

        // Show exact error message from Supabase
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.errorMessage ?? 'Invalid username or password',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid username or password'),
            backgroundColor: Colors.redAccent,
          ),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
      return;
    }

    // 2. Fallback ONLY when Supabase is not initialized (e.g. headless unit & widget tests)
    if (username.toLowerCase() == 'admin' && password == '123456') {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
      );
      return;
    } else if (username.toLowerCase() == 'manager' && password == '123456') {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ManagerDashboardScreen()),
      );
      return;
    } else if ((username.toLowerCase() == 'worker' ||
            username.toLowerCase() == 'staff') &&
        password == '123456') {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const WorkerDashboardScreen()),
      );
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    if (!_checkMockAuthStore(username, password)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid username or password'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  bool _checkMockAuthStore(String username, String password) {
    final reg = MockAuthStore.instance.getRegistrationByEmail(username);
    if (reg != null && reg.password == password) {
      switch (reg.status) {
        case AuthAccountStatus.pendingVerification:
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  EmailVerificationScreen(email: reg.email, signupRequest: reg),
            ),
          );
          return true;
        case AuthAccountStatus.pendingApproval:
        case AuthAccountStatus.rejected:
        case AuthAccountStatus.inactive:
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AccountStatusScreen(
                status: reg.status,
                userEmail: reg.email,
                userName: reg.fullName,
                requestedType: reg.requestedType,
                registration: reg,
              ),
            ),
          );
          return true;
        case AuthAccountStatus.active:
          if (reg.requestedType == RequestedAccountType.manager) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) =>
                    ManagerDashboardScreen(userProfile: reg.toUserProfile()),
              ),
            );
          } else {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) =>
                    WorkerDashboardScreen(userProfile: reg.toUserProfile()),
              ),
            );
          }
          return true;
      }
    }
    return false;
  }

  void _handleForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ForgotPasswordScreen(initialEmail: _usernameController.text.trim()),
      ),
    );
  }

  void _handleCreateAccount() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AccountTypeSelectionScreen()),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned(
              top: 16,
              right: 16,
              child: ThemeToggleButton(size: 40),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 800;

                return Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: constraints.maxWidth < 450 ? 12 : 24,
                      vertical: 16,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: isWide
                          ? Row(
                              children: [
                                Expanded(
                                  child: _BrandPanel(
                                    primaryColor: primaryColor,
                                  ),
                                ),
                                const SizedBox(width: 48),
                                SizedBox(
                                  width: 440,
                                  child: _LoginCard(
                                    formKey: _formKey,
                                    usernameController: _usernameController,
                                    passwordController: _passwordController,
                                    isPasswordVisible: _isPasswordVisible,
                                    rememberMe: _rememberMe,
                                    isLoading: _isLoading,
                                    bannerError: _bannerError,
                                    onDismissBanner: () =>
                                        setState(() => _bannerError = null),
                                    onPasswordVisibilityChanged: () {
                                      setState(() {
                                        _isPasswordVisible =
                                            !_isPasswordVisible;
                                      });
                                    },
                                    onRememberMeChanged: (value) {
                                      setState(() {
                                        _rememberMe = value ?? false;
                                      });
                                    },
                                    onLoginPressed: _handleLogin,
                                    onForgotPasswordPressed:
                                        _handleForgotPassword,
                                    onCreateAccountPressed:
                                        _handleCreateAccount,
                                  ),
                                ),
                              ],
                            )
                          : _LoginCard(
                              formKey: _formKey,
                              usernameController: _usernameController,
                              passwordController: _passwordController,
                              isPasswordVisible: _isPasswordVisible,
                              rememberMe: _rememberMe,
                              isLoading: _isLoading,
                              bannerError: _bannerError,
                              onDismissBanner: () =>
                                  setState(() => _bannerError = null),
                              onPasswordVisibilityChanged: () {
                                setState(() {
                                  _isPasswordVisible = !_isPasswordVisible;
                                });
                              },
                              onRememberMeChanged: (value) {
                                setState(() {
                                  _rememberMe = value ?? false;
                                });
                              },
                              onLoginPressed: _handleLogin,
                              onForgotPasswordPressed: _handleForgotPassword,
                              onCreateAccountPressed: _handleCreateAccount,
                              showBrandHeader: true,
                            ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({required this.primaryColor});

  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [primaryColor, primaryColor.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ActionFlowLogo.white(size: 76, iconSize: 42, borderRadius: 20),
              const SizedBox(height: 24),
              const Text(
                'ActionFlow',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Track workplace actions, assignments, progress, pending work, completion and manager review.',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.6,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.formKey,
    required this.usernameController,
    required this.passwordController,
    required this.isPasswordVisible,
    required this.rememberMe,
    required this.isLoading,
    required this.onPasswordVisibilityChanged,
    required this.onRememberMeChanged,
    required this.onLoginPressed,
    required this.onForgotPasswordPressed,
    required this.onCreateAccountPressed,
    this.bannerError,
    this.onDismissBanner,
    this.showBrandHeader = false,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool isPasswordVisible;
  final bool rememberMe;
  final bool isLoading;
  final VoidCallback onPasswordVisibilityChanged;
  final ValueChanged<bool?> onRememberMeChanged;
  final VoidCallback onLoginPressed;
  final VoidCallback onForgotPasswordPressed;
  final VoidCallback onCreateAccountPressed;
  final String? bannerError;
  final VoidCallback? onDismissBanner;
  final bool showBrandHeader;

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = MediaQuery.sizeOf(context).width < 400;

    return Card(
      color: AppTheme.cardBg(context),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppTheme.cardBorder(context)),
      ),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 18 : 28),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showBrandHeader) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: ActionFlowBrand(
                      logoSize: 34,
                      fontSize: 18,
                      subtitle: 'Workplace Action Tracker',
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Divider(color: AppTheme.cardBorder(context)),
                const SizedBox(height: 16),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Welcome back',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Sign in to continue',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: AppTheme.textSecondary(context)),
                ),
              ),
              const SizedBox(height: 24),
              if (bannerError != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Color(0xFFDC2626),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          bannerError!,
                          style: const TextStyle(
                            color: Color(0xFFDC2626),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                      if (onDismissBanner != null)
                        InkWell(
                          onTap: onDismissBanner,
                          child: const Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: usernameController,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Please enter your username or email'
                    : null,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                style: TextStyle(color: AppTheme.textPrimary(context)),
                decoration: InputDecoration(
                  labelText: 'Username or email',
                  labelStyle: TextStyle(color: AppTheme.textSecondary(context)),
                  prefixIcon: Icon(
                    Icons.person_outline_rounded,
                    color: AppTheme.textSecondary(context),
                  ),
                  filled: true,
                  fillColor: AppTheme.inputFill(context),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: AppTheme.inputBorder(context),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: AppTheme.primaryAccent(context),
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: passwordController,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Please enter your password'
                    : null,
                obscureText: !isPasswordVisible,
                textInputAction: TextInputAction.done,
                style: TextStyle(color: AppTheme.textPrimary(context)),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: TextStyle(color: AppTheme.textSecondary(context)),
                  prefixIcon: Icon(
                    Icons.lock_outline_rounded,
                    color: AppTheme.textSecondary(context),
                  ),
                  suffixIcon: IconButton(
                    onPressed: onPasswordVisibilityChanged,
                    icon: Icon(
                      isPasswordVisible
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                  filled: true,
                  fillColor: AppTheme.inputFill(context),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: AppTheme.inputBorder(context),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: AppTheme.primaryAccent(context),
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: rememberMe,
                        onChanged: onRememberMeChanged,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      Text(
                        'Remember me',
                        style: TextStyle(color: AppTheme.textPrimary(context)),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: onForgotPasswordPressed,
                    child: const Text('Forgot Password?'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: isLoading ? null : onLoginPressed,
                  icon: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login_rounded),
                  label: Text(isLoading ? 'Signing In...' : 'Sign In'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Divider(color: AppTheme.cardBorder(context)),
              const SizedBox(height: 12),
              Center(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Don\'t have an account? ',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                    TextButton(
                      onPressed: onCreateAccountPressed,
                      child: const Text(
                        'Create Account',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
