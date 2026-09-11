import 'package:flutter/material.dart';
import '../core/theme.dart';

/// User-safe alert dialog for displaying error messages cleanly.
class ErrorDialog extends StatelessWidget {
  final String title;
  final String message;
  final String buttonText;
  final VoidCallback? onDismiss;

  const ErrorDialog({
    super.key,
    this.title = 'Unable to Proceed',
    required this.message,
    this.buttonText = 'OK',
    this.onDismiss,
  });

  /// Static helper to display the ErrorDialog quickly with standard styling.
  static Future<void> show(
    BuildContext context, {
    String title = 'Unable to Proceed',
    required String message,
    String buttonText = 'OK',
  }) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ErrorDialog(
        title: title,
        message: message,
        buttonText: buttonText,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppTheme.border, width: 1),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              color: AppTheme.error,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
      content: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              onDismiss?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.surfaceVariant,
              foregroundColor: AppTheme.textPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(
              buttonText,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
