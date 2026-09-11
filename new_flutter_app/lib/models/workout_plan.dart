class PlannedExercise {
  final String exerciseId;
  final String exerciseName;
  final int sets;
  final String reps;
  final int restSeconds;
  final String? coachingNote;

  const PlannedExercise({
    required this.exerciseId,
    required this.exerciseName,
    required this.sets,
    required this.reps,
    required this.restSeconds,
    this.coachingNote,
  });

  factory PlannedExercise.fromJson(Map<String, dynamic> json) =>
      PlannedExercise(
        exerciseId:
            (json['exercise_id'] ?? json['exerciseId'] ?? '').toString(),
        exerciseName:
            (json['exercise_name'] ?? json['exerciseName'] ?? 'Exercise')
                .toString(),
        sets: _int(json['sets']),
        reps: (json['reps'] ?? '').toString(),
        restSeconds: _int(json['rest_seconds'] ?? json['restSeconds']),
        coachingNote: json['coaching_note']?.toString() ??
            json['coachingNote']?.toString(),
      );
}

class WorkoutDay {
  final String dayLabel;
  final String focus;
  final List<PlannedExercise> exercises;

  const WorkoutDay({
    required this.dayLabel,
    required this.focus,
    this.exercises = const [],
  });

  factory WorkoutDay.fromJson(Map<String, dynamic> json) => WorkoutDay(
        dayLabel:
            (json['day_label'] ?? json['dayLabel'] ?? 'Workout').toString(),
        focus: (json['focus'] ?? '').toString(),
        exercises:
            _maps(json['exercises']).map(PlannedExercise.fromJson).toList(),
      );
}

class WeeklyWorkoutPlan {
  final List<WorkoutDay> days;
  final String weeklySummary;

  const WeeklyWorkoutPlan({this.days = const [], this.weeklySummary = ''});

  factory WeeklyWorkoutPlan.fromJson(Map<String, dynamic> json) =>
      WeeklyWorkoutPlan(
        days: _maps(json['days']).map(WorkoutDay.fromJson).toList(),
        weeklySummary:
            (json['weekly_summary'] ?? json['weeklySummary'] ?? '').toString(),
      );
}

class WorkoutPlan {
  final String userId;
  final WeeklyWorkoutPlan plan;
  final String generatedAt;
  final String source;

  const WorkoutPlan({
    required this.userId,
    required this.plan,
    required this.generatedAt,
    required this.source,
  });

  factory WorkoutPlan.fromJson(Map<String, dynamic> json) => WorkoutPlan(
        userId: (json['user_id'] ?? json['userId'] ?? '').toString(),
        plan: WeeklyWorkoutPlan.fromJson(json['plan'] is Map<String, dynamic>
            ? json['plan'] as Map<String, dynamic>
            : const {}),
        generatedAt:
            (json['generated_at'] ?? json['generatedAt'] ?? '').toString(),
        source: (json['source'] ?? '').toString(),
      );
}

int _int(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

List<Map<String, dynamic>> _maps(dynamic value) => value is List
    ? value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList()
    : const [];
