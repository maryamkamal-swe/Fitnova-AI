import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/progress_stats.dart';
import '../services/api_client.dart';
import '../services/progress_service.dart';
import 'daily_progress_screen.dart';
import 'progress_charts_screen.dart';
import 'progress_history_screen.dart';
import 'progress_stats_screen.dart';

class ProgressOverviewScreen extends StatefulWidget {
  final ProgressService? progressService;
  const ProgressOverviewScreen({super.key, this.progressService});
  @override
  State<ProgressOverviewScreen> createState() => _ProgressOverviewScreenState();
}

class _ProgressOverviewScreenState extends State<ProgressOverviewScreen> {
  late final ProgressService _service;
  ProgressStats? _stats;
  bool _todayLogged = false;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _service = widget.progressService ?? ProgressService();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait(
          [_service.getTodayProgress(), _service.getProgressStats()]);
      _todayLogged = results[0] != null;
      _stats = results[1] as ProgressStats;
    } on ApiException catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen))
          .then((_) => _load());
  @override
  Widget build(BuildContext context) => RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _header(),
          const SizedBox(height: 18),
          if (_loading)
            const LinearProgressIndicator()
          else ...[
            _statusCard(),
            const SizedBox(height: 14),
            if ((_stats?.totalEntries ?? 0) == 0)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No progress logged yet. Log your first day above to unlock history charts!',
                  ),
                ),
              ),
            if ((_stats?.totalEntries ?? 0) == 0) const SizedBox(height: 14),
            Row(children: [
              Expanded(
                  child: _metric('Streak', '${_stats?.workoutStreak ?? 0} days',
                      Icons.local_fire_department_rounded)),
              const SizedBox(width: 12),
              Expanded(
                  child: _metric(
                      'Avg weight',
                      _stats?.avgWeight == null
                          ? '--'
                          : '${_stats!.avgWeight!.toStringAsFixed(1)} kg',
                      Icons.monitor_weight_outlined))
            ]),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed: () => _open(
                          ProgressHistoryScreen(progressService: _service)),
                      icon: const Icon(Icons.history_rounded),
                      label: const Text('History'))),
              const SizedBox(width: 12),
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed: () =>
                          _open(ProgressStatsScreen(progressService: _service)),
                      icon: const Icon(Icons.insights_rounded),
                      label: const Text('Stats')))
            ]),
            const SizedBox(height: 12),
            SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                    onPressed: () =>
                        _open(ProgressChartsScreen(progressService: _service)),
                    icon: const Icon(Icons.show_chart_rounded),
                    label: const Text('View charts'))),
            const SizedBox(height: 24),
            ElevatedButton.icon(
                onPressed: () =>
                    _open(DailyProgressScreen(progressService: _service)),
                icon: const Icon(Icons.add_rounded),
                label: Text(_todayLogged
                    ? 'Update today\'s progress'
                    : 'Log today\'s progress'))
          ]
        ],
      ));
  Widget _header() =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Progress',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Small steps, visible results.',
              style: TextStyle(color: AppTheme.textSecondary))
        ]),
        const Icon(Icons.auto_graph_rounded, color: AppTheme.primary, size: 32)
      ]);
  Widget _statusCard() => Card(
      child: ListTile(
          leading: Icon(
              _todayLogged
                  ? Icons.check_circle_rounded
                  : Icons.pending_actions_rounded,
              color: AppTheme.primary,
              size: 32),
          title: Text(
              _todayLogged ? 'Today is logged' : 'Today is waiting for you',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(_todayLogged
              ? 'Your daily record is up to date.'
              : 'Capture your baseline and keep the streak moving.')));
  Widget _metric(String label, String value, IconData icon) => Card(
      child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: AppTheme.primary),
            const SizedBox(height: 12),
            Text(value,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text(label,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12))
          ])));
}
