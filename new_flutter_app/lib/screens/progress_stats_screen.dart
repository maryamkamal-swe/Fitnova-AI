import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/progress_stats.dart';
import '../services/api_client.dart';
import '../services/progress_service.dart';

class ProgressStatsScreen extends StatefulWidget {
  final ProgressService? progressService;
  const ProgressStatsScreen({super.key, this.progressService});
  @override
  State<ProgressStatsScreen> createState() => _ProgressStatsScreenState();
}

class _ProgressStatsScreenState extends State<ProgressStatsScreen> {
  late final ProgressService _service;
  ProgressStats? _stats;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _service = widget.progressService ?? ProgressService();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _stats = await _service.getProgressStats();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.message), backgroundColor: AppTheme.error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _number(double? value, String suffix) =>
      value == null ? '--' : '${value.toStringAsFixed(1)} $suffix';
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Progress Stats'), actions: [
        IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded))
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _stats == null
              ? const Center(child: Text('Stats unavailable.'))
              : RefreshIndicator(
                  color: AppTheme.primary,
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    Card(
                        child: ListTile(
                            leading: const Icon(
                                Icons.local_fire_department_rounded,
                                color: AppTheme.primary,
                                size: 32),
                            title: Text('${_stats!.workoutStreak} day streak!',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            subtitle:
                                const Text('Keep building your consistency.'))),
                    const SizedBox(height: 12),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.45,
                      children: [
                        _stat(
                            'Average weight',
                            _number(_stats!.avgWeight, 'kg'),
                            Icons.monitor_weight_outlined),
                        _stat(
                            'Weight change',
                            _number(_stats!.weightChange, 'kg'),
                            Icons.trending_down_rounded),
                        _stat('Workouts', '${_stats!.totalWorkouts}',
                            Icons.fitness_center_rounded),
                        _stat('Calories', _number(_stats!.avgCalories, 'kcal'),
                            Icons.local_fire_department_outlined),
                        _stat('Water', _number(_stats!.avgWater, 'L'),
                            Icons.water_drop_outlined),
                        _stat('Sleep', _number(_stats!.avgSleep, 'hrs'),
                            Icons.bedtime_outlined)
                      ],
                    ),
                  ])));
  Widget _stat(String label, String value, IconData icon) => Card(
      child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: AppTheme.primary),
                Text(value,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                Text(label,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12))
              ])));
}
