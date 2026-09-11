import '../core/constants.dart';
import '../models/chat_message.dart';
import 'api_client.dart';
import 'dart:convert';

class ChatService {
  final ApiClient _apiClient;

  ChatService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Future<ChatMessage> sendMessage({
    required String query,
    required String sessionId,
  }) async {
    final response = await _apiClient.post(
      AppConstants.aiChatEndpoint,
      requiresAuth: true,
      body: {'query': query.trim(), 'session_id': sessionId},
    );
    if (response is! Map<String, dynamic>) {
      throw const ApiException(message: 'Invalid AI chat response.');
    }
    final text = (response['response'] ?? response['answer'] ?? '').toString();
    if (text.isEmpty) {
      throw const ApiException(message: 'The AI returned an empty response.');
    }
    return ChatMessage(text: text, isUser: false);
  }

  Stream<String> streamMessage({
    required String query,
    required String sessionId,
  }) async* {
    await for (final line in _apiClient.postSse(
      '${AppConstants.aiChatEndpoint}/stream',
      body: {'query': query.trim(), 'session_id': sessionId},
    )) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') return;
      String? text;
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map) {
          final value = decoded['completion'] ??
              decoded['content'] ??
              decoded['text'] ??
              decoded['response'] ??
              decoded['answer'] ??
              decoded['delta'];
          text = value is Map
              ? (value['content'] ?? value['text'] ?? '').toString()
              : value?.toString();
        } else if (decoded is String) {
          text = decoded;
        }
      } catch (_) {
        text = payload;
      }
      if (text != null && text.isNotEmpty) yield text;
    }
  }
}
