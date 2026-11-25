# HealthTrack 2.0 — Architecture Documentation

## Overview

HealthTrack 2.0 is a multi-platform health tracking and recovery platform consisting of:
- **Flask Backend** (Python) — Central API, business logic, SQLAlchemy ORM
- **React Web Application** (TypeScript) — Browser-based dashboard and management
- **Flutter Mobile Application** (Dart) — Android APK with offline capability
- **Firebase Services** — Authentication, Firestore, Storage, Cloud Messaging

---

## System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         HEALTH TRACKER 2.0                              │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
┌───────▼───────┐         ┌─────────▼─────────┐         ┌───────▼───────┐
│   FLASK       │         │   REACT WEB       │         │   FLUTTER     │
│   BACKEND     │         │   APPLICATION     │         │   MOBILE APP  │
│               │         │                   │         │               │
│  • API v1     │◄───────►│  • AuthContext    │◄───────►│  • Auth       │
│  • SQLAlchemy │         │  • ApiService     │         │  • SQLite     │
│  • JWT Auth   │         │  • Firebase Auth  │         │  • Sync       │
│  • Scheduler  │         │  • Charts/Views   │         │  • Notifs     │
└───────┬───────┘         └────────┬──────────┘         └───────┬───────┘
        │                          │                           │
        │                          │                           │
        └──────────────────────────┼───────────────────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │       FIREBASE SERVICES     │
                    │                             │
                    │  • Firebase Auth            │
                    │  • Cloud Firestore          │
                    │  • Firebase Storage         │
                    │  • Cloud Messaging (FCM)    │
                    └─────────────────────────────┘
```

---

## Backend Architecture (Flask)

### Technology Stack
- **Framework**: Flask 2.x
- **Database ORM**: SQLAlchemy 2.x
- **Database**: PostgreSQL (production) / SQLite (development)
- **Authentication**: Flask-JWT-Extended (API) + Flask-Login (sessions)
- **Migrations**: Flask-Migrate (Alembic)
- **Email**: Flask-Mail
- **Caching**: Flask-Caching
- **Scheduler**: APScheduler
- **CORS**: Flask-CORS

### Project Structure
```
routes/
├── api/                    # REST API endpoints (JWT protected)
│   ├── auth_api.py         # Registration, login, token refresh
│   ├── dashboard_api.py    # Dashboard data aggregation
│   ├── tracker_api.py      # BP, weight, water, sugar, sleep, steps, HR
│   ├── medicine_api.py     # Medicine CRUD, logs, adherence
│   ├── meal_api.py         # Recipes, meal plans, grocery
│   ├── exercise_api.py     # Exercise logging, library
│   ├── lab_api.py          # Lab test management
│   ├── appointment_api.py  # Appointment scheduling
│   ├── document_api.py     # Document upload/retrieval
│   ├── ai_assistant_api.py # AI chat integration
│   ├── family_api.py       # Family member management
│   ├── timeline_api.py     # Health timeline events
│   ├── health_modules_api.py # Lab, visits, appointments, emergency, AI camera
│   └── notification_api.py # Notifications and reminders
├── auth_routes.py          # Web auth (Flask-Login sessions)
├── google_auth.py          # Google OAuth
├── bp_routes.py            # Web BP routes
├── tracker_routes.py       # Web tracker routes
├── meal_routes.py          # Web meal routes
└── ... (other web blueprints)
```

### Data Models (Key Entities)

```python
# Core User & Health Data
User ◄──┬──► UserHealthProfile (1:1)
      ├──► UserGoal (1:1)
      ├──► HealthMetric (1:N) — BP, weight, water, sugar, HR
      ├──► SleepLog (1:N)
      ├──► StepLog (1:N)
      ├──► ExerciseLog (1:N)
      ├──► Medicine (1:N) ◄──► MedicineLog (1:N)
      ├──► LabTest (1:N)
      ├──► Appointment (1:N)
      ├──► Document (1:N)
      ├──► FamilyMember (1:N) ◄──► FamilyHealthMetric, FamilyMedicine, etc.
      ├──► Reminder (1:N)
      ├──► Notification (1:N)
      ├──► HealthTimelineEvent (1:N)
      ├──► UserSubscription (1:1)
      └──► Alert (1:N)
