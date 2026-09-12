import logging
from deep_translator import GoogleTranslator

logger = logging.getLogger(__name__)

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
    Translates text FROM the user's chosen language INTO English.
    Cleans country codes (e.g., 'ur-PK' -> 'ur') and falls back to original text on failure.
    """
    clean_lang = source_lang.split("-")[0].split("_")[0].lower()
    if clean_lang == "en" or not text.strip():
        return text
    try:
        return GoogleTranslator(source=clean_lang, target="en").translate(text)
    except Exception as e:
        logger.error(f"Translation to English failed: {e}")
        return text


def translate_from_english(text: str, target_lang: str) -> str:
    """
    Translates the chatbot's English response BACK into the user's language.
    Cleans country codes (e.g., 'ur-PK' -> 'ur') and falls back to original text on failure.
    """
    clean_lang = target_lang.split("-")[0].split("_")[0].lower()
    if clean_lang == "en" or not text.strip():
        return text
    try:
        return GoogleTranslator(source="en", target=clean_lang).translate(text)
    except Exception as e:
        logger.error(f"Translation from English failed: {e}")
        return text