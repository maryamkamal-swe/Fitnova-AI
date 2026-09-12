import asyncio
import unittest

from app.services.weekly_update_job import get_weekly_avg_weight_change


class MockAsyncCursor:
    def __init__(self, docs):
        self.docs = docs

    def sort(self, *args, **kwargs):
        return self

    def limit(self, *args, **kwargs):
        return self

    def __aiter__(self):
        self._iter = iter(self.docs)
        return self

    async def __anext__(self):
        try:
            return next(self._iter)
        except StopIteration:
            raise StopAsyncIteration


class MockCollection:
    def __init__(self, docs=None):
        self.docs = docs if docs is not None else []

    def find(self, *args, **kwargs):
        return MockAsyncCursor(self.docs)


class MockDB:
    def __init__(self, progress_docs=None, progress_logs_docs=None):
        self.progress = MockCollection(progress_docs)
        self.progress_logs = MockCollection(progress_logs_docs)


class WeeklyUpdateJobTests(unittest.TestCase):
    def test_get_weekly_avg_weight_change_returns_none_if_fewer_than_14_entries(self):
        progress_docs = [{"weight": 70.0} for _ in range(10)]
        db = MockDB(progress_docs=progress_docs)

        result = asyncio.run(get_weekly_avg_weight_change(db, "user-1"))
        self.assertIsNone(result)

    def test_get_weekly_avg_weight_change_calculates_difference_from_progress(self):
        # 7 days at 70.0 kg (this week), 7 days at 71.0 kg (last week)
        this_week = [{"weight": 70.0} for _ in range(7)]
        last_week = [{"weight": 71.0} for _ in range(7)]
        db = MockDB(progress_docs=this_week + last_week)

        result = asyncio.run(get_weekly_avg_weight_change(db, "user-1"))
        self.assertAlmostEqual(result, -1.0)

    def test_get_weekly_avg_weight_change_fallback_to_progress_logs(self):
        # 0 in progress, 14 in progress_logs
        this_week = [{"value": 75.0} for _ in range(7)]
        last_week = [{"value": 72.0} for _ in range(7)]
        db = MockDB(progress_docs=[], progress_logs_docs=this_week + last_week)

        result = asyncio.run(get_weekly_avg_weight_change(db, "user-1"))
        self.assertAlmostEqual(result, 3.0)


if __name__ == "__main__":
    unittest.main()
