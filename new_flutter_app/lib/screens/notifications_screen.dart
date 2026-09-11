import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/notification.dart' as notification_model;
import '../services/api_client.dart';
import '../services/notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  final NotificationService notificationService;

  const NotificationsScreen({super.key, required this.notificationService});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<notification_model.Notification> _notifications = [];
  bool _unreadOnly = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final notifications = await widget.notificationService
          .getNotifications(unreadOnly: _unreadOnly);
      if (!mounted) return;
      setState(() => _notifications = notifications);
      await widget.notificationService.refreshUnreadCount();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAsRead(notification_model.Notification notification) async {
    if (notification.isRead) return;
    try {
      final updated =
          await widget.notificationService.markAsRead(notification.id);
      if (!mounted) return;
      setState(() {
        _notifications = _notifications
            .map((item) => item.id == updated.id ? updated : item)
            .toList();
      });
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('All')),
                ButtonSegment(value: true, label: Text('Unread')),
              ],
              selected: {_unreadOnly},
              onSelectionChanged: (selection) {
                setState(() => _unreadOnly = selection.first);
                _loadNotifications();
              },
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppTheme.primary,
              backgroundColor: AppTheme.surface,
              onRefresh: _loadNotifications,
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading && _notifications.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _notifications.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: 220, child: Center(child: Text(_error!))),
        ],
      );
    }
    if (_notifications.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 220),
          Icon(Icons.notifications_none_rounded,
              size: 56, color: AppTheme.textSecondary),
          SizedBox(height: 12),
          Center(child: Text('No notifications yet')),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      itemCount: _notifications.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, index) {
        final notification = _notifications[index];
        return Dismissible(
          key: ValueKey(notification.id),
          direction: notification.isRead
              ? DismissDirection.none
              : DismissDirection.endToStart,
          confirmDismiss: (_) async {
            await _markAsRead(notification);
            return false;
          },
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.done_rounded, color: AppTheme.success),
          ),
          child: _NotificationCard(notification: notification),
        );
      },
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final notification_model.Notification notification;

  const _NotificationCard({required this.notification});

  @override
  Widget build(BuildContext context) {
    final icon = _typeIcon(notification.type);
    final priorityColor = switch (notification.priority) {
      'high' => const Color(0xFFFF4444),
      'low' => const Color(0xFF64748B),
      _ => AppTheme.primary,
    };
    return Container(
      decoration: BoxDecoration(
        color: notification.isRead ? AppTheme.surface : const Color(0xFF253347),
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: priorityColor, width: 4)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 25)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                      child: Text(notification.title,
                          style: Theme.of(context).textTheme.titleMedium)),
                  if (!notification.isRead)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: CircleAvatar(
                          radius: 4, backgroundColor: Colors.lightBlueAccent),
                    ),
                ]),
                const SizedBox(height: 5),
                Text(notification.message,
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 9),
                Text(_relativeTime(notification.createdAt),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _typeIcon(String type) => switch (type) {
        'workout_reminder' => '🏋️',
        'meal_reminder' => '🍽️',
        'water_intake_reminder' => '💧',
        'motivation' => '🔥',
        'weekly_progress_reminder' => '📊',
        _ => '🔔',
      };

  String _relativeTime(DateTime date) {
    final difference = DateTime.now().difference(date.toLocal());
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes} minutes ago';
    if (difference.inDays < 1) return '${difference.inHours} hours ago';
    if (difference.inDays < 7) return '${difference.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}
