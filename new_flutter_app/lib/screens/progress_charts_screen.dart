import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/api_client.dart';
import '../services/progress_service.dart';

class ProgressChartsScreen extends StatefulWidget {
  final ProgressService? progressService;
  const ProgressChartsScreen({super.key, this.progressService});
  @override
  State<ProgressChartsScreen> createState() => _ProgressChartsScreenState();
}

class _ProgressChartsScreenState extends State<ProgressChartsScreen> {
  late final ProgressService _service;
  int _days = 30;
  List<Map<String, dynamic>> _weights = [], _calories = [];
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
      final results = await Future.wait([
        _service.getWeightChartData(days: _days),
        _service.getCaloriesChartData(days: _days)
      ]);
      _weights = results[0];
      _calories = results[1];
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.message), backgroundColor: AppTheme.error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<FlSpot> _spots(List<Map<String, dynamic>> data, String key) =>
      List.generate(data.length, (index) {
        final value = data[index][key] ?? data[index]['value'] ?? 0;
        final number =
            value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
        return FlSpot(index.toDouble(), number);
      });
  LineChartData _chart(List<FlSpot> spots) => LineChartData(
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineBarsData: [
          LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppTheme.primary,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                  show: true, color: AppTheme.primary.withValues(alpha: .12)))
        ],
      );
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Progress Charts')),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 7, label: Text('7d')),
                  ButtonSegment(value: 14, label: Text('14d')),
                  ButtonSegment(value: 30, label: Text('30d')),
                  ButtonSegment(value: 90, label: Text('90d'))
                ],
                selected: {
                  _days
                },
                onSelectionChanged: (value) {
                  setState(() => _days = value.first);
                  _load();
                })),
        Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(padding: const EdgeInsets.all(16), children: [
                    if (_weights.isEmpty && _calories.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'No progress logged yet. Log your first day above to unlock history charts!',
                          ),
                        ),
                      )
                    else ...[
                      _chartCard(
                          'Weight trend', 'kg', _spots(_weights, 'weight')),
                      const SizedBox(height: 16),
                      _chartCard('Calories consumed', 'kcal',
                          _spots(_calories, 'calories')),
                    ]
                  ]))
      ]));
  Widget _chartCard(String title, String unit, List<FlSpot> spots) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text('Last $_days days • $unit',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 20),
            SizedBox(
                height: 190,
                child: spots.isEmpty
                    ? const Center(child: Text('No chart data yet.'))
                    : LineChart(_chart(spots)))
          ])));
}
