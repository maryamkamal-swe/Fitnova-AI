import sqlite3

def verify_database(db_path: str = "fitnova_nutrition.db"):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    tables = ["food_categories", "foods", "nutrients", "measure_units", "macros", "food_portions"]
    
    for table in tables:
        try:
            cursor.execute(f"SELECT COUNT(*) FROM {table}")
            count = cursor.fetchone()[0]
            print(f"Table '{table}': {count:,} rows")
            
            cursor.execute(f"SELECT * FROM {table} LIMIT 1")
            sample = cursor.fetchone()
            print(f"  Sample: {sample}\n")
        except sqlite3.OperationalError as e:
            print(f"Table '{table}': Error or missing ({e})\n")
            
    conn.close()

if __name__ == "__main__":
    verify_database()