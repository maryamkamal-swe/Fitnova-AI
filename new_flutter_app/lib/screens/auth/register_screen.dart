import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/utils/string_utils.dart';
import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../models/user_profile.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/error_dialog.dart';
import '../../widgets/primary_button.dart';

/// Registration screen for new FitNova AI users.
class RegisterScreen extends StatefulWidget {
  final AuthService? authService;
  final ProfileService? profileService;

  const RegisterScreen({
    super.key,
    this.authService,
    this.profileService,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  late final AuthService _authService;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
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
      final name = _nameController.text.toNameCase();
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      final registration = await _authService.register(
        email: email,
        password: password,
      );

      if (!mounted) return;

      final pendingProfile = UserProfile(name: name);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(registration.message)),
      );
      Navigator.of(context).pushReplacementNamed(
        AppConstants.emailVerificationRoute,
        arguments: {
          'email': registration.email.isEmpty ? email : registration.email,
          'profile': pendingProfile,
          'developmentCode': registration.developmentCode,
        },
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      await ErrorDialog.show(
        context,
        title: 'Registration Failed',
        message: e.message,
      );
    } catch (_) {
      if (!mounted) return;
      await ErrorDialog.show(
        context,
        title: 'Registration Error',
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 28.0, vertical: 12.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title & Subtitle
                  Text(
                    'Create Account',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Join FitNova AI and begin your fitness journey',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                  ),
                  const SizedBox(height: 32),

                  // Full Name Field
                  AppTextField(
                    label: 'Full Name',
                    hint: 'Jane Doe',
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    prefixIcon: const Icon(
                      Icons.person_outline_rounded,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                    validator: Validators.validateName,
                  ),
                  const SizedBox(height: 18),

                  // Email Address Field
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
                  const SizedBox(height: 18),

                  // Password Field
                  AppTextField(
                    label: 'Password',
                    hint: 'At least 8 characters with numbers & symbols',
                    controller: _passwordController,
                    isPassword: true,
                    textInputAction: TextInputAction.next,
                    prefixIcon: const Icon(
                      Icons.lock_outline_rounded,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                    validator: Validators.validatePassword,
                  ),
                  const SizedBox(height: 18),

                  // Confirm Password Field
                  AppTextField(
                    label: 'Confirm Password',
                    hint: 'Re-enter your password',
                    controller: _confirmPasswordController,
                    isPassword: true,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _handleRegister(),
                    prefixIcon: const Icon(
                      Icons.lock_reset_rounded,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                    validator: (val) => Validators.validateConfirmPassword(
                      val,
                      _passwordController.text,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Register Button
                  PrimaryButton(
                    label: 'Create Account',
                    isLoading: _isLoading,
                    onPressed: _handleRegister,
                  ),
                  const SizedBox(height: 24),

                  // Link back to Login
                  Wrap(
                    alignment: WrapAlignment.center,
                    runSpacing: 4,
                    spacing: 4,
                    children: [
                      Text(
                        'Already have an account? ',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                            ),
                      ),
                      GestureDetector(
                        onTap: _isLoading
                            ? null
                            : () {
                                if (Navigator.of(context).canPop()) {
                                  Navigator.of(context).pop();
                                } else {
                                  Navigator.of(context).pushReplacementNamed(
                                    AppConstants.loginRoute,
                                  );
                                }
                              },
                        child: const Text(
                          'Sign In',
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
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
