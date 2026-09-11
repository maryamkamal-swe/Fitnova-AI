import unittest
from unittest.mock import patch

from app.services.otp_service import issue_otp


class OtpDeliveryTests(unittest.TestCase):
    @patch("app.services.otp_service.send_otp_email", return_value=False)
    @patch("app.services.otp_service.settings.ENVIRONMENT", "development")
    def test_development_response_exposes_local_code_when_email_is_unavailable(
        self, _send_email
    ):
        result = issue_otp("developer@example.com")

        self.assertFalse(result["delivered"])
        self.assertRegex(result["development_code"], r"^\d{6}$")
        self.assertIn("not configured", result["message"])

    @patch("app.services.otp_service.send_otp_email", return_value=False)
    @patch("app.services.otp_service.settings.ENVIRONMENT", "production")
    def test_production_response_never_exposes_code(self, _send_email):
        result = issue_otp("user@example.com")

        self.assertFalse(result["delivered"])
        self.assertNotIn("development_code", result)


if __name__ == "__main__":
    unittest.main()
