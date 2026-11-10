import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/auth/models/manager_scope_item.dart';
import 'package:action_flow/features/auth/screens/email_verification_screen.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:action_flow/widgets/common/action_flow_logo.dart';
import 'package:action_flow/widgets/common/theme_toggle_button.dart';
import 'package:flutter/material.dart';

/// Screen allowing new Staff members to register their personal details
/// and select their primary department, site, and optional team.
class StaffAccountSetupScreen extends StatefulWidget {
  const StaffAccountSetupScreen({
    super.key,
    this.authService,
    this.initialDepartments,
    this.initialSites,
    this.initialTeams,
  });

  final AuthService? authService;
  final List<DepartmentOption>? initialDepartments;
  final List<SiteOption>? initialSites;
  final List<TeamOption>? initialTeams;

  @override
  State<StaffAccountSetupScreen> createState() =>
      _StaffAccountSetupScreenState();
}

class _StaffAccountSetupScreenState extends State<StaffAccountSetupScreen> {
  final _formKey = GlobalKey<FormState>();

  late final AuthService _authService =
      widget.authService ?? AuthService.instance;

  // SECTION 1: Personal Information controllers
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _designationController = TextEditingController();

  // SECTION 2: Organization state & selections
  List<Organization> _organizations = const [];
  String? _selectedOrganizationId;
  List<DepartmentOption> _departments = const [];
  List<SiteOption> _sites = const [];
  List<TeamOption> _teams = const [];
  bool _isLoadingOrg = false;
  String? _orgLoadError;

  String? _selectedDepartmentId;
  String? _selectedSiteId;
  String? _selectedTeamId;
  String? _organizationError;


