# Riogram — Android + iOS messenger (development)

Flutter mobile application and FastAPI messaging service.

## Current capabilities
- Flutter: responsive demo chat list, conversation UI, contacts, calls screen, profile, light/dark theme, server health check.
- API: authenticated direct chats, messages, edit/delete, idempotency, contact matching (E.164), device token registration, WebSocket message events and WebRTC signaling messages.
- Twilio Verify SMS flow and Firebase Cloud Messaging integration are implemented as **optional server integrations**; they are disabled until real credentials are supplied.
- SQLite is supported for local development; PostgreSQL is supported by SQLAlchemy and the initial Alembic migration.

**Not production-ready:** The mobile UI currently uses clearly labeled demo data and is not connected to real messaging/login. Calls have signaling only, not an actual WebRTC media connection. There is no production-grade distributed WebSocket fanout, encrypted local cache, rate limiting, contact permissions, offline queue, APNs setup, or full security audit. Never use the Render demo SQLite for personal data: its filesystem is ephemeral.

## Backend local run
```sh
pip install -r backend/requirements.txt
cd backend
export RIOGRAM_DEMO_SQLITE=1
uvicorn app.main:app --reload
```
Use `DATABASE_URL=postgresql+psycopg://...` for PostgreSQL. Configure migrations before production. Set `JWT_SECRET` to a random secret of 32+ characters.

For SMS verification, configure:
- `TWILIO_ACCOUNT_SID`
- `TWILIO_AUTH_TOKEN`
- `TWILIO_VERIFY_SERVICE_SID`

For Firebase push notifications, configure `FIREBASE_SERVICE_ACCOUNT_JSON` with a service account JSON object. Never commit secrets.

## Tests
```sh
cd backend && PYTHONPATH=. pytest -q
```
Android APK CI: [GitHub Actions](https://github.com/zuhra19868619-beep/Riogram/actions/workflows/android-apk.yml). A debug APK is uploaded as a workflow artifact **only after the workflow succeeds**. The APK is an early demo build, not a finished messenger.

## Flutter
```sh
cd mobile
flutter create --platforms=android,ios --project-name riogram .
flutter pub get
flutter test
flutter run
```
iOS build/signing requires macOS, Xcode and Apple signing credentials.
