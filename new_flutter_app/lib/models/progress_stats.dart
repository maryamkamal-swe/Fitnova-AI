class ProgressStats {
  final int workoutStreak;
  final double? avgWeight;
  final double? weightChange;
  final int totalWorkouts;
  final double? avgCalories;
  final double? avgWater;
  final double? avgSleep;
  final double? avgSteps;
  final double? avgActiveMinutes;
  final double? avgGoalCompletion;
  final int totalEntries;

  const ProgressStats({
    this.workoutStreak = 0,
    this.avgWeight,
    this.weightChange,
    this.totalWorkouts = 0,
    this.avgCalories,
    this.avgWater,
    this.avgSleep,
    this.avgSteps,
    this.avgActiveMinutes,
    this.avgGoalCompletion,
    this.totalEntries = 0,
  });

  factory ProgressStats.fromJson(Map<String, dynamic> json) => ProgressStats(
        workoutStreak: _int(json['workout_streak']) ?? 0,
        avgWeight: _double(json['avg_weight']),
        weightChange: _double(json['weight_change']),
        totalWorkouts: _int(json['total_workouts']) ?? 0,
        avgCalories: _double(json['avg_calories']),
        avgWater: _double(json['avg_water_intake']),
        avgSleep: _double(json['avg_sleep_hours']),
        avgSteps: _double(json['avg_steps']),
        avgActiveMinutes: _double(json['avg_active_minutes']),
        avgGoalCompletion: _double(json['goal_completion_rate']),
        totalEntries: _int(json['total_days_tracked']) ?? 0,
      );

  static double? _double(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  static int? _int(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }
}
