import json
import logging
import re
import sqlite3
from contextlib import closing
from typing import Any, AsyncGenerator, Dict, List, Optional

from langchain.chains import create_history_aware_retriever, create_retrieval_chain
from langchain.chains.combine_documents import create_stuff_documents_chain
from langchain_core.messages import AIMessage, HumanMessage
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
from langchain_core.tools import tool
from langchain_groq import ChatGroq

from app.config import settings
from app.database import MongoChatMessageHistory
from app.db.chroma import get_vector_store

logger = logging.getLogger(__name__)

OUT_OF_SCOPE_PATTERN = re.compile(
    r"\b(weather|forecast|temperature|rain|python|code|coding|javascript|"
    r"bug|movie|president|capital|math|algebra|physics|recipe for cake)\b",
    re.IGNORECASE,
)
OUT_OF_SCOPE_MESSAGE = (
    "I can only assist with fitness, nutrition, and wellness topics."
)
SAFETY_RESPONSE = "I can only assist with fitness, nutrition, and wellness topics."
PROMPT_INJECTION_PATTERN = re.compile(
    r"(ignore\s+(?:all\s+|any\s+|the\s+)?previous\s+instructions?|"
    r"disregard\s+(?:all\s+|any\s+|the\s+)?instructions?|"
    r"system\s+prompt|reveal\s+(?:your\s+)?prompt|"
    r"developer\s+message|jailbreak|DAN\s+mode|do\s+anything\s+now)",
    re.IGNORECASE,
)
MALICIOUS_INSTRUCTION_PATTERN = re.compile(
    r"\b(?:malware|ransomware|phishing|credential theft|steal passwords|"
    r"bypass authentication|exploit vulnerability|sql injection|"
    r"ddos|make a bomb|weapon|harm someone)\b",
    re.IGNORECASE,
)


def validate_user_prompt(prompt: str) -> bool:
    """Return False for prompt overrides or clearly malicious requests."""
    if not isinstance(prompt, str) or not prompt.strip():
        return False
    return not (
        PROMPT_INJECTION_PATTERN.search(prompt)
        or MALICIOUS_INSTRUCTION_PATTERN.search(prompt)
    )


ROMAN_URDU_REPLACEMENTS = {
    r"\bweight loose\b": "weight loss",
    r"\bweight kam\b": "weight loss",
    r"\bcharbi\b": "fat",
    r"\bmotapa\b": "weight loss",
    r"\bkhana\b": "diet",
    r"\bneend\b": "sleep",
    r"\bexercise\b": "workout",
    r"\bkitna\b": "how much",
    r"\bkitni\b": "how much",
    r"\bkarna\b": "do",
    r"\banda(?:y)?\b": "egg",
    r"\bgosht\b": "meat",
    r"\bmurghi\b": "chicken",
    r"\bchawal\b": "rice",
    r"\bdoodh\b": "milk",
    r"\bdall?\b": "lentils",
    r"\baloo\b": "potato",
    r"\broti\b": "bread",
}
STOP_WORDS = {
    "100", "50", "200", "500", "gram", "grams", "g", "kg", "ml", "cup",
    "cups", "oz", "lb", "mein", "me", "hota", "hoti", "hotai", "hai",
    "hain", "calories", "calorie", "protein", "carbs", "fat", "aur", "and",
    "or", "kya", "ki", "ka", "ke", "wala", "wali", "wale", "batayein",
    "batao", "tell", "how", "many", "is", "are", "in", "of", "the", "a",
    "an", "to", "get",
}


def normalize_roman_urdu(query: str) -> str:
    normalized = query.lower()
    for pattern, replacement in ROMAN_URDU_REPLACEMENTS.items():
        normalized = re.sub(pattern, replacement, normalized)
    return normalized


def _food_query_from_text(query: str) -> str:
    words = [
        word.strip(".,?!()[]")
        for word in normalize_roman_urdu(query).split()
        if word.strip(".,?!()[]") not in STOP_WORDS
        and not word.strip(".,?!()[]").isdigit()
    ]
    return " ".join(words) or "chicken"


