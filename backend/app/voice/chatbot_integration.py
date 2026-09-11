"""
Chatbot Integration for Voice Pipeline
Bridges voice interactions with the main FitNova AI chatbot
"""

async def chatbot_response(user_text: str, user_id: str = None) -> str:
    """
    Integration function to connect voice pipeline with real FitNova AI chatbot.
    
    This replaces the dummy chatbot logic with a real API call to the RAG/AI service.
    
    Args:
        user_text: The transcribed or translated user input
        user_id: Optional user ID for personalized responses
        
    Returns:
        AI-generated response text
    """
    try:
        # Import the real AI service
        from ..services.llm_service import get_chatbot_response
        
        # Get AI response using the RAG pipeline
        response = await get_chatbot_response(
            user_message=user_text,
            user_id=user_id
        )
        
        return response
        
    except Exception as e:
        # Fallback to basic response if AI service fails
        print(f"AI service error: {e}, falling back to basic responses")
        return get_fallback_response(user_text)


def get_fallback_response(user_text: str) -> str:
    """
    Fallback chatbot logic when AI service is unavailable.
    Provides basic keyword-based responses.
    """
    text = user_text.lower()

    if "workout" in text or "exercise" in text:
        return "Sure! Today's workout is 3 sets of squats, 20 push-ups, and a 15-minute walk."
    elif "meal" in text or "eat" in text or "food" in text:
        return "For today's meal, I'd suggest grilled chicken, brown rice, and steamed vegetables."
    elif "water" in text or "hydrate" in text or "drink" in text:
        return "Try to drink at least 8 glasses of water today to stay hydrated."
    else:
        return "I'm your FitNova fitness assistant. You can ask me about workouts, meals, or hydration."


if __name__ == "__main__":
    # Quick manual test without needing STT
    import asyncio
    
    async def test():
        test_input = "what about meals and workout"
        print(f"You said: {test_input}")
        response = await chatbot_response(test_input)
        print(f"Bot says: {response}")
    
    asyncio.run(test())
