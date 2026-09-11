import 'package:flutter/material.dart';

import '../core/theme.dart';

class MacroSummary {
  final double calories;
  final double protein;
  final double carbs;
  final double fat;

  const MacroSummary({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  String get asText => 'Macro Summary\nCalories: ${calories.round()} kcal\n'
      'Protein: ${protein.toStringAsFixed(1)} g\n'
      'Carbs: ${carbs.toStringAsFixed(1)} g\n'
      'Fat: ${fat.toStringAsFixed(1)} g';
}

class TypingBubble extends StatefulWidget {
  const TypingBubble({super.key});

  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: FadeTransition(
            opacity: Tween<double>(begin: .35, end: 1).animate(_controller),
            child: const Text('AI Coach is typing...'),
          ),
        ),
      );
}

class MacroRatioBar extends StatelessWidget {
  final MacroSummary summary;

  const MacroRatioBar({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final total = summary.protein + summary.carbs + summary.fat;
    if (total <= 0) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Row(
        children: [
          Expanded(
            flex: (summary.protein / total * 100).round().clamp(1, 100).toInt(),
            child: Container(height: 8, color: Colors.blue),
          ),
          Expanded(
            flex: (summary.carbs / total * 100).round().clamp(1, 100).toInt(),
            child: Container(height: 8, color: Colors.orange),
          ),
          Expanded(
            flex: (summary.fat / total * 100).round().clamp(1, 100).toInt(),
            child: Container(height: 8, color: Colors.redAccent),
          ),
        ],
      ),
    );
  }
}
