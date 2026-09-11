import pyttsx3
from gtts import gTTS
from playsound import playsound
import os
import tempfile

def speak(text: str, language_code: str = "en"):
    """
    Converts text to speech and plays it out loud.
    - English uses pyttsx3 (offline, fast, no internet needed)
    - Other languages use gTTS (online, correct native pronunciation)
    """
    if language_code == "en":
        engine = pyttsx3.init()
        engine.setProperty('rate', 170)
        engine.setProperty('volume', 1.0)
        engine.say(text)
        engine.runAndWait()
    else:
        tts = gTTS(text=text, lang=language_code)
        # Save to a temporary file, play it, then clean up
        with tempfile.NamedTemporaryFile(delete=False, suffix=".mp3") as fp:
            temp_path = fp.name
        tts.save(temp_path)
        playsound(temp_path)
        os.remove(temp_path)


if __name__ == "__main__":
    speak("╪ó╪¼ ┌⌐█Æ ┌⌐┌╛╪º┘å█Æ ┌⌐█Æ ┘ä█î█Æ╪î ┘à█î┌║ ┌»╪▒┘ä┌ê ┌å┌⌐┘å ╪¬╪¼┘ê█î╪▓ ┌⌐╪▒┘ê┌║ ┌»╪º█ö", language_code="ur")
