import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/auth/models/manager_scope_item.dart';
import 'package:action_flow/features/auth/screens/email_verification_screen.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:action_flow/widgets/common/action_flow_logo.dart';
import 'package:action_flow/widgets/common/theme_toggle_button.dart';
import 'package:flutter/material.dart';

/// Configuration state for a department's site selections in Section 2
class _DepartmentScopeEntry {
  _DepartmentScopeEntry({this.departmentId, Set<String>? siteIds})
    : selectedSiteIds = siteIds ?? <String>{};

  String? departmentId;
  final Set<String> selectedSiteIds;
}

/// Screen allowing new Managers to register their details and configure
/// their exact multi-scope Department + Site management permissions.
class ManagerAccountSetupScreen extends StatefulWidget {
  const ManagerAccountSetupScreen({
    super.key,
    this.authService,
    this.initialDepartments,
    this.initialSites,
  });

  final AuthService? authService;
  final List<DepartmentOption>? initialDepartments;
  final List<SiteOption>? initialSites;

  @override
  State<ManagerAccountSetupScreen> createState() =>
      _ManagerAccountSetupScreenState();
}

class _ManagerAccountSetupScreenState extends State<ManagerAccountSetupScreen> {
  final _formKey = GlobalKey<FormState>();

  late final AuthService _authService =
      widget.authService ?? AuthService.instance;

  // SECTION 1: Personal Information controllers
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _designationController = TextEditingController();

  // SECTION 2: Organization state & scope entries
  List<Organization> _organizations = const [];
  String? _selectedOrganizationId;
  List<DepartmentOption> _departments = const [];
  List<SiteOption> _sites = const [];
  bool _isLoadingOrg = false;
  String? _orgLoadError;

