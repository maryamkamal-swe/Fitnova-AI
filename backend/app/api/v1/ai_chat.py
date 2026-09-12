import logging
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from app.config import settings
from app.database import DEFAULT_RAG_PROFILE, get_user_profile
from app.services.rag_service import rag_service
from app.core.limiter import limiter
from app.utils.security import get_current_user_id

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
    user_profile: Optional[Dict[str, Any]] = Field(
        default=None,
        description="Optional profile override (for testing without MongoDB)",
    )


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
    # Map the test payload first, fallback to DB fetch
    user_profile = payload.user_profile or await get_user_profile(user_id) or DEFAULT_RAG_PROFILE

    try:
        result = await rag_service.agenerate_response(
            user_query=payload.query,
            user_profile=user_profile,
            session_id=payload.session_id,
            user_id=user_id,
        )
        return ChatResponse(
            response=result["answer"],
            session_id=payload.session_id,
            sources=result["sources"],
        )
    except Exception:
        logger.exception("RAG chat request failed")
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
    user_profile = payload.user_profile or await get_user_profile(user_id) or DEFAULT_RAG_PROFILE

    return StreamingResponse(
        rag_service.astream_response(
            user_query=payload.query,
            user_profile=user_profile,
            session_id=payload.session_id,
            user_id=user_id,
        ),
        media_type="text/event-stream",
    )
