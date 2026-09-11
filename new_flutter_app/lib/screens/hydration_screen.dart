import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/user_profile.dart';
import '../services/profile_service.dart';
import '../services/progress_service.dart';
import '../widgets/design_system.dart';

class HydrationScreen extends StatefulWidget {
  const HydrationScreen({super.key});

  @override
  State<HydrationScreen> createState() => _HydrationScreenState();
}

class _HydrationScreenState extends State<HydrationScreen> {
  double _liters = 0;
  double _goal = UserProfile.defaultHydrationGoal;
  final ProfileService _profileService = ProfileService();
  final ProgressService _progressService = ProgressService();
  bool _isLoading = false;
  String? _errorMessage;

  void _addWater(double amount) {
    setState(() => _liters = (_liters + amount).clamp(0, 10));
    _saveHydration();
  }

  Future<void> _loadHydration() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final results = await Future.wait([
        _progressService.getTodayHydration(),
        _profileService.getProfile(),
      ]);
      final data = results[0] as Map<String, dynamic>;
      final profile = results[1] as UserProfile;
      final liters = (data['liters'] as num?)?.toDouble() ?? 0.0;
      if (mounted) {
        setState(() {
          _liters = liters;
          _goal = profile.hydrationGoal;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load hydration data';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveHydration() async {
    try {
      await _progressService.logHydration(_liters);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save hydration')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadHydration();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Hydration')),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
            FitNovaCard(
              child: Row(
                children: [
                  FitNovaProgressRing(
                    value: (_liters / _goal).clamp(0.0, 1.0),
                    label: '${_liters.toStringAsFixed(1)}L',
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Daily hydration',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 6),
                        Text('${_goal.toStringAsFixed(1)}L goal',
                            style: const TextStyle(
                                color: AppTheme.textSecondary)),
                        const SizedBox(height: 10),
                        FitNovaProgressBar(
                            value: (_liters / _goal).clamp(0.0, 1.0)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_liters == 0) ...[
              const SizedBox(height: 20),
              const Text('No hydration logged today. Add your first entry.',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ],
            const SizedBox(height: 20),
            const Text('Quick add', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              children: [0.25, 0.5, 0.75]
                  .map((amount) => ActionChip(
                        label: Text('+${amount.toStringAsFixed(2)}L'),
                        onPressed: () => _addWater(amount),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _addWater(0.25),
              icon: const Icon(Icons.water_drop_outlined),
              label: const Text('Log a glass'),
            ),
            const SizedBox(height: 12),
            Text(
              _liters >= _goal
                  ? 'Hydration goal complete. Great work!'
                  : '${(_goal - _liters).toStringAsFixed(2)}L remaining today',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
}
