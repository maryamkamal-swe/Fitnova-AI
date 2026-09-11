import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/meal_plan.dart';
import '../models/progress_entry.dart';
import '../services/api_client.dart';
import '../services/meal_plan_service.dart';
import '../services/progress_service.dart';
import '../widgets/design_system.dart';

class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key});

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  final List<_FoodEntry> _foods = [];
  final MealPlanService _mealPlanService = MealPlanService();
  final ProgressService _progressService = ProgressService();
  ProgressEntry? _todayProgress;
  double _calorieTarget = 0;
  bool _isLoading = false;
  String? _errorMessage;

  double get _calories =>
      _todayProgress?.caloriesConsumed ??
      _foods.fold(0, (total, food) => total + food.calories);

  @override
  void initState() {
    super.initState();
    _loadNutrition();
  }

  Future<void> _loadNutrition() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final todayProgress = await _progressService.getTodayProgress();
      MealPlan? mealPlan;
      try {
        mealPlan = await _mealPlanService.getCurrent();
      } on ApiException catch (error) {
        if (error.statusCode != 404) rethrow;
      }
      if (!mounted) return;
      setState(() {
        _todayProgress = todayProgress;
        _calorieTarget = mealPlan?.dailyCalorieTarget ?? 0;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load nutrition data';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _addFood() async {
    final name = TextEditingController();
    final calories = TextEditingController();
    final result = await showDialog<_FoodEntry>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add food'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Food name')),
            TextField(
              controller: calories,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Calories'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(calories.text.trim());
              if (name.text.trim().isNotEmpty && value != null) {
                Navigator.pop(
                    context, _FoodEntry(name.text.trim(), 'Snack', value));
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    name.dispose();
    calories.dispose();
    if (result != null) {
      setState(() => _foods.add(result));
      _saveFood(result);
    }
  }

  Future<void> _saveFood(_FoodEntry food) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _mealPlanService.logFoodEntry(
        food.name,
        food.calories,
        meal: food.meal,
      );
      final today = await _progressService.getTodayProgress();
      final total = (today?.caloriesConsumed ?? 0) + food.calories;
      if (today?.id != null && today!.id!.isNotEmpty) {
        await _progressService.updateProgress(
          today.id!,
          today.copyWith(caloriesConsumed: total),
        );
      } else {
        await _progressService.logProgress(
          ProgressEntry(
            date: DateTime.now(),
            caloriesConsumed: total,
          ),
        );
      }
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _foods.remove(food);
          _errorMessage = 'Failed to save food entry';
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save food entry.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Nutrition')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_isLoading) const Center(child: CircularProgressIndicator()),
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Today'),
                  Text(
                      '${_calories.toStringAsFixed(0)} / ${_calorieTarget.toStringAsFixed(0)} kcal',
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (!_isLoading && _todayProgress == null && _foods.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No nutrition entries today. Add your first entry.',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            ..._foods.map((food) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.restaurant_menu,
                        color: AppTheme.primary),
                    title: Text(food.name),
                    subtitle: Text(food.meal),
                    trailing: Text('${food.calories} kcal'),
                  ),
                )),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _addFood,
              icon: const Icon(Icons.add),
              label: const Text('Add food'),
            ),
          ],
        ),
      );
}

class _FoodEntry {
  final String name;
  final String meal;
  final int calories;
  const _FoodEntry(this.name, this.meal, this.calories);
}
