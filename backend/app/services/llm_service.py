"""
Single shared entry point for every LLM call in the app.
Both the workout planner and the meal planner use this -- only the
prompt text and the target Pydantic schema differ between them.

Uses Groq (not OpenAI) for generation, matching the rest of the project's
stack. Embeddings/ChromaDB/HuggingFace stay reserved for the chatbot's RAG --
these two planners never touch a vector store.
"""
from __future__ import annotations

from app.config import settings

PLANNER_MODEL = settings.GROQ_ROUTER_MODEL


def get_llm(temperature: float = 0.4) -> ChatGroq:
    from langchain_groq import ChatGroq

    return ChatGroq(
        model=PLANNER_MODEL,
        temperature=temperature,
        api_key=settings.GROQ_API_KEY,
    )


def generate_structured(system_prompt: str, user_prompt: str, schema):
    """
    Calls the LLM and forces its response to match `schema` exactly
    (via Groq's tool-calling based structured output under the hood).
    Returns an already-validated instance of `schema`.
    """
    llm = get_llm()
    structured_llm = llm.with_structured_output(schema)
    return structured_llm.invoke(
        [
            ("system", system_prompt),
            ("user", user_prompt),
        ]
    )


async def get_chatbot_response(user_message: str, user_id: str = None) -> str:
    """Adapt the legacy voice chatbot contract to the shared RAG service."""
    from app.database import get_user_profile
    from app.services.rag_service import rag_service

    owner_id = user_id or "voice-anonymous"
    profile = await get_user_profile(owner_id)
    result = await rag_service.agenerate_response(
        user_query=user_message,
        user_profile=profile or {"goal": "general", "activity_level": "moderate"},
        session_id=f"voice-{owner_id}",
        user_id=owner_id,
    )
    return result["answer"]
