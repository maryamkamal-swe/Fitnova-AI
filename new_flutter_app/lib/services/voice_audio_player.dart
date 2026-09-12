// new_flutter_app/lib/services/voice_audio_player.dart
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';

class VoiceAudioPlayer {
  final AudioPlayer _player = AudioPlayer();

  Stream<PlayerState> get onPlayerStateChanged => _player.onPlayerStateChanged;

  Future<void> play(String audioData) async {
    final value = audioData.trim();
    if (value.isEmpty) return;
    
    if (value.startsWith('http') || value.startsWith('data:')) {
      await _player.play(UrlSource(value));
      return;
    }
    
    // Fixed: Removes all whitespace/newlines that might corrupt the decoder.
    final sanitizedBase64 = value.replaceAll(RegExp(r'\s+'), '');
    await _player.play(BytesSource(base64Decode(sanitizedBase64)));
  }

  Future<void> stop() => _player.stop();

  Future<void> dispose() => _player.dispose();
}