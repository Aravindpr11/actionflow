import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:flutter/material.dart';

/// Auth provider for managing authentication state
class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService.instance;

  bool _isLoading = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _authService.isAuthenticated;
  UserProfile? get currentProfile => _authService.currentProfile;
  AuthProfileData? get currentProfileData => _authService.currentProfileData;

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _authService.signIn(
        email: email,
        password: password,
      );
      if (result.isSuccess) {
        _errorMessage = null;
        notifyListeners();
        return true;
      } else {
        _errorMessage = result.errorMessage ?? 'Invalid username or password';
        return false;
      }
    } catch (e) {
      _errorMessage = 'Invalid username or password';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.signOut();
    } catch (e) {
      _errorMessage = 'Logout failed';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
