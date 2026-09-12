import logging
import asyncio
from datetime import date as date_type
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from app.config import settings
from app.database import DEFAULT_RAG_PROFILE, get_user_profile
from app.services.rag_service import rag_service, translate_query_to_english
from app.core.limiter import limiter
from app.utils.security import get_current_user_id
from app.services.progress_service import ProgressService

router = APIRouter()
logger = logging.getLogger(__name__)


class ChatRequest(BaseModel):
    query: str = Field(
        ...,
        min_length=1,
        description="User question or fitness/nutrition request",
        json_schema_extra={"example": "What should I eat before a high-intensity workout?"},
    )
    session_id: str = Field(
        ...,
        min_length=1,
        description="Unique chat session identifier",
        json_schema_extra={"example": "session_123"},
    )
    language_code: Optional[str] = Field(
        default=None,
        description="Optional input language code, such as ur or hi",
    )
    user_profile: Optional[Dict[str, Any]] = Field(
        default=None,
        description="Optional profile override (for testing without MongoDB)",
    )
    calories_consumed: Optional[int] = Field(default=None, ge=0)
    date: date_type = Field(default_factory=date_type.today)


class ChatResponse(BaseModel):
    response: str
    session_id: str
    sources: List[Dict[str, Any]] = Field(
        default_factory=list,
        description="Retrieved source documents and metadata supporting the response",
    )


@router.post("/chat", response_model=ChatResponse)
@limiter.limit("10/minute")
async def chat_endpoint(
    request: Request,
    payload: ChatRequest,
    user_id: str = Depends(get_current_user_id),
):
    try:
        if payload.calories_consumed:
            await ProgressService().increment_progress(
                user_id,
                payload.date,
                calories_consumed=payload.calories_consumed,
            )
        # Map the test payload first, fallback to DB fetch.
        user_profile = (
            payload.user_profile
            or await get_user_profile(user_id)
            or DEFAULT_RAG_PROFILE
        )
        english_query = await asyncio.to_thread(
            translate_query_to_english, payload.query, payload.language_code
        )
        result = await rag_service.agenerate_response(
            user_query=english_query,
            user_profile=user_profile,
            session_id=payload.session_id,
            user_id=user_id,
        )
        return ChatResponse(
            response=result["answer"],
            session_id=payload.session_id,
            sources=result["sources"],
        )
    except HTTPException:
        raise
    except (TimeoutError, ConnectionError) as error:
        logger.exception("RAG infrastructure/provider failure: %s", error)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="The AI coach is temporarily unavailable. Please try again.",
        ) from error
    except Exception as error:
        logger.exception("RAG chat unexpected failure: %s", error)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An error occurred while processing your request.",
        )


@router.post("/chat/stream")
@limiter.limit("10/minute")
async def chat_stream_endpoint(
    request: Request,
    payload: ChatRequest,
    user_id: str = Depends(get_current_user_id),
):
    if payload.calories_consumed:
        await ProgressService().increment_progress(
            user_id,
            payload.date,
            calories_consumed=payload.calories_consumed,
        )
    user_profile = payload.user_profile or await get_user_profile(user_id) or DEFAULT_RAG_PROFILE

    english_query = await asyncio.to_thread(
        translate_query_to_english, payload.query, payload.language_code
    )
    return StreamingResponse(
        rag_service.astream_response(
            user_query=english_query,
            user_profile=user_profile,
            session_id=payload.session_id,
            user_id=user_id,
        ),
        media_type="text/event-stream",
    )
