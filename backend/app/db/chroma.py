import os
from typing import Optional
from langchain_chroma import Chroma
from langchain_huggingface import HuggingFaceEndpointEmbeddings
from app.config import settings

os.environ["ANONYMIZED_TELEMETRY"] = "False"


def get_embeddings() -> HuggingFaceEndpointEmbeddings:
    """Initialize serverless cloud embeddings."""
    return HuggingFaceEndpointEmbeddings(
        model="BAAI/bge-base-en-v1.5",
        task="feature-extraction",
        huggingfacehub_api_token=os.getenv("HUGGINGFACEHUB_API_TOKEN")
        or getattr(settings, "HUGGINGFACEHUB_API_TOKEN", None),
    )


def get_vector_store(
    collection_name: str = "fitnova_knowledge",
    persist_directory: Optional[str] = None,
) -> Chroma:
    embeddings = get_embeddings()
    target_dir = persist_directory or settings.CHROMA_PERSIST_DIRECTORY
    return Chroma(
        collection_name=collection_name,
        persist_directory=target_dir,
        embedding_function=embeddings,
    )