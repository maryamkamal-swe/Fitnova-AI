"""
Single shared entry point for every LLM call in the app.
Both the workout planner and the meal planner use this -- only the
prompt text and the target Pydantic schema differ between them.
"""
from __future__ import annotations
import logging
from app.config import settings

logger = logging.getLogger(__name__)
PLANNER_MODEL = settings.GROQ_ROUTER_MODEL


def get_llm(temperature: float = 0.4):
    from langchain_groq import ChatGroq
    return ChatGroq(
        model=PLANNER_MODEL,
        temperature=temperature,
        api_key=settings.GROQ_API_KEY,
    )


def generate_structured(system_prompt: str, user_prompt: str, schema):
    """
    Calls the LLM and forces its response to match `schema` exactly
    via Groq's structured output. Raises exceptions clearly so service layers 
    know if a fallback is genuinely required due to structural failure.
    """
    llm = get_llm()
    try:
        structured_llm = llm.with_structured_output(schema)
        result = structured_llm.invoke(
            [
                ("system", system_prompt),
                ("user", user_prompt),
            ]
        )
        if result is None:
            raise ValueError("LLM returned an empty structured response.")
        return result
    except Exception as e:
        logger.error(f"Structured LLM generation failed for schema {schema.__name__}: {e}")
        raise e