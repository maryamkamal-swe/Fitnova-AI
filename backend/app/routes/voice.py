# backend/app/routes/voice.py
import asyncio
import base64
import io
import logging
from typing import Optional

# ADD Response here
from fastapi import APIRouter, Depends, HTTPException, Request, status, Response 
from gtts import gTTS
from pydantic import BaseModel, Field
import speech_recognition as sr

from ..core.limiter import limiter
from ..services.rag_service import (
    SAFETY_RESPONSE,
    translate_query_to_english,
    validate_user_prompt,
)
from ..utils.security import get_current_user
from ..voice import translator
# ADD this line here
from ..voice.tts import generate_audio

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/voice", tags=["Voice Interaction"])

# Base64 inflates byte size by ~33%. To allow 10MB of raw audio, the string length must accommodate ~13.4M chars.
MAX_AUDIO_BASE64_CHARS = 14_000_000  


class VoiceTranscribeRequest(BaseModel):
    audio_data: str = Field(..., max_length=MAX_AUDIO_BASE64_CHARS, description="Base64 encoded audio data (WAV format)")
    language_code: str = Field(default="en-US", description="Language code for STT (e.g., en-US, ur-PK)")


class VoiceTranscribeResponse(BaseModel):
    transcribed_text: str
    language_code: str
    success: bool = True


class VoiceChatRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=4_000, description="Transcribed text from user")
    language_code: str = Field(default="en", description="User's language code (e.g., en, ur, ar)")
    translate_to_english: bool = Field(default=False, description="Whether to translate input to English")


class VoiceChatResponse(BaseModel):
    response_text: str
    response_audio: Optional[str] = Field(None, description="Base64 encoded audio response (MP3)")
    language_code: str
    success: bool = True


class TextToSpeechRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=4_000, description="Text to convert to speech")
    language_code: str = Field(default="en", description="Language code (e.g., en, ur, ar)")


class TextToSpeechResponse(BaseModel):
    audio_data: str = Field(..., description="Base64 encoded audio (MP3 format)")
    language_code: str
    success: bool = True


class LanguageListResponse(BaseModel):
    languages: dict
    total_count: int


def _transcribe_audio(audio_data: str, language_code: str) -> str:
    try:
        audio_bytes = base64.b64decode(audio_data, validate=True)
    except (ValueError, base64.binascii.Error) as error:
        raise HTTPException(status_code=400, detail="audio_data must be valid base64") from error
    
    recognizer = sr.Recognizer()
    
    # Try reading directly as a WAV file first
    try:
        with sr.AudioFile(io.BytesIO(audio_bytes)) as source:
            audio = recognizer.record(source)
    except (ValueError, OSError, RuntimeError) as wav_error:
        logger.info(
            "Audio is not directly readable as WAV; attempting WebM/OGG conversion: %s",
            wav_error,
        )
        # Fallback: If pydub and FFmpeg are installed, convert WebM/OGG to WAV.
        try:
            from pydub import AudioSegment
        except ImportError as import_error:
            logger.warning(
                "WebM/OGG voice input is unavailable because pydub is not installed. "
                "Install pydub and FFmpeg to enable conversion."
            )
            raise HTTPException(
                status_code=400,
                detail=(
                    "Must be WAV. WebM/OGG requires "
                    "pydub and FFmpeg on the server."
                ),
            ) from import_error

        try:
            audio_segment = AudioSegment.from_file(io.BytesIO(audio_bytes))
            wav_io = io.BytesIO()
            audio_segment.export(wav_io, format="wav")
            wav_io.seek(0)
            with sr.AudioFile(wav_io) as source:
                audio = recognizer.record(source)
        except (OSError, RuntimeError, ValueError) as conversion_error:
            logger.exception(
                "WebM/OGG audio conversion failed; FFmpeg may be missing or "
                "the audio payload may be invalid."
            )
            raise HTTPException(
                status_code=400, 
                detail="Invalid audio format. Ensure audio is recorded as WAV or configure pydub/ffmpeg for WebM conversion."
            ) from conversion_error
            
    requested_language = language_code.strip() or "en-US"
    language_candidates = [requested_language]
    base_language = requested_language.split("-")[0].split("_")[0].lower()
    if base_language != "en":
        language_candidates.append("en-US")
    if base_language != "ur":
        language_candidates.append("ur-PK")

    last_unknown_error = None
    for candidate in dict.fromkeys(language_candidates):
        try:
            return recognizer.recognize_google(audio, language=candidate)
        except sr.UnknownValueError as error:
            last_unknown_error = error
            logger.info(
                "Speech was not recognized with language %s; trying the next "
                "supported language.",
                candidate,
            )
        except sr.RequestError as error:
            raise HTTPException(
                status_code=503,
                detail="Speech recognition service unavailable",
            ) from error

    raise HTTPException(
        status_code=422,
        detail="Audio could not be understood",
    ) from last_unknown_error


