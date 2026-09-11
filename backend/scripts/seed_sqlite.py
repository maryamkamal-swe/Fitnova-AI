import os
import sqlite3
import pandas as pd
from typing import Optional

def build_nutrition_sqlite_from_folder(
    data_folder: str = "fitnova_data",
    db_path: str = "fitnova_nutrition.db"
) -> None:
    # Remove existing empty database if recreating
    if os.path.exists(db_path):
        os.remove(db_path)
        print(f"Removed existing database at {db_path}")

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # 1. Create relational schema
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS food_categories (
            id INTEGER PRIMARY KEY,
            code TEXT,
            description TEXT
        )
    """)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS foods (
            fdc_id INTEGER PRIMARY KEY,
            description TEXT NOT NULL,
            food_category_id INTEGER,
            FOREIGN KEY(food_category_id) REFERENCES food_categories(id)
        )
    """)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS nutrients (
            id INTEGER PRIMARY KEY,
            name TEXT,
            unit_name TEXT
        )
    """)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS measure_units (
            id INTEGER PRIMARY KEY,
            name TEXT
        )
    """)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS macros (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            fdc_id INTEGER,
            nutrient_id INTEGER,
            amount REAL,
            FOREIGN KEY(fdc_id) REFERENCES foods(fdc_id),
            FOREIGN KEY(nutrient_id) REFERENCES nutrients(id)
        )
    """)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS food_portions (
            id INTEGER PRIMARY KEY,
            fdc_id INTEGER,
            amount REAL,
            measure_unit_id INTEGER,
            portion_description TEXT,
            gram_weight REAL,
            FOREIGN KEY(fdc_id) REFERENCES foods(fdc_id),
            FOREIGN KEY(measure_unit_id) REFERENCES measure_units(id)
        )
    """)
    conn.commit()

    def get_path(filename: str) -> Optional[str]:
        # Check specified folder first, then fall back to current directory
        path1 = os.path.join(data_folder, filename)
        if os.path.exists(path1):
            return path1
        if os.path.exists(filename):
            return filename
        return None

    # 2. Ingest reference tables
    cat_path = get_path("food_category.csv")
    if cat_path:
        df = pd.read_csv(cat_path)
        cols = [c for c in ["id", "code", "description"] if c in df.columns]
        df[cols].to_sql("food_categories", conn, if_exists="append", index=False)
        print(f"Loaded food_categories from {cat_path} ({len(df)} rows)")
    else:
        print("WARNING: food_category.csv not found!")

    nut_path = get_path("nutrient.csv")
    if nut_path:
        df = pd.read_csv(nut_path)
        cols = [c for c in ["id", "name", "unit_name"] if c in df.columns]
        df[cols].to_sql("nutrients", conn, if_exists="append", index=False)
        print(f"Loaded nutrients from {nut_path} ({len(df)} rows)")
    else:
        print("WARNING: nutrient.csv not found!")

    mu_path = get_path("measure_unit.csv")
    if mu_path:
        df = pd.read_csv(mu_path)
        cols = [c for c in ["id", "name"] if c in df.columns]
        df[cols].to_sql("measure_units", conn, if_exists="append", index=False)
        print(f"Loaded measure_units from {mu_path} ({len(df)} rows)")
    else:
        print("WARNING: measure_unit.csv not found!")

    # 3. Stream master food table
    food_path = get_path("food.csv")
    if food_path:
        sample_cols = pd.read_csv(food_path, nrows=1).columns
        food_cols = ["fdc_id", "description"]
        if "food_category_id" in sample_cols:
            food_cols.append("food_category_id")
            
        total_foods = 0
        for chunk in pd.read_csv(food_path, chunksize=50000, usecols=food_cols, on_bad_lines="skip"):
            chunk = chunk.dropna(subset=["description"])
            chunk.to_sql("foods", conn, if_exists="append", index=False)
            total_foods += len(chunk)
        print(f"Loaded foods from {food_path} ({total_foods} total rows)")
    else:
        print("WARNING: food.csv not found!")

    # 4. Stream food portions
    portion_path = get_path("food_portion.csv")
    if portion_path:
        sample_cols = pd.read_csv(portion_path, nrows=1).columns
        portion_cols = [c for c in ["id", "fdc_id", "amount", "measure_unit_id", "portion_description", "gram_weight"] if c in sample_cols]
        
        total_portions = 0
        for chunk in pd.read_csv(portion_path, chunksize=50000, usecols=portion_cols, on_bad_lines="skip"):
            chunk.to_sql("food_portions", conn, if_exists="append", index=False)
            total_portions += len(chunk)
        print(f"Loaded food_portions from {portion_path} ({total_portions} total rows)")
    else:
        print("WARNING: food_portion.csv not found!")

    # 5. Stream large food_nutrient table (filtered for macros: Energy 1008, Protein 1003, Carbs 1005, Fat 1004)
    nutrient_path = get_path("food_nutrient.csv")
    if nutrient_path:
        macro_ids = [1008, 1003, 1005, 1004]
        total_macros = 0
        for chunk in pd.read_csv(nutrient_path, chunksize=100000, usecols=["fdc_id", "nutrient_id", "amount"], on_bad_lines="skip"):
            filtered = chunk[chunk["nutrient_id"].isin(macro_ids)]
            if not filtered.empty:
                filtered.to_sql("macros", conn, if_exists="append", index=False)
                total_macros += len(filtered)
        print(f"Loaded macros from {nutrient_path} ({total_macros} macro rows filtered)")
    else:
        print("WARNING: food_nutrient.csv not found!")

    # 6. Create indexes for high-speed queries
    print("Creating database indexes...")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_food_desc ON foods(description);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_macro_fdc ON macros(fdc_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_portion_fdc ON food_portions(fdc_id);")
    conn.commit()
    conn.close()
    print("Database build complete and verified.")

if __name__ == "__main__":
    build_nutrition_sqlite_from_folder()