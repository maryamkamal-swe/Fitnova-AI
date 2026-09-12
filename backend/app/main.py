"""
FitNova AI Backend - Main Application
FastAPI backend for personalized fitness and nutrition coaching
"""
import asyncio
import logging
import sqlite3
from uuid import uuid4
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from slowapi.errors import RateLimitExceeded
from pymongo.errors import ConnectionFailure

from .config import settings
from .database import close_mongodb_connection, connect_to_mongodb, db
from .core.limiter import limiter


# Configure logging
logging.basicConfig(
    level=logging.INFO if settings.DEBUG else logging.WARNING,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def _import_ai_and_voice_routers():
    """Import RAG/voice routers off the critical boot path (Chroma/HuggingFace)."""
    from .api.v1 import ai_chat
    from .routes.voice import router as voice_router

    return ai_chat, voice_router


async def _mount_ai_and_voice_routers(app: FastAPI) -> None:
    """Mount AI and voice routes before the application accepts requests."""
    ai_chat, voice_router = await asyncio.to_thread(_import_ai_and_voice_routers)
    app.include_router(ai_chat.router, prefix="/api/v1/ai", tags=["ai"])
    app.include_router(voice_router, prefix="/api/v1")
    app.state.ai_voice_ready = True
    logger.info("AI chat and voice routers mounted")


def _check_sqlite_database() -> None:
    """Verify the configured SQLite file is readable without mutating it."""
    sqlite_path = Path(settings.SQLITE_DB_PATH)
    if not sqlite_path.is_file():
        raise FileNotFoundError(f"SQLite database not found: {sqlite_path}")
    connection = sqlite3.connect(f"file:{sqlite_path.resolve().as_posix()}?mode=ro", uri=True)
    try:
        connection.execute("SELECT 1")
    finally:
        connection.close()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Lifespan context manager for startup and shutdown events
    """
    logger.info("🚀 Starting FitNova AI Backend...")
    await connect_to_mongodb()
    await _mount_ai_and_voice_routers(app)
    await asyncio.to_thread(_check_sqlite_database)
    app.state.core_ready = True
    logger.info("✅ Application started successfully")

    yield

    logger.info("🛑 Shutting down FitNova AI Backend...")
    await close_mongodb_connection()
    logger.info("✅ Application shutdown complete")


# Create FastAPI app
app = FastAPI(
    title="FitNova AI API",
    redirect_slashes=False,
    description="AI-powered personalized fitness and nutrition coaching system",
    version="1.0.0",
    docs_url=None if settings.ENVIRONMENT.strip().lower() in {"production", "prod"} else "/docs",
    redoc_url=None if settings.ENVIRONMENT.strip().lower() in {"production", "prod"} else "/redoc",
    lifespan=lifespan
)
app.state.limiter = limiter


async def rate_limit_exceeded_handler(request: Request, exc: RateLimitExceeded):
    return JSONResponse(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        content={
            "detail": "Rate limit exceeded. Please try again later.",
            "error": {"message": "Rate limit exceeded. Please try again later."},
        },
    )


app.add_exception_handler(RateLimitExceeded, rate_limit_exceeded_handler)


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    message = exc.detail if isinstance(exc.detail, str) else "Request failed."
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": exc.detail, "error": {"message": message}},
        headers=exc.headers,
    )


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    """Return 413 for oversized voice payloads, otherwise keep FastAPI-style 422s."""
    errors = exc.errors()
    if request.url.path.endswith("/voice/transcribe"):
        for error in errors:
            location = error.get("loc", ())
            message = str(error.get("msg", "")).lower()
            if "audio_data" in location and (
                "at most" in message or "less than" in message or "too long" in message
            ):
                return JSONResponse(
                    status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                    content={
                        "detail": "Audio payload exceeds the 10 MB limit.",
                        "error": {"message": "Audio payload exceeds the 10 MB limit."},
                    },
                )
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={"detail": errors, "error": {"message": "Request validation failed."}},
    )

# Configure CORS from ALLOWED_ORIGINS and regex for hosted/local environments
cors_origins = getattr(settings, "origins_list", []) or [
    "https://fitnova-frontend.onrender.com",
    "https://fitnova-ai-dv0n.onrender.com",
    "http://localhost:3000",
    "http://localhost:8000",
    "http://localhost:8080",
    "http://127.0.0.1:8080",
    "http://10.0.2.2:8000",
    "http://127.0.0.1:8000",
]
if not cors_origins:
    logger.warning("ALLOWED_ORIGINS is empty; browser cross-origin requests are disabled")

app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/", tags=["Health"])
async def root():
    """
    Root endpoint - Health check
    """
    return {
        "message": "FitNova AI Backend API",
        "status": "running",
        "version": "1.0.0",
        "docs": "/docs"
    }


@app.get("/health", tags=["Health"])
async def health_check():
    """Readiness probe for MongoDB and the configured SQLite nutrition data."""
    try:
        if (
            db.client is None
            or db.db is None
            or not getattr(app.state, "core_ready", False)
            or not getattr(app.state, "ai_voice_ready", False)
        ):
            raise RuntimeError("Core services are not initialized")
        await db.client.admin.command("ping")
        await asyncio.to_thread(_check_sqlite_database)
    except (ConnectionFailure, OSError, RuntimeError, sqlite3.Error) as error:
        error_id = uuid4().hex
        logger.exception(
            "Health check infrastructure failure [%s]: %s", error_id, error
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Core services are unavailable.",
        ) from error
    except Exception as error:
        error_id = uuid4().hex
        logger.exception(
            "Health check unexpected failure [%s]: %s", error_id, error
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Core services are unavailable.",
        ) from error
    return {"status": "ok", "mongodb": "connected", "sqlite": "available"}


# Import non-RAG routers after limiter init so rate-limit decorators share
# this limiter. Voice/AI routers load Chroma/HuggingFace and are mounted
# in lifespan so /health can pass while those imports finish.
from .routes.auth import router as auth_router
from .routes.profile import router as profile_router
from .routes.progress import router as progress_router
from .routes.notifications import router as notification_router
from .routes.meal import router as meal_planner_router
from .routes.workout import router as workout_planner_router

app.include_router(auth_router, prefix="/api/v1")
app.include_router(profile_router, prefix="/api/v1")
app.include_router(progress_router, prefix="/api/v1")
app.include_router(notification_router, prefix="/api/v1")
app.include_router(workout_planner_router, prefix="/api/v1")
app.include_router(meal_planner_router, prefix="/api/v1")


# Global exception handler
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """
    Global exception handler for unhandled errors
    """
    error_id = uuid4().hex
    logger.error(
        "Unhandled exception [%s] on %s %s: %s",
        error_id,
        request.method,
        request.url.path,
        exc,
        exc_info=True,
    )
    
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "detail": "An internal server error occurred.",
            "error": {"message": "An internal server error occurred."},
        },
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=settings.PORT,
        reload=settings.DEBUG
    )
