import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';

class VoiceAudioPlayer {
  final AudioPlayer _player = AudioPlayer();

  Future<void> play(String audioData) async {
    final value = audioData.trim();
    if (value.isEmpty) return;
    if (value.startsWith('http') || value.startsWith('data:')) {
      await _player.play(UrlSource(value));
      return;
    }
    await _player.play(BytesSource(base64Decode(value)));
  }

  Future<void> dispose() => _player.dispose();
}
