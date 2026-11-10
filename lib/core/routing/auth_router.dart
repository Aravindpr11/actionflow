import 'package:action_flow/features/auth/models/auth_models.dart';
import 'package:action_flow/features/auth/screens/account_status_screen.dart';
import 'package:action_flow/features/auth/screens/login_screen.dart';
import 'package:action_flow/features/dashboard/admin_dashboard/screens/admin_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/platform_admin_dashboard/screens/platform_admin_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:flutter/material.dart';

/// Centralized role-based portal routing for ActionFlow.
/// Strictly enforces the four core role portal destinations:
/// 1. Platform Administrator -> PlatformAdminDashboardScreen
/// 2. Company Administrator -> AdminDashboardScreen
/// 3. Manager -> ManagerDashboardScreen
/// 4. Staff / Worker -> WorkerDashboardScreen
class AuthRouter {
  AuthRouter._();

  /// Navigates the user to their authoritative role-based portal.
  /// Replaces the current navigation stack to prevent returning to auth screens.
  static void navigateToRolePortal(
    BuildContext context,
    AuthProfileData profileData,
  ) {
    // 1. Guard against inactive or deactivated profiles
    if (!profileData.isPlatformAdmin &&
        (profileData.status != 'active' || !profileData.isActive)) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AccountStatusScreen(
            status: AuthAccountStatus.inactive,
            userEmail: profileData.userProfile.email,
            userName: profileData.userProfile.name,
          ),
        ),
      );
      return;
    }

    if (profileData.isPlatformAdmin) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const PlatformAdminDashboardScreen()),
      );
      return;
    }

    final role = profileData.roleCode.toLowerCase().trim();
    if (role == 'admin' || profileData.isPrimaryAdmin) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              AdminDashboardScreen(adminProfile: profileData.userProfile),
        ),
      );
      return;
    }

    if (role == 'manager') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              ManagerDashboardScreen(userProfile: profileData.userProfile),
        ),
      );
      return;
    }

    // Default to Worker / Staff
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            WorkerDashboardScreen(userProfile: profileData.userProfile),
      ),
    );
  }

  /// Navigates back to the LoginScreen
  static void navigateToLogin(BuildContext context) {
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }
}
