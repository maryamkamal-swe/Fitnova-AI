// new_flutter_app/lib/screens/chat_screen.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';

import '../core/theme.dart';
import '../models/chat_message.dart';
import '../models/progress_entry.dart';
import '../services/api_client.dart';
import '../services/chat_service.dart';
import '../services/progress_service.dart';
import '../services/voice_service.dart';
import '../services/voice_audio_player.dart';
import '../services/recording_storage.dart'
    if (dart.library.html) '../services/recording_storage_web.dart';
import '../widgets/chat_insights.dart';

class ChatScreen extends StatefulWidget {
  final ChatService? chatService;
  final VoiceService? voiceService;

  const ChatScreen({super.key, this.chatService, this.voiceService});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatService _chatService;
  late final VoiceService _voiceService;
  final _progressService = ProgressService();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final String _sessionId = 'flutter-${DateTime.now().millisecondsSinceEpoch}';
  List<VoiceLanguage> _languages = const [];
  String _languageCode = 'en';
  bool _sending = false;
  bool _isRecording = false;
  final _audioPlayer = VoiceAudioPlayer();
  final AudioRecorder _recorder = AudioRecorder();
  String? _recordingPath;
  String? _playingMessage;
  int _playbackRequestId = 0;
  StreamSubscription<PlayerState>? _audioStateSubscription;
  bool _waitingForFirstChunk = false;
  bool _loggingProgress = false;

