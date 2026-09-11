import csv
import hashlib
import json
from pathlib import Path
from typing import Iterator, List

from langchain_core.documents import Document
from langchain_text_splitters import RecursiveCharacterTextSplitter
from pypdf import PdfReader

from app.config import settings
from app.db.chroma import get_vector_store


def _read_markdown_file(path: Path) -> List[Document]:
    with open(path, "r", encoding="utf-8") as file:
        content = file.read()
    return [
        Document(
            page_content=content,
            metadata={"source": path.name, "file_type": "md", "title": path.stem},
        )
    ]


def _read_pdf_file(path: Path) -> List[Document]:
    reader = PdfReader(str(path))
    metadata = reader.metadata
    author = metadata.author if metadata and metadata.author else "Unknown"
    title = metadata.title if metadata and metadata.title else path.stem
    documents = []
    for index, page in enumerate(reader.pages):
        text = page.extract_text() or ""
        if text.strip():
            documents.append(
                Document(
                    page_content=text,
                    metadata={
                        "source": path.name,
                        "file_type": "pdf",
                        "page_number": index + 1,
                        "author": author,
                        "title": title,
                    },
                )
            )
    return documents


def _read_csv_file(path: Path) -> List[Document]:
    documents = []
    with open(path, newline="", encoding="utf-8-sig") as file:
        for index, row in enumerate(csv.DictReader(file)):
            documents.append(
                Document(
                    page_content=" | ".join(
                        f"{key}: {value}" for key, value in row.items() if value
                    ),
                    metadata={
                        "source": path.name,
                        "file_type": "csv",
                        "row_number": index + 1,
                    },
                )
            )
    return documents


def _read_json_file(path: Path) -> List[Document]:
    with open(path, "r", encoding="utf-8") as file:
        data = json.load(file)
    if isinstance(data, dict):
        data = [data]
    return [
        Document(
            page_content=json.dumps(item, ensure_ascii=False),
            metadata={"source": path.name, "file_type": "json", "item_index": index},
        )
        for index, item in enumerate(data)
    ]


def iter_documents_from_directory(directory: str) -> Iterator[Document]:
    for file_path in Path(directory).rglob("*"):
        if not file_path.is_file():
            continue
        readers = {
            ".pdf": _read_pdf_file,
            ".csv": _read_csv_file,
            ".json": _read_json_file,
            ".md": _read_markdown_file,
        }
        reader = readers.get(file_path.suffix.lower())
        if reader is None:
            continue
        yield from reader(file_path)


def _generate_chunk_id(document: Document) -> str:
    source = document.metadata.get("source", "unknown")
    position = "_".join(
        f"{key}{document.metadata.get(key, '')}"
        for key in ("page_number", "row_number", "item_index")
    )
    digest = hashlib.sha256(document.page_content.encode("utf-8")).hexdigest()[:16]
    return f"{source}_{position}_{digest}"


def index_directory(directory: str = "data", batch_size: int = 250) -> None:
    vector_store = get_vector_store()
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=1000,
        chunk_overlap=150,
        separators=["\n# ", "\n## ", "\n### ", "\n\n", "\n", " ", ""],
    )
    documents: List[Document] = []
    ids: List[str] = []
    total_documents = 0
    total_chunks = 0

    for document in iter_documents_from_directory(directory):
        total_documents += 1
        for chunk in splitter.split_documents([document]):
            documents.append(chunk)
            ids.append(_generate_chunk_id(chunk))
            if len(documents) >= batch_size:
                vector_store.add_documents(documents=documents, ids=ids)
                total_chunks += len(documents)
                documents.clear()
                ids.clear()

    if documents:
        vector_store.add_documents(documents=documents, ids=ids)
        total_chunks += len(documents)

    if total_chunks == 0:
        print(f"No valid documents found in '{directory}'. Check your file paths.")
        return
    print(
        f"Indexing complete! Processed {total_documents} source documents "
        f"and stored {total_chunks} chunks in ChromaDB."
    )


def index_knowledge_base(directory: str = "data") -> None:
    """Compatibility entry point used by the existing services package."""
    index_directory(directory)


if __name__ == "__main__":
    index_directory("data")
