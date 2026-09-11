import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../core/utils/string_utils.dart';
import '../../core/theme.dart';
import '../../models/user_profile.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../widgets/error_dialog.dart';
import '../../widgets/primary_button.dart';

class EmailVerificationScreen extends StatefulWidget {
  final AuthService authService;
  final String email;
  final UserProfile? pendingProfile;
  final String? developmentCode;
  final ValueChanged<UserProfile>? onVerified;

  const EmailVerificationScreen({
    super.key,
    required this.authService,
    required this.email,
    this.pendingProfile,
    this.developmentCode,
    this.onVerified,
  });

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _nodes = List.generate(6, (_) => FocusNode());
  bool _busy = false;
  String? _developmentCode;

  @override
  void initState() {
    super.initState();
    _developmentCode = widget.developmentCode;
    _fillDevelopmentCode(widget.developmentCode);
  }

  void _fillDevelopmentCode(String? code) {
    if (code == null || !RegExp(r'^\d{6}$').hasMatch(code)) return;
    for (var index = 0; index < _controllers.length; index++) {
      _controllers[index].text = code[index];
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_code.length != 6) return;
    setState(() => _busy = true);
    try {
      await widget.authService.verifyOtp(email: widget.email, otp: _code);
      if (!mounted) return;
      final profile = widget.pendingProfile ??
          UserProfile(name: widget.email.split('@').first.toNameCase());
      if (widget.onVerified != null) {
        widget.onVerified!(profile);
        return;
      }
      Navigator.of(context).pushReplacementNamed(
        AppConstants.profileSetupRoute,
        arguments: profile,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      await ErrorDialog.show(
        context,
        title: 'Verification Failed',
        message: error.message,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _busy = true);
    try {
      final result = await widget.authService.sendOtp(email: widget.email);
      if (!mounted) return;
      setState(() => _developmentCode = result.developmentCode);
      _fillDevelopmentCode(_developmentCode);
      if (result.autoVerified) {
        final profile = widget.pendingProfile ??
            UserProfile(name: widget.email.split('@').first.toNameCase());
        if (widget.onVerified != null) {
          widget.onVerified!(profile);
          return;
        }
        Navigator.of(context).pushReplacementNamed(
          AppConstants.profileSetupRoute,
          arguments: profile,
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      await ErrorDialog.show(context, message: error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildOtpCell(int index) {
    return SizedBox(
      width: 54,
      height: 62,
      child: TextField(
        controller: _controllers[index],
        focusNode: _nodes[index],
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
        cursorColor: AppTheme.primary,
        keyboardType: TextInputType.number,
        textInputAction: index < 5 ? TextInputAction.next : TextInputAction.done,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(1),
        ],
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xFF1B1D25),
          contentPadding: EdgeInsets.zero,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: _nodes[index].hasFocus ? AppTheme.primary : AppTheme.border,
              width: _nodes[index].hasFocus ? 2 : 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppTheme.primary, width: 2),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppTheme.border, width: 1),
          ),
        ),
        onChanged: (value) {
          if (value.isNotEmpty && index < 5) {
            _nodes[index + 1].requestFocus();
          }
          if (value.isEmpty && index > 0) {
            _nodes[index - 1].requestFocus();
          }
          if (_code.length == 6) _verify();
          setState(() {});
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Verify Email'),
        automaticallyImplyLeading: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Enter the 6-digit code sent to ${widget.email}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                _developmentCode == null
                    ? 'Check your inbox and spam folder for the code.'
                    : 'Email delivery is not configured locally. The development code is filled in below.',
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, _buildOtpCell),
              ),
              const SizedBox(height: 28),
              PrimaryButton(
                label: 'Verify',
                isLoading: _busy,
                onPressed: _verify,
              ),
              TextButton(
                onPressed: _busy ? null : _resend,
                child: const Text('Resend code'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
