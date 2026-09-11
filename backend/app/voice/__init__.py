"""
Voice Interaction Module
Provides speech-to-text, text-to-speech, and multilingual translation capabilities
"""

from .stt import listen_and_transcribe
from .tts import speak
from .translator import (
    LANGUAGE_OPTIONS,
    translate_to_english,
    translate_from_english
)
from .chatbot_integration import chatbot_response, get_fallback_response

__all__ = [
    'listen_and_transcribe',
    'speak',
    'LANGUAGE_OPTIONS',
    'translate_to_english',
    'translate_from_english',
    'chatbot_response',
    'get_fallback_response',
]
