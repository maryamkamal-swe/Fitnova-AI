import sys
import unittest
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from app.models.progress import ProgressCreate
from app.services.progress_service import ProgressService


class ProgressTrackingTests(unittest.TestCase):
    def test_create_progress_model_supports_daily_activity_fields(self):
        payload = ProgressCreate(
            date=date(2026, 8, 16),
            weight=71.5,
            workout_completed=True,
            calories_consumed=2200,
            water_intake=2.4,
            sleep_hours=7.5,
            steps=8500,
            active_minutes=42,
            calories_burned=420,
            goal_completion=78.5,
            notes="Strong day",
        )

        self.assertEqual(payload.steps, 8500)
        self.assertEqual(payload.active_minutes, 42)
        self.assertEqual(payload.calories_burned, 420)
        self.assertEqual(payload.goal_completion, 78.5)

    def test_goal_summary_aggregates_daily_activity(self):
        records = [
            {"weight": 72.0, "workout_completed": True, "steps": 9000, "active_minutes": 50, "goal_completion": 70},
            {"weight": 71.5, "workout_completed": True, "steps": 10000, "active_minutes": 60, "goal_completion": 82},
            {"weight": 71.0, "workout_completed": False, "steps": 6000, "active_minutes": 30, "goal_completion": 75},
        ]

        summary = ProgressService.calculate_activity_summary(records)

        self.assertAlmostEqual(summary["avg_steps"], 8333.33, places=2)
        self.assertAlmostEqual(summary["avg_active_minutes"], 46.67, places=2)
        self.assertAlmostEqual(summary["goal_completion_rate"], 75.67, places=2)
        self.assertEqual(summary["workout_days"], 2)


if __name__ == "__main__":
    unittest.main()
