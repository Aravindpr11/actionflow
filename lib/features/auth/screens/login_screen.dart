import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _rememberMe = true;
  bool _isLoading = false;

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 600));

    if (!mounted) {
      return;
    }

    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.toLowerCase() == 'manager' && password == '123456') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ManagerDashboardScreen()),
      );
    } else if (username.toLowerCase() == 'worker' && password == '123456') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const WorkerDashboardScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid username or password'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 800;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: isWide
                      ? Row(
                          children: [
                            Expanded(
                              child: _BrandPanel(primaryColor: primaryColor),
                            ),
                            const SizedBox(width: 48),
                            SizedBox(
                              width: 440,
                              child: _LoginCard(
                                formKey: _formKey,
                                usernameController: _usernameController,
                                passwordController: _passwordController,
                                isPasswordVisible: _isPasswordVisible,
                                rememberMe: _rememberMe,
                                isLoading: _isLoading,
                                onPasswordVisibilityChanged: () {
                                  setState(() {
                                    _isPasswordVisible = !_isPasswordVisible;
                                  });
                                },
                                onRememberMeChanged: (value) {
                                  setState(() {
                                    _rememberMe = value ?? false;
                                  });
                                },
                                onLoginPressed: _handleLogin,
                              ),
                            ),
                          ],
                        )
                      : _LoginCard(
                          formKey: _formKey,
                          usernameController: _usernameController,
                          passwordController: _passwordController,
                          isPasswordVisible: _isPasswordVisible,
                          rememberMe: _rememberMe,
                          isLoading: _isLoading,
                          onPasswordVisibilityChanged: () {
                            setState(() {
                              _isPasswordVisible = !_isPasswordVisible;
                            });
                          },
                          onRememberMeChanged: (value) {
                            setState(() {
                              _rememberMe = value ?? false;
                            });
                          },
                          onLoginPressed: _handleLogin,
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({required this.primaryColor});

  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [primaryColor, primaryColor.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.work_history_rounded,
                  size: 42,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'ActionFlow',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'HSSE Action Tracker',
                style: TextStyle(fontSize: 22, color: Colors.white70),
              ),
              const SizedBox(height: 24),
              Text(
                'Track workplace actions, assignments, progress, pending work, completion and manager review.',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.6,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.formKey,
    required this.usernameController,
    required this.passwordController,
    required this.isPasswordVisible,
    required this.rememberMe,
    required this.isLoading,
    required this.onPasswordVisibilityChanged,
    required this.onRememberMeChanged,
    required this.onLoginPressed,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool isPasswordVisible;
  final bool rememberMe;
  final bool isLoading;
  final VoidCallback onPasswordVisibilityChanged;
  final ValueChanged<bool?> onRememberMeChanged;
  final VoidCallback onLoginPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Welcome back',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Sign in to continue',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: Colors.grey.shade600),
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: usernameController,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Please enter your username or email'
                    : null,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Username or email',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: passwordController,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Please enter your password'
                    : null,
                obscureText: !isPasswordVisible,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    onPressed: onPasswordVisibilityChanged,
                    icon: Icon(
                      isPasswordVisible
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: rememberMe,
                    onChanged: onRememberMeChanged,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const Text('Remember me'),
                  const Spacer(),
                  TextButton(
                    onPressed: () {},
                    child: const Text('Forgot Password?'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: isLoading ? null : onLoginPressed,
                  icon: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login_rounded),
                  label: Text(isLoading ? 'Signing In...' : 'Sign In'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
