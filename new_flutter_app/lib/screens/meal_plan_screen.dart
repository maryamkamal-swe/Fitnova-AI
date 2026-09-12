import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../core/utils/string_utils.dart';
import '../models/meal_plan.dart';
import '../services/api_client.dart';
import '../services/meal_plan_service.dart';

class MealPlanScreen extends StatefulWidget {
  final MealPlanService? mealPlanService;

  const MealPlanScreen({super.key, this.mealPlanService});

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen> {
  late final MealPlanService _service;
  MealPlan? _plan;
  bool _loading = true;
  String _cuisine = 'desi';

  @override
  void initState() {
    super.initState();
    _service = widget.mealPlanService ?? MealPlanService();
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
      final plan = await _service.generate(cuisine: _cuisine);
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
        title: const Text('Nutrition & Meals'),
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
          Text('AI Meal Plan',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            plan?.plan.weeklySummary ??
                'Generate a personalized weekly meal plan from your profile.',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _cuisine,
                decoration: const InputDecoration(labelText: 'Cuisine'),
                items: const [
                  DropdownMenuItem(value: 'desi', child: Text('Desi')),
                  DropdownMenuItem(
                      value: 'international', child: Text('International')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _cuisine = value);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _generate,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Generate'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
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
          if (plan != null) ...[
            const SizedBox(height: 16),
            Text('${plan.dailyCalorieTarget.round()} kcal/day',
                style: Theme.of(context).textTheme.titleLarge),
            ...plan.plan.days.map(_dayCard),
          ],
          if (plan == null && !_loading)
            Card(
              margin: const EdgeInsets.only(top: 16),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.restaurant_menu, size: 40),
                    const SizedBox(height: 12),
                    const Text(
                      'No meal plan yet',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Generate a personalized plan to see your meals for the week.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      onPressed: _generate,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Generate meal plan'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _copyPlan(MealPlan plan) async {
    final text = plan.plan.days
        .map((day) => '${day.dayLabel}\n${[
              ...day.breakfast,
              ...day.lunch,
              ...day.dinner,
              ...day.snacks,
            ].map((item) => '- ${item.foodName}: ${item.portionGrams.round()} g').join('\n')}')
        .join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan copied to clipboard')),
      );
    }
  }

  Widget _dayCard(MealPlanDay day) {
    final items = [
      ...day.breakfast,
      ...day.lunch,
      ...day.dinner,
      ...day.snacks
    ];
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: ExpansionTile(
        title: Text(day.dayLabel.toTitleCase()),
        subtitle:
            Text(day.note?.toTitleCase() ?? '${items.length} Planned Items'),
        children: items
            .map((item) => ListTile(
                  title: Text(item.foodName.toTitleCase()),
                  subtitle: Text('${item.portionGrams.round()} g'),
                  trailing: item.calories == null
                      ? null
                      : Text('${item.calories!.round()} kcal'),
                ))
            .toList(),
      ),
    );
  }
}
