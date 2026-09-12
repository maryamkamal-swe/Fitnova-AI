# backend/tests/test_components.py
import pytest
import base64
from unittest.mock import patch, MagicMock
from fastapi import HTTPException
from app.routes.voice import _synthesize_speech, _transcribe_audio
from app.services.otp_service import send_otp_email, create_otp
from app.utils.security import verify_password, hash_password
from app.services.rag_indexer import _read_json_file
import tempfile
import json
from pathlib import Path


def test_verify_password_catches_invalid_hash():
    """Verify password handles invalid format hashes safely."""
    assert verify_password("plain", "invalidhash") is False
    assert verify_password("plain", hash_password("plain")) is True


def test_transcribe_audio_invalid_format():
    """Test that STT rejects payload when its not a valid WAV base64 string."""
    invalid_audio = base64.b64encode(b"not a wav file").decode()
    with pytest.raises(HTTPException) as exc:
        _transcribe_audio(invalid_audio, "en-US")
    assert exc.value.status_code == 400
    assert "Must be WAV" in exc.value.detail


@patch("app.routes.voice.gTTS")
def test_synthesize_speech_fallback(mock_gtts):
    """Test TTS properly falls back to English when language is unsupported."""
    mock_gtts.side_effect = [ValueError("unsupported lang"), MagicMock()]
    result = _synthesize_speech("hello", "xx-YY")
    assert result is not None
    assert mock_gtts.call_count == 2


@patch("app.services.otp_service.smtplib")
@patch("app.services.otp_service.settings")
def test_send_otp_email_tls_vs_ssl(mock_settings, mock_smtplib):
    """Test that OTP service adjusts delivery based on SMTP Port."""
    mock_settings.SMTP_HOST = "smtp.test"
    mock_settings.SMTP_USER = "test@test.com"
    mock_settings.SMTP_PASSWORD = "pass"
    mock_settings.SMTP_PORT = 465
    
    mock_ssl_instance = MagicMock()
    mock_smtplib.SMTP_SSL.return_value.__enter__.return_value = mock_ssl_instance
    
    success = send_otp_email("test@example.com", "123456")
    assert success is True
    mock_smtplib.SMTP_SSL.assert_called_with("smtp.test", 465, timeout=15)
    mock_ssl_instance.login.assert_called_with("test@test.com", "pass")
    mock_ssl_instance.send_message.assert_called_once()


def test_read_json_file_handles_flat_objects():
    """Test RAG Indexer json utility parses both lists and objects correctly."""
    with tempfile.NamedTemporaryFile("w+", delete=False) as f:
        json.dump({"title": "Diet Advice", "content": "Eat healthy."}, f)
        temp_path = f.name
    
    try:
        documents = _read_json_file(Path(temp_path))
        assert len(documents) == 1
        assert "Eat healthy" in documents[0].page_content
    finally:
        Path(temp_path).unlink()