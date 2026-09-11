import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../core/utils/string_utils.dart';
import '../models/user_profile.dart';
import '../services/api_client.dart';
import '../services/profile_service.dart';
import '../services/token_storage.dart';
import '../services/voice_service.dart';
import '../services/chat_service.dart';
import 'chat_screen.dart';

class ProfileScreen extends StatefulWidget {
  final ProfileService profileService;
  final VoiceService? voiceService;
  final ChatService? chatService;
  final Future<void> Function()? onLogout;

  const ProfileScreen({
    super.key,
    required this.profileService,
    this.voiceService,
    this.chatService,
    this.onLogout,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile _profile = const UserProfile(name: 'FitNova user');
  HealthMetrics _metrics = const HealthMetrics();
  late final VoiceService _voiceService;

  @override
  void initState() {
    super.initState();
    _voiceService = widget.voiceService ?? VoiceService();
    _loadData();
  }

  Future<void> _showLanguages() async {
    try {
      final languages = await _voiceService.getLanguages();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Voice languages'),
          content: languages.isEmpty
              ? const Text('English is available for voice chat.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: languages
                      .map((language) => ListTile(
                            leading: const Icon(Icons.language),
                            title: Text(language.name.toTitleCase()),
                            subtitle:
                                Text(language.translateCode.toTitleCase()),
                          ))
                      .toList(),
                ),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _loadData() async {
    try {
      final result = await Future.wait<dynamic>([
        widget.profileService.getProfile(),
        widget.profileService.getHealthMetrics(),
      ]);
      final profile = result[0] as UserProfile;
      final metrics = result[1] as HealthMetrics;
      if (mounted) {
        setState(() {
          _profile = profile;
          _metrics = metrics;
        });
      }
    } catch (_) {
      // Quietly handle errors or keep cached data without blocking UI
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content:
            const Text('This permanently deletes your profile and account.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.profileService.deleteProfile();
      await _leaveAccount();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _signOut() async {
    await _leaveAccount();
  }

  Future<void> _leaveAccount() async {
    if (widget.onLogout != null) {
      await widget.onLogout!();
      return;
    }
    await TokenStorage().deleteToken();
    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil(AppConstants.loginRoute, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _profileHeader(_profile),
          const SizedBox(height: 20),
          _sectionTitle('Health metrics'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _metric('BMI', _number(_metrics.bmi), Icons.speed)),
            const SizedBox(width: 12),
            Expanded(
                child: _metric('Category', _display(_metrics.bmiCategory),
                    Icons.assessment_outlined)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: _metric('BMR', '${_number(_metrics.bmr)} kcal',
                    Icons.local_fire_department_outlined)),
            const SizedBox(width: 12),
            Expanded(
                child: _metric('TDEE', '${_number(_metrics.tdee)} kcal',
                    Icons.bolt_outlined)),
          ]),
          const SizedBox(height: 24),
          _sectionTitle('Profile details'),
          const SizedBox(height: 8),
          Card(
              child: Column(children: [
            _detail('Age', '${_profile.age}'),
            _detail('Gender', _display(_profile.gender)),
            _detail('Height', '${_profile.height} cm'),
            _detail('Weight', '${_profile.weight} kg'),
            _detail('Goal', _display(_profile.fitnessGoal)),
            _detail('Activity', _display(_profile.activityLevel)),
            _detail('Experience', _display(_profile.fitnessExperience)),
            _detail(
                'Diet',
                _profile.dietaryPreferences
                    .map((item) => item.toTitleCase())
                    .join(', ')),
            _detail(
                'Medical conditions',
                _profile.medicalConditions
                    .map((item) => item.toTitleCase())
                    .join(', ')),
          ])),
          const SizedBox(height: 20),
          OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pushNamed(
                    AppConstants.notificationsRoute,
                  ),
              icon: const Icon(Icons.notifications_outlined),
              label: const Text('Notifications')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout),
              label: const Text('Sign out')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
              onPressed: _deleteAccount,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete account')),
        ],
      ),
    );
  }

  Widget _profileHeader(UserProfile profile) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const CircleAvatar(
            radius: 30,
            backgroundColor: AppTheme.primary,
            child: Icon(Icons.person, color: AppTheme.onPrimary, size: 34),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              (profile.name.isEmpty ? 'FitNova user' : profile.name)
                  .toTitleCase(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton(
            onPressed: _showLanguages,
            icon: const Icon(Icons.language),
            tooltip: 'Voice languages',
          ),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatScreen(chatService: widget.chatService),
              ),
            ),
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'AI coach',
          ),
          IconButton(
            onPressed: () => Navigator.pushNamed(
              context,
              AppConstants.profileSetupRoute,
              arguments: profile,
            ),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit profile',
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.border),
              ),
            ),
          ),
        ],
      );

  Widget _sectionTitle(String text) =>
      Text(text, style: Theme.of(context).textTheme.titleLarge);

  Widget _metric(String label, String value, IconData icon) => Card(
      child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: AppTheme.primary),
            const SizedBox(height: 10),
            Text(label),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold))
          ])));

  Widget _detail(String label, String value) => ListTile(
      title: Text(label),
      trailing: Text(value.isEmpty ? '-' : value,
          style: const TextStyle(color: AppTheme.textSecondary)));

  String _number(double? value) =>
      value == null ? '-' : value.toStringAsFixed(1);

  String _display(String? value) =>
      value == null || value.isEmpty ? '-' : value.toTitleCase();
}
