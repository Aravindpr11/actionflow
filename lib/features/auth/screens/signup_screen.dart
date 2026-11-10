import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/auth/data/mock_auth_store.dart';
import 'package:action_flow/features/auth/models/auth_models.dart';
import 'package:action_flow/features/auth/screens/signup_success_screen.dart';
import 'package:action_flow/widgets/common/action_flow_logo.dart';
import 'package:action_flow/widgets/common/theme_toggle_button.dart';
import 'package:flutter/material.dart';

/// Screen allowing new users to register for ActionFlow (Staff or Manager Access Request)
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();

  // Personal Information
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  // Work Information
  final _designationController = TextEditingController();
  final _teamController = TextEditingController();
  final _supervisorController = TextEditingController();
  String _selectedDepartment = 'HSE';
  String _selectedSite = 'North Plant';

  // Account
  RequestedAccountType _requestedType = RequestedAccountType.staff;
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;

  final List<String> _departments = [
    'HSE',
    'Maintenance',
    'Operations',
    'Projects',
    'Accounts',
    'Purchase',
    'HR',
    'Field Services',
  ];

  final List<String> _sites = [
    'North Plant',
    'Warehouse B',
    'Central Yard',
    'Admin Block',
    'Storage Area',
    'Main Facility',
    'Offshore Platform A',
  ];

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _designationController.dispose();
    _teamController.dispose();
    _supervisorController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  int _calculatePasswordStrength(String password) {
    if (password.isEmpty) return 0;
    int strength = 0;
    if (password.length >= 6) strength++;
    if (password.length >= 8) strength++;
    if (RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[a-z]').hasMatch(password)) {
      strength++;
    }
    if (RegExp(r'[0-9]').hasMatch(password) ||
        RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      strength++;
    }
    return strength;
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 600));

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    final request = SignupRequest(
      fullName: _fullNameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      designation: _designationController.text.trim().isNotEmpty
          ? _designationController.text.trim()
          : 'Field Operations Specialist',
      department: _selectedDepartment,
      site: _selectedSite,
      team: _teamController.text.trim(),
      supervisor: _supervisorController.text.trim(),
      requestedType: _requestedType,
      password: _passwordController.text,
      status: AuthAccountStatus.pendingVerification,
      isEmailVerified: false,
    );

    // Save to persistent local mock auth store
    MockAuthStore.instance.addRegistration(request);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => SignupSuccessScreen(request: request)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= 900;
    final primaryColor = Theme.of(context).colorScheme.primary;

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
            padding: EdgeInsets.symmetric(
              horizontal: screenWidth < 400 ? 12 : 24,
              vertical: 16,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: isDesktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 4,
                          child: _buildSideBrandCard(primaryColor),
                        ),
                        const SizedBox(width: 32),
                        Expanded(flex: 6, child: _buildSignupFormCard()),
                      ],
                    )
                  : _buildSignupFormCard(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSideBrandCard(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [primaryColor, primaryColor.withValues(alpha: 0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ActionFlowLogo.white(size: 64, iconSize: 36, borderRadius: 16),
          const SizedBox(height: 20),
          const Text(
            'Create your ActionFlow Account',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Join your organization\'s action tracking network. Report field progress, attach inspection evidence, and collaborate seamlessly.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.55,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 28),
          _featureBullet(
            icon: Icons.assignment_turned_in_outlined,
            title: 'Action Tracking',
            desc: 'Real-time progress, roadblocks & completion reports.',
          ),
          const SizedBox(height: 14),
          _featureBullet(
            icon: Icons.shield_outlined,
            title: 'Governance & Roles',
            desc: 'Role-controlled workflows for Staff, Managers, and Admins.',
          ),
          const SizedBox(height: 14),
          _featureBullet(
            icon: Icons.devices_rounded,
            title: 'Field Ready',
            desc: 'Designed for desktop, tablet, and mobile field inspections.',
          ),
        ],
      ),
    );
  }

  Widget _featureBullet({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSignupFormCard() {
    final screenWidth = MediaQuery.sizeOf(context).width;

    return Card(
      color: AppTheme.cardBg(context),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppTheme.cardBorder(context)),
      ),
      child: Padding(
        padding: EdgeInsets.all(screenWidth < 450 ? 16 : 28),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Mobile branding header
              if (screenWidth < 900) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: ActionFlowBrand(
                      logoSize: 32,
                      fontSize: 18,
                      subtitle: 'Workplace Action Tracker',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Divider(color: AppTheme.cardBorder(context)),
                const SizedBox(height: 16),
              ],

              // Header
              Text(
                'Create an account',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Enter your details to register for your organization\'s ActionFlow platform',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary(context),
                ),
              ),
              const SizedBox(height: 20),

              // SECTION 1: PERSONAL INFORMATION
              _sectionHeader(
                icon: Icons.person_outline_rounded,
                title: 'PERSONAL INFORMATION',
              ),
              const SizedBox(height: 12),

              _buildField(
                label: 'Full Name *',
                controller: _fullNameController,
                hintText: 'e.g. R. Kumar / Sarah Jenkins',
                prefixIcon: Icons.person_outline_rounded,
                validator: (val) => val == null || val.trim().isEmpty
                    ? 'Please enter your full name'
                    : null,
              ),
              const SizedBox(height: 12),

              LayoutBuilder(
                builder: (context, constraints) {
                  final isTight = constraints.maxWidth < 460;
                  final emailField = _buildField(
                    label: 'Email Address *',
                    controller: _emailController,
                    hintText: 'name@company.com',
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: Icons.mail_outline_rounded,
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!val.contains('@') || !val.contains('.')) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  );
                  final phoneField = _buildField(
                    label: 'Phone Number *',
                    controller: _phoneController,
                    hintText: '+1 (555) 000-0000',
                    keyboardType: TextInputType.phone,
                    prefixIcon: Icons.phone_outlined,
                    validator: (val) => val == null || val.trim().isEmpty
                        ? 'Please enter your phone number'
                        : null,
                  );

                  if (isTight) {
                    return Column(
                      children: [
                        emailField,
                        const SizedBox(height: 12),
                        phoneField,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: emailField),
                      const SizedBox(width: 12),
                      Expanded(child: phoneField),
                    ],
                  );
                },
              ),
              const SizedBox(height: 22),

              // SECTION 2: WORK INFORMATION
              _sectionHeader(
                icon: Icons.business_outlined,
                title: 'WORK INFORMATION',
              ),
              const SizedBox(height: 12),

              // Designation
              _buildField(
                label: 'Designation / Job Title *',
                controller: _designationController,
                hintText: 'e.g. Field Operations Specialist / HSE Officer',
                prefixIcon: Icons.badge_outlined,
                validator: (val) => val == null || val.trim().isEmpty
                    ? 'Please enter your designation'
                    : null,
              ),
              const SizedBox(height: 12),

              // Department & Site Row
              LayoutBuilder(
                builder: (context, constraints) {
                  final isTight = constraints.maxWidth < 460;
                  final deptField = DropdownButtonFormField<String>(
                    initialValue: _selectedDepartment,
                    isExpanded: true,
                    dropdownColor: AppTheme.cardBg(context),
                    style: TextStyle(
                      fontSize: 13.5,
                      color: AppTheme.textPrimary(context),
                    ),
                    decoration: _inputDecoration(
                      label: 'Department *',
                      prefixIcon: Icons.domain_rounded,
                    ),
                    items: _departments
                        .map(
                          (d) => DropdownMenuItem(
                            value: d,
                            child: Text(
                              d,
                              style: TextStyle(
                                color: AppTheme.textPrimary(context),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedDepartment = val);
                      }
                    },
                  );

                  final siteField = DropdownButtonFormField<String>(
                    initialValue: _selectedSite,
                    isExpanded: true,
                    dropdownColor: AppTheme.cardBg(context),
                    style: TextStyle(
                      fontSize: 13.5,
                      color: AppTheme.textPrimary(context),
                    ),
                    decoration: _inputDecoration(
                      label: 'Site / Facility *',
                      prefixIcon: Icons.location_on_outlined,
                    ),
                    items: _sites
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(
                              s,
                              style: TextStyle(
                                color: AppTheme.textPrimary(context),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedSite = val);
                    },
                  );

                  if (isTight) {
                    return Column(
                      children: [
                        deptField,
                        const SizedBox(height: 12),
                        siteField,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: deptField),
                      const SizedBox(width: 12),
                      Expanded(child: siteField),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),

              // Team & Supervisor
              LayoutBuilder(
                builder: (context, constraints) {
                  final isTight = constraints.maxWidth < 460;
                  final teamField = _buildField(
                    label: 'Team / Unit (Optional)',
                    controller: _teamController,
                    hintText: 'e.g. Squad A / Compliance Unit',
                    prefixIcon: Icons.group_outlined,
                  );
                  final supervisorField = _buildField(
                    label: 'Supervisor (Optional)',
                    controller: _supervisorController,
                    hintText: 'e.g. Sarah Jenkins (HSSE Manager)',
                    prefixIcon: Icons.supervisor_account_outlined,
                  );

                  if (isTight) {
                    return Column(
                      children: [
                        teamField,
                        const SizedBox(height: 12),
                        supervisorField,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: teamField),
                      const SizedBox(width: 12),
                      Expanded(child: supervisorField),
                    ],
                  );
                },
              ),
              const SizedBox(height: 22),

              // SECTION 3: ACCOUNT & ROLE SELECTION
              _sectionHeader(
                icon: Icons.shield_outlined,
                title: 'ACCOUNT & ACCESS TYPE',
              ),
              const SizedBox(height: 12),

              // Account Type Selector
              _buildAccountTypeSelector(),
              const SizedBox(height: 14),

              // Password & Confirm Password
              LayoutBuilder(
                builder: (context, constraints) {
                  final isTight = constraints.maxWidth < 460;
                  final passField = TextFormField(
                    controller: _passwordController,
                    obscureText: !_isPasswordVisible,
                    style: TextStyle(
                      color: AppTheme.textPrimary(context),
                      fontSize: 13.5,
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (val) {
                      if (val == null || val.isEmpty) {
                        return 'Please enter a password';
                      }
                      if (val.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                    decoration: _inputDecoration(
                      label: 'Password *',
                      prefixIcon: Icons.lock_outline_rounded,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isPasswordVisible
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 18,
                          color: AppTheme.textSecondary(context),
                        ),
                        onPressed: () {
                          setState(() {
                            _isPasswordVisible = !_isPasswordVisible;
                          });
                        },
                      ),
                    ),
                  );

                  final confirmPassField = TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: !_isConfirmPasswordVisible,
                    style: TextStyle(
                      color: AppTheme.textPrimary(context),
                      fontSize: 13.5,
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty) {
                        return 'Please confirm your password';
                      }
                      if (val != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                    decoration: _inputDecoration(
                      label: 'Confirm Password *',
                      prefixIcon: Icons.lock_clock_outlined,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isConfirmPasswordVisible
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 18,
                          color: AppTheme.textSecondary(context),
                        ),
                        onPressed: () {
                          setState(() {
                            _isConfirmPasswordVisible =
                                !_isConfirmPasswordVisible;
                          });
                        },
                      ),
                    ),
                  );

                  if (isTight) {
                    return Column(
                      children: [
                        passField,
                        const SizedBox(height: 12),
                        confirmPassField,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: passField),
                      const SizedBox(width: 12),
                      Expanded(child: confirmPassField),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),

              // Password Strength Indicator
              _buildPasswordStrengthIndicator(),
              const SizedBox(height: 18),

              // SECTION 4: ORGANIZATIONAL INFORMATION DISCLAIMER
              _buildOrganizationalDisclaimer(),
              const SizedBox(height: 24),

              // Submit Button
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _handleSignup,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: Text(
                    _isLoading
                        ? 'Creating Account...'
                        : (_requestedType == RequestedAccountType.manager
                              ? 'Submit Manager Access Request'
                              : 'Create Staff Account'),
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

              // Already have account
              Center(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Already have an account? ',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text(
                        'Sign In',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1565C0),
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

  Widget _sectionHeader({required IconData icon, required String title}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF1565C0)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1565C0),
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    String? hintText,
    IconData? prefixIcon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(color: AppTheme.textPrimary(context), fontSize: 13.5),
      decoration: _inputDecoration(
        label: label,
        hintText: hintText,
        prefixIcon: prefixIcon,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    String? hintText,
    IconData? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      hintStyle: TextStyle(color: AppTheme.textMuted(context), fontSize: 12),
      labelStyle: TextStyle(
        color: AppTheme.textSecondary(context),
        fontSize: 12.5,
      ),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, color: AppTheme.textSecondary(context), size: 18)
          : null,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppTheme.inputFill(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppTheme.inputBorder(context)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: Color(0xFF1565C0), width: 1.8),
      ),
    );
  }

  Widget _buildAccountTypeSelector() {
    final isManager = _requestedType == RequestedAccountType.manager;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.inputFill(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Requested Account Type',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final isTight = constraints.maxWidth < 420;
              final staffChoice = _accountTypeChoice(
                type: RequestedAccountType.staff,
                isSelected: !isManager,
                title: 'Staff',
                subtitle: 'Action Owner / Field Assignee',
                icon: Icons.person_rounded,
              );
              final managerChoice = _accountTypeChoice(
                type: RequestedAccountType.manager,
                isSelected: isManager,
                title: 'Manager',
                subtitle: 'Requires Organization Approval',
                icon: Icons.verified_user_outlined,
              );

              if (isTight) {
                return Column(
                  children: [
                    staffChoice,
                    const SizedBox(height: 8),
                    managerChoice,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: staffChoice),
                  const SizedBox(width: 10),
                  Expanded(child: managerChoice),
                ],
              );
            },
          ),
          if (isManager) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Color(0xFF7C3AED),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Manager access request: Selecting Manager does not grant instant administrator privileges. Your account will require approval from an Organization Administrator.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF7C3AED),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _accountTypeChoice({
    required RequestedAccountType type,
    required bool isSelected,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return InkWell(
      onTap: () => setState(() => _requestedType = type),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF1565C0).withValues(alpha: 0.1)
              : AppTheme.cardBg(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF1565C0)
                : AppTheme.cardBorder(context),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected
                      ? const Color(0xFF1565C0)
                      : AppTheme.textMuted(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? const Color(0xFF1565C0)
                          : AppTheme.textPrimary(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF1565C0)
                          : AppTheme.cardBorder(context),
                      width: isSelected ? 5 : 1.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10.5,
                color: AppTheme.textSecondary(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordStrengthIndicator() {
    final strength = _calculatePasswordStrength(_passwordController.text);
    if (_passwordController.text.isEmpty) return const SizedBox.shrink();

    String label = 'Weak';
    Color col = const Color(0xFFDC2626);
    if (strength == 2) {
      label = 'Fair';
      col = const Color(0xFFD97706);
    } else if (strength == 3) {
      label = 'Good';
      col = const Color(0xFF0284C7);
    } else if (strength >= 4) {
      label = 'Strong';
      col = const Color(0xFF16A34A);
    }

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: strength / 4,
              backgroundColor: AppTheme.inputBorder(context),
              valueColor: AlwaysStoppedAnimation<Color>(col),
              minHeight: 4,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Strength: $label',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: col,
          ),
        ),
      ],
    );
  }

  Widget _buildOrganizationalDisclaimer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.containerBg(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lock_person_outlined,
            size: 16,
            color: AppTheme.textMuted(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Department, Site, Designation, Role and Supervisor assignments are organization-controlled after account creation. Contact your administrator if these details need to be changed.',
              style: TextStyle(
                fontSize: 11.5,
                color: AppTheme.textSecondary(context),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
