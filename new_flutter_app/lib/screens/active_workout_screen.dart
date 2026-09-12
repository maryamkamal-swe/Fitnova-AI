import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/progress_entry.dart';
import '../models/user_profile.dart';
import '../models/workout_plan.dart';
import '../services/notification_service.dart';
import '../services/progress_service.dart';
import '../services/profile_service.dart';

class ActiveWorkoutScreen extends StatefulWidget {
  final WorkoutDay workout;
  final NotificationService? notificationService;
  final ProgressService? progressService;
  final UserProfile? userProfile;
  const ActiveWorkoutScreen({
    super.key,
    required this.workout,
    this.notificationService,
    this.progressService,
    this.userProfile,
  });

  @override
  State<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends State<ActiveWorkoutScreen> {
  Timer? _timer;
  int _seconds = 0;
  final Set<int> _completed = {};
  late final ProgressService _progressService;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _progressService = widget.progressService ?? ProgressService();
    _timer = Timer.periodic(
        const Duration(seconds: 1), (_) => setState(() => _seconds++));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    _timer?.cancel();
    final elapsedMinutes =
        (_seconds == 0 ? 30 : (_seconds / 60).ceil()).clamp(1, 30 * 24);
    UserProfile? latestProfile;
    try {
      latestProfile = await ProfileService().getProfile();
    } catch (_) {
      latestProfile = widget.userProfile;
    }
    final weight = latestProfile?.weight;
    if (weight == null || weight <= 0 || weight > 300) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A valid current profile weight is required.')),
        );
      }
      return;
    }
    final caloriesBurned = (elapsedMinutes *
            (0.071 * weight))
        .round();

    try {
      await _progressService.logCaloriesBurned(
        caloriesBurned,
        date: _dateOnly(DateTime.now()),
      );
      await _progressService.logProgress(
        ProgressEntry(date: DateTime.now(), workoutCompleted: true),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save workout: $error')),
        );
      }
      return;
    }

    if (mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Workout complete'),
          content: Text(
              '${_completed.length}/${widget.workout.exercises.length} exercises completed in ${_seconds ~/ 60}m ${_seconds % 60}s.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.workout.focus),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                  child: Text('${_seconds ~/ 60}:${_seconds % 60}'.padLeft(4, '0'))),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Stay focused and move with control.',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            ...widget.workout.exercises.asMap().entries.map((entry) {
              final index = entry.key;
              final exercise = entry.value;
              final done = _completed.contains(index);
              return Card(
                child: CheckboxListTile(
                  value: done,
                  onChanged: (_) => setState(() {
                    if (done) {
                      _completed.remove(index);
                    } else {
                      _completed.add(index);
                    }
                  }),
                  title: Text(exercise.exerciseName),
                  subtitle: Text(
                      '${exercise.sets} sets × ${exercise.reps} • ${exercise.restSeconds}s rest'),
                  secondary: Icon(Icons.fitness_center,
                      color: done ? AppTheme.success : AppTheme.primary),
                ),
              );
            }),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _finish,
              icon: const Icon(Icons.check),
              label: const Text('Finish workout'),
            ),
          ],
        ),
      );

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
