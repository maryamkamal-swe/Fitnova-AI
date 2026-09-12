// new_flutter_app/integration_test/app_e2e_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fitnova_app/app.dart';
import 'package:fitnova_app/services/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Clear storage before tests
    await TokenStorage().deleteToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  });

  testWidgets('E2E App Navigation and Login Flow', (tester) async {
    await tester.pumpWidget(const FitNovaApp());
    // Wait for splash/loading
    await tester.pumpAndSettle();

    // Verify we are on the Login screen
    expect(find.text('Sign in to continue your fitness journey with FitNova AI'), findsOneWidget);

    // Switch to Register Tab
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();
    expect(find.text('Create Account'), findsOneWidget);

    // Enter details using robust indexed finding instead of text match for Form fields
    final textFields = find.byType(TextFormField);
    
    // Full Name
    await tester.enterText(textFields.at(0), 'E2E Tester');
    
    // Email Address
    await tester.enterText(textFields.at(1), 'e2e@example.com');
    
    // Password
    await tester.enterText(textFields.at(2), 'Test1234!');
    
    // Confirm Password
    await tester.enterText(textFields.at(3), 'Test1234!');
    
    // NOTE: In a true E2E, pressing "Create Account" here will hit the live API_BASE_URL.
    // Ensure you point API_BASE_URL to localhost:8000.
    // await tester.tap(find.text('Create Account'));
    // await tester.pumpAndSettle();
  });
}