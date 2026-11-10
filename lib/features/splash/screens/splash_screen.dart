import 'dart:async';

import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/core/routing/auth_router.dart';
import 'package:action_flow/features/auth/screens/create_password_screen.dart';
import 'package:action_flow/features/auth/screens/login_screen.dart';
import 'package:action_flow/features/external_update/screens/external_action_update_screen.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:action_flow/widgets/common/action_flow_logo.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The official ActionFlow Splash Screen with smooth brand animations
/// and seamless navigation to the authentication flow.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.duration});

  /// Optional custom duration for splash timing (useful for testing or platform overrides).
  final Duration? duration;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _logoFadeAnimation;
  late final Animation<double> _logoScaleAnimation;
  late final Animation<double> _textFadeAnimation;
  late final Animation<double> _progressFadeAnimation;
  Timer? _navTimer;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    // Subtle scale & fade for the logo
    _logoFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _logoScaleAnimation = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
      ),
    );

    // Fade for typography
    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.35, 0.9, curve: Curves.easeOut),
      ),
    );

    // Fade for loading indicator
    _progressFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
      ),
    );

    _animController.forward();
    _scheduleNavigation();
  }

  void _scheduleNavigation() {
    final effectiveDuration =
        widget.duration ??
        (kIsWeb
            ? const Duration(milliseconds: 1200)
            : const Duration(milliseconds: 1600));

    _navTimer = Timer(effectiveDuration, () async {
      if (!mounted) return;

      final linkError = AuthService.capturedAuthLinkError;
      if (linkError != null) {
        AuthService.clearCapturedAuthLinkError();
        AuthService.clearCapturedInitialAuthFlow();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder<void>(
            pageBuilder: (context, animation, secondaryAnimation) =>
                LoginScreen(initialErrorMessage: linkError.userFriendlyMessage),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
            transitionDuration: const Duration(milliseconds: 300),
          ),
        );
        return;
      }

      final externalToken = AuthService.capturedExternalUpdateToken;
      if (externalToken != null) {
        AuthService.clearCapturedExternalUpdateToken();
        AuthService.clearCapturedInitialAuthFlow();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder<void>(
            pageBuilder: (context, animation, secondaryAnimation) =>
                ExternalActionUpdateScreen(token: externalToken),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
            transitionDuration: const Duration(milliseconds: 300),
          ),
        );
        return;
      }

      if (SupabaseConfig.isInitialized) {
        final isInvite = AuthService.isIncomingInviteFlow;
        final isRecovery =
            AuthService.isIncomingRecoveryFlow ||
            AuthService.isPasswordRecoveryActive;
        final session = AuthService.instance.currentSession;

        if (session != null) {
          try {
            final profileData = await AuthService.instance.fetchProfile(
              session.user.id,
            );
            if (!mounted) return;

            // When arriving through an invitation or password recovery flow,
            // intercept and route to CreatePasswordScreen first!
            if (isInvite || isRecovery) {
              AuthService.clearCapturedInitialAuthFlow();
              AuthService.clearPasswordRecoveryState();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => CreatePasswordScreen(
                    mode: (isRecovery && !isInvite)
                        ? PasswordScreenMode.recovery
                        : PasswordScreenMode.invite,
                    profileData: profileData,
                    email: session.user.email,
                  ),
                ),
              );
              return;
            }

            if (profileData != null &&
                profileData.status.toLowerCase() == 'active' &&
                profileData.isActive) {
              AuthService.instance.setCurrentProfileData(profileData);
              AuthService.clearCapturedInitialAuthFlow();
              AuthRouter.navigateToRolePortal(context, profileData);
              return;
            }
          } catch (_) {
            // If session resume fails or network is unavailable, fall through to LoginScreen
          }
        } else if (isInvite || isRecovery) {
          AuthService.clearCapturedInitialAuthFlow();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => CreatePasswordScreen(
                mode: isRecovery
                    ? PasswordScreenMode.recovery
                    : PasswordScreenMode.invite,
              ),
            ),
          );
          return;
        }
      }

      AuthService.clearCapturedInitialAuthFlow();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const LoginScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    });
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D47A1), Color(0xFF1565C0), Color(0xFF1E88E5)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 32,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Animated Logo Emblem
                        ScaleTransition(
                          scale: _logoScaleAnimation,
                          child: FadeTransition(
                            opacity: _logoFadeAnimation,
                            child: ActionFlowSymbol.white(size: 96),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Animated ActionFlow Branding
                        FadeTransition(
                          opacity: _textFadeAnimation,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Text(
                                'ActionFlow',
                                style: TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Streamline Actions • Track Progress',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.white70,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 48),

                        // Subtle Loading / Progress indicator
                        FadeTransition(
                          opacity: _progressFadeAnimation,
                          child: SizedBox(
                            width: 120,
                            height: 3,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: const LinearProgressIndicator(
                                backgroundColor: Colors.white24,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
