import io
import os
import tempfile
import pyttsx3
from gtts import gTTS

def generate_audio(text: str, language_code: str = "en") -> bytes:
    """
    Converts text to speech and RETURNS the audio bytes.
    This is safe for cloud servers (FastAPI/Render).
    """
    if language_code == "en":
        engine = pyttsx3.init()
        engine.setProperty('rate', 170)
        engine.setProperty('volume', 1.0)
        
        with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as fp:
            temp_path = fp.name
        
        try:
            engine.save_to_file(text, temp_path)
            engine.runAndWait() 
            
            with open(temp_path, "rb") as f:
                audio_bytes = f.read()
            return audio_bytes
        finally:
            if os.path.exists(temp_path):
                os.remove(temp_path)
    else:
        tts = gTTS(text=text, lang=language_code)
        buffer = io.BytesIO()
        tts.write_to_fp(buffer)
        return buffer.getvalue()

def speak(text: str, language_code: str = "en"):
    """
    Plays audio out loud. 
    Strictly for local CLI testing (voice_pipeline_cli.py) ONLY.
    """
    from playsound import playsound
    
    audio_data = generate_audio(text, language_code)
    with tempfile.NamedTemporaryFile(delete=False, suffix=".mp3") as fp:
        temp_path = fp.name
        
    with open(temp_path, "wb") as f:
        f.write(audio_data)
        
    playsound(temp_path)
    os.remove(temp_path)