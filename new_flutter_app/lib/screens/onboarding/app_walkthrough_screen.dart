import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';

const onboardingCompletedKey = 'onboarding_completed';
const dashboardTourCompletedKey = 'dashboard_tour_completed';

class AppWalkthroughScreen extends StatefulWidget {
  final VoidCallback onFinished;

  const AppWalkthroughScreen({super.key, required this.onFinished});

  @override
  State<AppWalkthroughScreen> createState() => _AppWalkthroughScreenState();
}

class _AppWalkthroughScreenState extends State<AppWalkthroughScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _cards = [
    (
      icon: Icons.auto_awesome,
      title: 'AI Coach & Family Daal Estimator',
      body:
          'Ask the Coach tab for training advice, or estimate a family daal serving before you cook.',
    ),
    (
      icon: Icons.restaurant_menu,
      title: 'Personalized Meal & Workout Plans',
      body:
          'Generate weekly meals and workouts from your profile. Plans still work with staple defaults if the food or exercise library is empty.',
    ),
    (
      icon: Icons.water_drop_outlined,
      title: 'Daily Progress & Hydration Tracking',
      body:
          'Log calorie intake, workouts, water, and sleep from Home or Progress so charts can unlock.',
    ),
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(onboardingCompletedKey, true);
    if (!mounted) return;
    widget.onFinished();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child:
                    TextButton(onPressed: _finish, child: const Text('Skip')),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _cards.length,
                  onPageChanged: (index) => setState(() => _page = index),
                  itemBuilder: (_, index) {
                    final card = _cards[index];
                    return Card(
                      color: AppTheme.surface,
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(card.icon, size: 64, color: AppTheme.primary),
                            const SizedBox(height: 28),
                            Text(
                              card.title,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              card.body,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _cards.length,
                  (index) => Container(
                    width: _page == index ? 22 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: _page == index
                          ? AppTheme.primary
                          : AppTheme.borderStrong,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    if (_page == _cards.length - 1) {
                      _finish();
                    } else {
                      _controller.nextPage(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                  child: Text(_page == _cards.length - 1
                      ? 'Start using FitNova'
                      : 'Next'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
