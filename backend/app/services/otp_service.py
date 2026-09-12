from __future__ import annotations

import asyncio
import logging
import secrets
import smtplib
from datetime import datetime, timedelta, timezone
from email.message import EmailMessage
from typing import Optional

from app.config import settings
from app.database import get_database

logger = logging.getLogger(__name__)

_OTP_TTL = timedelta(minutes=10)


def smtp_configured() -> bool:
    return bool(settings.SMTP_HOST and settings.SMTP_USER and settings.SMTP_PASSWORD)


def _generate_otp() -> str:
    return f"{secrets.randbelow(900000) + 100000:06d}"


async def create_otp(email: str) -> tuple[str, datetime]:
    normalized_email = email.lower().strip()
    code = _generate_otp()
    now = datetime.now(timezone.utc)
    expires_at = now + _OTP_TTL
    await get_database().otps.insert_one(
        {
            "email": normalized_email,
            "code": code,
            "expires_at": expires_at,
            "created_at": now,
        }
    )
    return code, expires_at


async def verify_otp(email: str, otp: str) -> Optional[dict]:
    """Find an unexpired OTP without consuming it."""
    now = datetime.now(timezone.utc)
    return await get_database().otps.find_one(
        {
            "email": email.lower().strip(),
            "code": otp.strip(),
            "expires_at": {"$gt": now},
        }
    )


async def consume_otp(otp_id) -> None:
    await get_database().otps.delete_one({"_id": otp_id})


def send_otp_email(email: str, otp: str) -> bool:
    if not smtp_configured():
        logger.warning("SMTP is not configured; OTP email was not delivered to %s", email)
        if settings.ENVIRONMENT.lower() == "development":
            print(f"[FitNova OTP] {email}: {otp}")
        return False

    message = EmailMessage()
    message["Subject"] = "Your FitNova AI verification code"
    message["From"] = settings.SMTP_FROM or settings.SMTP_USER
    message["To"] = email
    message.set_content(
        f"Your FitNova AI verification code is {otp}. It expires in 10 minutes."
    )

    try:
        if settings.SMTP_PORT == 465:
            with smtplib.SMTP_SSL(settings.SMTP_HOST, settings.SMTP_PORT, timeout=15) as smtp:
                smtp.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
                smtp.send_message(message)
        else:
            with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT, timeout=15) as smtp:
                if settings.SMTP_USE_TLS:
                    smtp.starttls()
                smtp.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
                smtp.send_message(message)
        return True
    except Exception as error:
        logger.exception("Failed to send OTP email to %s", email)
        raise RuntimeError(f"Failed to send OTP email to {email}") from error


async def issue_otp(email: str) -> dict:
    otp, _ = await create_otp(email)
    delivered = await asyncio.to_thread(send_otp_email, email, otp)
    development_mode = settings.ENVIRONMENT.lower() == "development"
    response = {
        "email": email,
        "delivered": delivered,
        "auto_verified": False,
        "message": (
            "A 6-digit code was sent. Check your email."
            if delivered
            else (
                "Email delivery is not configured. Use the development code shown below."
                if development_mode
                else "Email delivery is currently unavailable. Please try again later."
            )
        ),
    }
    if development_mode and not delivered:
        response["development_code"] = otp
    return response