```

### API Design
- **Base URL**: `/api/v1/`
- **Authentication**: Bearer JWT token
- **Response Format**:
  ```json
  {
    "success": true,
    "message": "Description",
    "data": { ... }
  }
  ```
- **Error Format**:
  ```json
  {
    "success": false,
    "message": "Error description",
    "errors": { "field": "message" }
  }
  ```

---

## Frontend Architecture (React + TypeScript)

### Technology Stack
- **Framework**: React 18 + TypeScript
- **Build Tool**: Vite
- **Routing**: React Router v6
- **State Management**: React Context + @tanstack/react-query
- **Forms**: React Hook Form + Zod validation
- **Charts**: Recharts
- **UI**: Tailwind CSS + custom components
- **HTTP Client**: Axios (with interceptors)

### Project Structure
```
healthtrack-web/src/
├── main.tsx                 # App entry point
├── App.tsx                  # Routing + ProtectedRoute
├── index.css                # Tailwind imports
├── context/
│   ├── AuthContext.tsx      # Authentication state & actions
│   └── ThemeContext.tsx     # Dark/light mode
├── hooks/
│   ├── useAuth.ts           # Auth context hook
│   └── useTheme.ts          # Theme hook
├── services/
│   ├── api.ts               # Axios API client (NEW)
│   └── firebase.ts          # Firebase initialization
├── components/
│   ├── ui/                  # Reusable UI components
│   │   ├── Button.tsx
│   │   ├── Card.tsx
│   │   ├── Input.tsx
│   │   ├── Select.tsx
│   │   ├── Modal.tsx
│   │   ├── Avatar.tsx
│   │   ├── Progress.tsx
│   │   ├── Toast.tsx
│   │   └── LoadingScreen.tsx
│   └── layout/
│       ├── Navbar.tsx
│       └── Layout.tsx
├── pages/
│   ├── auth/
│   │   ├── Login.tsx
│   │   ├── Register.tsx
│   │   ├── ForgotPassword.tsx
│   │   └── ResetPassword.tsx
│   ├── dashboard/
│   │   └── Dashboard.tsx
│   ├── Profile.tsx
│   ├── Settings.tsx
│   └── NotFound.tsx
└── utils/
    └── cn.ts                # Class name utility
```

### Authentication Flow (React)
```
1. App loads → AuthContext initializes
2. onAuthStateChanged listener monitors Firebase Auth
3. User logs in → Firebase ID token obtained
4. (Future) Send to Flask /api/auth/firebase-login → Receive JWT
5. Store JWT in localStorage for API calls
6. Protected routes check user state via useAuth()
```

---

## Mobile Architecture (Flutter)

### Technology Stack
- **Framework**: Flutter 3.x / Dart 3
- **State Management**: Provider
- **HTTP Client**: http + dio
- **Local Database**: sqflite (SQLite)
- **Security**: flutter_secure_storage, local_auth (biometric)
- **Notifications**: flutter_local_notifications + firebase_messaging
- **Camera**: image_picker, file_picker
- **Charts**: fl_chart

### Project Structure
```
healthtrack_clean/lib/
├── main.dart                      # App entry, providers, routes
├── constants/
│   └── app_theme.dart             # Colors, text styles, theming
├── models.dart                    # Local SQLite models
├── services/
│   ├── api_service.dart           # HTTP API client (Flask)
│   ├── auth_service.dart          # Firebase Auth wrapper
│   ├── firebase_service.dart      # Firestore + FCM
│   ├── local_db_service.dart      # SQLite operations
│   ├── sync_service.dart          # Offline ↔ Online sync
│   ├── security_service.dart      # Biometric/PIN lock
│   ├── notification_service.dart  # Local + push notifications
│   ├── step_tracking_service.dart # Pedometer integration
│   ├── google_auth_service.dart   # Google Sign-In
│   └── native_step_service.dart   # Platform channels
├── screens/                       # 28+ screens
│   ├── splash_screen.dart
│   ├── login_screen.dart
│   ├── lock_screen.dart
│   ├── dashboard_screen.dart
│   ├── bp_tracker_screen.dart
│   ├── weight_tracker_screen.dart
│   ├── water_tracker_screen.dart
│   ├── sleep_tracker_screen.dart
│   ├── exercise_screen.dart
│   ├── meal_screen.dart
│   ├── analytics_screen.dart
│   ├── family_screen.dart
│   ├── profile_screen.dart
│   ├── reminders_screen.dart
│   ├── sugar_tracker_screen.dart
│   ├── documents_screen.dart
│   ├── reports_screen.dart
│   ├── medicine_screen.dart
│   ├── lab_test_screen.dart
│   ├── appointments_screen.dart
│   ├── emergency_card_screen.dart
│   ├── timeline_screen.dart
│   ├── ai_assistant_screen.dart
│   ├── ai_camera_screen.dart
│   └── subscription_screen.dart
├── widgets/
│   ├── bottom_nav.dart
│   ├── common_widgets.dart
│   └── tts_speaker_button.dart
└── test/
    └── widget_test.dart