def _synthesize_speech(text: str, language_code: str) -> str:
    clean_lang = language_code.split("-")[0].split("_")[0].lower()
    audio_buffer = io.BytesIO()
    try:
        gTTS(text=text, lang=clean_lang).write_to_fp(audio_buffer)
    except ValueError:
        logger.warning(f"Language {clean_lang} not supported by TTS. Falling back to English.")
        gTTS(text=text, lang="en").write_to_fp(audio_buffer)
    
    return base64.b64encode(audio_buffer.getvalue()).decode("ascii")


@router.get("/languages", response_model=LanguageListResponse)
async def get_supported_languages():
    return {
        "languages": translator.LANGUAGE_OPTIONS,
        "total_count": len(translator.LANGUAGE_OPTIONS)
    }


@router.post("/transcribe", response_model=VoiceTranscribeResponse)
@limiter.limit("10/minute")
async def transcribe_audio(
    request: Request,
    payload: VoiceTranscribeRequest,
    current_user: dict = Depends(get_current_user)
):
    try:
        logger.info(f"Transcription request from user {current_user['id']} in language {payload.language_code}")
        text = await asyncio.to_thread(
            _transcribe_audio, payload.audio_data, payload.language_code
        )
        return VoiceTranscribeResponse(
            transcribed_text=text,
            language_code=payload.language_code,
        )
    except HTTPException:
        raise
    except (OSError, RuntimeError, ValueError) as error:
        logger.exception("Voice transcription infrastructure/format error: %s", error)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An error occurred while processing your request.",
        )


@router.post("/chat", response_model=VoiceChatResponse)
@limiter.limit("10/minute")
async def voice_chat(
    request: Request,
    payload: VoiceChatRequest,
    current_user: dict = Depends(get_current_user)
):
    try:
        language_code = (payload.language_code or "en").split("-")[0].split("_")[0].lower()
        logger.info(f"Voice chat from user {current_user['id']} in language {language_code}")
        english_text = await asyncio.to_thread(
            translate_query_to_english,
            payload.text,
            language_code,
        )
        if not validate_user_prompt(english_text):
            return VoiceChatResponse(
                response_text=SAFETY_RESPONSE,
                response_audio=None,
                language_code=language_code,
            )
        
        from ..database import get_user_profile
        from ..services.rag_service import rag_service

        user_id = current_user["id"]
        user_profile = await get_user_profile(user_id)
        
        if not user_profile:
            user_profile = {"goal": "general", "activity_level": "moderate"}
        
        session_id = f"voice-{user_id}"
        
        result = await rag_service.agenerate_response(
            user_query=english_text,
            user_profile=user_profile,
            session_id=session_id,
            user_id=user_id,
        )
        
        ai_response = result["answer"]
        
        final_response = ai_response
        if language_code != "en":
            final_response = await asyncio.to_thread(
                translator.translate_from_english, ai_response, language_code
            )
        
        return VoiceChatResponse(
            response_text=final_response,
            response_audio=None,
            language_code=language_code,
            success=True
        )
        
    except (OSError, RuntimeError, TimeoutError) as error:
        logger.exception("Voice chat infrastructure/provider error: %s", error)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An error occurred while processing your request.",
        ) from error
    except Exception as error:
        logger.exception("Voice chat unexpected error: %s", error)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An error occurred while processing your request.",
        )


@router.post("/tts", response_model=TextToSpeechResponse)
@limiter.limit("10/minute")
async def text_to_speech(
    request: Request,
    payload: TextToSpeechRequest,
    current_user: dict = Depends(get_current_user)
):
    try:
        language_code = (payload.language_code or "en").split("-")[0].split("_")[0].lower()
        logger.info(f"TTS request from user {current_user['id']} in language {language_code}")
        
        encoded_audio = await asyncio.to_thread(
            _synthesize_speech, payload.text, language_code
        )
        return TextToSpeechResponse(
            audio_data=encoded_audio,
            language_code=language_code,
        )
    except HTTPException:
        raise
    except (OSError, RuntimeError, ValueError, TimeoutError) as error:
        logger.exception("Text-to-speech provider/infrastructure error: %s", error)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An error occurred while processing your request.",
        ) from error
    except Exception as error:
        logger.exception("Text-to-speech unexpected error: %s", error)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An error occurred while processing your request.",
        )
@router.post("/speak")
@limiter.limit("10/minute")
async def get_spoken_text(
    request: Request,
    text: str,
    lang: str = "en",
    current_user: dict = Depends(get_current_user),
):
    """
    Returns raw audio bytes directly with the correct media type 
    (audio/wav for English pyttsx3, audio/mpeg for gTTS other languages).
    """
    logger.info("Legacy voice speech request from user %s", current_user["id"])
    audio_bytes = await asyncio.to_thread(generate_audio, text, lang)
    clean_lang = lang.split("-")[0].split("_")[0].lower()
    media_type = "audio/wav" if clean_lang == "en" else "audio/mpeg"
    
    return Response(content=audio_bytes, media_type=media_type)

@router.get("/health")
async def voice_health_check():
    return {
        "status": "healthy",
        "services": {
            "stt": "available",
            "tts": "available",
            "translation": "available",
            "languages_supported": len(translator.LANGUAGE_OPTIONS)
        }
    }