// new_flutter_app/test/components_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fitnova_app/services/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('ApiClient Error Extraction', () {
    test('extracts detailed FastAPI validation errors correctly', () async {
      final client = MockClient((request) async {
        return http.Response(
          '{"detail": [{"loc": ["body", "email"], "msg": "value is not a valid email address", "type": "value_error.email"}]}',
          422,
        );
      });
      
      final apiClient = ApiClient(client: client);
      
      try {
        await apiClient.post('/test');
        fail('Should have thrown an exception');
      } on ApiException catch (e) {
        expect(e.message, 'value is not a valid email address');
        expect(e.statusCode, 422);
      }
    });

    test('extracts fallback messages gracefully on 500 errors', () async {
      final client = MockClient((request) async {
        return http.Response('Internal Server Error HTML trace...', 500);
      });
      
      final apiClient = ApiClient(client: client);
      
      try {
        await apiClient.post('/test');
        fail('Should have thrown an exception');
      } on ApiException catch (e) {
        expect(e.message, 'Something went wrong on the server. Please try again later.');
        expect(e.statusCode, 500);
      }
    });

    test('extracts standard nested message structures', () async {
      final client = MockClient((request) async {
        return http.Response(
          '{"error": {"message": "Invalid password."}}',
          400,
        );
      });
      
      final apiClient = ApiClient(client: client);
      
      try {
        await apiClient.post('/test');
        fail('Should have thrown an exception');
      } on ApiException catch (e) {
        expect(e.message, 'Invalid password.');
        expect(e.statusCode, 400);
      }
    });
  });
}