  final List<_DepartmentScopeEntry> _scopeEntries = [];
  String? _scopeError;

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
      _scopeEntries.clear();
      if (_departments.isNotEmpty) {
        _scopeEntries.add(
          _DepartmentScopeEntry(departmentId: _departments.first.id),
        );
      }
    } else if (_authService.hasClient) {
      _loadOrganizationData();
    } else {
      _organizations = [Organization.sobha()];
      _selectedOrganizationId = Organization.sobhaId;
      _departments = defaultDepartments;
      _sites = defaultSites;
      _scopeEntries.clear();
      if (_departments.isNotEmpty) {
        _scopeEntries.add(
          _DepartmentScopeEntry(departmentId: _departments.first.id),
        );
      }
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
      if (!mounted) return;
      setState(() {
        _organizations = orgs;
        _selectedOrganizationId = orgId;
        _departments = depts;
        _sites = sites;
        _isLoadingOrg = false;
        _orgLoadError = null;
        if (depts.isNotEmpty) {
          if (_scopeEntries.isEmpty) {
            _scopeEntries.add(
              _DepartmentScopeEntry(departmentId: depts.first.id),
            );
          } else {
            for (final entry in _scopeEntries) {
              if (entry.departmentId == null ||
                  !depts.any((d) => d.id == entry.departmentId)) {
                entry.departmentId = depts.first.id;
              }
            }
          }
        }
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
      _scopeEntries.clear();
    });
    try {
      final depts = await _authService.fetchDepartments(
        organizationId: newOrgId,
      );
      final sites = await _authService.fetchSites(organizationId: newOrgId);
      if (!mounted) return;
      setState(() {
        _departments = depts;
        _sites = sites;
        _isLoadingOrg = false;
        if (depts.isNotEmpty) {
          _scopeEntries.add(
            _DepartmentScopeEntry(departmentId: depts.first.id),
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingOrg = false;
        _orgLoadError = 'Failed to load data for selected organization.';
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

  // --- Helpers for Scope Management ---

  DepartmentOption? _findDepartment(String? id) {
    if (id == null) return null;
    try {
      return _departments.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  SiteOption? _findSite(String id) {
    try {
      return _sites.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Extracts all active (Department ID + Site ID) scope items
  List<ManagerScopeItem> _getSelectedScopes() {
    final List<ManagerScopeItem> scopes = [];
    for (final entry in _scopeEntries) {
      if (entry.departmentId == null) continue;
      final dept = _findDepartment(entry.departmentId);
      if (dept == null) continue;

      for (final siteId in entry.selectedSiteIds) {
        final site = _findSite(siteId);
        if (site == null) continue;

        scopes.add(
          ManagerScopeItem(
            departmentId: dept.id,
            departmentName: dept.name,
            siteId: site.id,
            siteName: site.name,
          ),
        );
      }
    }
    return scopes;
  }

  void _addDepartmentBlock() {
    if (_departments.isEmpty) return;
    setState(() {
      _scopeError = null;
      // Pick the first available department that isn't already used
      final usedDeptIds = _scopeEntries
          .map((e) => e.departmentId)
          .whereType<String>()
          .toSet();
      final unusedDept = _departments.firstWhere(
        (d) => !usedDeptIds.contains(d.id),
        orElse: () => _departments.first,
      );

      _scopeEntries.add(_DepartmentScopeEntry(departmentId: unusedDept.id));
    });
  }

  void _removeDepartmentBlock(int index) {
    if (_scopeEntries.length <= 1) return;
    setState(() {
      _scopeError = null;
      _scopeEntries.removeAt(index);
    });
  }

  void _removeScope(ManagerScopeItem item) {
    setState(() {
      _scopeError = null;
      for (final entry in _scopeEntries) {
        if (entry.departmentId == item.departmentId) {
          entry.selectedSiteIds.remove(item.siteId);
        }
      }
    });
  }

  bool _validateScopes() {
    if (_orgLoadError != null || _departments.isEmpty || _sites.isEmpty) {
      setState(() {
        _scopeError = 'Organization data is unavailable. Please check your connection and tap Retry.';
      });
      return false;
    }

    final allScopes = _getSelectedScopes();

    if (allScopes.isEmpty) {
      setState(() {
        _scopeError = 'At least one Department + Site combination required';
      });
      return false;
    }

    // Check if every configured department block has at least one site selected
    for (final entry in _scopeEntries) {
      if (entry.departmentId != null && entry.selectedSiteIds.isEmpty) {
        final dept = _findDepartment(entry.departmentId);
        setState(() {
          _scopeError =
              'Every selected Department must have at least one Site. (${dept?.name ?? "Department"} has no sites selected)';
        });
        return false;
      }
    }

    // Check for duplicate Department + Site combinations
    final seen = <String>{};
    for (final scope in allScopes) {
      final key = '${scope.departmentId}::${scope.siteId}';
      if (seen.contains(key)) {
        setState(() {
          _scopeError =
              'Duplicate Department + Site combinations are not allowed (${scope.label})';
        });
        return false;
      }
      seen.add(key);
    }

    // Check for duplicate department blocks
    final deptSeen = <String>{};
    for (final entry in _scopeEntries) {
      if (entry.departmentId != null) {
        if (deptSeen.contains(entry.departmentId)) {
          final dept = _findDepartment(entry.departmentId);
          setState(() {
            _scopeError =
                'Duplicate department "${dept?.name}" configured. Merge sites into a single department block or choose another department.';
          });
          return false;
        }
        deptSeen.add(entry.departmentId!);
      }
    }

    setState(() {
      _scopeError = null;
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
    final scopesValid = _validateScopes();

    if (!formValid || !scopesValid) {
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

    final selectedScopes = _getSelectedScopes();

    // Show temporary success/debug confirmation dialog (local validation passed)
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
                color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF16A34A),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Manager Request Validated',
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
                Text(
                  'Form and management scopes passed all local validation rules successfully.',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: AppTheme.textSecondary(context),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                _buildSummaryRow('Full Name', _fullNameController.text.trim()),
                _buildSummaryRow('Email', _emailController.text.trim()),
                if (_phoneController.text.trim().isNotEmpty)
                  _buildSummaryRow('Phone', _phoneController.text.trim()),
                _buildSummaryRow(
                  'Designation',
                  _designationController.text.trim(),
                ),
                const SizedBox(height: 12),
                Divider(color: AppTheme.cardBorder(context)),
                const SizedBox(height: 10),
                Text(
                  'Configured Management Scopes (${selectedScopes.length}):',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 8),
                ...selectedScopes.map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '• ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            s.label,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textPrimary(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary
                          .withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
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
            child: const Text('Close'),
          ),
          ElevatedButton(
            key: const ValueKey('manager_dialog_continue_button'),
            onPressed: () {
              Navigator.of(ctx).pop();
              _performSignup(selectedScopes);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
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

  Future<void> _performSignup(List<ManagerScopeItem> scopes) async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final fullName = _fullNameController.text.trim();
      final phone = _phoneController.text.trim();
      final designation = _designationController.text.trim();

      final metadata = AuthService.buildManagerSignupMetadata(
        fullName: fullName,
        phone: phone.isNotEmpty ? phone : null,
        designation: designation,
        scopes: scopes,
      );

      final result = await _authService.signUp(
        email: email,
        password: password,
        data: metadata,
      );

      if (!mounted) return;

      setState(() {
        _isSubmitting = false;
      });

      if (result.isSuccess) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => EmailVerificationScreen(email: email),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.errorMessage ?? 'Failed to submit account request',
            ),
            backgroundColor: Colors.red.shade700,
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
          content: const Text('An unexpected error occurred during signup'),
          backgroundColor: Colors.red.shade700,
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
            width: 100,
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
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 1.8,
        ),
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
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: Theme.of(context).colorScheme.primary,
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
    final primaryColor = Theme.of(context).colorScheme.primary;
    final selectedScopes = _getSelectedScopes();

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
                              'Create Manager Account',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary(context),
                                    letterSpacing: -0.5,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Enter your details and select the departments and sites you will manage.',
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
                                    hintText: 'e.g. John Doe',
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
                                    hintText: 'e.g. j.doe@company.com',
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
                                    hintText: 'e.g. +971 50 123 4567',
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
                                    hintText:
                                        'e.g. Operations Manager / HSE Lead',
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
                            // SECTION 2: Management Scope
                            // ==========================================
                            _sectionHeader(
                              icon: Icons.business_center_outlined,
                              title: 'MANAGEMENT SCOPE',
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Select the departments and active sites you oversee. You can configure multiple discrete department + site combinations.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppTheme.textSecondary(context),
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 16),

                            if (_organizations.length > 1) ...[
                              DropdownButtonFormField<String>(
                                key: const ValueKey('manager_org_dropdown'),
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
                                        'manager_retry_org_button',
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

                            // Department Blocks
                            ..._scopeEntries.asMap().entries.map((mapEntry) {
                              final index = mapEntry.key;
                              final entry = mapEntry.value;

                              return Container(
                                key: ValueKey('dept_block_$index'),
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppTheme.inputFill(context),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: AppTheme.cardBorder(context),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Department Block Header
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: primaryColor.withValues(
                                              alpha: 0.12,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            'Department ${index + 1}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: primaryColor,
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        if (_scopeEntries.length > 1)
                                          IconButton(
                                            icon: Icon(
                                              Icons.delete_outline_rounded,
                                              size: 18,
                                              color: AppTheme.textMuted(
                                                context,
                                              ),
                                            ),
                                            tooltip: 'Remove Department',
                                            onPressed: () =>
                                                _removeDepartmentBlock(index),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),

                                    // Department Selector
                                    DropdownButtonFormField<String>(
                                      value:
                                          _departments.any(
                                            (d) => d.id == entry.departmentId,
                                          )
                                          ? entry.departmentId
                                          : null,
                                      isExpanded: true,
                                      dropdownColor: AppTheme.cardBg(context),
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        color: AppTheme.textPrimary(context),
                                      ),
                                      decoration: _inputDecoration(
                                        label: 'Department',
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
                                      onChanged: (newDeptId) {
                                        if (newDeptId != null &&
                                            newDeptId != entry.departmentId) {
                                          setState(() {
                                            entry.departmentId = newDeptId;
                                            _scopeError = null;
                                          });
                                        }
                                      },
                                    ),
                                    const SizedBox(height: 14),

                                    // Sites Multi-select Checkboxes/Chips
                                    Text(
                                      'Sites (Select all that apply):',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textPrimary(context),
                                      ),
                                    ),
                                    const SizedBox(height: 8),

                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: _sites.map((site) {
                                        final isChecked = entry.selectedSiteIds
                                            .contains(site.id);

                                        return FilterChip(
                                          key: ValueKey(
                                            'chip_${entry.departmentId}_${site.id}',
                                          ),
                                          label: Text(site.name),
                                          labelStyle: TextStyle(
                                            fontSize: 12,
                                            fontWeight: isChecked
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                            color: isChecked
                                                ? primaryColor
                                                : AppTheme.textPrimary(context),
                                          ),
                                          selected: isChecked,
                                          selectedColor: primaryColor
                                              .withValues(alpha: 0.15),
                                          backgroundColor: AppTheme.cardBg(
                                            context,
                                          ),
                                          checkmarkColor: primaryColor,
                                          side: BorderSide(
                                            color: isChecked
                                                ? primaryColor
                                                : AppTheme.cardBorder(context),
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          onSelected: (selected) {
                                            setState(() {
                                              _scopeError = null;
                                              if (selected) {
                                                entry.selectedSiteIds.add(
                                                  site.id,
                                                );
                                              } else {
                                                entry.selectedSiteIds.remove(
                                                  site.id,
                                                );
                                              }
                                            });
                                          },
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ),
                              );
                            }),

                            // "+ Add another department" Button
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: _addDepartmentBlock,
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text('Add another department'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: primaryColor,
                                  side: BorderSide(
                                    color: primaryColor.withValues(alpha: 0.5),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),

                            // Scope Summary Section
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppTheme.containerBg(context),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppTheme.cardBorder(context),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      Text(
                                        'Management Scope',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textPrimary(context),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: primaryColor.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          '${selectedScopes.length} Scopes',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                            color: primaryColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (selectedScopes.isEmpty)
                                    Text(
                                      'No management scopes configured yet. Select at least one department and site above.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                        color: AppTheme.textMuted(context),
                                      ),
                                    )
                                  else
                                    ...selectedScopes.map(
                                      (scope) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 6,
                                        ),
                                        child: Row(
                                          children: [
                                            Text(
                                              '• ',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: primaryColor,
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                scope.label,
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w500,
                                                  color: AppTheme.textPrimary(
                                                    context,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              key: ValueKey(
                                                'remove_scope_${scope.departmentId}_${scope.siteId}',
                                              ),
                                              icon: Icon(
                                                Icons.close_rounded,
                                                size: 16,
                                                color: AppTheme.textMuted(
                                                  context,
                                                ),
                                              ),
                                              tooltip: 'Remove scope',
                                              onPressed: () =>
                                                  _removeScope(scope),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            // Scope Error Notice if any
                            if (_scopeError != null) ...[
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
                                        _scopeError!,
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
                                    onPressed: _isSubmitting
                                        ? null
                                        : _handleSubmit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: primaryColor,
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
