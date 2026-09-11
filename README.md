# FITNOVA AI

FitNova AI is a full-stack fitness and nutrition coaching app built with a
FastAPI backend and a Flutter frontend. It includes JWT authentication, profile
setup, AI chat with RAG, voice chat, meal planning, workout planning,
notifications, hydration tracking, and progress analytics.

The project is designed around free-tier or self-hosted services only:
MongoDB Atlas Free Tier or local MongoDB, SQLite, ChromaDB, Groq free-tier
LLM access, gTTS/SpeechRecognition, and free SMTP providers.

## Project Structure

```text
fitnova/
├── backend/
│   ├── app/
│   │   ├── api/v1/              # AI chat route modules
│   │   ├── core/                # Shared infrastructure such as rate limiter
│   │   ├── db/                  # Chroma vector-store helpers
│   │   ├── models/              # Pydantic request/response models
│   │   ├── routes/              # Auth, profile, progress, notifications, plans, voice
│   │   ├── services/            # Auth, RAG, planners, OTP, progress, notifications
│   │   ├── voice/               # Legacy/CLI voice helpers
│   │   ├── config.py
│   │   ├── database.py
│   │   └── main.py
│   ├── data/                    # RAG source data
│   ├── fitnova_data/            # Nutrition CSV source data
│   ├── tests/                   # Unit/contract tests
│   ├── Dockerfile
│   ├── Procfile
│   ├── requirements.txt
│   ├── fitnova_nutrition.db     # Local SQLite nutrition database
│   └── .env.example
├── new_flutter_app/
│   ├── lib/
│   │   ├── core/                # Constants, theme, validators, string helpers
│   │   ├── models/              # Dart data models
│   │   ├── screens/             # App screens
│   │   ├── services/            # ApiClient and feature services
│   │   └── widgets/             # Reusable UI widgets
│   ├── assets/images/
│   ├── test/
│   └── pubspec.yaml
└── Readme.md
```

## Backend Features

- FastAPI app with `/docs`, `/health`, and versioned `/api/v1` routes.
- MongoDB persistence through Motor.
- Idempotent startup migration that normalizes legacy `ObjectId` `user_id`
  fields to string values across user-owned collections.
- Startup indexes for users, progress, food logs, notifications, plans,
  chat histories, and refresh tokens.
- JWT access tokens plus persisted refresh-token rotation/revocation.
- Email OTP workflow with SMTP delivery when configured. In local development,
  a missing SMTP setup returns the development code to the app, fills the six
  verification fields automatically, and prints it to the backend console.
- Route-specific rate limiting through SlowAPI.
- AI chat backed by Chroma retrieval, Groq, Mongo chat history, and a local
  SQLite macro lookup helper.
- Meal/workout generators with deterministic fallbacks when reference data or
  LLM calls are unavailable.
- Voice routes for transcription, chat, and TTS with blocking providers run
  off-thread and a 10 MB audio payload ceiling.

## Frontend Features

- Flutter app with strict dark theme.
- Login, registration, OTP verification, profile setup, onboarding walkthrough,
  and first-dashboard tour.
- App-scoped `ApiClient` with auth headers, refresh-token retry, SSE support,
  and session-expiry handling.
- Dashboard, workout plan, meal plan, progress, hydration, notifications,
  profile, and AI coach screens.
- Voice message recording/playback integration for the coach screen.
- Dynamic API base URL using `--dart-define=API_BASE_URL=...`.

## Prerequisites

- Python 3.11 recommended.
- Flutter SDK 3.x or newer for frontend work.
- MongoDB local instance or MongoDB Atlas Free Tier.
- Groq API key for AI chat and plan generation.
- Optional SMTP credentials for real email OTP delivery.
- Optional Docker Desktop for container testing.

## Backend Setup

```bash
cd backend
python -m venv .venv
```

Windows PowerShell:

```powershell
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
Copy-Item .env.example .env
```

macOS/Linux:

```bash
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
cp .env.example .env
```

Edit `backend/.env`:

