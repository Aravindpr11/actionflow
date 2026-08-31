import 'package:flutter/material.dart';
import 'package:action_flow/models/user.dart';
import 'package:action_flow/services/auth_service.dart';

/// Auth provider for managing authentication state
/// This can be extended with a state management solution (Riverpod, BLoC, etc.)
class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  User? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _currentUser != null;

  // TODO: Implement authentication state management
  // This will include:
  // - Login logic with state updates
  // - Logout logic
  // - Token refresh
  // - Persist user session

  Future<void> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final success = await _authService.login(email, password);
      if (success) {
        // TODO: Fetch and set current user
        notifyListeners();
      } else {
        _errorMessage = 'Login failed';
      }
    } catch (e) {
      _errorMessage = 'An error occurred: $e';
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
      await _authService.logout();
      _currentUser = null;
    } catch (e) {
      _errorMessage = 'Logout failed: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