```

### Offline Synchronization Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    FLUTTER SYNC SERVICE                         │
├─────────────────────────────────────────────────────────────────┤
│  1. User Action (Add/Edit/Delete)                               │
│           │                                                     │
│           ▼                                                     │
│  2. Write to Local SQLite Immediately                          │
│           │                                                     │
│           ▼                                                     │
│  3. Queue Sync Operation in sync_queue table                   │
│           │                                                     │
│           ▼                                                     │
│  4. Background: Check Connectivity (connectivity_plus)         │
│           │                                                     │
│           ▼                                                     │
│  5. If Online: Send to Flask API                                │
│     • On Success: Mark synced, update local                    │
│     • On Conflict: Apply conflict resolution (server wins)     │
│     • On Failure: Retry with exponential backoff               │
│           │                                                     │
│           ▼                                                     │
│  6. FCM/Data Message triggers immediate sync                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Firebase Architecture

### Authentication
- **Provider**: Email/Password + Google Sign-In
- **Clients**: React Web, Flutter Mobile
- **Backend Integration**: Flask verifies Firebase ID tokens (future: `/api/auth/firebase-login`)

### Firestore Collections
```
/users/{userId}/
  ├── settings/preferences
  ├── health_profile
  ├── goals/goals
  ├── health_metrics/
  ├── blood_pressure/
  ├── blood_sugar/
  ├── weight_records/
  ├── water_records/
  ├── sleep_records/
  ├── heart_rate/
  ├── steps/
  ├── symptoms/
  ├── medicines/
  │   ├── {medicineId}/logs/
  │   ├── {medicineId}/schedules/
  │   └── {medicineId}/stock/
  ├── meals/
  ├── meal_plans/items/
  ├── recipes/
  ├── grocery_lists/
  ├── nutrition_logs/
  ├── exercises/
  ├── activity_records/
  ├── breathing_sessions/
  ├── lab_tests/
  ├── appointments/
  ├── documents/
  ├── family_members/
  │   └── {memberId}/health_metrics/, medicines/, appointments/, documents/
  ├── reminders/
  ├── notifications/
  ├── health_timeline/
  ├── habits/logs/
  ├── emergency_card/
  ├── health_scores/
  ├── health_reports/
  ├── subscription/
  └── trusted_contacts/

# Shared (read-only for authenticated users)
/exercise_library/
/recipes/
/health_conditions/
```

### Firebase Storage Paths
```
users/{userId}/
  ├── documents/{documentId}/{fileName}
  ├── profile/{fileName}
  ├── medicines/{medicineId}/{fileName}
  └── lab_reports/{testId}/{fileName}

emergency_cards/{userId}/{fileName} (public read)

