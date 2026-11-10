import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/auth/screens/manager_account_setup_screen.dart';
import 'package:action_flow/features/auth/screens/staff_account_setup_screen.dart';
import 'package:action_flow/widgets/common/action_flow_logo.dart';
import 'package:action_flow/widgets/common/theme_toggle_button.dart';
import 'package:flutter/material.dart';

/// Screen allowing new users to select their account type: Manager or Staff.
/// Administrator accounts are strictly excluded from self-service selection.
class AccountTypeSelectionScreen extends StatefulWidget {
  const AccountTypeSelectionScreen({super.key});

  @override
  State<AccountTypeSelectionScreen> createState() =>
      _AccountTypeSelectionScreenState();
}

class _AccountTypeSelectionScreenState
    extends State<AccountTypeSelectionScreen> {
  void _navigateToManagerSetup() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ManagerAccountSetupScreen()),
    );
  }

  void _navigateToStaffSetup() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const StaffAccountSetupScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
          tooltip: 'Back to Sign In',
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
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ActionFlow Brand Header
                  Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: ActionFlowBrand(
                        logoSize: 42,
                        fontSize: 22,
                        subtitle: 'Workplace Action Tracker',
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Main Selection Card
                  Card(
                    color: AppTheme.cardBg(context),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(color: AppTheme.cardBorder(context)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(
                        MediaQuery.sizeOf(context).width < 400 ? 18 : 28,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Title & Subtitle
                          Text(
                            'Create a New Account',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary(context),
                                  letterSpacing: -0.5,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Choose the account type',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: AppTheme.textSecondary(context),
                                ),
                          ),
                          const SizedBox(height: 24),

                          // Card 1: Manager
                          _AccountTypeCard(
                            key: const ValueKey('account_type_manager'),
                            title: 'Manager',
                            description: 'Manage actions across assigned departments & sites',
                            icon: Icons.business_center_outlined,
                            iconBgColor: primaryColor.withValues(alpha: 0.12),
                            iconColor: primaryColor,
                            badgeLabel: 'Department & Site Scope',
                            onTap: _navigateToManagerSetup,
                          ),
                          const SizedBox(height: 16),

                          // Card 2: Staff
                          _AccountTypeCard(
                            key: const ValueKey('account_type_staff'),
                            title: 'Staff',
                            description: 'Execute actions and submit progress',
                            icon: Icons.badge_outlined,
                            iconBgColor: const Color(0xFF0D9488)
                                .withValues(alpha: 0.12),
                            iconColor: const Color(0xFF0D9488),
                            badgeLabel: 'Execution & Updates',
                            onTap: _navigateToStaffSetup,
                          ),
                          const SizedBox(height: 24),

                          // Informational Note regarding Administrator accounts
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1E293B)
                                        .withValues(alpha: 0.6)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppTheme.cardBorder(context),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 18,
                                  color: AppTheme.textSecondary(context),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Administrator accounts are created by existing administrators.',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      height: 1.4,
                                      color: AppTheme.textSecondary(context),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          Divider(color: AppTheme.cardBorder(context)),
                          const SizedBox(height: 14),

                          // Bottom Back to Login Link
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
                                  onPressed: () =>
                                      Navigator.of(context).maybePop(),
                                  child: const Text(
                                    'Sign In',
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountTypeCard extends StatefulWidget {
  const _AccountTypeCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.iconBgColor,
    required this.iconColor,
    required this.badgeLabel,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color iconBgColor;
  final Color iconColor;
  final String badgeLabel;
  final VoidCallback onTap;

  @override
  State<_AccountTypeCard> createState() => _AccountTypeCardState();
}

class _AccountTypeCardState extends State<_AccountTypeCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    final borderColor = _isHovered
        ? primaryColor
        : AppTheme.cardBorder(context);

    final bgColor = _isHovered
        ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC))
        : AppTheme.inputFill(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: borderColor,
                width: _isHovered ? 1.5 : 1.0,
              ),
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: widget.iconColor.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon Box
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.iconBgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.icon, color: widget.iconColor, size: 26),
                ),
                const SizedBox(width: 16),

                // Text details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary(context),
                              letterSpacing: -0.2,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: widget.iconColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              widget.badgeLabel,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: widget.iconColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.description,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Chevron icon
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 15,
                    color: _isHovered
                        ? widget.iconColor
                        : AppTheme.textSecondary(context)
                              .withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
