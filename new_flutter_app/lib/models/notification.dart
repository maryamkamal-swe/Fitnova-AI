/// Notification delivered to the authenticated FitNova user.
class Notification {
  final String id;
  final String userId;
  final String type;
  final String title;
  final String message;
  final String channel;
  final String priority;
  final bool isRead;
  final DateTime? scheduledFor;
  final DateTime createdAt;

  const Notification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.message,
    required this.channel,
    required this.priority,
    required this.isRead,
    this.scheduledFor,
    required this.createdAt,
  });

  factory Notification.fromJson(Map<String, dynamic> json) {
    final data = json['notification'] is Map<String, dynamic>
        ? json['notification'] as Map<String, dynamic>
        : json;
    final createdAt =
        DateTime.tryParse('${data['created_at'] ?? data['createdAt'] ?? ''}') ??
            DateTime.now();

    return Notification(
      id: '${data['id'] ?? data['_id'] ?? ''}',
      userId: '${data['user_id'] ?? data['userId'] ?? ''}',
      type: '${data['type'] ?? 'motivation'}',
      title: '${data['title'] ?? ''}',
      message: '${data['message'] ?? ''}',
      channel: '${data['channel'] ?? 'in_app'}',
      priority: '${data['priority'] ?? 'normal'}',
      isRead: data['is_read'] as bool? ?? data['isRead'] as bool? ?? false,
      scheduledFor: _parseDate(data['scheduled_for'] ?? data['scheduledFor']),
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'title': title,
        'message': message,
        if (scheduledFor != null)
          'scheduled_for': scheduledFor!.toIso8601String(),
        'channel': channel,
        'priority': priority,
      };

  Notification copyWith({bool? isRead}) => Notification(
        id: id,
        userId: userId,
        type: type,
        title: title,
        message: message,
        channel: channel,
        priority: priority,
        isRead: isRead ?? this.isRead,
        scheduledFor: scheduledFor,
        createdAt: createdAt,
      );

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
