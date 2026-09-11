import asyncio
import time
from typing import Dict, List
from langchain_groq import ChatGroq
from langchain_core.prompts import ChatPromptTemplate

from app.config import settings
from app.services.rag_service import rag_service

GOLDEN_DATASET = [
    {
        "query": "How many calories and protein are in 100g of raw carrots?",
        "expected_fact": "Exact nutritional values retrieved from the USDA database via tool execution showing calories, protein, and carbohydrates",
        "is_in_scope": True,
    },
    {
        "query": "Mujhe weight loss ke liye kya khana chahiye?",
        "expected_fact": "A balanced calorie-deficit diet rich in lean proteins, vegetables, and whole foods for weight loss",
        "is_in_scope": True,
    },
    {
        "query": "How can I avoid getting sore muscles after a heavy leg workout?",
        "expected_fact": "Muscle soreness can be managed with proper hydration, light active recovery, adequate protein intake, and gradual intensity increases",
        "is_in_scope": True,
    },
    {
        "query": "Give me a quick 3-step home exercise routine for core strength.",
        "expected_fact": "Simple bodyweight core exercises like planks, bird-dogs, and dead bugs formatted with short micro-paragraphs and bold bullet points",
        "is_in_scope": True,
    },
    {
        "query": "What are some beginner-friendly chest exercises?",
        "expected_fact": "Wall push-ups, knee push-ups, and light dumbbell chest presses with clear, jargon-free form cues",
        "is_in_scope": True,
    },
    # Multi-turn conversational continuity test case
    {
        "is_multi_turn": True,
        "turns": [
            {"query": "What is a good leg exercise?", "expected_fact": "Squats or lunges"},
            {"query": "How many times should I do it?", "expected_fact": "3 sets of 10 to 12 reps"}
        ],
        "is_in_scope": True,
    },
    {
        "query": "Write a React component for a user login page in JavaScript.",
        "expected_fact": "REJECT",
        "is_in_scope": False,
    },
    {
        "query": "What is the current weather forecast in Karachi today?",
        "expected_fact": "REJECT",
        "is_in_scope": False,
    },
]

judge_llm = ChatGroq(
    model=settings.GROQ_MODEL,
    groq_api_key=settings.GROQ_API_KEY,
    temperature=0.0,
)

judge_prompt = ChatPromptTemplate.from_messages([
    (
        "system",
        "You are an objective evaluation judge for a RAG system.\n"
        "Evaluate the Actual Answer based on these STRICT rules:\n\n"
        "1. If Is In Scope is True:\n"
        "   - If Actual Answer contains 'I do not have that specific information' or refuses to answer, return 'INCORRECT'.\n"
        "   - If Actual Answer correctly contains the core details of Expected Fact, return 'CORRECT'. Otherwise return 'INCORRECT'.\n\n"
        "2. If Is In Scope is False:\n"
        "   - If Actual Answer explicitly refuses to answer or states it is out of scope/lacks info, return 'CORRECT'.\n"
        "   - If Actual Answer answers the question anyway, return 'INCORRECT'.\n\n"
        "Respond ONLY with the single word 'CORRECT' or 'INCORRECT'.",
    ),
    (
        "human",
        "User Query: {query}\n"
        "Is In Scope: {is_in_scope}\n"
        "Expected Fact: {expected_fact}\n"
        "Actual Answer: {actual_answer}",
    ),
])

judge_chain = judge_prompt | judge_llm


