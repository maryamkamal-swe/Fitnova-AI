import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/progress_entry.dart';
import '../services/api_client.dart';
import '../services/progress_service.dart';
import 'daily_progress_screen.dart';

class ProgressHistoryScreen extends StatefulWidget {
  final ProgressService? progressService;
  const ProgressHistoryScreen({super.key, this.progressService});

  @override
  State<ProgressHistoryScreen> createState() => _ProgressHistoryScreenState();
}

class _ProgressHistoryScreenState extends State<ProgressHistoryScreen> {
  late final ProgressService _service;
  List<ProgressEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _service = widget.progressService ?? ProgressService();
    _load();
  }

  Future<void> _load() async {
    try {
      _entries = await _service.getProgressHistory(limit: 100);
    } on ApiException catch (error) {
      if (mounted) _message(error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: AppTheme.error));
  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}';
  String _value(num? value, String suffix) =>
      value == null ? '--' : '${value.toStringAsFixed(1)} $suffix';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Progress History')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                color: AppTheme.primary,
                onRefresh: _load,
                child: _entries.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 180),
                        Center(child: Text('No progress logged yet.'))
                      ])
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: _entries.length,
                        itemBuilder: (_, index) => _entryTile(_entries[index]),
                      ),
              ),
      );

  Widget _entryTile(ProgressEntry entry) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: CircleAvatar(
              backgroundColor: AppTheme.primary.withValues(alpha: .15),
              child: Icon(
                  entry.workoutCompleted
                      ? Icons.check_rounded
                      : Icons.remove_rounded,
                  color: entry.workoutCompleted
                      ? AppTheme.primary
                      : AppTheme.textSecondary)),
          title: Text(_date(entry.date),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
              'Weight ${_value(entry.weight, 'kg')}  •  ${entry.caloriesConsumed?.round() ?? '--'} kcal\nWater ${_value(entry.waterIntake, 'L')}'),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => DailyProgressScreen(
                      progressService: _service,
                      initialEntry: entry))).then((_) => _load()),
        ),
      );
}
