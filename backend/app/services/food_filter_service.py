# dietary_preferences entries -> tags that must NOT appear on a candidate dish.
# profile.dietary_preferences is free-text (List[str]), so unrecognized values
# are simply ignored rather than raising an error.
RESTRICTION_EXCLUDES = {
    "vegetarian": ["non_veg", "beef", "chicken", "mutton", "fish"],
    "vegan": ["non_veg", "beef", "chicken", "mutton", "fish", "dairy", "egg"],
    "no_beef": ["beef"],
    "no_nuts": ["contains_nuts"],
    "gluten_free": ["contains_gluten"],
    "dairy_free": ["dairy"],
}


def _excluded_tags(dietary_preferences: list[str]) -> list[str]:
    excluded: set[str] = set()
    for pref in dietary_preferences:
        excluded.update(RESTRICTION_EXCLUDES.get(pref.lower().strip(), []))
    return list(excluded)


DEFAULT_STAPLE_FOODS = [
    {"id": "staple-oats", "name": "Oats", "calories_per_100g": 389, "protein_g_per_100g": 17, "tags": ["vegetarian"], "cuisine": "international", "category": "breakfast"},
    {"id": "staple-eggs", "name": "Eggs", "calories_per_100g": 155, "protein_g_per_100g": 13, "tags": ["vegetarian", "egg"], "cuisine": "international", "category": "breakfast"},
    {"id": "staple-rice", "name": "Rice", "calories_per_100g": 130, "protein_g_per_100g": 2.7, "tags": ["vegetarian"], "cuisine": "desi", "category": "lunch"},
    {"id": "staple-daal", "name": "Daal", "calories_per_100g": 116, "protein_g_per_100g": 9, "tags": ["vegetarian"], "cuisine": "desi", "category": "lunch"},
    {"id": "staple-chicken", "name": "Chicken", "calories_per_100g": 165, "protein_g_per_100g": 31, "tags": ["non_veg", "chicken"], "cuisine": "desi", "category": "dinner"},
    {"id": "staple-roti", "name": "Roti", "calories_per_100g": 264, "protein_g_per_100g": 9, "tags": ["vegetarian", "contains_gluten"], "cuisine": "desi", "category": "dinner"},
    {"id": "staple-yogurt", "name": "Yogurt", "calories_per_100g": 59, "protein_g_per_100g": 10, "tags": ["vegetarian", "dairy"], "cuisine": "desi", "category": "snack"},
    {"id": "staple-banana", "name": "Banana", "calories_per_100g": 89, "protein_g_per_100g": 1.1, "tags": ["vegan"], "cuisine": "international", "category": "snack"},
]


def _default_foods(category: str, dietary_preferences: list[str]) -> list[dict]:
    excluded = set(_excluded_tags(dietary_preferences))
    foods = []
    for food in DEFAULT_STAPLE_FOODS:
        if food["category"] != category:
            continue
        if excluded and any(tag in excluded for tag in food.get("tags", [])):
            continue
        foods.append(food)
    return foods or [food for food in DEFAULT_STAPLE_FOODS if food["category"] == category] or list(DEFAULT_STAPLE_FOODS)


async def get_candidate_foods(
    db, cuisine: str, category: str, dietary_preferences: list[str], limit: int = 40,
) -> list[dict]:
    query: dict = {"cuisine": cuisine, "category": category}
    excluded = _excluded_tags(dietary_preferences)
    if excluded:
        query["tags"] = {"$nin": excluded}

    cursor = db.foods_ref.find(query).limit(limit)
    foods = [doc async for doc in cursor]
    if foods:
        return foods
    return _default_foods(category, dietary_preferences)[:limit]


def format_food_candidates_for_prompt(foods: list[dict]) -> str:
    lines = []
    for f in foods:
        lines.append(
            f"- id={f['id']} | {f['name']} | kcal/100g={f['calories_per_100g']} "
            f"| protein/100g={f['protein_g_per_100g']}g | tags={','.join(f.get('tags', []))}"
        )
    return "\n".join(lines)
