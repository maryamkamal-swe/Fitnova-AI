import 'package:flutter/material.dart';

import '../core/theme.dart';

class FitNovaCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const FitNovaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(padding: padding, child: child),
      );
}

class FitNovaBadge extends StatelessWidget {
  final String label;
  final Color? color;
  const FitNovaBadge({super.key, required this.label, this.color});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: (color ?? AppTheme.primary).withValues(alpha: .16),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              color: color ?? AppTheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
}

class FitNovaProgressRing extends StatelessWidget {
  final double value;
  final String? label;
  const FitNovaProgressRing({super.key, required this.value, this.label});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 72,
        height: 72,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: value.clamp(0, 1),
              strokeWidth: 7,
              backgroundColor: AppTheme.surfaceVariant,
            ),
            Text(label ?? '${(value * 100).round()}%'),
          ],
        ),
      );
}

class FitNovaProgressBar extends StatelessWidget {
  final double value;
  const FitNovaProgressBar({super.key, required this.value});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: value.clamp(0, 1),
          minHeight: 8,
          backgroundColor: AppTheme.surfaceVariant,
        ),
      );
}

class FitNovaMacroCardGauge extends StatelessWidget {
  final String label;
  final String value;
  final double progress;
  final Color? color;
  const FitNovaMacroCardGauge({
    super.key,
    required this.label,
    required this.value,
    required this.progress,
    this.color,
  });

  @override
  Widget build(BuildContext context) => FitNovaCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            FitNovaProgressBar(value: progress),
          ],
        ),
      );
}

class FitNovaAccentSwitcher extends StatelessWidget {
  const FitNovaAccentSwitcher({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AccentTheme>(
        valueListenable: AppTheme.accent,
        builder: (_, selected, __) => SegmentedButton<AccentTheme>(
          segments: const [
            ButtonSegment(value: AccentTheme.babyBlue, label: Text('Blue')),
            ButtonSegment(value: AccentTheme.lightPink, label: Text('Pink')),
            ButtonSegment(value: AccentTheme.lime, label: Text('Lime')),
          ],
          selected: {selected},
          onSelectionChanged: (value) =>
              AppTheme.accent.value = value.first,
        ),
      );
}
