import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../core/utils/string_utils.dart';
import '../models/user_profile.dart';
import '../services/api_client.dart';
import '../services/profile_service.dart';

class ProfileSetupScreen extends StatefulWidget {
  final ProfileService profileService;
  final UserProfile? initialProfile;
  final ValueChanged<UserProfile>? onComplete;

  const ProfileSetupScreen(
      {super.key,
      required this.profileService,
      this.initialProfile,
      this.onComplete});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _diet = TextEditingController();
  final _medical = TextEditingController();
  String? _gender;
  String? _goal;
  String? _activity;
  String? _experience;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.initialProfile;
    if (profile != null) {
      _name.text = profile.name;
      _age.text = '${profile.age}';
      _height.text = '${profile.height}';
      _weight.text = '${profile.weight}';
      _diet.text = profile.dietaryPreferences.join(', ');
      _medical.text = profile.medicalConditions.join(', ');
      _gender = profile.gender;
      _goal = profile.fitnessGoal;
      _activity = profile.activityLevel;
      _experience = profile.fitnessExperience;
    }
  }

  @override
  void dispose() {
    for (final controller in [_name, _age, _height, _weight, _diet, _medical]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final profile = UserProfile(
      name: _name.text.toNameCase(),
      age: int.parse(_age.text),
      gender: _gender ?? 'other',
      height: double.parse(_height.text),
      weight: double.parse(_weight.text),
      fitnessGoal: _goal ?? 'maintenance',
      activityLevel: _activity ?? 'moderate',
      fitnessExperience: _experience ?? 'beginner',
      dietaryPreferences: _split(_diet.text),
      medicalConditions: _split(_medical.text),
    );
    try {
      final saved = await widget.profileService.updateProfile(profile);
      if (!mounted) return;
      final preferences = await SharedPreferences.getInstance();
      if (!mounted) return;
      await preferences.setBool('isProfileCompleted', true);
      if (!mounted) return;
      widget.onComplete?.call(saved);
      if (!mounted) return;
      final seenWalkthrough =
          preferences.getBool('onboarding_completed') ?? false;
      Navigator.of(context).pushNamedAndRemoveUntil(
        seenWalkthrough
            ? AppConstants.homeRoute
            : AppConstants.walkthroughRoute,
        (route) => false,
        arguments: saved,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<String> _split(String value) => value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

  String? _requiredField(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required' : null;

  String? _ageValidator(String? value) {
    final error = _number(value, integer: true);
    if (error != null) return error;
    return int.parse(value!.trim()) < 13 ? 'Age must be 13 or above' : null;
  }

  String? _heightValidator(String? value) {
    final error = _number(value, integer: false);
    if (error != null) return error;
    return double.parse(value!.trim()) < 50
        ? 'Height must be at least 50 cm'
        : null;
  }

  String? _weightValidator(String? value) {
    final error = _number(value, integer: false);
    if (error != null) return error;
    return double.parse(value!.trim()) < 20
        ? 'Weight must be at least 20 kg'
        : null;
  }

  String? _goalValidator(String? value) =>
      value == null ? 'Please select a fitness goal' : null;

  String? _number(String? value, {required bool integer}) {
    if (value == null || value.trim().isEmpty) return 'This field is required';
    final parsed = integer ? int.tryParse(value) : double.tryParse(value);
    return parsed == null || parsed <= 0
        ? 'Enter a valid number greater than 0'
        : null;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up your profile')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Tell us about you',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('We use these details to personalize your plan.'),
            const SizedBox(height: 24),
            _field(_name, 'Name', Icons.person_outline, _requiredField,
                capitalizeWords: true),
            _field(_age, 'Age', Icons.cake_outlined, _ageValidator,
                numeric: true),
            _dropdown('Gender', _gender, ['male', 'female', 'other'],
                (value) => setState(() => _gender = value)),
            _field(_height, 'Height (cm)', Icons.height, _heightValidator,
                numeric: true),
            _field(_weight, 'Weight (kg)', Icons.monitor_weight_outlined,
                _weightValidator,
                numeric: true),
            _dropdown(
                'Fitness goal',
                _goal,
                ['weight_loss', 'muscle_gain', 'maintenance'],
                (value) => setState(() => _goal = value),
                validator: _goalValidator),
            _dropdown(
                'Activity level',
                _activity,
                ['sedentary', 'light', 'moderate', 'active'],
                (value) => setState(() => _activity = value)),
            _dropdown(
                'Fitness experience',
                _experience,
                ['beginner', 'intermediate', 'advanced'],
                (value) => setState(() => _experience = value)),
            _field(_diet, 'Dietary preferences (comma separated)',
                Icons.restaurant_outlined, (_) => null),
            _field(_medical, 'Medical conditions (comma separated)',
                Icons.health_and_safety_outlined, (_) => null),
            const SizedBox(height: 12),
            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const CircularProgressIndicator()
                    : const Text('Save profile'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, IconData icon,
      String? Function(String?) validator,
      {bool numeric = false, bool capitalizeWords = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        validator: validator,
        textCapitalization: capitalizeWords
            ? TextCapitalization.words
            : TextCapitalization.none,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      ),
    );
  }

  Widget _dropdown(String label, String? value, List<String> values,
      ValueChanged<String?> onChanged,
      {String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        validator: validator ?? _requiredField,
        decoration: InputDecoration(labelText: label),
        items: values
            .map((item) =>
                DropdownMenuItem(value: item, child: Text(_format(item))))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  String _format(String value) => value.toTitleCase();
}