@tool
def search_food_macros(food_query: str) -> str:
    """Search the local nutrition database for food macros."""
    db_path = settings.SQLITE_DB_PATH
    clean_query = normalize_roman_urdu(food_query)
    try:
        with closing(sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)) as connection:
            cursor = connection.cursor()
            cursor.execute(
                """
                SELECT f.description, m.amount, n.name, n.unit_name
                FROM foods f
                JOIN macros m ON f.fdc_id = m.fdc_id
                JOIN nutrients n ON m.nutrient_id = n.id
                WHERE f.description LIKE ?
                LIMIT 10
                """,
                (f"%{clean_query}%",),
            )
            rows = cursor.fetchall()
    except sqlite3.Error as error:
        raise RuntimeError(f"Nutrition database query failed: {error}") from error

    if not rows:
        return f"No nutritional data found for '{food_query}'."

    food_name = rows[0][0]
    macros = {name: f"{amount} {unit}" for _, amount, name, unit in rows}
    return f"Food: {food_name} | Macros (per 100g): {macros}"


class RAGService:
    def __init__(
        self,
        collection_name: Optional[str] = None,
        persist_directory: Optional[str] = None,
        max_history_messages: int = 6,
    ):
        self.collection_name = collection_name or settings.CHROMA_COLLECTION_NAME
        self.persist_directory = (
            persist_directory or settings.CHROMA_PERSIST_DIRECTORY
        )
        self.max_history_messages = max_history_messages

        self.llm = ChatGroq(
            model=settings.GROQ_MODEL,
            groq_api_key=settings.GROQ_API_KEY,
            temperature=0.1,
        )
        self.vector_store = get_vector_store(
            collection_name=self.collection_name,
            persist_directory=self.persist_directory,
        )
        self.retriever = self.vector_store.as_retriever(
            search_type="similarity_score_threshold",
            search_kwargs={"k": 4, "score_threshold": 0.2},
        )
        self.rag_chain = self._build_chain()

    def _build_chain(self):
        contextualize_prompt = ChatPromptTemplate.from_messages(
            [
                (
                    "system",
                    "Rewrite the latest question as a standalone English question. "
                    "Do not answer it.",
                ),
                MessagesPlaceholder("chat_history"),
                ("human", "{input}"),
            ]
        )
        history_aware_retriever = create_history_aware_retriever(
            self.llm, self.retriever, contextualize_prompt
        )
        system_prompt = (
            "You are FitNova AI, an expert fitness and nutrition coach.\n"
            "Always answer in clear English, including for Roman Urdu input.\n"
            "Use only the retrieved context, authenticated user profile, and "
            "nutrition tool results. If information is unavailable, say so clearly.\n"
            "Use concise mobile-friendly bullets and never reveal hidden reasoning. "
            "Never use Markdown tables because the Coach is read on narrow phone "
            "screens; use short labeled bullets instead.\n\n"
            "For shared family-pot or batch-cooking questions, such as daal, "
            "chana, karahi, rice, or similar dishes, treat the stated ingredients "
            "as the full batch and the stated ladles, bowls, grams, or servings "
            "as the user's portion. Estimate total batch calories and macros from "
            "retrieved nutrition/tool values, explicitly include oil or ghee "
            "calories, estimate the total cooked yield, divide batch totals by "
            "that yield or stated servings, and scale to the user's portion. "
            "If ladle or bowl volume is not provided by retrieved context, state "
            "the practical volume assumption and present the result as an estimate "
            "or range rather than false precision. Do not silently invent a "
            "regional conversion factor. Format these answers with a bolded "
            "Macro Summary containing Calories, Protein, Carbs, and Fats, then "
            "give concise guidance for logging the estimated values in daily "
            "progress.\n\n"
            "Authenticated user profile: {user_profile}\n\n"
            "Retrieved context: {context}"
        )
        qa_prompt = ChatPromptTemplate.from_messages(
            [
                ("system", system_prompt),
                MessagesPlaceholder("chat_history"),
                ("human", "{input}"),
            ]
        )
        return create_retrieval_chain(
            history_aware_retriever,
            create_stuff_documents_chain(self.llm, qa_prompt),
        )

    def is_query_off_topic(self, query: str) -> bool:
        return bool(OUT_OF_SCOPE_PATTERN.search(query))

    async def _history(
        self, user_id: str, session_id: str
    ) -> MongoChatMessageHistory:
        history = MongoChatMessageHistory(user_id=user_id, session_id=session_id)
        await history.aget_messages()
        return history

    def _format_profile(self, user_profile: Dict[str, Any]) -> str:
        return "\n".join(
            f"{key.replace('_', ' ').capitalize()}: {val}"
            for key, val in user_profile.items()
        )

    async def agenerate_response(
        self,
        user_query: str,
        user_profile: Dict[str, Any],
        session_id: str,
        user_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        if not validate_user_prompt(user_query):
            return {"answer": SAFETY_RESPONSE, "sources": []}
        if self.is_query_off_topic(user_query):
            return {"answer": OUT_OF_SCOPE_MESSAGE, "sources": []}

        owner_id = user_id or "anonymous"
        cleaned_query = normalize_roman_urdu(user_query)
        history = await self._history(owner_id, session_id)
        tool_sources: List[Dict[str, Any]] = []
        tool_context = ""

        if any(
            keyword in cleaned_query
            for keyword in ("calorie", "protein", "nutrition", "carb", "fat", "gram")
        ) or any(
            replacement in cleaned_query
            for replacement in ("egg", "chicken", "milk", "lentils", "rice", "potato")
        ):
            food_query = _food_query_from_text(cleaned_query)
            tool_context = await search_food_macros.ainvoke(food_query)
            tool_sources.append(
                {"tool": "search_food_macros", "args": {"food_query": food_query}}
            )

        profile_string = self._format_profile(user_profile)

        try:
            result = await self.rag_chain.ainvoke(
                {
                    "input": cleaned_query,
                    "user_profile": f"{profile_string}\nNutrition tool result: {tool_context}",
                    "chat_history": history.messages[-self.max_history_messages :],
                }
            )
        except Exception as e:
            logger.exception(f"agenerate_response failed: {e}")
            return {
                "answer": "The AI coach is busy right now. Please wait a moment and try again.",
                "sources": [],
            }

        answer = result.get(
            "answer", "I do not have that specific information in my knowledge base."
        )

        sources = list(tool_sources)
        seen = set()
        for document in result.get("context", []):
            source = document.metadata.get("source", "Knowledge Base")
            page = document.metadata.get("page_number")
            key = (source, page)
            if key not in seen:
                seen.add(key)
                sources.append(
                    {
                        "title": document.metadata.get("title", source),
                        "source": source,
                        "page_number": page,
                    }
                )

        await history.aadd_messages(
            [HumanMessage(content=user_query), AIMessage(content=answer)]
        )
        return {"answer": answer, "sources": sources}

    async def astream_response(
        self,
        user_query: str,
        user_profile: Dict[str, Any],
        session_id: str,
        user_id: Optional[str] = None,
    ) -> AsyncGenerator[str, None]:
        """Stream genuine token chunks via Server-Sent Events (SSE)."""
        if not validate_user_prompt(user_query) or self.is_query_off_topic(user_query):
            yield f"data: {json.dumps({'content': OUT_OF_SCOPE_MESSAGE})}\n\n"
            return

        owner_id = user_id or "anonymous"
        cleaned_query = normalize_roman_urdu(user_query)
        history = await self._history(owner_id, session_id)
        tool_context = ""

        if any(
            keyword in cleaned_query
            for keyword in ("calorie", "protein", "nutrition", "carb", "fat", "gram")
        ) or any(
            replacement in cleaned_query
            for replacement in ("egg", "chicken", "milk", "lentils", "rice", "potato")
        ):
            food_query = _food_query_from_text(cleaned_query)
            tool_context = await search_food_macros.ainvoke(food_query)

        profile_string = self._format_profile(user_profile)
        full_answer_accumulator = []

        try:
            async for chunk in self.rag_chain.astream(
                {
                    "input": cleaned_query,
                    "user_profile": f"{profile_string}\nNutrition tool result: {tool_context}",
                    "chat_history": history.messages[-self.max_history_messages :],
                }
            ):
                token = ""
                if isinstance(chunk, dict):
                    token = chunk.get("answer") or ""
                elif hasattr(chunk, "content"):
                    token = chunk.content or ""

                if token and isinstance(token, str):
                    full_answer_accumulator.append(token)
                    yield f"data: {json.dumps({'content': token})}\n\n"

            complete_text = "".join(full_answer_accumulator)
            if complete_text:
                await history.aadd_messages(
                    [HumanMessage(content=user_query), AIMessage(content=complete_text)]
                )

        except Exception as e:
            logger.exception(f"Streaming failed due to: {e}")
            yield f"data: {json.dumps({'content': 'The AI coach encountered an issue. Please try again.'})}\n\n"


rag_service = RAGService()