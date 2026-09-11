import 'package:flutter/material.dart';

import '../models/meal_plan.dart';
import '../services/meal_plan_service.dart';
import '../widgets/design_system.dart';

class MealPreparationScreen extends StatefulWidget {
  final MealPlanItem meal;
  const MealPreparationScreen({super.key, required this.meal});

  @override
  State<MealPreparationScreen> createState() => _MealPreparationScreenState();
}

class _MealPreparationScreenState extends State<MealPreparationScreen> {
  final MealPlanService _mealPlanService = MealPlanService();
  bool _prepared = false;
  final _steps = <String>[
    'Gather ingredients and measure the portions.',
    'Prepare the ingredients using your preferred method.',
    'Plate, enjoy, and log the meal when finished.',
  ];
  final Set<int> _done = {};

  Future<void> _savePreparationState() async {
    try {
      await _mealPlanService.logRecipePreparation(
        widget.meal.foodName,
        _done.toList(),
        10,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Meal preparation')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(widget.meal.foodName,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('${widget.meal.portionGrams.round()} g portion',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 20),
            const FitNovaBadge(label: 'Personalized recipe'),
            const SizedBox(height: 18),
            const Text('Preparation steps',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ..._steps.asMap().entries.map((entry) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _done.contains(entry.key),
                  title: Text(entry.value),
                  onChanged: (_) {
                    setState(() {
                      if (_done.contains(entry.key)) {
                        _done.remove(entry.key);
                      } else {
                        _done.add(entry.key);
                      }
                    });
                    _savePreparationState();
                  },
                )),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _done.length == _steps.length
                  ? () {
                      setState(() => _prepared = true);
                      _savePreparationState();
                    }
                  : null,
              child: Text(_prepared ? 'Meal prepared' : 'Mark as prepared'),
            ),
          ],
        ),
      );
}