  @override
  void initState() {
    super.initState();
    _chatService = widget.chatService ?? ChatService();
    _voiceService = widget.voiceService ?? VoiceService();
    _audioStateSubscription =
        _audioPlayer.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.completed || state == PlayerState.stopped) {
        if (mounted) setState(() => _playingMessage = null);
      }
    });
    _loadLanguages();
  }

  Future<void> _loadLanguages() async {
    try {
      final languages = await _voiceService.getLanguages();
      if (mounted && languages.isNotEmpty) {
        setState(() => _languages = languages);
      }
    } catch (_) {
      // Voice language discovery is optional; English remains available.
    }
  }

  Future<void> _send([String? prompt]) async {
    final text = (prompt ?? _controller.text).trim();
    if (text.isEmpty || _sending) return;
    if (prompt == null) _controller.clear();
    setState(() {
      _sending = true;
      _waitingForFirstChunk = true;
      _messages.add(ChatMessage(text: text, isUser: true));
    });
    try {
      String message;
      final buffer = StringBuffer();
      await for (final chunk
          in _chatService.streamMessage(query: text, sessionId: _sessionId)) {
        buffer.write(chunk);
        if (mounted) {
          setState(() {
            _waitingForFirstChunk = false;
            if (_messages.isEmpty || _messages.last.isUser) {
              _messages
                  .add(ChatMessage(text: buffer.toString(), isUser: false));
            } else {
              _messages[_messages.length - 1] =
                  ChatMessage(text: buffer.toString(), isUser: false);
            }
          });
        }
      }
      message = buffer.toString();
      if (message.isEmpty) {
        throw const ApiException(message: 'The AI returned an empty response.');
      }
      if (mounted) {
        setState(() {
          _waitingForFirstChunk = false;
          if (_messages.isEmpty || _messages.last.isUser) {
            _messages.add(ChatMessage(text: message, isUser: false));
          }
        });
      }
    } on ApiException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Unable to reach your AI coach right now.');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _waitingForFirstChunk = false;
        });
      }
      _scrollToBottom();
    }
  }

  Future<void> _startRecording() async {
    if (_sending || _isRecording) return;
    try {
      if (!await _recorder.hasPermission()) {
        _showError(
            'Allow microphone access for FitNova in your browser, then try again.');
        return;
      }
      final path = recordingPath(
          'fitnova-${DateTime.now().microsecondsSinceEpoch}.wav');
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      if (mounted) setState(() => _isRecording = true);
    } catch (error) {
      _showError(error is ApiException
          ? error.message
          : 'Unable to start microphone recording.');
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    try {
      final path = await _recorder.stop();
      if (mounted) setState(() => _isRecording = false);
      if (path == null) return;
      _recordingPath = path;
      final bytes = await readRecording(path);
      await _sendVoice(base64Encode(bytes));
      await deleteRecording(path);
      _recordingPath = null;
    } catch (error) {
      if (mounted) setState(() => _isRecording = false);
      _showError(error is ApiException
          ? error.message
          : 'Unable to send the recorded voice message.');
    }
  }

  Future<void> _sendVoice(String audioData) async {
    if (audioData.isEmpty || _sending) return;
    setState(() {
      _sending = true;
    });
    try {
      final language = _languages.isEmpty 
          ? 'en-US'
          : _languages.firstWhere(
              (item) => item.translateCode == _languageCode,
              orElse: () => const VoiceLanguage(
                id: 'en',
                name: 'English',
                sttCode: 'en-US',
                translateCode: 'en',
              ),
            ).sttCode;
          
      final reply = await _voiceService.sendVoiceMessage(
        audioData: audioData,
        languageCode: language,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(text: 'Voice message', isUser: true));
        _messages.add(ChatMessage(text: reply.responseText, isUser: false));
      });
    } on ApiException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Unable to process your voice message.');
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  Future<void> _playMessageAudio(String text) async {
    if (_playingMessage == text) {
      _playbackRequestId++;
      await _audioPlayer.stop();
      if (mounted) setState(() => _playingMessage = null);
      return;
    }
    final requestId = ++_playbackRequestId;
    if (_playingMessage != null) {
      await _audioPlayer.stop();
    }
    if (mounted) setState(() => _playingMessage = text);
    try {
      final language = _languages.isEmpty 
          ? 'en-US'
          : _languages.firstWhere(
              (item) => item.translateCode == _languageCode,
              orElse: () => const VoiceLanguage(
                id: 'en',
                name: 'English',
                sttCode: 'en-US',
                translateCode: 'en',
              ),
            ).sttCode;

      final base64Audio = await _voiceService.textToSpeech(
        text: text,
        languageCode: language,
      );
      if (requestId != _playbackRequestId || _playingMessage != text) return;
      if (base64Audio.isEmpty) {
        if (mounted) setState(() => _playingMessage = null);
        return;
      }
      await _audioPlayer.play(base64Audio);
    } catch (_) {
      if (mounted &&
          requestId == _playbackRequestId &&
          _playingMessage == text) {
        setState(() => _playingMessage = null);
      }
      _showError('Unable to generate or play voice audio for this message.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  MacroSummary? _macroSummary(String text) {
    final match = RegExp(
      r'(?:\*\*|__)?Calories(?:\*\*|__)?\s*:\s*([0-9]+(?:\.[0-9]+)?)\D+'
      r'(?:\*\*|__)?Protein(?:\*\*|__)?\s*:\s*([0-9]+(?:\.[0-9]+)?)\D+'
      r'(?:\*\*|__)?Carbs?(?:\*\*|__)?\s*:\s*([0-9]+(?:\.[0-9]+)?)\D+'
      r'(?:\*\*|__)?Fats?(?:\*\*|__)?\s*:\s*([0-9]+(?:\.[0-9]+)?)',
      caseSensitive: false,
    ).firstMatch(text) ?? RegExp(
      r'Calories\s*:\s*([0-9]+(?:\.[0-9]+)?).*?'
      r'Protein\s*:\s*([0-9]+(?:\.[0-9]+)?).*?'
      r'Carbs?\s*:\s*([0-9]+(?:\.[0-9]+)?).*?'
      r'Fats?\s*:\s*([0-9]+(?:\.[0-9]+)?)',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(text);

    if (match == null) return null;
    final values = List.generate(
      4,
      (index) => double.tryParse(match.group(index + 1) ?? ''),
    );
    if (values.any((value) => value == null)) return null;
    return MacroSummary(
      calories: values[0]!,
      protein: values[1]!,
      carbs: values[2]!,
      fat: values[3]!,
    );
  }

  Future<void> _logMacroSummary(MacroSummary summary) async {
    if (_loggingProgress) return;
    setState(() => _loggingProgress = true);
    try {
      final today = await _progressService.getTodayProgress();
      if (today?.id != null && today!.id!.isNotEmpty) {
        await _progressService.updateProgress(
          today.id!,
          today.copyWith(
            caloriesConsumed: summary.calories,
            notes: summary.asText,
          ),
        );
      } else {
        await _progressService.logProgress(
          ProgressEntry(
            date: DateTime.now(),
            caloriesConsumed: summary.calories,
            notes: summary.asText,
          ),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Logged ${summary.calories.round()} kcal to daily progress',
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Unable to log calories to daily progress.');
    } finally {
      if (mounted) setState(() => _loggingProgress = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _recorder.dispose();
    _audioStateSubscription?.cancel();
    final path = _recordingPath;
    if (path != null) deleteRecording(path);
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Coach'),
        actions: [
          if (_languages.isNotEmpty)
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _languages
                        .any((item) => item.translateCode == _languageCode)
                    ? _languageCode
                    : null,
                hint: const Icon(Icons.language),
                dropdownColor: AppTheme.surface,
                onChanged: (value) {
                  if (value != null) setState(() => _languageCode = value);
                },
                items: _languages
                    .map((language) => DropdownMenuItem(
                          value: language.translateCode,
                          child: Text(language.name),
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty && !_waitingForFirstChunk
                ? const Center(
                    child:
                        Text('Ask your AI coach about training or nutrition.'),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount:
                        _messages.length + (_waitingForFirstChunk ? 1 : 0),
                    itemBuilder: (_, index) {
                      if (_waitingForFirstChunk && index == _messages.length) {
                        return const TypingBubble();
                      }
                      final message = _messages[index];
                      final summary =
                          message.isUser ? null : _macroSummary(message.text);
                      final viewportWidth = MediaQuery.sizeOf(context).width;
                      final coachBubbleWidth =
                          viewportWidth < 760 ? viewportWidth - 32 : 720.0;
                      return Align(
                        alignment: message.isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: message.isUser ? 480 : coachBubbleWidth,
                          ),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: message.isUser
                                ? AppTheme.primary
                                : AppTheme.surface,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (message.isUser)
                                Text(
                                  message.text,
                                  style: const TextStyle(
                                    color: AppTheme.onPrimary,
                                  ),
                                )
                              else
                                MarkdownBody(
                                  data: message.text,
                                  selectable: true,
                                  styleSheet: MarkdownStyleSheet(
                                    p: const TextStyle(
                                      color: AppTheme.textPrimary,
                                      height: 1.4,
                                    ),
                                    strong: const TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    listBullet: const TextStyle(
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                ),
                              if (summary != null) ...[
                                const SizedBox(height: 10),
                                MacroRatioBar(summary: summary),
                                const SizedBox(height: 6),
                                OutlinedButton.icon(
                                  onPressed: _loggingProgress
                                      ? null
                                      : () => _logMacroSummary(summary),
                                  icon:
                                      const Icon(Icons.flag_outlined, size: 16),
                                  label: Text(_loggingProgress
                                      ? 'Logging...'
                                      : 'Log to Daily Progress'),
                                ),
                              ],
                              if (!message.isUser) ...[
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () => _playMessageAudio(message.text),
                                    icon: Icon(
                                      _playingMessage == message.text
                                          ? Icons.stop
                                          : Icons.volume_up,
                                      size: 16,
                                    ),
                                    label: Text(
                                      _playingMessage == message.text
                                          ? 'Stop'
                                          : 'Listen',
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppTheme.primary,
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(50, 30),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_messages.isEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                children: [
                  ActionChip(
                    label: const Text('Family Daal Estimator'),
                    onPressed: _sending
                        ? null
                        : () => _send(
                            'Family Daal Estimator: 1 cup chana, 3 tbsp oil for 5 people. I ate 1.5 ladles.',
                          ),
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    label: const Text('Desi Chicken Karahi Portion'),
                    onPressed: _sending
                        ? null
                        : () => _send(
                            'Desi Chicken Karahi Portion: 1kg chicken, 4 tbsp ghee for 4 people. I ate 1 bowl.',
                          ),
                  ),
                ],
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Message your coach...',
                        prefixIcon: Icon(Icons.chat_bubble_outline),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onLongPressStart: (_) => _startRecording(),
                    onLongPressEnd: (_) => _stopRecording(),
                    child: Tooltip(
                      message: 'Hold to speak',
                      child: CircleAvatar(
                        backgroundColor:
                            _isRecording ? Colors.red : AppTheme.primary,
                        child: Icon(
                          _isRecording ? Icons.mic : Icons.mic_none,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Send message',
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}