  // SECTION 3: Password controllers
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialDepartments != null) {
      _organizations = [Organization.sobha()];
      _selectedOrganizationId = Organization.sobhaId;
      _departments = widget.initialDepartments!;
      _sites = widget.initialSites ?? const [];
      _teams = widget.initialTeams ?? const [];
      _selectedDepartmentId = _departments.isNotEmpty
          ? _departments.first.id
          : null;
      _selectedSiteId = _sites.isNotEmpty ? _sites.first.id : null;
    } else if (_authService.hasClient) {
      _loadOrganizationData();
    } else {
      _organizations = [Organization.sobha()];
      _selectedOrganizationId = Organization.sobhaId;
      _departments = defaultDepartments;
      _sites = defaultSites;
      _teams = defaultTeams;
      _selectedDepartmentId = _departments.isNotEmpty
          ? _departments.first.id
          : null;
      _selectedSiteId = _sites.isNotEmpty ? _sites.first.id : null;
    }
  }

  Future<void> _loadOrganizationData() async {
    setState(() {
      _isLoadingOrg = true;
      _orgLoadError = null;
    });

    try {
      final orgs = await _authService.fetchOrganizations();
      final defaultOrgId = orgs.any((o) => o.id == Organization.sobhaId)
          ? Organization.sobhaId
          : (orgs.isNotEmpty ? orgs.first.id : null);
      final orgId = _selectedOrganizationId ?? defaultOrgId;

      final depts = await _authService.fetchDepartments(organizationId: orgId);
      final sites = await _authService.fetchSites(organizationId: orgId);
      final teams = await _authService.fetchTeams(organizationId: orgId);
      if (!mounted) return;
      setState(() {
        _organizations = orgs;
        _selectedOrganizationId = orgId;
        _departments = depts;
        _sites = sites;
        _teams = teams;
        _selectedDepartmentId = depts.isNotEmpty ? depts.first.id : null;
        _selectedSiteId = sites.isNotEmpty ? sites.first.id : null;
        _selectedTeamId = null;
        _isLoadingOrg = false;
        _orgLoadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingOrg = false;
        _orgLoadError = 'Unable to load organization data from server. Please check your connection and tap Retry.';
      });
    }
  }

  Future<void> _onOrganizationChanged(String? newOrgId) async {
    if (newOrgId == null || newOrgId == _selectedOrganizationId) return;
    setState(() {
      _selectedOrganizationId = newOrgId;
      _isLoadingOrg = true;
      _orgLoadError = null;
    });
    try {
      final depts = await _authService.fetchDepartments(
        organizationId: newOrgId,
      );
      final sites = await _authService.fetchSites(organizationId: newOrgId);
      final teams = await _authService.fetchTeams(organizationId: newOrgId);
      if (!mounted) return;
      setState(() {
        _departments = depts;
        _sites = sites;
        _teams = teams;
        _selectedDepartmentId = depts.isNotEmpty ? depts.first.id : null;
        _selectedSiteId = sites.isNotEmpty ? sites.first.id : null;
        _selectedTeamId = null;
        _isLoadingOrg = false;
        _orgLoadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _departments = const [];
        _sites = const [];
        _teams = const [];
        _selectedDepartmentId = null;
        _selectedSiteId = null;
        _selectedTeamId = null;
        _isLoadingOrg = false;
        _orgLoadError =
            'Selected organization has no active departments or sites configured.';
      });
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _designationController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // --- Organizational Helpers ---

  DepartmentOption? _findDepartment(String? id) {
    if (id == null) return null;
    try {
      return _departments.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  SiteOption? _findSite(String? id) {
    if (id == null) return null;
    try {
      return _sites.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  TeamOption? _findTeam(String? id) {
    if (id == null) return null;
    try {
      return _teams.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  List<TeamOption> _getAvailableTeamsForSelectedDepartment() {
    if (_selectedDepartmentId == null) return const [];
    return _teams
        .where((t) => t.departmentId == _selectedDepartmentId && t.isActive)
        .toList();
  }

  void _onDepartmentChanged(String? newDeptId) {
    if (newDeptId == null || newDeptId == _selectedDepartmentId) return;

    setState(() {
      _selectedDepartmentId = newDeptId;
      _organizationError = null;

      // If the currently selected team does not belong to the new department, clear it
      if (_selectedTeamId != null) {
        final currentTeam = _findTeam(_selectedTeamId);
        if (currentTeam == null || currentTeam.departmentId != newDeptId) {
          _selectedTeamId = null;
        }
      }
    });
  }

  bool _validateOrganization() {
    if (_orgLoadError != null || _departments.isEmpty || _sites.isEmpty) {
      setState(() {
        _organizationError = _orgLoadError ??
            'Organization data is unavailable. Please check your connection and tap Retry.';
      });
      return false;
    }

    if (_selectedDepartmentId == null) {
      setState(() {
        _organizationError = 'Please select your department';
      });
      return false;
    }

    if (_selectedSiteId == null) {
      setState(() {
        _organizationError = 'Please select your site';
      });
      return false;
    }

    // If a team is selected, verify it exists and is active in the organization
    if (_selectedTeamId != null) {
      final team = _findTeam(_selectedTeamId);
      if (team == null || !team.isActive) {
        setState(() {
          _organizationError =
              'Selected team is inactive or does not belong to your organization.';
        });
        return false;
      }
    }

    setState(() {
      _organizationError = null;
    });
    return true;
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

  Future<void> _handleSubmit() async {
    final formValid = _formKey.currentState!.validate();
    final orgValid = _validateOrganization();

    if (!formValid || !orgValid) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
    });

    final department = _findDepartment(_selectedDepartmentId);
    final site = _findSite(_selectedSiteId);
    final team = _findTeam(_selectedTeamId);

    final registrationData = StaffRegistrationData(
      fullName: _fullNameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      designation: _designationController.text.trim(),
      departmentId: _selectedDepartmentId!,
      departmentName: department?.name ?? '',
      siteId: _selectedSiteId!,
      siteName: site?.name ?? '',
      teamId: _selectedTeamId,
      teamName: team?.name,
      password: _passwordController.text,
    );

    _showPreviewDialog(registrationData);
  }

  void _showPreviewDialog(StaffRegistrationData data) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardBg(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppTheme.cardBorder(context)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_outline_rounded,
                color: Color(0xFF0D9488),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Review Staff Account Request',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
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
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSummaryRow('Full Name', data.fullName),
                _buildSummaryRow('Email', data.email),
                if (data.phone.isNotEmpty)
                  _buildSummaryRow('Phone', data.phone),
                _buildSummaryRow('Designation', data.designation),
                const SizedBox(height: 8),
                Divider(color: AppTheme.cardBorder(context)),
                const SizedBox(height: 8),
                _buildSummaryRow('Department', data.departmentName),
                _buildSummaryRow('Site', data.siteName),
                if (data.teamName != null && data.teamName!.isNotEmpty)
                  _buildSummaryRow('Team', data.teamName!),
                const SizedBox(height: 14),

                // Approval Disclaimer
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D9488).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF0D9488).withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: Color(0xFF0D9488),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Your account will require email verification and Administrator approval.',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                            color: AppTheme.textPrimary(context),
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
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Edit'),
          ),
          ElevatedButton(
            key: const ValueKey('staff_dialog_continue_button'),
            onPressed: () {
              Navigator.of(ctx).pop();
              _performSignup(data);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D9488),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _performSignup(StaffRegistrationData data) async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      final metadata = AuthService.buildStaffSignupMetadata(
        fullName: data.fullName,
        phone: data.phone.isNotEmpty ? data.phone : null,
        designation: data.designation,
        departmentId: data.departmentId,
        siteId: data.siteId,
        teamId: data.teamId,
      );

      final result = await _authService.signUp(
        email: data.email,
        password: data.password,
        data: metadata,
      );

      if (!mounted) return;

      setState(() {
        _isSubmitting = false;
      });

      if (result.isSuccess) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => EmailVerificationScreen(email: data.email),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.errorMessage ??
                  'Unable to complete registration. Please try again.',
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AuthService.sanitizeSignUpError(e.toString())),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- UI Builders ---

  InputDecoration _inputDecoration({
    required String label,
    String? hintText,
    IconData? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      labelStyle: TextStyle(
        fontSize: 13,
        color: AppTheme.textSecondary(context),
      ),
      hintStyle: TextStyle(fontSize: 12.5, color: AppTheme.textMuted(context)),
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
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF0D9488), width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.8),
      ),
    );
  }

  Widget _sectionHeader({required IconData icon, required String title}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF0D9488)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: Color(0xFF0D9488),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordStrengthIndicator() {
    final text = _passwordController.text;
    if (text.isEmpty) return const SizedBox.shrink();

    final strength = _calculatePasswordStrength(text);
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

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final availableTeams = _getAvailableTeamsForSelectedDepartment();

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
          tooltip: 'Back',
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
              horizontal: MediaQuery.sizeOf(context).width < 360 ? 10 : 16,
              vertical: 20,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Brand Header
                  Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: ActionFlowBrand(
                        logoSize: 38,
                        fontSize: 20,
                        subtitle: 'Workplace Action Tracker',
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Main Form Card
                  Card(
                    color: AppTheme.cardBg(context),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(color: AppTheme.cardBorder(context)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(
                        MediaQuery.sizeOf(context).width < 360
                            ? 12
                            : (MediaQuery.sizeOf(context).width < 420
                                  ? 18
                                  : 28),
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Screen Title & Subtitle
                            Text(
                              'Create Staff Account',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary(context),
                                    letterSpacing: -0.5,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Enter your personal details and select your department, site, and optional team.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: AppTheme.textSecondary(context),
                                    height: 1.4,
                                  ),
                            ),
                            const SizedBox(height: 24),

                            // ==========================================
                            // SECTION 1: Personal Information
                            // ==========================================
                            _sectionHeader(
                              icon: Icons.person_outline_rounded,
                              title: 'PERSONAL INFORMATION',
                            ),
                            const SizedBox(height: 14),

                            LayoutBuilder(
                              builder: (context, constraints) {
                                final isWide = constraints.maxWidth >= 520;

                                final fullNameField = TextFormField(
                                  controller: _fullNameController,
                                  textCapitalization: TextCapitalization.words,
                                  style: TextStyle(
                                    color: AppTheme.textPrimary(context),
                                    fontSize: 13.5,
                                  ),
                                  validator: (val) =>
                                      val == null || val.trim().isEmpty
                                      ? 'Please enter your full name'
                                      : null,
                                  decoration: _inputDecoration(
                                    label: 'Full Name *',
                                    hintText: 'e.g. Alex Morgan',
                                    prefixIcon: Icons.badge_outlined,
                                  ),
                                );

                                final emailField = TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  style: TextStyle(
                                    color: AppTheme.textPrimary(context),
                                    fontSize: 13.5,
                                  ),
                                  validator: (val) {
                                    if (val == null || val.trim().isEmpty) {
                                      return 'Please enter your email address';
                                    }
                                    if (!RegExp(r'^[\w\.-]+@[\w\.-]+\.\w{2,}$')
                                        .hasMatch(val.trim())) {
                                      return 'Please enter a valid email address';
                                    }
                                    return null;
                                  },
                                  decoration: _inputDecoration(
                                    label: 'Email *',
                                    hintText: 'e.g. alex.m@company.com',
                                    prefixIcon: Icons.email_outlined,
                                  ),
                                );

                                final phoneField = TextFormField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  style: TextStyle(
                                    color: AppTheme.textPrimary(context),
                                    fontSize: 13.5,
                                  ),
                                  decoration: _inputDecoration(
                                    label: 'Phone (Optional)',
                                    hintText: 'e.g. +971 50 234 5678',
                                    prefixIcon: Icons.phone_outlined,
                                  ),
                                );

                                final designationField = TextFormField(
                                  controller: _designationController,
                                  style: TextStyle(
                                    color: AppTheme.textPrimary(context),
                                    fontSize: 13.5,
                                  ),
                                  validator: (val) =>
                                      val == null || val.trim().isEmpty
                                      ? 'Please enter your designation'
                                      : null,
                                  decoration: _inputDecoration(
                                    label: 'Designation *',
                                    hintText: 'e.g. Field Safety Officer / Specialist',
                                    prefixIcon: Icons.work_outline_rounded,
                                  ),
                                );

                                if (isWide) {
                                  return Column(
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(child: fullNameField),
                                          const SizedBox(width: 14),
                                          Expanded(child: emailField),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                      Row(
                                        children: [
                                          Expanded(child: phoneField),
                                          const SizedBox(width: 14),
                                          Expanded(child: designationField),
                                        ],
                                      ),
                                    ],
                                  );
                                } else {
                                  return Column(
                                    children: [
                                      fullNameField,
                                      const SizedBox(height: 12),
                                      emailField,
                                      const SizedBox(height: 12),
                                      phoneField,
                                      const SizedBox(height: 12),
                                      designationField,
                                    ],
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 28),

                            // ==========================================
                            // SECTION 2: Organization
                            // ==========================================
                            _sectionHeader(
                              icon: Icons.domain_rounded,
                              title: 'ORGANIZATION',
                            ),
                            const SizedBox(height: 14),

                            if (_organizations.length > 1) ...[
                              DropdownButtonFormField<String>(
                                key: const ValueKey('staff_org_dropdown'),
                                value: _selectedOrganizationId,
                                isExpanded: true,
                                dropdownColor: AppTheme.cardBg(context),
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: AppTheme.textPrimary(context),
                                ),
                                decoration: _inputDecoration(
                                  label: 'Company / Organization *',
                                  prefixIcon: Icons.apartment_rounded,
                                ),
                                items: _organizations.map((org) {
                                  return DropdownMenuItem<String>(
                                    value: org.id,
                                    child: Text(
                                      org.name,
                                      style: TextStyle(
                                        color: AppTheme.textPrimary(context),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: _onOrganizationChanged,
                              ),
                              const SizedBox(height: 14),
                            ] else if (_organizations.isNotEmpty) ...[
                              Container(
                                margin: const EdgeInsets.only(bottom: 14),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 11,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.inputFill(context),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: AppTheme.inputBorder(context),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.apartment_rounded,
                                      size: 18,
                                      color: AppTheme.textSecondary(context),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Company: ',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textSecondary(context),
                                      ),
                                    ),
                                    Text(
                                      _organizations.first.name,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            if (_isLoadingOrg) ...[
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  children: [
                                    const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Loading organization departments and sites...',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textMuted(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (_orgLoadError != null) ...[
                              Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.amber.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.cloud_off_rounded,
                                      size: 18,
                                      color: Colors.amber,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _orgLoadError!,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.textPrimary(
                                                context,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton(
                                      key: const ValueKey(
                                        'staff_retry_org_button',
                                      ),
                                      onPressed: _loadOrganizationData,
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            LayoutBuilder(
                              builder: (context, constraints) {
                                final isWide = constraints.maxWidth >= 520;

                                final deptField =
                                    DropdownButtonFormField<String>(
                                      key: const ValueKey(
                                        'staff_dept_dropdown',
                                      ),
                                      value:
                                          _departments.any(
                                            (d) =>
                                                d.id == _selectedDepartmentId,
                                          )
                                          ? _selectedDepartmentId
                                          : null,
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
                                      items: _departments.map((dept) {
                                        return DropdownMenuItem<String>(
                                          value: dept.id,
                                          child: Text(
                                            dept.name,
                                            style: TextStyle(
                                              color: AppTheme.textPrimary(
                                                context,
                                              ),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: _onDepartmentChanged,
                                    );

                                final siteField =
                                    DropdownButtonFormField<String>(
                                      key: const ValueKey(
                                        'staff_site_dropdown',
                                      ),
                                      value:
                                          _sites.any(
                                            (s) => s.id == _selectedSiteId,
                                          )
                                          ? _selectedSiteId
                                          : null,
                                      isExpanded: true,
                                      dropdownColor: AppTheme.cardBg(context),
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        color: AppTheme.textPrimary(context),
                                      ),
                                      decoration: _inputDecoration(
                                        label: 'Site *',
                                        prefixIcon: Icons.location_on_outlined,
                                      ),
                                      items: _sites.map((site) {
                                        return DropdownMenuItem<String>(
                                          value: site.id,
                                          child: Text(
                                            site.name,
                                            style: TextStyle(
                                              color: AppTheme.textPrimary(
                                                context,
                                              ),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (newSiteId) {
                                        setState(() {
                                          _selectedSiteId = newSiteId;
                                          _organizationError = null;
                                        });
                                      },
                                    );

                                if (isWide) {
                                  return Row(
                                    children: [
                                      Expanded(child: deptField),
                                      const SizedBox(width: 14),
                                      Expanded(child: siteField),
                                    ],
                                  );
                                } else {
                                  return Column(
                                    children: [
                                      deptField,
                                      const SizedBox(height: 12),
                                      siteField,
                                    ],
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 14),

                            // Team (Optional) Dropdown with zero-teams fallback
                            if (availableTeams.isEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.inputFill(context),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: AppTheme.cardBorder(context),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.group_off_outlined,
                                      size: 18,
                                      color: AppTheme.textMuted(context),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'No teams available for this department',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontStyle: FontStyle.italic,
                                          color: AppTheme.textMuted(context),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              DropdownButtonFormField<String?>(
                                key: ValueKey(
                                  'staff_team_dropdown_$_selectedDepartmentId',
                                ),
                                value:
                                    availableTeams.any(
                                      (t) => t.id == _selectedTeamId,
                                    )
                                    ? _selectedTeamId
                                    : null,
                                isExpanded: true,
                                dropdownColor: AppTheme.cardBg(context),
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: AppTheme.textPrimary(context),
                                ),
                                decoration: _inputDecoration(
                                  label: 'Team / Unit (Optional)',
                                  prefixIcon: Icons.groups_outlined,
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text(
                                      'None / No Team',
                                      style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                  ...availableTeams.map((team) {
                                    return DropdownMenuItem<String?>(
                                      value: team.id,
                                      child: Text(
                                        team.name,
                                        style: TextStyle(
                                          color: AppTheme.textPrimary(context),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }),
                                ],
                                onChanged: (newTeamId) {
                                  setState(() {
                                    _selectedTeamId = newTeamId;
                                    _organizationError = null;
                                  });
                                },
                              ),

                            // Organization Error Notice
                            if (_organizationError != null) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.redAccent.withValues(
                                      alpha: 0.3,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.error_outline_rounded,
                                      size: 16,
                                      color: Colors.redAccent,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _organizationError!,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.redAccent,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 28),

                            // ==========================================
                            // SECTION 3: Password
                            // ==========================================
                            _sectionHeader(
                              icon: Icons.lock_outline_rounded,
                              title: 'PASSWORD',
                            ),
                            const SizedBox(height: 14),

                            LayoutBuilder(
                              builder: (context, constraints) {
                                final isWide = constraints.maxWidth >= 520;

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
                                    hintText: 'Minimum 6 characters',
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
                                          _isPasswordVisible =
                                              !_isPasswordVisible;
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
                                    hintText: 'Re-enter password',
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

                                if (isWide) {
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: passField),
                                      const SizedBox(width: 14),
                                      Expanded(child: confirmPassField),
                                    ],
                                  );
                                } else {
                                  return Column(
                                    children: [
                                      passField,
                                      const SizedBox(height: 12),
                                      confirmPassField,
                                    ],
                                  );
                                }
                              },
                            ),
                            _buildPasswordStrengthIndicator(),
                            const SizedBox(height: 28),

                            Divider(color: AppTheme.cardBorder(context)),
                            const SizedBox(height: 20),

                            // ==========================================
                            // BOTTOM ACTIONS
                            // ==========================================
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final isSmall = constraints.maxWidth < 420;

                                final backButton = SizedBox(
                                  height: 48,
                                  child: OutlinedButton(
                                    key: const ValueKey('staff_back_button'),
                                    onPressed: () =>
                                        Navigator.of(context).maybePop(),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppTheme.textPrimary(
                                        context,
                                      ),
                                      side: BorderSide(
                                        color: AppTheme.cardBorder(context),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text('Back'),
                                  ),
                                );

                                final submitButton = SizedBox(
                                  height: 48,
                                  child: ElevatedButton(
                                    key: const ValueKey('staff_submit_button'),
                                    onPressed: _isSubmitting
                                        ? null
                                        : _handleSubmit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0D9488),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_isSubmitting)
                                            const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          else
                                            const Icon(
                                              Icons
                                                  .assignment_turned_in_outlined,
                                              size: 18,
                                            ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _isSubmitting
                                                ? 'Validating...'
                                                : 'Submit Account Request',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );

                                if (isSmall) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      submitButton,
                                      const SizedBox(height: 10),
                                      backButton,
                                    ],
                                  );
                                }

                                return Row(
                                  children: [
                                    Expanded(flex: 1, child: backButton),
                                    const SizedBox(width: 14),
                                    Expanded(flex: 2, child: submitButton),
                                  ],
                                );
                              },
                            ),
                          ],
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
    );
  }
}
