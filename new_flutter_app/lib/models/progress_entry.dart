class ProgressEntry {
  final String? id;
  final String? userId;
  final DateTime date;
  final DateTime? createdAt;
  final double? weight;
  final bool workoutCompleted;
  final double? caloriesConsumed;
  final double? caloriesBurned;
  final double? waterIntake;
  final double? sleepHours;
  final int? steps;
  final int? activeMinutes;
  final double? goalCompletion;
  final String? notes;

  const ProgressEntry({
    this.id,
    this.userId,
    required this.date,
    this.createdAt,
    this.weight,
    this.workoutCompleted = false,
    this.caloriesConsumed,
    this.caloriesBurned,
    this.waterIntake,
    this.sleepHours,
    this.steps,
    this.activeMinutes,
    this.goalCompletion,
    this.notes,
  });

  factory ProgressEntry.fromJson(Map<String, dynamic> json) {
    final dateValue = json['date'] ?? json['logged_date'];
    return ProgressEntry(
      id: (json['id'] ?? json['_id'])?.toString(),
      userId: json['user_id']?.toString() ?? json['userId']?.toString(),
      date: DateTime.tryParse('$dateValue') ?? DateTime.now(),
      createdAt: _dateTime(json['created_at'] ?? json['createdAt']),
      weight: _double(json['weight']),
      workoutCompleted: json['workout_completed'] as bool? ??
          json['workoutCompleted'] as bool? ??
          false,
      caloriesConsumed: _double(
          json['calories_consumed'] ?? json['calories'] ?? json['caloriesConsumed']),
      caloriesBurned:
          _double(json['calories_burned'] ?? json['caloriesBurned']),
      waterIntake: _double(json['water_intake'] ?? json['waterIntake']),
      sleepHours: _double(json['sleep_hours'] ?? json['sleepHours']),
      steps: _int(json['steps']),
      activeMinutes: _int(json['active_minutes'] ?? json['activeMinutes']),
      goalCompletion:
          _double(json['goal_completion'] ?? json['goalCompletion']),
      notes: json['notes']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    final consumed = caloriesConsumed;
    final burned = caloriesBurned;
    final note = notes;
    return {
      'date': _dateOnly(date),
      if (weight != null) 'weight': weight,
      'workout_completed': workoutCompleted,
      if (consumed != null) 'calories_consumed': consumed.round(),
      if (burned != null) 'calories_burned': burned.round(),
      if (waterIntake != null) 'water_intake': waterIntake,
      if (sleepHours != null) 'sleep_hours': sleepHours,
      if (steps != null) 'steps': steps,
      if (activeMinutes != null) 'active_minutes': activeMinutes,
      if (goalCompletion != null) 'goal_completion': goalCompletion,
      if (note != null && note.trim().isNotEmpty) 'notes': note,
    };
  }

  ProgressEntry copyWith({
    String? id,
    DateTime? date,
    double? weight,
    bool? workoutCompleted,
    double? caloriesConsumed,
    double? caloriesBurned,
    double? waterIntake,
    double? sleepHours,
    int? steps,
    int? activeMinutes,
    double? goalCompletion,
    String? notes,
  }) =>
      ProgressEntry(
        id: id ?? this.id,
        userId: userId,
        date: date ?? this.date,
        createdAt: createdAt,
        weight: weight ?? this.weight,
        workoutCompleted: workoutCompleted ?? this.workoutCompleted,
        caloriesConsumed: caloriesConsumed ?? this.caloriesConsumed,
        caloriesBurned: caloriesBurned ?? this.caloriesBurned,
        waterIntake: waterIntake ?? this.waterIntake,
        sleepHours: sleepHours ?? this.sleepHours,
        steps: steps ?? this.steps,
        activeMinutes: activeMinutes ?? this.activeMinutes,
        goalCompletion: goalCompletion ?? this.goalCompletion,
        notes: notes ?? this.notes,
      );

  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static double? _double(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  static int? _int(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }

  static DateTime? _dateTime(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString());
}
