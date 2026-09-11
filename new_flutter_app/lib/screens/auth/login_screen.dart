import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../models/user_profile.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/error_dialog.dart';
import '../../widgets/primary_button.dart';

/// Login screen for authenticating existing FitNova AI users.
class LoginScreen extends StatefulWidget {
  final AuthService? authService;
  final ProfileService? profileService;
  final ValueChanged<UserProfile>? onSignedIn;

  const LoginScreen({
    super.key,
    this.authService,
    this.profileService,
    this.onSignedIn,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  late final AuthService _authService;
  late final ProfileService _profileService;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
    _profileService = widget.profileService ?? ProfileService();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    // Hide keyboard
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      // 1. Submit login request
      final authResponse = await _authService.login(
        email: email,
        password: password,
      );

      if (authResponse.accessToken.isEmpty) {
        throw const ApiException(
          message: 'The server returned an invalid login response.',
        );
      }

      // 2. Fetch authenticated profile data
      UserProfile? profile;
      try {
        profile = await _profileService.getProfile();
      } catch (_) {
        // Fallback to minimal profile if profile endpoint is not yet fully configured
        profile = UserProfile(name: email.split('@').first);
      }

      if (!mounted) return;

      // 3. Show success notification
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Login successful!'),
          backgroundColor: AppTheme.surface,
          duration: Duration(seconds: 2),
        ),
      );

      final resolvedProfile = profile;
      if (widget.onSignedIn != null) {
        widget.onSignedIn!(resolvedProfile);
        return;
      }

      Navigator.of(context).pushNamedAndRemoveUntil(
        AppConstants.homeRoute,
        (route) => false,
        arguments: resolvedProfile,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      await ErrorDialog.show(
        context,
        title: 'Login Failed',
        message: e.message,
      );
    } catch (_) {
      if (!mounted) return;
      await ErrorDialog.show(
        context,
        title: 'Login Error',
        message:
            'Unable to connect to the server. Check your internet connection and try again.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo / Header
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.fitness_center_rounded,
                        size: 38,
                        color: AppTheme.onPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // App Title
                  Text(
                    'Welcome Back',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sign in to continue your fitness journey with FitNova AI',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                  ),
                  const SizedBox(height: 36),

                  // Email Input Field
                  AppTextField(
                    label: 'Email Address',
                    hint: 'name@example.com',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                    validator: Validators.validateEmail,
                  ),
                  const SizedBox(height: 20),

                  // Password Input Field
                  AppTextField(
                    label: 'Password',
                    hint: '••••••••',
                    controller: _passwordController,
                    isPassword: true,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _handleLogin(),
                    prefixIcon: const Icon(
                      Icons.lock_outline_rounded,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty) {
                        return 'Please enter your password.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),

                  // Login Submit Button
                  PrimaryButton(
                    label: 'Sign In',
                    isLoading: _isLoading,
                    onPressed: _handleLogin,
                  ),
                  const SizedBox(height: 24),

                  // Navigation Link to Register
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account? ",
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                            ),
                      ),
                      GestureDetector(
                        onTap: _isLoading
                            ? null
                            : () {
                                Navigator.of(context)
                                    .pushNamed(AppConstants.registerRoute);
                              },
                        child: const Text(
                          'Sign Up',
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            decoration: TextDecoration.underline,
                            decorationColor: AppTheme.primary,
                          ),
                        ),
                      ),
                    ],
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
