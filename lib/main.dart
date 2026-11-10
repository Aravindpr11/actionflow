import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/core/constants/app_constants.dart';
import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/core/theme/theme_controller.dart';
import 'package:action_flow/features/external_update/screens/external_action_update_screen.dart';
import 'package:action_flow/features/splash/screens/splash_screen.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:action_flow/services/notification_service.dart';
import 'package:action_flow/services/sound_service.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AuthService.captureInitialAuthFlow();
  await SupabaseConfig.initialize();
  if (SupabaseConfig.isInitialized) {
    AuthService.instance.initializeAuthStateListener();
    NotificationService.instance.initializeAuthStateListener();
    SoundService.instance.unlockAudio();
  }
  await ThemeController.instance.loadSavedTheme();
  runApp(const ActionFlowApp());
}

class ActionFlowApp extends StatelessWidget {
  const ActionFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        return Listener(
          onPointerDown: (_) {
            SoundService.instance.unlockAudio();
          },
          child: MaterialApp(
            title: AppConstants.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeController.instance.themeMode,
            home: const SplashScreen(),
            onGenerateRoute: (settings) {
              if (settings.name != null) {
                final uri = Uri.tryParse(settings.name!);
                if (uri != null &&
                    (uri.path == '/external-update' ||
                        uri.path.startsWith('/external-update'))) {
                  final token = uri.queryParameters['token'] ?? '';
                  return MaterialPageRoute(
                    builder: (_) => ExternalActionUpdateScreen(token: token),
                  );
                }
              }
              return null;
            },
          ),
        );
      },
    );
  }
}
