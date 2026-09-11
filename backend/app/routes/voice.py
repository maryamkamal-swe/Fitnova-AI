"""
Voice Interaction API Routes
Handles speech-to-text, text-to-speech, and multilingual voice interactions
"""
import asyncio
from fastapi import APIRouter, HTTPException, Depends, Request, status
from pydantic import BaseModel, Field
from typing import Optional
import base64
import io
import logging

from ..voice import translator
import speech_recognition as sr
from gtts import gTTS
from ..services.llm_service import get_chatbot_response
from ..utils.security import get_current_user
from ..services.rag_service import SAFETY_RESPONSE, validate_user_prompt
from ..core.limiter import limiter

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/voice", tags=["Voice Interaction"])
MAX_AUDIO_BASE64_BYTES = 10 * 1024 * 1024


class VoiceTranscribeRequest(BaseModel):
    """Request model for voice transcription"""
    audio_data: str = Field(..., max_length=MAX_AUDIO_BASE64_BYTES, description="Base64 encoded audio data (WAV format)")
    language_code: str = Field(default="en-US", description="Language code for STT (e.g., en-US, ur-PK)")


class VoiceTranscribeResponse(BaseModel):
    """Response model for voice transcription"""
    transcribed_text: str
    language_code: str
    success: bool = True


class VoiceChatRequest(BaseModel):
    """Request model for voice-based chat"""
    text: str = Field(..., min_length=1, max_length=4_000, description="Transcribed text from user")
    language_code: str = Field(default="en", description="User's language code (e.g., en, ur, ar)")
    translate_to_english: bool = Field(default=False, description="Whether to translate input to English")


class VoiceChatResponse(BaseModel):
    """Response model for voice chat"""
    response_text: str
    response_audio: Optional[str] = Field(None, description="Base64 encoded audio response (MP3)")
    language_code: str
    success: bool = True


class TextToSpeechRequest(BaseModel):
    """Request model for text-to-speech conversion"""
    text: str = Field(..., min_length=1, max_length=4_000, description="Text to convert to speech")
    language_code: str = Field(default="en", description="Language code (e.g., en, ur, ar)")


class TextToSpeechResponse(BaseModel):
    """Response model for text-to-speech"""
    audio_data: str = Field(..., description="Base64 encoded audio (MP3 format)")
    language_code: str
    success: bool = True


class LanguageListResponse(BaseModel):
    """Response model for supported languages"""
    languages: dict
    total_count: int


def _transcribe_audio(audio_data: str, language_code: str) -> str:
    """Decode and transcribe WAV bytes in a worker thread."""
    try:
        audio_bytes = base64.b64decode(audio_data, validate=True)
    except (ValueError, base64.binascii.Error) as error:
        raise HTTPException(status_code=400, detail="audio_data must be valid base64") from error
    recognizer = sr.Recognizer()
    with sr.AudioFile(io.BytesIO(audio_bytes)) as source:
        audio = recognizer.record(source)
    try:
        return recognizer.recognize_google(audio, language=language_code)
    except sr.UnknownValueError as error:
        raise HTTPException(status_code=422, detail="Audio could not be understood") from error
    except sr.RequestError as error:
        raise HTTPException(status_code=503, detail="Speech recognition service unavailable") from error


def _synthesize_speech(text: str, language_code: str) -> str:
    """Generate MP3 audio in a worker thread and return base64 content."""
    audio_buffer = io.BytesIO()
    gTTS(text=text, lang=language_code).write_to_fp(audio_buffer)
    return base64.b64encode(audio_buffer.getvalue()).decode("ascii")


@router.get("/languages", response_model=LanguageListResponse)
async def get_supported_languages():
    """
    Get list of all supported languages for voice interaction
    
    Returns language options with their STT and translation codes
    """
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
    """
    Transcribe audio to text using speech recognition
    
    Requires authentication. Accepts base64-encoded WAV audio data.
    """
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
    except Exception:
        logger.exception("Transcription error")
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
    """
    Process voice chat interaction with multilingual support
    
    Flow:
    1. Receives text (already transcribed or direct input)
    2. Optionally translates to English if needed
    3. Sends to AI chatbot
    4. Translates response back to user's language
    5. Returns text response (audio generation optional)
    """
    try:
        language_code = (payload.language_code or "en").split("-")[0].split("_")[0].lower()
        logger.info(f"Voice chat from user {current_user['id']} in language {language_code}")
        if not validate_user_prompt(payload.text):
            return VoiceChatResponse(
                response_text=SAFETY_RESPONSE,
                response_audio=None,
                language_code=language_code,
            )
        
        # Step 1: Translate input to English if needed
        english_text = payload.text
        if payload.translate_to_english and language_code != "en":
            english_text = await asyncio.to_thread(
                translator.translate_to_english, payload.text, language_code
            )
        
        # Step 2: Get AI response using RAG service
        from ..services.rag_service import rag_service
        from ..database import get_user_profile

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
        
        # Step 3: Translate response back if needed
        final_response = ai_response
        if language_code != "en":
            final_response = await asyncio.to_thread(
                translator.translate_from_english, ai_response, language_code
            )
        
        return {
            "response_text": final_response,
            "response_audio": None,
            "language_code": language_code,
            "success": True
        }
        
    except Exception:
        logger.exception("Voice chat error")
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
    """
    Convert text to speech audio
    
    Returns base64-encoded MP3 audio data
    """
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
    except Exception:
        logger.exception("TTS error")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An error occurred while processing your request.",
        )


@router.get("/health")
async def voice_health_check():
    """
    Health check for voice services
    """
    return {
        "status": "healthy",
        "services": {
            "stt": "available",
            "tts": "available",
            "translation": "available",
            "languages_supported": len(translator.LANGUAGE_OPTIONS)
        }
    }
