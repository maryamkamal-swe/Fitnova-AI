"""
Voice Pipeline CLI - Standalone Testing Script
Allows testing the complete voice interaction flow locally without API calls

Usage: python -m app.voice.voice_pipeline_cli
"""

from .stt import listen_and_transcribe
from .tts import speak
from .translator import LANGUAGE_OPTIONS, translate_to_english, translate_from_english
from .chatbot_integration import get_fallback_response


def choose_language():
    """Display language menu and get user selection"""
    print("\n" + "="*50)
    print("FitNova Voice Assistant - Language Selection")
    print("="*50)
    
    for key, value in LANGUAGE_OPTIONS.items():
        print(f"{key}. {value['name']}")
    
    choice = input("\nEnter choice: ").strip()
    
    if choice not in LANGUAGE_OPTIONS:
        print("Invalid choice, defaulting to English.")
        choice = "3"  # English
    
    return LANGUAGE_OPTIONS[choice]


def run_voice_pipeline():
    """
    Run the complete voice interaction pipeline:
    1. Select language
    2. Listen to user speech (STT)
    3. Translate to English if needed
    4. Get chatbot response
    5. Translate response back
    6. Speak response (TTS)
    """
    print("\n" + "="*50)
    print("🎤 FitNova Voice Assistant - CLI Mode")
    print("="*50)
    
    # Step 1: Language selection
    selected_lang = choose_language()
    print(f"\n✓ Selected language: {selected_lang['name']}")
    print(f"  STT Code: {selected_lang['stt_code']}")
    print(f"  Translate Code: {selected_lang['translate_code']}")
    
    # Step 2: Speech-to-text
    print("\n" + "-"*50)
    print("Step 1: Speech Recognition")
    print("-"*50)
    user_text = listen_and_transcribe(language_code=selected_lang["stt_code"])
    
    if user_text is None:
        print("❌ No valid input received. Try again.")
        speak("Sorry, I didn't catch that. Please try again.", language_code=selected_lang["translate_code"])
        return
    
    print(f"✓ You said: {user_text}")
    
    # Step 3: Translation to English (if needed)
    print("\n" + "-"*50)
    print("Step 2: Translation to English")
    print("-"*50)
    
    if selected_lang["translate_code"] != "en":
        english_text = translate_to_english(user_text, selected_lang["translate_code"])
        print(f"✓ English version: {english_text}")
    else:
        english_text = user_text
        print("✓ Already in English, skipping translation")
    
    # Step 4: Get chatbot response (using fallback)
    print("\n" + "-"*50)
    print("Step 3: Chatbot Processing")
    print("-"*50)
    
    response = get_fallback_response(english_text)
    print(f"✓ FitNova (English): {response}")
    
    # Step 5: Translation back (if needed)
    print("\n" + "-"*50)
    print("Step 4: Translation to Target Language")
    print("-"*50)
    
    if selected_lang["translate_code"] != "en":
        final_response = translate_from_english(response, selected_lang["translate_code"])
        print(f"✓ FitNova ({selected_lang['name']}): {final_response}")
    else:
        final_response = response
        print("✓ Already in English, skipping translation")
    
    # Step 6: Text-to-speech
    print("\n" + "-"*50)
    print("Step 5: Text-to-Speech")
    print("-"*50)
    print("🔊 Playing audio response...")
    
    speak(final_response, language_code=selected_lang["translate_code"])
    
    print("\n" + "="*50)
    print("✅ Voice pipeline completed successfully!")
    print("="*50)


def main():
    """Main entry point"""
    while True:
        try:
            run_voice_pipeline()
            
            # Ask if user wants to continue
            print("\n")
            continue_choice = input("Try again? (y/n): ").strip().lower()
            if continue_choice != 'y':
                print("\n👋 Thank you for using FitNova Voice Assistant!")
                break
                
        except KeyboardInterrupt:
            print("\n\n👋 Goodbye!")
            break
        except Exception as e:
            print(f"\n❌ Error: {e}")
            print("Please try again.")


if __name__ == "__main__":
    main()
