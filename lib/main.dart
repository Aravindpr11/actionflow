import 'package:action_flow/core/constants/app_constants.dart';
import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/auth/screens/login_screen.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const ActionFlowApp());
}

class ActionFlowApp extends StatelessWidget {
  const ActionFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: const LoginScreen(),
    );
  }
}