ai_camera/{userId}/{timestamp}/{fileName} (temp, 24hr TTL)

assets/{fileName} (app assets, public read)

backups/{userId}/{backupId}/{fileName}
```

---

## AI Integration Architecture

### Providers
1. **Google Gemini** (Primary)
   - Text: `gemini-flash-latest` or `gemini-pro`
   - Vision: `gemini-pro-vision`
   - Key: `GEMINI_API_KEY` (backend only)

2. **NVIDIA API** (Configured but not yet implemented)
   - For specific medical image analysis if needed

### Implementation
```python
# utils/gemini_ai.py — Backend-only AI service
def ask_gemini(message: str, user: User, history: list) -> dict:
    # Build context from user health profile
    # Send to Gemini
    # Return structured response
```

### Security
- API keys ONLY in backend environment variables
- Never exposed to React or Flutter
- Rate limiting on AI endpoints
- Image validation before sending
- No sensitive health data sent without consent

---

## Data Synchronization & Consistency

### Cross-Platform Identity
```
Flutter: Firebase Auth UID → Flask User.id (mapped)
React:   Firebase Auth UID → Flask User.id (mapped)
```

### Timestamp Handling
- **Storage**: All timestamps stored in IST (Asia/Kolkata) in SQL
- **API**: Returns ISO 8601 with timezone
- **Clients**: Convert to local timezone for display

### Conflict Resolution
```
Strategy: Server Wins (with last-write-wins timestamp)
1. Client sends update with local timestamp
2. Server compares with stored updated_at
3. If server newer → reject with 409, return server version
4. If client newer → apply, update timestamp
```

---

## Deployment Architecture

### Flask Backend
- **Platform**: Render, Netlify Functions, or standalone VPS
- **Process**: Gunicorn + gevent workers
- **Database**: PostgreSQL (managed)
- **Env**: All secrets via environment variables

### React Web
- **Platform**: Netlify / Vercel
- **Build**: `npm run build` → `dist/`
- **Proxy**: API calls proxied to Flask backend

### Flutter Mobile
- **Build**: `flutter build apk --release`
- **Output**: `build/app/outputs/flutter-apk/app-release.apk`
- **Distribution**: Play Store, direct APK, or internal testing

---

## Security Considerations

### API Security
- JWT tokens with 30-day access / 90-day refresh
- Rate limiting on auth and AI endpoints
- Input validation on all endpoints
- CORS restricted to known origins
- CSRF protection on web forms

### Data Protection
- Passwords: bcrypt hashing (cost factor 12)
- Health data: User-scoped, never cross-accessible
- File uploads: Type/size validation, signed URLs
- PII: Minimized, encrypted in transit

### Firebase Security
- Firestore rules: User-scoped read/write
- Storage rules: Owner-only + family permission checks
- Custom claims: Admin, subscription tier

---

## Configuration Management

### Environment Variables
```env
# Flask Core
SECRET_KEY=
DATABASE_URL=
FLASK_ENV=

# Auth
JWT_SECRET_KEY=

# AI
GEMINI_API_KEY=

# Email
MAIL_SERVER=
MAIL_PORT=
MAIL_USERNAME=
MAIL_PASSWORD=
MAIL_DEFAULT_SENDER=

# Firebase (Server)
FIREBASE_CREDENTIALS=
FCM_SERVER_KEY=

# CORS
CORS_ORIGINS=
```

### Client Configuration
- **React**: `VITE_API_URL`, `VITE_FIREBASE_*` (public, safe in bundle)
- **Flutter**: Firebase options via `flutterfire configure`, API base URL in `AppConfig`

---

## Monitoring & Observability

### Logging
- Flask: Structured logging (JSON format)
- Levels: DEBUG, INFO, WARNING, ERROR
- Sensitive data: Never logged

### Health Checks
- `GET /api/v1/health` → `{status: ok, app: HealthTrack, version: 2.0.0}`

### Error Tracking
- Backend: Sentry (configured via env)
- Frontend: Sentry Browser SDK
- Mobile: Sentry Flutter SDK