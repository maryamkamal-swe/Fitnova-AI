import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';
import '../core/utils/string_utils.dart';
import 'onboarding/app_walkthrough_screen.dart';

class DashboardTourStep {
  const DashboardTourStep({
    required this.title,
    required this.body,
    required this.tabIndex,
  });

  final String title;
  final String body;
  final int tabIndex;
}

const dashboardTourSteps = [
  DashboardTourStep(
    title: 'Your Home Dashboard',
    body:
        'Quick actions live here: Hydration, Log Food, and Log Today. Start with logging once you have eaten or trained.',
    tabIndex: 0,
  ),
  DashboardTourStep(
    title: 'Generate A Workout',
    body:
        'Open Workouts and tap Generate Workout. This works from your profile defaults even if the exercise library is empty.',
    tabIndex: 1,
  ),
  DashboardTourStep(
    title: 'Generate A Meal Plan',
    body:
        'Open Meals and tap Generate. Staple foods such as rice, daal, chicken, eggs, and oats are used if the food library is empty.',
    tabIndex: 2,
  ),
  DashboardTourStep(
    title: 'Log Daily Progress',
    body:
        'Use Progress → Log Today for calorie intake, workout completion, and water. Charts stay empty until you save your first day.',
    tabIndex: 3,
  ),
  DashboardTourStep(
    title: 'AI Coach & Family Daal',
    body:
        'Coach answers training questions and can estimate family daal portions. Try it after you have a meal plan.',
    tabIndex: 4,
  ),
  DashboardTourStep(
    title: 'Profile & Preferences',
    body:
        'Keep your name, goal, and experience updated here. Title-case labels are display-only; API values stay unchanged.',
    tabIndex: 5,
  ),
];

class DashboardTourOverlay extends StatelessWidget {
  final int stepIndex;
  final VoidCallback onNext;
  final VoidCallback onFinished;

  const DashboardTourOverlay({
    super.key,
    required this.stepIndex,
    required this.onNext,
    required this.onFinished,
  });

  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(dashboardTourCompletedKey) ?? false);
  }

  static Future<void> markComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(dashboardTourCompletedKey, true);
  }

  DashboardTourStep get step => dashboardTourSteps[stepIndex];

  Future<void> _complete() async {
    await markComplete();
    onFinished();
  }

  void _next() {
    if (stepIndex >= dashboardTourSteps.length - 1) {
      _complete();
      return;
    }
    onNext();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.62),
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              color: AppTheme.surface,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Step ${stepIndex + 1} of ${dashboardTourSteps.length}',
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Text(step.title.toTitleCase(),
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(step.body,
                        style: const TextStyle(color: AppTheme.textSecondary)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        TextButton(
                          onPressed: _complete,
                          child: const Text('Got It!'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: _next,
                          child: Text(stepIndex == dashboardTourSteps.length - 1
                              ? 'Finish'
                              : 'Next'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
