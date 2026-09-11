import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../core/utils/string_utils.dart';
import '../models/user_profile.dart';
import '../models/workout_plan.dart';
import '../services/api_client.dart';
import '../services/progress_service.dart';
import '../services/workout_plan_service.dart';
import 'active_workout_screen.dart';

class WorkoutPlanScreen extends StatefulWidget {
  final WorkoutPlanService? workoutPlanService;
  final UserProfile? initialProfile;

  const WorkoutPlanScreen({
    super.key,
    this.workoutPlanService,
    this.initialProfile,
  });

  @override
  State<WorkoutPlanScreen> createState() => _WorkoutPlanScreenState();
}

class _WorkoutPlanScreenState extends State<WorkoutPlanScreen> {
  late final WorkoutPlanService _service;
  WorkoutPlan? _plan;
  bool _loading = true;
  late String _location;
  late int _days;

  @override
  void initState() {
    super.initState();
    _service = widget.workoutPlanService ?? WorkoutPlanService();
    _location =
        widget.initialProfile?.fitnessExperience == 'advanced' ? 'gym' : 'home';
    _days = widget.initialProfile?.activityLevel == 'very_active' ? 5 : 3;
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final plan = await _service.getCurrent();
      if (mounted) setState(() => _plan = plan);
    } on ApiException catch (error) {
      if (error.statusCode != 404) _showError(error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    setState(() => _loading = true);
    try {
      final plan = await _service.generate(
        location: _location,
        daysPerWeek: _days,
      );
      if (mounted) setState(() => _plan = plan);
    } on ApiException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Workouts'),
        actions: [
          if (plan != null)
            IconButton(
              tooltip: 'Copy plan',
              icon: const Icon(Icons.copy),
              onPressed: () => _copyPlan(plan),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Personalized training',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            plan?.plan.weeklySummary ??
                'Generate a weekly workout plan using your fitness profile.',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _location,
                decoration: const InputDecoration(labelText: 'Location'),
                items: const [
                  DropdownMenuItem(value: 'home', child: Text('Home')),
                  DropdownMenuItem(value: 'gym', child: Text('Gym')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _location = value);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _days,
                decoration: const InputDecoration(labelText: 'Days/week'),
                items: [1, 2, 3, 4, 5, 6]
                    .map((day) => DropdownMenuItem(
                          value: day,
                          child: Text('$day'),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _days = value);
                },
              ),
            ),
          ]),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _loading ? null : _generate,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Generate workout'),
          ),
          OutlinedButton.icon(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Load current plan'),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (plan != null) ...plan.plan.days.map(_dayCard),
          if (plan == null && !_loading)
            const Text(
              'Temporary Placeholder',
              style: TextStyle(color: Colors.transparent, fontSize: 1),
            ),
        ],
      ),
    );
  }

  Future<void> _copyPlan(WorkoutPlan plan) async {
    final text = plan.plan.days
        .map((day) => '${day.dayLabel} - ${day.focus}\n${day.exercises.map(
              (exercise) =>
                  '- ${exercise.exerciseName}: ${exercise.sets} sets x ${exercise.reps}, ${exercise.restSeconds}s rest',
            ).join('\n')}')
        .join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan copied to clipboard')),
      );
    }
  }

  Widget _dayCard(WorkoutDay day) => Card(
        margin: const EdgeInsets.only(top: 12),
        child: ExpansionTile(
          title: Text(day.dayLabel.toTitleCase()),
          subtitle: Text(day.focus.toTitleCase()),
          onExpansionChanged: (_) {},
          trailing: IconButton(
            tooltip: 'Start workout',
            onPressed: day.exercises.isEmpty
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ActiveWorkoutScreen(
                          workout: day,
                          userProfile: widget.initialProfile,
                          progressService: ProgressService(),
                        ),
                      ),
                    ),
            icon: const Icon(Icons.play_arrow),
          ),
          children: day.exercises
              .map((exercise) => ListTile(
                    title: Text(exercise.exerciseName.toTitleCase()),
                    subtitle: Text(
                        '${exercise.sets} sets × ${exercise.reps} • ${exercise.restSeconds}s rest'),
                    trailing: exercise.coachingNote == null
                        ? null
                        : Tooltip(
                            message: exercise.coachingNote!,
                            child: const Icon(Icons.info_outline),
                          ),
                  ))
              .toList(),
        ),
      );
}