```env
APP_NAME="FitNova AI"
DEBUG=false
ENVIRONMENT=development
PORT=8000
ALLOWED_ORIGINS=http://localhost:8000,http://127.0.0.1:8000,http://localhost:3000,http://10.0.2.2:8000

MONGODB_URI=mongodb://localhost:27017
DATABASE_NAME=fitnova_db

SECRET_KEY=replace_with_a_long_random_secret
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
REFRESH_TOKEN_EXPIRE_DAYS=7

GROQ_API_KEY=your_groq_api_key
GROQ_MODEL=openai/gpt-oss-120b
GROQ_ROUTER_MODEL=openai/gpt-oss-20b
CHROMA_PERSIST_DIRECTORY=./chroma_db
CHROMA_COLLECTION_NAME=fitnova_knowledge
SQLITE_DB_PATH=fitnova_nutrition.db

SMTP_HOST=
SMTP_PORT=587
SMTP_USER=
SMTP_PASSWORD=
SMTP_FROM=
SMTP_USE_TLS=true
```

Run the backend:

```bash
cd backend
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Open:

- API docs: <http://127.0.0.1:8000/docs>
- Health check: <http://127.0.0.1:8000/health>

## Frontend Setup

The Flutter app is in `new_flutter_app/` directly under the repo root.

```bash
cd new_flutter_app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Android emulator usually needs:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

Physical devices need your computer LAN IP:

```bash
flutter run --dart-define=API_BASE_URL=http://YOUR_LAN_IP:8000
```

## Docker Backend

The backend now includes `backend/Dockerfile`, `backend/Procfile`, and
`backend/.dockerignore`.

Build locally:

```bash
cd backend
docker build -t fitnova-ai-backend .
```

Run with your environment file:

```bash
docker run --rm -p 8000:8000 --env-file .env fitnova-ai-backend
```

Health check:

```bash
curl http://127.0.0.1:8000/health
```

## Free-Tier Deployment Notes

### Render with Docker

1. Create a new Web Service.
2. Set the root directory to `backend`.
3. Choose Docker runtime.
4. Add environment variables from `backend/.env.example`.
5. Use MongoDB Atlas Free Tier for `MONGODB_URI`.
6. Set `ALLOWED_ORIGINS` to the deployed frontend origin.

### Railway/Heroku-style Procfile

If the host uses the Procfile instead of Docker, the command is:

```text
web: uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}
```

Make sure the host installs from `backend/requirements.txt` and starts in the
`backend` directory.

## Backend Test Commands

From `backend/`:

```bash
python -m compileall app tests test_progress_tracking.py -q
python -m unittest discover -s tests -p "test_*.py" -v
python -m unittest test_progress_tracking -v
```

If `pytest` is installed:

```bash
python -m pytest -q
```

Useful import smoke check:

```bash
python -c "from app.main import app; print('backend import ok')"
```

## Frontend Test Commands

From `new_flutter_app/`:

```bash
flutter analyze
flutter test
```

Run a web smoke test:

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Build release web assets:

```bash
flutter build web --dart-define=API_BASE_URL=https://YOUR_BACKEND_URL
```

## Manual End-to-End Test Flow

1. Start MongoDB.
2. Start backend with `uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload`.
3. Confirm `/health` returns `200`.
4. Start Flutter with the correct `API_BASE_URL`.
5. Register a user.
6. If SMTP is not configured and `ENVIRONMENT=development`, the app fills the
   six OTP fields automatically. The code is also printed in the backend console.
7. Complete profile setup.
8. Generate a workout plan.
9. Generate a meal plan.
10. Log daily progress and hydration.
11. Open AI Coach and send a nutrition or workout question.
12. Test logout, then sign in again.

## Important Operational Notes

- Do not commit `.env`, SMTP passwords, MongoDB credentials, or Firebase
  service files.
- `fitnova_nutrition.db` is required by the backend health check and macro
  lookup path.
- AI features require `GROQ_API_KEY`; non-AI routes can still import without
  the Groq SDK being loaded at module import time.
- The frontend depends on the backend base URL passed via `API_BASE_URL`.
- Keep all services on free-tier or self-hosted infrastructure unless the
  project owner explicitly approves otherwise.
