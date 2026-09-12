"""
Authentication routes
Handles registration, login, logout, token refresh
"""
from fastapi import APIRouter, HTTPException, Request, status, Depends
from app.core.limiter import limiter
from pydantic import BaseModel, EmailStr, Field
from ..models.user import UserCreate, UserLogin, TokenResponse, TokenRefresh, PasswordChange
from ..services.auth_service import AuthService
from ..services.otp_service import issue_otp, verify_otp
from ..utils.security import get_current_user_id

router = APIRouter(prefix="/auth", tags=["Authentication"])
auth_service = AuthService()


class SendOtpRequest(BaseModel):
    email: EmailStr


class VerifyOtpRequest(BaseModel):
    email: EmailStr
    otp: str = Field(..., min_length=6, max_length=6)


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit("10/hour")
async def register(request: Request, user_data: UserCreate):
    """
    Register a new user
    
    - **email**: Valid email address
    - **password**: Minimum 8 characters with at least one digit and uppercase letter
    - **profile**: Optional user profile information
    
    Returns JWT access and refresh tokens
    """
    return await auth_service.register_user(user_data)


@router.post("/login", response_model=TokenResponse)
@limiter.limit("10/minute")
async def login(request: Request, login_data: UserLogin):
    """
    Authenticate user and get tokens
    
    - **email**: User's email
    - **password**: User's password
    
    Returns JWT access and refresh tokens
    """
    return await auth_service.login_user(login_data)


@router.post("/refresh", response_model=TokenResponse)
@limiter.limit("30/hour")
async def refresh_token(request: Request, token_data: TokenRefresh):
    """
    Refresh access token using refresh token
    
    - **refresh_token**: Valid refresh token
    
    Returns new JWT access and refresh tokens
    """
    return await auth_service.refresh_access_token(token_data.refresh_token)


@router.post("/logout", status_code=status.HTTP_200_OK)
@limiter.limit("30/minute")
async def logout(request: Request, user_id: str = Depends(get_current_user_id)):
    """
    Logout user and revoke all active refresh tokens.
    """
    await auth_service.revoke_user_refresh_tokens(user_id)
    return {"message": "Successfully logged out"}


@router.post("/change-password", status_code=status.HTTP_200_OK)
@limiter.limit("5/hour")
async def change_password(
    request: Request,
    password_data: PasswordChange,
    user_id: str = Depends(get_current_user_id)
):
    """
    Change user password
    
    - **old_password**: Current password
    - **new_password**: New password (min 8 characters)
    
    Requires authentication
    """
    await auth_service.change_password(
        user_id,
        password_data.old_password,
        password_data.new_password
    )
    return {"message": "Password changed successfully"}


@router.get("/me")
async def get_current_user(user_id: str = Depends(get_current_user_id)):
    """
    Get current authenticated user information
    
    Requires authentication
    """
    user = await auth_service.get_user_by_id(user_id)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    return user


import asyncio

@router.post("/send-otp")
@limiter.limit("5/hour")
async def send_otp(request: Request, payload: SendOtpRequest):
    """Send a rate-limited 6-digit email OTP."""
    return await asyncio.to_thread(issue_otp, str(payload.email))


@router.post("/verify-otp")
@limiter.limit("10/hour")

async def verify_email_otp(request: Request, payload: VerifyOtpRequest):
    """Confirm a previously issued OTP."""
    if not verify_otp(str(payload.email), payload.otp):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired verification code",
        )
    email = str(payload.email)
    user_updated = await auth_service.mark_email_verified(email)
    if not user_updated:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No user account exists for this email",
        )
    return {"verified": True, "email": email}
