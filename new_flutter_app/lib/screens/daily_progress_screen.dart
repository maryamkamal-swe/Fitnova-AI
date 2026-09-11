import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/progress_entry.dart';
import '../services/api_client.dart';
import '../services/progress_service.dart';
import '../widgets/app_text_field.dart';
import '../widgets/primary_button.dart';

class DailyProgressScreen extends StatefulWidget {
  final ProgressService? progressService;
  final ProgressEntry? initialEntry;
  const DailyProgressScreen({
    super.key,
    this.progressService,
    this.initialEntry,
  });

  @override
  State<DailyProgressScreen> createState() => _DailyProgressScreenState();
}

class _DailyProgressScreenState extends State<DailyProgressScreen> {
  late final ProgressService _service;
  final _formKey = GlobalKey<FormState>();
  final _weight = TextEditingController();
  final _calories = TextEditingController();
  final _caloriesBurned = TextEditingController();
  final _water = TextEditingController();
  final _sleep = TextEditingController();
  final _steps = TextEditingController();
  final _active = TextEditingController();
  final _notes = TextEditingController();
  bool _workoutCompleted = false;
  bool _loading = true;
  bool _saving = false;
  String? _entryId;

  @override
  void initState() {
    super.initState();
    _service = widget.progressService ?? ProgressService();
    if (widget.initialEntry != null) {
      _fill(widget.initialEntry!);
      _loading = false;
    } else {
      _loadToday();
    }
  }

  Future<void> _loadToday() async {
    try {
      final entry = await _service.getTodayProgress();
      if (entry != null) _fill(entry);
    } catch (_) {
      if (mounted) _showError('Could not load today\'s progress.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fill(ProgressEntry entry) {
    _entryId = entry.id;
    _weight.text = _format(entry.weight);
    _calories.text = _format(entry.caloriesConsumed);
    _caloriesBurned.text = _format(entry.caloriesBurned);
    _water.text = _format(entry.waterIntake);
    _sleep.text = _format(entry.sleepHours);
    _steps.text = entry.steps?.toString() ?? '';
    _active.text = entry.activeMinutes?.toString() ?? '';
    _notes.text = entry.notes ?? '';
    _workoutCompleted = entry.workoutCompleted;
  }

  String _format(num? value) => value == null ? '' : value.toString();
  double? _number(String value) => double.tryParse(value.trim());

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final entry = ProgressEntry(
      id: _entryId,
      date: DateTime.now(),
      weight: _number(_weight.text),
      workoutCompleted: _workoutCompleted,
      caloriesConsumed: _number(_calories.text),
      caloriesBurned: _number(_caloriesBurned.text),
      waterIntake: _number(_water.text),
      sleepHours: _number(_sleep.text),
      steps: int.tryParse(_steps.text.trim()),
      activeMinutes: int.tryParse(_active.text.trim()),
      notes: _notes.text,
    );
    try {
      if (_entryId == null) {
        final saved = await _service.logProgress(entry);
        _entryId = saved.id;
      } else {
        await _service.updateProgress(_entryId!, entry);
      }
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          const SnackBar(content: Text('Progress saved successfully.')),
        );
      }
    } on ApiException catch (error) {
      if (mounted) _showError(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppTheme.error),
      );

  String? _validateOptionalNumber(String? value) =>
      value == null || value.trim().isEmpty || _number(value) != null
          ? null
          : 'Enter a valid number';

  @override
  void dispose() {
    for (final controller in [
      _weight,
      _calories,
      _caloriesBurned,
      _water,
      _sleep,
      _steps,
      _active,
      _notes
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daily Progress')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  Text('Today, ${_dateLabel(DateTime.now())}',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 20),
                  AppTextField(
                      label: 'Weight (kg)',
                      controller: _weight,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: _validateOptionalNumber,
                      prefixIcon: const Icon(Icons.monitor_weight_outlined)),
                  AppTextField(
                      label: 'Calorie Intake (kcal)',
                      controller: _calories,
                      keyboardType: TextInputType.number,
                      validator: _validateOptionalNumber,
                      prefixIcon:
                          const Icon(Icons.local_fire_department_outlined)),
                  AppTextField(
                      label: 'Calories Burned (kcal)',
                      controller: _caloriesBurned,
                      keyboardType: TextInputType.number,
                      validator: _validateOptionalNumber,
                      prefixIcon: const Icon(Icons.local_fire_department)),
                  const SizedBox(height: 18),
                  Card(
                      child: SwitchListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          value: _workoutCompleted,
                          onChanged: (value) =>
                              setState(() => _workoutCompleted = value),
                          title: const Text('Workout completed'),
                          secondary: const Icon(Icons.fitness_center_rounded,
                              color: AppTheme.primary))),
                  const SizedBox(height: 18),
                  AppTextField(
                      label: 'Water intake (liters)',
                      controller: _water,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: _validateOptionalNumber,
                      prefixIcon: const Icon(Icons.water_drop_outlined)),
                  Slider(
                      value: _number(_water.text)?.clamp(0, 6) ?? 0,
                      max: 6,
                      divisions: 24,
                      label:
                          '${_number(_water.text)?.toStringAsFixed(1) ?? '0.0'} L',
                      onChanged: (value) {
                        _water.text = value.toStringAsFixed(1);
                        setState(() {});
                      }),
                  Row(children: [
                    Expanded(
                        child: AppTextField(
                            label: 'Sleep (hours)',
                            controller: _sleep,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            validator: _validateOptionalNumber,
                            prefixIcon: const Icon(Icons.bedtime_outlined))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: AppTextField(
                            label: 'Steps',
                            controller: _steps,
                            keyboardType: TextInputType.number,
                            validator: _validateOptionalNumber,
                            prefixIcon:
                                const Icon(Icons.directions_walk_rounded))),
                  ]),
                  const SizedBox(height: 18),
                  AppTextField(
                      label: 'Active minutes',
                      controller: _active,
                      keyboardType: TextInputType.number,
                      validator: _validateOptionalNumber,
                      prefixIcon: const Icon(Icons.timer_outlined)),
                  const SizedBox(height: 18),
                  AppTextField(
                      label: 'Notes',
                      controller: _notes,
                      hint: 'How did today feel?',
                      prefixIcon: const Icon(Icons.notes_rounded)),
                  const SizedBox(height: 28),
                  PrimaryButton(
                      label: 'Save Progress',
                      icon: Icons.check_rounded,
                      isLoading: _saving,
                      onPressed: _save),
                ],
              ),
            ),
    );
  }

  String _dateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
