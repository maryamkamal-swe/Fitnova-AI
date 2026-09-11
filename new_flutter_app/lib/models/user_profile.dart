/// Model representing the user's fitness profile.
class UserProfile {
  static const double defaultHydrationGoal = 2.5;

  final String name;
  final int age;
  final String gender;
  final double height;
  final double weight;
  final String fitnessGoal;
  final String activityLevel;
  final String fitnessExperience;
  final List<String> dietaryPreferences;
  final List<String> medicalConditions;
  final bool profileComplete;

  double get hydrationGoal =>
      weight > 0 ? weight * 0.035 : defaultHydrationGoal;

  const UserProfile({
    required this.name,
    this.age = 18,
    this.gender = 'other',
    this.height = 170,
    this.weight = 70,
    this.fitnessGoal = 'maintenance',
    this.activityLevel = 'moderate',
    this.fitnessExperience = 'beginner',
    this.dietaryPreferences = const [],
    this.medicalConditions = const [],
    this.profileComplete = false,
  });

  /// Factory constructor to safely parse UserProfile from top-level or wrapped JSON.
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    // Support nested 'profile' wrapper or 'user' wrapper if returned by backend
    final Map<String, dynamic> data = (json['profile'] is Map<String, dynamic>)
        ? json['profile'] as Map<String, dynamic>
        : (json['user'] is Map<String, dynamic> &&
                json['user']['profile'] is Map<String, dynamic>)
            ? json['user']['profile'] as Map<String, dynamic>
            : json;

    return UserProfile(
      name: (data['name'] ?? json['name'] ?? '').toString(),
      age: (data['age'] as num?)?.toInt() ?? 18,
      gender: (data['gender'] ?? 'other').toString(),
      height: (data['height'] as num?)?.toDouble() ?? 170,
      weight: (data['weight'] as num?)?.toDouble() ?? 70,
      fitnessGoal:
          (data['fitness_goal'] ?? data['fitnessGoal'] ?? 'maintenance')
              .toString(),
      activityLevel:
          (data['activity_level'] ?? data['activityLevel'] ?? 'moderate')
              .toString(),
      fitnessExperience:
          (data['fitness_experience'] ?? data['fitnessExperience'] ?? 'beginner')
              .toString(),
      dietaryPreferences: (data['dietary_preferences'] is List)
          ? List<String>.from(
              (data['dietary_preferences'] as List).map((e) => e.toString()))
          : (data['dietaryPreferences'] is List)
              ? List<String>.from(
                  (data['dietaryPreferences'] as List).map((e) => e.toString()))
              : const [],
      medicalConditions: (data['medical_conditions'] is List)
          ? List<String>.from(
              (data['medical_conditions'] as List).map((e) => e.toString()))
          : (data['medicalConditions'] is List)
              ? List<String>.from(
                  (data['medicalConditions'] as List).map((e) => e.toString()))
              : const [],
      profileComplete: (json['profile_complete'] as bool?) ??
          (data['age'] != null &&
              data['gender'] != null &&
              data['height'] != null &&
              data['weight'] != null &&
              data['fitness_goal'] != null &&
              data['activity_level'] != null &&
              data['fitness_experience'] != null),
    );
  }

  /// Converts the profile model into JSON matching backend schema.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'age': age,
      'gender': gender,
      'height': height,
      'weight': weight,
      'fitness_goal': fitnessGoal,
      'activity_level': activityLevel,
      'fitness_experience': fitnessExperience,
      'dietary_preferences': dietaryPreferences,
      'medical_conditions': medicalConditions,
    };
  }

  /// Creates a copy with specified fields modified.
  UserProfile copyWith({
    String? name,
    int? age,
    String? gender,
    double? height,
    double? weight,
    String? fitnessGoal,
    String? activityLevel,
    String? fitnessExperience,
    List<String>? dietaryPreferences,
    List<String>? medicalConditions,
    bool? profileComplete,
  }) {
    return UserProfile(
      name: name ?? this.name,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      height: height ?? this.height,
      weight: weight ?? this.weight,
      fitnessGoal: fitnessGoal ?? this.fitnessGoal,
      activityLevel: activityLevel ?? this.activityLevel,
      fitnessExperience: fitnessExperience ?? this.fitnessExperience,
      dietaryPreferences: dietaryPreferences ?? this.dietaryPreferences,
      medicalConditions: medicalConditions ?? this.medicalConditions,
      profileComplete: profileComplete ?? this.profileComplete,
    );
  }
}

class HealthMetrics {
  final double? bmi;
  final String? bmiCategory;
  final double? bmr;
  final double? tdee;

  const HealthMetrics({this.bmi, this.bmiCategory, this.bmr, this.tdee});

  factory HealthMetrics.fromJson(Map<String, dynamic> json) {
    return HealthMetrics(
      bmi: _number(json['bmi']),
      bmiCategory: (json['bmi_category'] ?? json['bmiCategory'])?.toString(),
      bmr: _number(json['bmr']),
      tdee: _number(json['tdee']),
    );
  }

  static double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }
}
