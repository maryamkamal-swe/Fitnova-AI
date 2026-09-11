import asyncio
import unittest

from app.core.limiter import limiter as core_limiter
from app.rate_limit import limiter as shim_limiter
from app.models.meal import MealPlanRequest
from app.models.workout import WorkoutLocation, WorkoutPlanRequest
from app.services.progress_service import ProgressService


class _NoopCollection:
    async def find_one(self, *_args, **_kwargs):
        raise AssertionError("Invalid ObjectIds should be rejected before querying")


class RefactorContractTests(unittest.TestCase):
    def test_rate_limit_shim_uses_core_limiter_instance(self):
        self.assertIs(shim_limiter, core_limiter)

    def test_plan_generation_requests_do_not_require_client_user_id(self):
        meal_request = MealPlanRequest(cuisine="desi")
        workout_request = WorkoutPlanRequest(location=WorkoutLocation.HOME)

        self.assertIsNone(meal_request.user_id)
        self.assertIsNone(workout_request.user_id)

    def test_progress_lookup_handles_invalid_object_id_without_name_error(self):
        service = ProgressService()
        service._get_collection = lambda: _NoopCollection()

        result = asyncio.run(
            service.get_progress_by_id("not-a-valid-object-id", "user-1")
        )

        self.assertIsNone(result)


if __name__ == "__main__":
    unittest.main()
