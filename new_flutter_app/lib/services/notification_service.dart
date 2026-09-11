import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../models/notification.dart';
import 'api_client.dart';

class NotificationService extends ChangeNotifier {
  final ApiClient _apiClient;
  int _unreadCount = 0;

  NotificationService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  int get unreadCount => _unreadCount;

  Future<int> refreshUnreadCount() async {
    final notifications = await getUnreadNotifications();
    _unreadCount = notifications.length;
    notifyListeners();
    return _unreadCount;
  }

  Future<List<Notification>> getNotifications({
    bool unreadOnly = false,
    int limit = 20,
  }) async {
    final response = await _apiClient.get(
      AppConstants.notificationsEndpoint,
      requiresAuth: true,
      queryParameters: {'unread_only': unreadOnly, 'limit': limit},
    );
    return _parseList(response);
  }

  Future<List<Notification>> getUnreadNotifications() async {
    final response = await _apiClient.get(
      AppConstants.unreadNotificationsEndpoint,
      requiresAuth: true,
    );
    return _parseList(response);
  }

  Future<Notification> markAsRead(String id) async {
    final response = await _apiClient.patch(
      '${AppConstants.notificationsEndpoint}/$id/read',
      requiresAuth: true,
    );
    final notification = _fromResponse(response);
    if (_unreadCount > 0) _unreadCount--;
    notifyListeners();
    return notification;
  }

  Future<Notification> createNotification(Notification notification) async {
    final response = await _apiClient.post(
      AppConstants.notificationsEndpoint,
      body: notification.toJson(),
      requiresAuth: true,
    );
    final created = _fromResponse(response);
    if (!created.isRead) _unreadCount++;
    notifyListeners();
    return created;
  }

  Future<Notification> createSmartNotification(
    String type, {
    String? title,
    String? message,
    String channel = 'in_app',
    String priority = 'normal',
  }) async {
    final response = await _apiClient.post(
      '${AppConstants.notificationsEndpoint}/smart',
      requiresAuth: true,
      queryParameters: {
        'notification_type': type,
        if (title != null) 'title': title,
        if (message != null) 'message': message,
        'channel': channel,
        'priority': priority,
      },
    );
    final created = _fromResponse(response);
    if (!created.isRead) _unreadCount++;
    notifyListeners();
    return created;
  }

  Future<Notification> notifyWorkoutCompleted() {
    const messages = [
      'Great job! You showed up and got it done.',
      'You are crushing it! Keep that momentum going.',
      'Beast mode unlocked. Your consistency is paying off.',
      'Strong finish! Take a moment to celebrate this win.',
      'Another workout in the books. Future you will thank you.',
      'That is how progress is made, one session at a time.',
      'You brought the energy today. Recovery well earned.',
      'Workout complete. Your dedication is showing.',
      'You made it happen today. Keep building the habit.',
      'Powerful work. You are closer to your goal than yesterday.',
    ];
    final message = messages[Random().nextInt(messages.length)];
    return createSmartNotification('motivation',
        title: 'Workout complete', message: message);
  }

  Future<Notification> notifyMealLogged({
    required double calories,
    required double dailyGoal,
    bool isCheatMeal = false,
  }) {
    final message = isCheatMeal
        ? 'Cheat meals are part of the journey! Enjoy it mindfully.'
        : calories <= dailyGoal
            ? 'Healthy choice! You are staying aligned with your goal.'
            : 'Enjoy! Balance is key. You can get back on track at your next meal.';
    return createSmartNotification('meal_reminder',
        title: 'Meal logged', message: message);
  }

  Future<Notification> notifyWaterIntake({
    required double currentLiters,
    double dailyGoalLiters = 3,
  }) {
    final progress = currentLiters / dailyGoalLiters;
    final message = progress >= 1
        ? 'Hydration champion! You reached your daily water goal.'
        : progress >= 0.5
            ? 'Almost there! ${(dailyGoalLiters - currentLiters).toStringAsFixed(1)}L to go!'
            : 'Keep sipping! You are at ${currentLiters.toStringAsFixed(1)}L.';
    return createSmartNotification('water_intake_reminder',
        title: 'Hydration check-in', message: message);
  }

  Future<Notification> notifyDailyWorkoutReminder({
    required bool workoutLogged,
  }) {
    final message = workoutLogged
        ? 'Amazing work! Rest and recover.'
        : '10 minutes is better than nothing. You can do this!';
    return createSmartNotification('workout_reminder',
        title: 'Daily check-in', message: message);
  }

  List<Notification> _parseList(dynamic response) {
    final values = response is List
        ? response
        : response is Map<String, dynamic>
            ? (response['items'] ??
                response['data'] ??
                response['notifications'] ??
                [])
            : [];
    return (values as List)
        .whereType<Map<String, dynamic>>()
        .map(Notification.fromJson)
        .toList();
  }

  Notification _fromResponse(dynamic response) {
    if (response is Map<String, dynamic>) {
      return Notification.fromJson(response);
    }
    throw const ApiException(
        message: 'Invalid notification response received.');
  }
}
