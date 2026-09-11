import speech_recognition as sr

def listen_and_transcribe(language_code: str = "en-US"):
    recognizer = sr.Recognizer()

    with sr.Microphone() as source:
        print("Adjusting for background noise... please wait")
        recognizer.adjust_for_ambient_noise(source, duration=1)

        print("Listening... speak now")
        audio = recognizer.listen(source)

    print("Processing...")

    try:
        text = recognizer.recognize_google(audio, language=language_code)
        print(f"You said: {text}")
        return text
    except sr.UnknownValueError:
        print("Sorry, I couldn't understand that.")
        return None
    except sr.RequestError as e:
        print(f"Could not request results; {e}")
        return None


if __name__ == "__main__":
    listen_and_transcribe()
