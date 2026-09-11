from deep_translator import GoogleTranslator

# Maps human-friendly names (shown in the menu) to the codes
# each library actually needs. STT and Translate use slightly
# different code formats, so both are stored together.
LANGUAGE_OPTIONS = {
    "1": {"name": "English", "stt_code": "en-US", "translate_code": "en"},
    "2": {"name": "Urdu",    "stt_code": "ur-PK", "translate_code": "ur"},
    "3": {"name": "Hindi",   "stt_code": "hi-IN", "translate_code": "hi"},
}


def translate_to_english(text: str, source_lang: str) -> str:
    """
    Translates text FROM the user's chosen language INTO English,
    so the dummy chatbot (which only understands English keywords)
    can process it normally.
    """
    return GoogleTranslator(source=source_lang, target="en").translate(text)


def translate_from_english(text: str, target_lang: str) -> str:
    """
    Translates the chatbot's English response BACK into the
    user's chosen language, so TTS can speak it correctly.
    """
    return GoogleTranslator(source="en", target=target_lang).translate(text)
