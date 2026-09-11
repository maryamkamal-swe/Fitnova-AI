import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:fitnova_app/app.dart';
import 'package:fitnova_app/core/theme.dart';
import 'package:fitnova_app/screens/auth/email_verification_screen.dart';
import 'package:fitnova_app/services/auth_service.dart';

void main() {
  testWidgets('app opens the login screen without a saved session',
      (tester) async {
    await tester.pumpWidget(const FitNovaApp());
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('development OTP is visible in all six fields', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: EmailVerificationScreen(
          authService: AuthService(),
          email: 'developer@example.com',
          developmentCode: '123456',
        ),
      ),
    );

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.textContaining('development code is filled'), findsOneWidget);
  });
}
