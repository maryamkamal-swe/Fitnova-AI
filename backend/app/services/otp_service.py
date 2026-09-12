# backend/app/services/otp_service.py
from __future__ import annotations
import logging
import secrets
import smtplib
from datetime import datetime, timedelta, timezone
from email.message import EmailMessage
from typing import Optional

from app.config import settings

logger = logging.getLogger(__name__)

_OTP_TTL = timedelta(minutes=10)
_store: dict[str, tuple[str, datetime]] = {}


def smtp_configured() -> bool:
    return bool(settings.SMTP_HOST and settings.SMTP_USER and settings.SMTP_PASSWORD)


def _generate_otp() -> str:
    return f"{secrets.randbelow(900000) + 100000:06d}"


def create_otp(email: str) -> str:
    code = _generate_otp()
    expiry = datetime.now(timezone.utc) + _OTP_TTL
    _store[email.lower().strip()] = (code, expiry)
    return code


def verify_otp(email: str, otp: str) -> bool:
    key = email.lower().strip()
    entry = _store.get(key)
    if entry is None:
        return False
    code, expiry = entry
    if datetime.now(timezone.utc) > expiry:
        _store.pop(key, None)
        return False
    if code != otp.strip():
        return False
    _store.pop(key, None)
    return True


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
    except Exception:
        logger.exception("Failed to send OTP email to %s", email)
        if settings.ENVIRONMENT.lower() == "development":
            print(f"[FitNova OTP fallback] {email}: {otp}")
        return False


def issue_otp(email: str) -> dict:
    otp = create_otp(email)
    delivered = send_otp_email(email, otp)
    auto_verified = False
    development_mode = settings.ENVIRONMENT.lower() == "development"
    response = {
        "email": email,
        "delivered": delivered,
        "auto_verified": auto_verified,
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