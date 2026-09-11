import os
from typing import Optional
from langchain_chroma import Chroma
from langchain_huggingface import HuggingFaceEmbeddings
from app.config import settings

os.environ["ANONYMIZED_TELEMETRY"] = "False"


def get_embeddings() -> HuggingFaceEmbeddings:
    return HuggingFaceEmbeddings(
        model_name="BAAI/bge-base-en-v1.5",
        encode_kwargs={"normalize_embeddings": True} 
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