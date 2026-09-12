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
  bool _savingFood = false;
  String? _errorMessage;

  double get _calories =>
      _todayProgress?.caloriesConsumed ??
      _foods.fold<double>(0.0, (total, food) => total + food.calories);

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
      final localDate = _dateOnly(DateTime.now());
      final todayProgress = await _progressService.getTodayProgress();
      final foods = await _mealPlanService.getFoodLogs(date: localDate);
      MealPlan? mealPlan;
      try {
        mealPlan = await _mealPlanService.getCurrent();
      } on ApiException catch (error) {
        if (error.statusCode != 404) rethrow;
      }
      if (!mounted) return;
      setState(() {
        _todayProgress = todayProgress;
        _foods
          ..clear()
          ..addAll(foods.map(_foodFromJson));
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
      await _saveFood(result);
    }
  }

  Future<void> _saveFood(_FoodEntry food) async {
    if (_savingFood) return;
    setState(() {
      _savingFood = true;
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await _mealPlanService.logFoodEntry(
        food.name,
        food.calories,
        meal: food.meal,
        date: _dateOnly(DateTime.now()),
      );
      if (mounted) {
        final progress = response['progress'];
        final foods = response['foods'];
        setState(() {
          _todayProgress = progress is Map<String, dynamic>
              ? ProgressEntry.fromJson(progress)
              : _todayProgress;
          _foods
            ..clear()
            ..addAll(foods is List
                ? foods
                    .whereType<Map<String, dynamic>>()
                    .map(_foodFromJson)
                : <_FoodEntry>[]);
          _isLoading = false;
          _savingFood = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to save food entry';
          _isLoading = false;
          _savingFood = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save food entry.')),
        );
      }
    }

  }

  _FoodEntry _foodFromJson(Map<String, dynamic> json) => _FoodEntry(
        (json['food_name'] ?? json['name'] ?? 'Food').toString(),
        (json['meal_type'] ?? 'Snack').toString(),
        (json['calories'] as num?)?.round() ?? 0,
      );

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

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
              onPressed: _savingFood ? null : _addFood,
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