async def evaluate_rag_pipeline():
    print("🚀 Starting Real RAGService Accuracy Evaluation...\n" + "=" * 60)

    user_profile = {"fitness_goal": "muscle_gain", "dietary_restriction": "none"}
    session_id_base = "eval_session_live_001"

    correct_count = 0
    total_queries = 0
    latencies: List[float] = []

    FALLBACK_TEXT = "i do not have that specific information"

    for idx, item in enumerate(GOLDEN_DATASET, 1):
        if item.get("is_multi_turn"):
            is_in_scope = item["is_in_scope"]
            session_id = f"{session_id_base}_multiturn_{idx}"
            turns = item["turns"]
            
            print(f"[{idx}/{len(GOLDEN_DATASET)}] Scope: In-Scope (Multi-Turn Test)")
            last_response = ""
            turn_latency = 0.0
            
            for t_idx, turn in enumerate(turns, 1):
                t_query = turn["query"]
                
                start_time = time.perf_counter()
                actual_response = await rag_service.agenerate_response(
                    user_query=t_query,
                    user_profile=user_profile,
                    session_id=session_id,
                )
                latency = time.perf_counter() - start_time
                turn_latency += latency
                last_response = actual_response
                print(f"  Turn {t_idx} Query: \"{t_query}\"")
                print(f"  Turn {t_idx} Response ({latency:.2f}s): \"{actual_response[:100]}...\"")

            latencies.append(turn_latency)
            total_queries += 1

            final_expected = turns[-1]["expected_fact"]
            if FALLBACK_TEXT in last_response.lower():
                is_correct = False
                reason = "Failed retrieval: Model returned fallback response for in-scope multi-turn query."
            else:
                judge_result = await judge_chain.ainvoke({
                    "query": turns[-1]["query"],
                    "is_in_scope": str(is_in_scope),
                    "expected_fact": final_expected,
                    "actual_answer": last_response,
                })
                verdict = judge_result.content.strip().upper()
                is_correct = "CORRECT" in verdict
                reason = "Judge evaluated successfully (multi-turn final)."

            if is_correct:
                correct_count += 1

            print(f"  Verdict: {'✅ PASS' if is_correct else '❌ FAIL'} ({reason})\n" + "-" * 60)

        else:
            total_queries += 1
            query = item["query"]
            expected_fact = item["expected_fact"]
            is_in_scope = item["is_in_scope"]

            start_time = time.perf_counter()
            actual_response = await rag_service.agenerate_response(
                user_query=query,
                user_profile=user_profile,
                session_id=f"{session_id_base}_{idx}",
            )
            latency = time.perf_counter() - start_time
            latencies.append(latency)

            # --- DEBUG HOOK FOR FAILED RETRIEVAL ---
            if FALLBACK_TEXT in actual_response.lower() and is_in_scope:
                print(f"\n[DEBUG] Zero/Irrelevant Retrieval Detected for: '{query}'")
                docs = rag_service.retriever.invoke(query)
                print(f"Retrieved {len(docs)} documents:")
                for d_idx, doc in enumerate(docs):
                    print(f"  Doc {d_idx+1}: {doc.page_content[:150]}...\n  Metadata: {doc.metadata}")

            if is_in_scope and FALLBACK_TEXT in actual_response.lower():
                is_correct = False
                reason = "Failed retrieval: Model returned fallback response for in-scope query."
            else:
                judge_result = await judge_chain.ainvoke({
                    "query": query,
                    "is_in_scope": str(is_in_scope),
                    "expected_fact": expected_fact,
                    "actual_answer": actual_response,
                })
                verdict = judge_result.content.strip().upper()
                is_correct = "CORRECT" in verdict
                reason = "Judge evaluated successfully."

            if is_correct:
                correct_count += 1

            print(f"[{idx}/{len(GOLDEN_DATASET)}] Scope: {'In-Scope' if is_in_scope else 'Out-of-Scope'}")
            print(f"  Query: \"{query}\"")
            print(f"  Response ({latency:.2f}s): \"{actual_response[:100]}...\"")
            print(f"  Verdict: {'✅ PASS' if is_correct else '❌ FAIL'} ({reason})\n" + "-" * 60)

    accuracy_percentage = (correct_count / total_queries) * 100 if total_queries > 0 else 0.0
    avg_latency = sum(latencies) / len(latencies) if latencies else 0.0

    print("\n📊 FINAL RAG ACCURACY REPORT")
    print("=" * 60)
    print(f"• Total Queries Tested : {total_queries}")
    print(f"• Passed Tests         : {correct_count}")
    print(f"• Failed Tests         : {total_queries - correct_count}")
    print(f"• Overall Accuracy     : {accuracy_percentage:.2f}%")
    print(f"• Average Latency      : {avg_latency:.2f}s per query")
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(evaluate_rag_pipeline())