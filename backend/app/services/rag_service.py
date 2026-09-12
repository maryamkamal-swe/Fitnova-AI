import json
import logging
import re
import sqlite3
from uuid import uuid4
from contextlib import closing
from typing import Any, AsyncGenerator, Dict, List, Optional
from pathlib import Path

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
IN_SCOPE_PATTERN = re.compile(
    r"\b(fitness|workout|exercise|training|gym|muscle|strength|cardio|"
    r"nutrition|food|meal|diet|eat|eating|calorie|protein|carb|fat|"
    r"fiber|fibre|sugar|sodium|cholesterol|vitamin|vitamins|mineral|"
    r"minerals|ingredient|ingredients|portion|serving|snack|breakfast|"
    r"lunch|dinner|rice|egg|eggs|chicken|milk|bread|weight|bmi|sleep|"
    r"hydration|water|recovery|health|wellness|recipe|body|"
    r"family|families|household|batch|pot|cooking|cooked|ladle|bowl|"
    r"estimate|estimator|macro|macros|kcal|portioning|servings|"
    r"sehat|sehatmand|khana|khurak|nashta|dophar|dopahar|raat|"
    r"pani|wazan|vazan|charbi|motapa|kam|zyada|faida|faide|"
    r"kitna|kitni|kitne|ghar|walay|wale|wali|log|bachay|bache|"
    r"anda|anday|gosht|murghi|chawal|doodh|daal|dal|aloo|roti|"
    r"chai|cheeni|namak|tel|ghee|bhook|hazma|qabz)\b",
    re.IGNORECASE,
)
IN_SCOPE_TERMS = (
    "fitness", "workout", "exercise", "training", "gym", "muscle", "strength",
    "cardio", "nutrition", "food", "meal", "diet", "eat", "eating", "calorie",
    "protein", "carb", "fat", "fiber", "fibre", "sugar", "sodium",
    "cholesterol", "vitamin", "mineral", "ingredient", "portion", "serving",
    "snack", "breakfast", "lunch", "dinner", "rice", "egg", "chicken", "milk",
    "bread", "weight", "bmi", "sleep", "hydration", "water", "recovery",
    "health", "wellness", "recipe", "body", "family", "household", "batch",
    "cooking", "cooked", "ladle", "bowl", "estimate", "estimator", "macro",
    "macros", "kcal", "sehat", "khana", "khurak", "nashta", "pani", "wazan",
    "vazan", "charbi", "motapa", "faida", "kitna", "kitni", "kitne", "ghar",
    "anda", "gosht", "murghi", "chawal", "doodh", "daal", "dal", "aloo",
    "roti", "chai", "cheeni", "namak", "ghee", "bhook", "hazma", "qabz",
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
ROMAN_URDU_HINT_PATTERN = re.compile(
    r"\b(mujhe|mujhy|mera|meri|mere|aap|ap|kya|kyun|kaise|kaisa|"
    r"ke|ki|ka|mein|main|hai|hain|ho|karna|karo|batao|batayein|"
    r"sehat|khana|khurak|nashta|pani|wazan|vazan|charbi|motapa|"
    r"faida|faide|kitna|kitni|kitne|ghar|walay|wale|wali|"
    r"anda|anday|gosht|murghi|chawal|doodh|daal|dal|aloo|roti)\b",
    re.IGNORECASE,
)
STOP_WORDS = {
    "100", "50", "200", "500", "gram", "grams", "g", "kg", "ml", "cup",
    "cups", "oz", "lb", "mein", "me", "hota", "hoti", "hotai", "hai",
    "hain", "calories", "calorie", "protein", "carbs", "fat", "aur", "and",
    "or", "kya", "ki", "ka", "ke", "wala", "wali", "wale", "batayein",
    "batao", "tell", "how", "many", "is", "are", "in", "of", "the", "a",
    "an", "to", "get", "versus", "vs", "compared", "difference", "between",
}


def normalize_roman_urdu(query: str) -> str:
    normalized = query.lower()
    for pattern, replacement in ROMAN_URDU_REPLACEMENTS.items():
        normalized = re.sub(pattern, replacement, normalized)
    return normalized


def _detect_query_language(query: str, language_code: Optional[str] = None) -> str:
    requested = (language_code or "").split("-")[0].split("_")[0].lower()
    if requested:
        return requested
    if re.search(r"[\u0600-\u06ff]", query):
        return "ur"
    if re.search(r"[\u0900-\u097f]", query):
        return "hi"
    if ROMAN_URDU_HINT_PATTERN.search(query):
        return "ur"
    return "en"


def translate_query_to_english(
    query: str, language_code: Optional[str] = None
) -> str:
    """Normalize Roman Urdu and translate script-based/non-English input for RAG."""
    source_language = _detect_query_language(query, language_code)
    if source_language == "en" or not query.strip():
        return normalize_roman_urdu(query)
    if (
        source_language in {"ur", "hi"}
        and not re.search(r"[\u0600-\u06ff\u0900-\u097f]", query)
        and not ROMAN_URDU_HINT_PATTERN.search(query)
    ):
        # A user may select Urdu/Hindi while speaking entirely in English.
        return normalize_roman_urdu(query)

    from app.voice.translator import translate_to_english

    return normalize_roman_urdu(
        translate_to_english(query, source_language)
    )


def _edit_distance(left: str, right: str) -> int:
    previous = list(range(len(right) + 1))
    for left_index, left_char in enumerate(left, start=1):
        current = [left_index]
        for right_index, right_char in enumerate(right, start=1):
            current.append(
                min(
                    current[-1] + 1,
                    previous[right_index] + 1,
                    previous[right_index - 1] + (left_char != right_char),
                )
            )
        previous = current
    return previous[-1]


def _has_fuzzy_in_scope_term(query: str) -> bool:
    for token in re.findall(r"[a-z]+", query.lower()):
        if len(token) < 4:
            continue
        max_distance = 2 if len(token) >= 7 else 1
        if any(
            abs(len(token) - len(term)) <= max_distance
            and _edit_distance(token, term) <= max_distance
            for term in IN_SCOPE_TERMS
        ):
            return True
    return False


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
    """Search the local nutrition database using flexible keyword matching with LLM fallback."""
    db_path = settings.SQLITE_DB_PATH
    sqlite_file = Path(db_path).resolve().as_posix()  # <-- Add this line here
    clean_query = normalize_roman_urdu(food_query)
    
    # Extract distinct non-stopword tokens
    tokens = [
        word.strip(".,?!()[]") 
        for word in clean_query.split() 
        if word.strip(".,?!()[]") not in STOP_WORDS and len(word.strip(".,?!()[]")) > 2
    ]
    
    if not tokens:
        return "Tool Message: No specific database keywords found. Fallback: Use general nutritional knowledge."

    try:
        # Update connection string to use sqlite_file instead of raw db_path
        with closing(sqlite3.connect(f"file:{sqlite_file}?mode=ro", uri=True)) as connection:
            cursor = connection.cursor()
            
            # Construct dynamic token-matching SQL
            conditions = " OR ".join(["f.description LIKE ?"] * len(tokens))
            params = [f"%{token}%" for token in tokens]
            
            query_str = f"""
                SELECT f.description, m.amount, n.name, n.unit_name
                FROM foods f
                JOIN macros m ON f.fdc_id = m.fdc_id
                JOIN nutrients n ON m.nutrient_id = n.id
                WHERE {conditions}
                LIMIT 30
            """
            cursor.execute(query_str, params)
            rows = cursor.fetchall()
    except (sqlite3.Error, OSError) as error:
        error_id = uuid4().hex
        logger.exception(
            "Nutrition database infrastructure failure [%s]: %s",
            error_id,
            error,
        )
        return "Tool Message: Database temporarily unavailable. Fallback: Estimate values using general AI knowledge."
    except Exception as error:
        logger.warning(f"Nutrition DB lookup failed: {error}")
        return "Tool Message: Database temporarily unavailable. Fallback: Estimate values using general AI knowledge."

    if not rows:
        return f"Tool Message: No database match found for '{food_query}'. Fallback: Use general expert nutritional knowledge to estimate standard values."

    # Format multi-item matches
    food_data: Dict[str, Dict[str, str]] = {}
    for food_name, amount, nutrient_name, unit in rows:
        if food_name not in food_data:
            food_data[food_name] = {}
        food_data[food_name][nutrient_name] = f"{amount} {unit}"

    formatted_matches = []
    for name, macros in list(food_data.items())[:3]:
        formatted_matches.append(f"Food: {name} | Macros (per 100g): {macros}")

    return "\n".join(formatted_matches)


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
        self.fallback_llm = (
            ChatGroq(
                model=settings.GROQ_FALLBACK_MODEL,
                groq_api_key=settings.GROQ_FALLBACK_API_KEY,
                temperature=0.1,
            )
            if settings.GROQ_FALLBACK_API_KEY and settings.GROQ_FALLBACK_MODEL
            else None
        )
        self.vector_store = get_vector_store(
            collection_name=self.collection_name,
            persist_directory=self.persist_directory,
        )
        self.retriever = self.vector_store.as_retriever(
            search_type="similarity_score_threshold",
            search_kwargs={"k": 4, "score_threshold": 0.2},
        )
        self.rag_chain = self._build_chain(self.llm)
        self.fallback_chain = (
            self._build_chain(self.fallback_llm) if self.fallback_llm else None
        )

    def _build_chain(self, llm):
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
            llm, self.retriever, contextualize_prompt
        )
        system_prompt = (
            "You are FitNova AI, an expert fitness and nutrition coach.\n"
            "Always answer in clear English, including for Roman Urdu input.\n"
            "Use only the retrieved context, authenticated user profile, and "
            "nutrition tool results. If information is unavailable, say so clearly.\n"
            "If nutrition tool results state that database values are missing or unavailable, "
            "use your general expert nutritional knowledge to provide accurate macro estimates.\n"
            "Use concise mobile-friendly bullets and never reveal hidden reasoning. "
            "Never use Markdown tables; use short labeled bullets instead.\n\n"
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
            "Use retrieved context, authenticated user profile, and nutrition tool results. "
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
            create_stuff_documents_chain(llm, qa_prompt),
        )

    async def _invoke_chain_with_fallback(self, chain_input: dict):
        try:
            return await self.rag_chain.ainvoke(chain_input)
        except Exception as primary_error:
            if self.fallback_chain is None:
                raise
            logger.exception(
                "Primary RAG provider failed; attempting configured fallback: %s",
                primary_error,
            )
            return await self.fallback_chain.ainvoke(chain_input)

    async def _stream_chain_with_fallback(self, chain_input: dict):
        try:
            async for chunk in self.rag_chain.astream(chain_input):
                yield chunk
        except Exception as primary_error:
            if self.fallback_chain is None:
                raise
            logger.exception(
                "Primary streaming RAG provider failed; attempting configured fallback: %s",
                primary_error,
            )
            async for chunk in self.fallback_chain.astream(chain_input):
                yield chunk

    def is_query_off_topic(self, query: str) -> bool:
        query = normalize_roman_urdu(query)
        # Keep explicit off-topic blocking, but let the model handle natural
        # language, spelling variants, and mixed Urdu-English questions.
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
        cleaned_query = normalize_roman_urdu(user_query)
        if not validate_user_prompt(cleaned_query):
            return {"answer": SAFETY_RESPONSE, "sources": []}
        if self.is_query_off_topic(cleaned_query):
            return {"answer": OUT_OF_SCOPE_MESSAGE, "sources": []}

        owner_id = user_id or "anonymous"
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
            result = await self._invoke_chain_with_fallback(
                {
                    "input": cleaned_query,
                    "user_profile": f"{profile_string}\nNutrition tool result: {tool_context}",
                    "chat_history": history.messages[-self.max_history_messages :],
                }
            )
        except (TimeoutError, ConnectionError) as error:
            error_id = uuid4().hex
            logger.exception(
                "RAG provider/infrastructure failure [%s]: %s",
                error_id,
                error,
            )
            return {
                "answer": "The AI coach is busy right now. Please wait a moment and try again.",
                "sources": [],
            }
        except (ValueError, TypeError) as error:
            error_id = uuid4().hex
            logger.exception(
                "RAG response validation failure [%s]: %s", error_id, error
            )
            return {
                "answer": "The AI coach is busy right now. Please wait a moment and try again.",
                "sources": [],
            }
        except Exception as error:
            error_id = uuid4().hex
            logger.exception(
                "Unexpected RAG generation failure [%s]: %s", error_id, error
            )
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
        cleaned_query = normalize_roman_urdu(user_query)
        if not validate_user_prompt(cleaned_query) or self.is_query_off_topic(
            cleaned_query
        ):
            yield f"data: {json.dumps({'content': OUT_OF_SCOPE_MESSAGE})}\n\n"
            return

        owner_id = user_id or "anonymous"
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
            async for chunk in self._stream_chain_with_fallback(
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

        except (TimeoutError, ConnectionError) as error:
            error_id = uuid4().hex
            logger.exception(
                "Streaming RAG provider/infrastructure failure [%s]: %s",
                error_id,
                error,
            )
            yield f"data: {json.dumps({'content': 'The AI coach encountered an issue. Please try again.'})}\n\n"
        except (ValueError, TypeError) as error:
            error_id = uuid4().hex
            logger.exception(
                "Streaming RAG response validation failure [%s]: %s",
                error_id,
                error,
            )
            yield f"data: {json.dumps({'content': 'The AI coach encountered an issue. Please try again.'})}\n\n"
        except Exception as error:
            error_id = uuid4().hex
            logger.exception(
                "Unexpected streaming RAG failure [%s]: %s", error_id, error
            )
            yield f"data: {json.dumps({'content': 'The AI coach encountered an issue. Please try again.'})}\n\n"


rag_service = RAGService()