import '../core/constants.dart';
import 'api_client.dart';

class VoiceLanguage {
  final String id;
  final String name;
  final String sttCode;
  final String translateCode;

  const VoiceLanguage({
    required this.id,
    required this.name,
    required this.sttCode,
    required this.translateCode,
  });

  factory VoiceLanguage.fromJson(String id, Map<String, dynamic> json) =>
      VoiceLanguage(
        id: id,
        name: (json['name'] ?? id).toString(),
        sttCode: (json['stt_code'] ?? json['sttCode'] ?? 'en-US').toString(),
        translateCode: (json['translate_code'] ?? json['translateCode'] ?? 'en')
            .toString(),
      );
}

class VoiceChatResult {
  final String responseText;
  final String? responseAudio;
  final String languageCode;

  const VoiceChatResult({
    required this.responseText,
    this.responseAudio,
    required this.languageCode,
  });

  factory VoiceChatResult.fromJson(Map<String, dynamic> json) =>
      VoiceChatResult(
        responseText:
            (json['response_text'] ?? json['responseText'] ?? '').toString(),
        responseAudio:
            (json['response_audio'] ?? json['responseAudio'])?.toString(),
        languageCode:
            (json['language_code'] ?? json['languageCode'] ?? 'en').toString(),
      );
}

class VoiceService {
  final ApiClient _apiClient;

  VoiceService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Future<List<VoiceLanguage>> getLanguages() async {
    final response = await _apiClient.get(
      AppConstants.voiceLanguagesEndpoint,
      requiresAuth: false,
    );
    if (response is! Map<String, dynamic>) {
      throw const ApiException(message: 'Invalid voice language response.');
    }
    final languages = response['languages'];
    if (languages is! Map) return const [];
    return languages.entries
        .where((entry) => entry.value is Map)
        .map((entry) => VoiceLanguage.fromJson(entry.key.toString(),
            Map<String, dynamic>.from(entry.value as Map)))
        .toList();
  }

  Future<String> transcribe({
    required String audioData,
    String languageCode = 'en-US',
  }) async {
    final response = await _apiClient.post(
      AppConstants.voiceTranscribeEndpoint,
      requiresAuth: true,
      body: {'audio_data': audioData, 'language_code': languageCode},
    );
    if (response is! Map<String, dynamic>) {
      throw const ApiException(message: 'Invalid transcription response.');
    }
    return (response['transcribed_text'] ?? '').toString();
  }

  Future<VoiceChatResult> chat({
    required String text,
    String languageCode = 'en',
    bool translateToEnglish = false,
  }) async {
    final response = await _apiClient.post(
      AppConstants.voiceChatEndpoint,
      requiresAuth: true,
      body: {
        'text': text,
        'language_code': languageCode,
        'translate_to_english': translateToEnglish,
      },
    );
    if (response is! Map<String, dynamic>) {
      throw const ApiException(message: 'Invalid voice chat response.');
    }
    return VoiceChatResult.fromJson(response);
  }

  static String _baseLanguageCode(String languageCode) {
    final normalized = languageCode.trim();
    if (normalized.isEmpty) return 'en';
    return normalized.split(RegExp(r'[-_]')).first.toLowerCase();
  }

  Future<String> textToSpeech({
    required String text,
    String languageCode = 'en',
  }) async {
    final response = await _apiClient.post(
      AppConstants.voiceTtsEndpoint,
      requiresAuth: true,
      body: {
        'text': text,
        'language_code': _baseLanguageCode(languageCode),
      },
    );
    if (response is! Map<String, dynamic>) {
      throw const ApiException(message: 'Invalid text-to-speech response.');
    }
    return (response['audio_data'] ?? '').toString();
  }

  Future<VoiceChatResult> sendVoiceMessage({
    required String audioData,
    String languageCode = 'en-US',
  }) async {
    final sttCode = languageCode.trim().isEmpty ? 'en-US' : languageCode.trim();
    final speakCode = _baseLanguageCode(sttCode);
    final text = await transcribe(audioData: audioData, languageCode: sttCode);
    if (text.trim().isEmpty) {
      throw const ApiException(message: 'Could not recognize any speech. Please try speaking again.');
    }
    final reply = await chat(
      text: text,
      languageCode: speakCode,
      translateToEnglish: speakCode != 'en',
    );
    final audio = reply.responseAudio?.trim().isNotEmpty == true
        ? reply.responseAudio
        : await textToSpeech(
            text: reply.responseText,
            languageCode: speakCode,
          );
    return VoiceChatResult(
      responseText: reply.responseText,
      responseAudio: audio,
      languageCode: reply.languageCode,
    );
  }
}