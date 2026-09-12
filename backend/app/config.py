"""
Configuration settings for FitNova AI Backend
Loads environment variables and manages app configuration
Combines authentication, progress tracking, and RAG/AI features
"""
import json
from typing import Any, List

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


def parse_allowed_origins(value: Any) -> List[str]:
    """Split env origins into a CORS list (comma-separated string or JSON array)."""
    if value is None:
        return []
    if isinstance(value, (list, tuple, set)):
        raw_items = [str(item) for item in value]
    else:
        text = str(value).strip()
        if not text:
            return []
        if text.startswith("["):
            try:
                parsed = json.loads(text)
                raw_items = [str(item) for item in parsed]
            except json.JSONDecodeError:
                raw_items = text.split(",")
        else:
            raw_items = text.split(",")

    origins: List[str] = []
    seen = set()
    for item in raw_items:
        origin = item.strip().strip("\"'").rstrip("/")
        if not origin or origin in seen or origin == "*":
            continue
        seen.add(origin)
        origins.append(origin)
    return origins


class Settings(BaseSettings):
    # App Settings
    APP_NAME: str = "FitNova AI"
    DEBUG: bool = False
    ENVIRONMENT: str = "production"
    PORT: int = 8000
    ALLOWED_ORIGINS: str = (
        "https://fitnova-ai-dv0n.onrender.com,"
        "http://localhost:3000,http://localhost:8000,"
        "http://localhost:8080,http://127.0.0.1:8080,"
        "http://192.168.0.34:8000,http://10.0.2.2:8000,"
        "http://127.0.0.1:8000"
    )
    
    # MongoDB
    MONGODB_URI: str = "mongodb://localhost:27017"
    DATABASE_NAME: str = "fitnova_db"
    
    # JWT Authentication
    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7
    
    # AI/RAG Settings (Maryam's features)
    GROQ_API_KEY: str = ""
    GROQ_MODEL: str = "openai/gpt-oss-120b"
    GROQ_ROUTER_MODEL: str = "openai/gpt-oss-20b"
    GROQ_FALLBACK_API_KEY: str = ""
    GROQ_FALLBACK_MODEL: str = "openai/gpt-oss-20b"
    CHROMA_PERSIST_DIRECTORY: str = "./chroma_db"
    CHROMA_COLLECTION_NAME: str = "fitnova_knowledge"
    SQLITE_DB_PATH: str = "fitnova_nutrition.db"
    
    # OpenAI (for future use)
    OPENAI_API_KEY: str = ""
    
    # Firebase
    FIREBASE_CREDENTIALS_PATH: str = ""
    
    # Retell API (Voice features)
    RETELL_API_KEY: str = ""

    # Optional SMTP (Gmail / Brevo). Leave empty in development.
    SMTP_HOST: str = ""
    SMTP_PORT: int = 587
    SMTP_USER: str = ""
    SMTP_PASSWORD: str = ""
    SMTP_FROM: str = ""
    SMTP_USE_TLS: bool = True
    
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )

    @field_validator("ALLOWED_ORIGINS", mode="before")
    @classmethod
    def coerce_allowed_origins(cls, value: Any) -> str:
        if isinstance(value, (list, tuple, set)):
            return ",".join(parse_allowed_origins(value))
        return value

    @property
    def origins_list(self) -> List[str]:
        """CORS origins from a comma-separated env string or JSON array."""
        return parse_allowed_origins(self.ALLOWED_ORIGINS)


# Create global settings instance
settings = Settings()
