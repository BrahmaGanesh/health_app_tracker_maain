# HealthTracker 2.0 — Complete Project Audit Report

**Date:** 2025-11-25  
**Auditor:** AI Assistant  
**Project:** HealthTracker 2.0  
**Current Status:** Deployed on Render with PostgreSQL connection error

---

## 1. EXECUTIVE SUMMARY

HealthTracker 2.0 is a comprehensive health tracking application with:
- **Flask Backend** (Python) - REST API + Jinja2 Web Templates
- **Flutter Mobile App** (Android) - Native mobile application
- **Firebase Integration** - Auth, Firestore, FCM, Storage
- **Gemini AI** - Health assistant and image analysis
- **PostgreSQL** (currently failing) → **Target: Firebase Cloud Firestore**

**Current Issue:** PostgreSQL connection failing on Render with Supabase pooler error:
```
psycopg2.OperationalError: FATAL: (ENOTFOUND) tenant/user postgres.dnnrtnptjfexmvvolgsx not found
```

---

## 2. COMPLETE FILE INVENTORY

### 2.1 Flask Backend (Root)
```
/c/health_app_main/
├── app.py                      # Flask app factory (370 lines)
├── config.py                   # Configuration (194 lines)
├── extensions.py               # Flask extensions (22 lines)
├── models.py                   # SQLAlchemy models (1876 lines, 60+ models)
├── config.py                   # Config classes (194 lines)
├── wsgi.py                     # WSGI entry point
├── .env                        # Environment variables
├── requirements.txt            # Python dependencies
├── migrations/                 # Alembic migrations
├── routes/                     # Flask routes (25+ files)
├── utils/                      # Utilities (10 files)
├── templates/                  # Jinja2 templates (15+ dirs)
├── static/                     # Static assets (CSS, JS, images)
├── firebase/                   # Firebase config
├── healthtrack_clean/          # Flutter Android app
└── healthtrack-web/            # React web app (to be removed)
```

### 2.2 Key Flask Routes (25+ files)
| Route File | Purpose |
|------------|---------|
| `auth_routes.py` | Web authentication (login, register, password reset) |
| `auth_api.py` | JWT REST API for mobile (register, login, tokens) |
| `google_auth.py` | Google OAuth 2.0 |
| `tracker_api.py` | Health metrics (BP, weight, water, sugar, sleep, steps, HR) |
| `tracker_routes.py` | Web tracker pages |
| `dashboard_api.py` | Dashboard summary API |
| `medicine_api.py` | Medicine management |
| `medicine_routes.py` | Web medicine pages |
| `health_modules_api.py` | Lab tests, appointments, emergency, AI |
| `meal_routes.py` / `meal_api.py` | Nutrition & meals |
| `exercise_routes.py` / `exercise_api.py` | Exercise tracking |
| `sleep_routes.py` / `tracker_api.py` | Sleep tracking |
| `report_routes.py` / `report_api.py` | Reports & email |
| `document_routes.py` / `document_api.py` | Document management |
| `family_routes.py` / `family_api.py` | Family member sharing |
| `appointment_api.py` | Appointments |
| `lab_api.py` | Lab tests |
| `notification_routes.py` / `notification_api.py` | Notifications |
| `timeline_api.py` | Health timeline |
| `ai_assistant_api.py` | AI chat |
| `admin_routes.py` | Admin panel |
| `business_routes.py` | Subscription/billing |
| `profile_routes.py` | User profile |
| `notification_routes.py` | Notifications |

### 2.2 Flutter App Structure (healthtrack_clean/)
```
healthtrack_clean/
├── lib/
│   ├── main.dart                 # App entry point
│   ├── constants/app_theme.dart  # Theme constants
│   ├── screens/                  # 27 screens
│   │   ├── dashboard_screen.dart
│   │   ├── bp_tracker_screen.dart
│   │   ├── sugar_tracker_screen.dart
│   │   ├── weight_tracker_screen.dart
│   │   ├── water_tracker_screen.dart
│   │   ├── sleep_tracker_screen.dart
│   │   ├── exercise_screen.dart
│   │   ├── meal_screen.dart
│   │   ├── medicine_screen.dart
│   │   ├── lab_test_screen.dart
│   │   ├── appointments_screen.dart
│   │   ├── documents_screen.dart
│   │   ├── reports_screen.dart
│   │   ├── family_screen.dart
│   │   ├── analytics_screen.dart
│   │   ├── timeline_screen.dart
│   │   ├── ai_assistant_screen.dart
│   │   ├── ai_camera_screen.dart
│   │   ├── emergency_card_screen.dart
│   │   ├── subscription_screen.dart
│   │   ├── onboarding_screen.dart
│   │   ├── login_screen.dart
│   │   ├── profile_screen.dart
│   │   └── ...
│   ├── services/
│   │   ├── api_service.dart      # REST API client (718 lines)
│   │   ├── firebase_service.dart # Firebase client (464 lines)
│   │   ├── auth_service.dart     # Auth wrapper
│   │   ├── local_db_service.dart # SQLite offline cache
│   │   ├── sync_service.dart     # Offline sync
│   │   ├── notification_service.dart
│   │   ├── step_tracking_service.dart
│   │   ├── security_service.dart
│   │   ├── google_auth_service.dart
│   │   └── sync_service.dart
│   ├── widgets/                  # Reusable widgets
│   └── constants/app_theme.dart
├── android/                      # Android config
├── pubspec.yaml                  # Dependencies
└── build/                        # Build output
```

---

## 3. DATABASE MODEL INVENTORY (60+ SQLAlchemy Models)

### Core Models (models.py - 1876 lines)
| Model | Purpose | Key Fields |
|-------|---------|------------|
| **User** | Core user | id, name, email, password_hash, google_id, fcm_token, health_profile, goals, conditions |
| **UserHealthProfile** | Profile | gender, dob, height, weight, activity_level, diet, blood_group |
| **UserGoal** | Targets | weight, water, steps, sleep, exercise, BP, sugar targets |
| **HealthCondition** | Conditions | name, icon, category |
| **UserCondition** | User conditions | severity, diagnosed_at |
| **HealthMetric** | BP, weight, water, sugar, HR | metric_type, value1/2/3, unit, recorded_at |
| **SleepLog** | Sleep tracking | sleep_time, wake_time, duration, quality |
| **ExerciseLog** | Exercise | name, type, duration, calories, sets, reps |
| **StepLog** | Steps | steps, distance, calories, goal |
| **HeartRateLog** | Heart rate | bpm, reading_type |
| **Medicine** | Medications | name, dosage, schedule, stock, reminders |
| **MedicineLog** | Adherence | status, taken, ai_verified, scheduled_time |
| **LabTest** | Lab results | category, value, ref_ranges, status |
| **DoctorVisit** | Visits | doctor, hospital, diagnosis, prescription |
| **Appointment** | Appointments | type, date, time, reminders |
| **Document** | Documents | type, file_path, mime_type, tags |
| **FamilyMember** | Family sharing | name, relation, health data |
| **EmergencyCard** | Emergency | blood_group, allergies, contacts |
| **TrustedContact** | Emergency contacts | name, phone, notify flags |
| **Appointment** | Appointments | type, date, reminders |
| **Document** | Documents | type, file_path, tags |
| **Habit** / **HabitLog** | Habits | streak, target |
| **HealthTimelineEvent** | Timeline | event_type, date, title |
| **Notification** | Notifications | type, title, message, read |
| **Reminder** | Reminders | time, repeat, sound |
| **Alert** | Alerts | type, title, message |
| **DailyHealthScore** | Scoring | bp, weight, water, sleep, exercise scores |
| **EmergencyCard** | Emergency | blood_group, allergies, contacts |
| **TrustedContact** | Emergency contacts | notify flags |
| **UserSubscription** | Subscriptions | plan, expires_at |
| **HealthTimelineEvent** | Timeline | event_type, title, icon |
| **Alert** | Alerts | type, title, message |
| **WeeklyInsight** | AI insights | metric, change, direction |
| **Recipe** | Recipes | nutrition, tags, scores |
| **MealPlan/MealItem** | Meal planning | week, slots |
| **GroceryItem** | Grocery | purchased status |
| **NutritionDailyLog** | Nutrition | macros, water |
| **EmailReportConfig** | Email reports | frequency, recipients |
| **DailyHealthScore** | Scoring | component scores |
| **Backup** | Backups | type, file_path |
| **AdminLog** | Audit | action, target |
| **WeeklyInsight** | AI insights | metric, change, direction |
| **Alert** | Alerts | type, title, message |
| **UserSettings** | Settings | notifications, targets |

---

## 4. API ENDPOINT INVENTORY

### 4.1 Authentication API (`/api/v1/auth/`)
| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/register` | POST | No | Register user |
| `/login` | POST | No | Login, returns JWT |
| `/refresh` | POST | Refresh | Refresh access token |
| `/me` | GET | JWT | Current user |
| `/fcm-token` | POST | JWT | Update FCM token |
| `/forgot-password` | POST | No | Send reset email |
| `/reset-password` | POST | No | Reset password |
| `/change-password` | POST | JWT | Change password |
| `/logout` | POST | JWT | Logout |

### 4.2 Tracker API (`/api/v1/tracker/`)
| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/bp` | POST/GET | Blood pressure |
| `/bp/<id>` | DELETE | Delete BP |
| `/weight` | POST/GET | Weight |
| `/water` | POST | Add water |
| `/water/today` | GET | Today's water |
| `/sugar` | POST/GET | Blood sugar |
| `/sleep` | POST/GET | Sleep |
| `/steps` | POST/GET | Steps |
| `/heart-rate` | POST/GET | Heart rate |
| `/summary/today` | GET | Dashboard summary |
| `/ai/chat` | POST | AI chat |

### 4.3 Other API Modules
| Module | Prefix | Key Endpoints |
|--------|--------|---------------|
| Dashboard | `/api/v1/dashboard/` | Dashboard summary |
| Meals | `/api/v1/meals/` | Recipes, plans, grocery |
| Exercise | `/api/v1/exercise/` | Logs, library |
| Medicines | `/api/v1/medicines/` | CRUD, logs, adherence |
| Lab Tests | `/api/v1/lab-tests/` | Lab results |
| Appointments | `/api/v1/appointments/` | CRUD, status |
| Documents | `/api/v1/documents/` | Upload, list |
| Family | `/api/v1/family/` | Members, metrics |
| Notifications | `/api/v1/notifications/` | CRUD, reminders |
| Timeline | `/api/v1/timeline/` | Events, calendar |
| AI Assistant | `/api/v1/ai-assistant/` | Chat |
| AI Camera | `/api/v1/ai-camera/` | Food/med analysis |
| Emergency | `/api/v1/emergency-alerts/` | Contacts |
| Subscription | `/api/v1/subscription/` | Status, verify |

---

## 5. FIREBASE CONFIGURATION AUDIT

### Current Firebase Files
| File | Status |
|------|--------|
| `firebase/firebase.json` | Config |
| `firebase/firestore.rules` | Rules (269 lines) |
| `firebase/firestore.indexes.json` | Indexes |
| `firebase/storage.rules` | Storage rules |
| `firebase/SETUP.md` | Setup guide |

### Firestore Rules Analysis
- **User-scoped collections** under `/users/{userId}/` - ✅ Proper isolation
- **Family member access** via `isFamilyMemberAuthorized()` - ✅ Implemented
- **Admin collections** protected by `isAdmin()` - ✅
- **Shared data** (exercises, recipes, conditions) - ✅ Read-only for auth users
- **Emergency card public read** - ✅ With `shareable` flag

### Storage Rules Analysis
- User documents: `/users/{userId}/documents/` - ✅ Owner + family
- Profile photos: `/users/{userId}/profile/` - ✅ Owner write, all read
- Medicine photos: `/users/{userId}/medicines/` - ✅ Owner only
- Lab reports: `/users/{userId}/lab_reports/` - ✅ Owner + family
- Emergency cards: `/emergency_cards/{userId}/` - ✅ Public read
- AI camera temp: `/ai_camera/{userId}/` - ✅ Owner only
- Backup files: `/backups/{userId}/` - ✅ Owner only

### Firebase Service (Flutter) - `firebase_service.dart`
- **Auth**: Email/password, Google sign-in
- **Firestore**: User-scoped subcollections
- **FCM**: Token management, foreground/background messages
- **Offline**: Persistence enabled, unlimited cache
- **Offline Sync**: Local SQLite + sync service

---

## 6. FLUTTER APP AUDIT

### Screens (27 screens)
| Screen | Purpose |
|--------|---------|
| `dashboard_screen.dart` | Main dashboard |
| `bp_tracker_screen.dart` | BP tracking |
| `sugar_tracker_screen.dart` | Blood sugar |
| `weight_tracker_screen.dart` | Weight |
| `water_tracker_screen.dart` | Water intake |
| `sleep_tracker_screen.dart` | Sleep |
| `exercise_screen.dart` | Exercise logging |
| `meal_screen.dart` | Meals/nutrition |
| `medicine_screen.dart` | Medicines |
| `lab_test_screen.dart` | Lab tests |
| `appointments_screen.dart` | Appointments |
| `documents_screen.dart` | Documents |
| `reports_screen.dart` | Reports |
| `family_screen.dart` | Family sharing |
| `analytics_screen.dart` | Analytics/charts |
| `timeline_screen.dart` | Health timeline |
| `ai_assistant_screen.dart` | AI chat |
| `ai_camera_screen.dart` | Camera analysis |
| `emergency_card_screen.dart` | Emergency card |
| `subscription_screen.dart` | Subscription |
| `onboarding_screen.dart` | First-time setup |
| `login_screen.dart` | Login |
| `profile_screen.dart` | Profile |
| `reports_screen.dart` | Reports |
| `analytics_screen.dart` | Analytics |
| `reminders_screen.dart` | Reminders |
| `sugar_tracker_screen.dart` | Blood sugar |
- `water_tracker_screen.dart` - Water
- `weight_tracker_screen.dart` - Weight

### API Service (`api_service.dart` - 718 lines)
- **Complete API coverage** for all endpoints
- **JWT token management** with auto-refresh
- **SharedPreferences** for token storage
- **Error handling** with auto-refresh on 401

### Firebase Service (`firebase_service.dart` - 464 lines)
- **Auth**: Email/password, Google
- **Firestore**: User-scoped subcollections
- **FCM**: Token, foreground/background
- **Offline**: Persistence enabled
- **Sync**: Local SQLite + sync service

---

## 7. WEB APPLICATION AUDIT

### Templates Structure (Jinja2)
```
templates/
├── base.html (49KB) - Main layout
├── auth/ (login, register, password reset)
├── dashboard/ (dashboard, widgets)
├── bp/ (BP tracking)
├── tracker/ (generic tracker)
├── bp/ (BP)
├── sleep/ (sleep)
├── exercise/ (exercise)
├── meals/ (meals, recipes, grocery)
├── nutrition/ (nutrition)
├── documents/ (documents)
├── reports/ (reports, email)
├── alerts/ (alerts)
├── analytics (analytics)
├── alerts/ (alerts)
├── family/ (family)
├── profile/ (profile)
├── notifications/ (notifications)
├── reports/ (reports)
├── errors/ (404, 500, 403)
```

### Static Assets
- `static/css/style.css` - Main styles
- `static/js/main.js` - Main JS
- `static/js/charts.js` - Chart.js integration
- `static/js/animations.js` - Animations
- `static/js/notifications.js` - Notifications
- `static/js/sw.js` - Service worker
- `static/icons/` - PWA icons
- `static/manifest.json` - PWA manifest

---

## 7. GEMINI AI INTEGRATION

### Current Implementation (`utils/gemini_ai.py`)
- **Model**: `gemini-flash-latest`
- **Lazy initialization** with error handling
- **Context building** from user profile
- **History support** (last 5 messages)
- **Health-focused prompts** with safety guidelines
- **Error handling** with graceful degradation

### AI Endpoints
| Endpoint | Purpose |
|----------|---------|
| `/api/v1/ai-assistant/chat` | Chat with health context |
| `/api/v1/ai-camera/food` | Food image analysis |
| `/api/v1/ai-camera/medicine` | Medicine identification |
| `/api/v1/modules/claude/chat` | Claude chat (backup) |
| `/api/v1/modules/ai-camera/food` | Food analysis (vision) |
| `/api/v1/modules/ai-camera/medicine` | Medicine analysis (vision) |

### Issues Found
1. **Duplicate AI implementations** - Both `gemini_ai.py` and `health_modules_api.py` have AI chat
2. **Vision model undefined** - `vision_model` referenced but not initialized in `health_modules_api.py`
3. **Deprecated model name** - `gemini-flash-latest` may not be current

---

## 8. DATABASE MIGRATION REQUIREMENTS

### Current PostgreSQL Issues
1. **Connection failing** on Render with Supabase pooler
2. **ENOTFOUND tenant/user** - Invalid pooler connection string
3. **SQLAlchemy models** - 60+ models tightly coupled to PostgreSQL

### Migration Requirements
| SQL Table | Firestore Collection | Migration Complexity |
|-----------|---------------------|---------------------|
| `users` | `users/{uid}` | Medium (auth migration) |
| `userhealthprofiles` | `users/{uid}/profile` | Easy |
| `usergoals` | `users/{uid}/goals` | Easy |
| `healthmetrics` | `users/{uid}/health_metrics` | High (6 types) |
| `sleeplogs` | `users/{uid}/sleep_records` | Medium |
| `exerciselogs` | `users/{uid}/exercise_logs` | Medium |
| `steplogs` | `users/{uid}/steps` | Medium |
| `heartratelogs` | `users/{uid}/heart_rate` | Medium |
| `medicines` | `users/{uid}/medicines` | High (logs, schedules) |
| `medicine_logs` | `users/{uid}/medicines/{id}/logs` | High |
| `lab_tests` | `users/{uid}/lab_tests` | Medium |
| `doctor_visits` | `users/{uid}/doctor_visits` | Medium |
| `appointments` | `users/{uid}/appointments` | Medium |
| `documents` | `users/{uid}/documents` | High (files) |
| `family_members` | `users/{uid}/family_members` | High (nested) |
| `notifications` | `users/{uid}/notifications` | Medium |
| `reminders` | `users/{uid}/reminders` | Medium |
| `alerts` | `users/{uid}/alerts` | Medium |
| `health_timeline_events` | `users/{uid}/health_timeline` | Medium |
| `habits` / `habit_logs` | `users/{uid}/habits` | Medium |
| `dailyhealthscores` | `users/{uid}/health_scores` | Medium |
| `emergency_cards` | `users/{uid}/emergency_card` | Easy |
| `trusted_contacts` | `users/{uid}/trusted_contacts` | Easy |
| `user_subscriptions` | `users/{uid}/subscription` | Easy |
| `health_timeline_events` | `users/{uid}/health_timeline` | Medium |
| `habits` / `habit_logs` | `users/{uid}/habits` | Medium |
| `dailyhealthscores` | `users/{uid}/health_scores` | Medium |
| `recipes` | `recipes/` (shared) | Medium |
| `exerciselibrary` | `exercise_library/` (shared) | Medium |
| `healthconditions` | `health_conditions/` (shared) | Easy |

---

## 8. AUTHENTICATION AUDIT

### Current Auth Systems (Dual!)
1. **Flask Session + Flask-Login** - Web templates
2. **JWT (Flask-JWT-Extended)** - API for mobile
3. **Firebase Auth** - Flutter app direct
4. **Google OAuth** - Web only

### Issues
- **Two independent auth systems** (Flask session + JWT)
- **Flutter uses Firebase Auth directly** - bypasses Flask
- **Web uses Flask-Login** - separate from Firebase
- **No unified identity** across platforms

---

## 9. CRITICAL ISSUES IDENTIFIED

| # | Issue | Severity | Impact |
|---|-------|----------|--------|
| 1 | PostgreSQL connection failing on Render | **Critical** | App non-functional on Render |
| 2 | Dual auth systems (Flask + Firebase) | **High** | Data isolation issues |
| 2 | PostgreSQL connection failing | **Critical** | App down on Render |
| 3 | Dual auth systems | **High** | Data isolation, sync issues |
| 4 | Duplicate AI implementations | **Medium** | Maintenance burden |
| 5 | Vision model undefined in `health_modules_api.py` | **High** | AI camera broken |
| 6 | React web app (`healthtrack-web/`) unused | **Medium** | Confusion, bloat |
| 7 | Flutter test broken (`MyApp` vs `HealthTrackApp`) | **Medium** | Tests fail |
| 8 | `vision_model` undefined in `health_modules_api.py` | **High** | AI camera broken |
| 9 | PostgreSQL migration files unused | **Low** | Cleanup needed |
| 10 | Duplicate AI endpoints (`/ai-assistant/chat` + `/modules/claude/chat`) | **Medium** | Confusion |
| 11 | `vision_model` undefined in `health_modules_api.py` | **High** | AI camera broken |
| 12 | `healthtrack-web/` React app unused | **Medium** | Waste, confusion |

---

## 10. MIGRATION PLAN SUMMARY

### Phase 1: Foundation (Week 1)
1. **Fix Firestore rules** for new structure
2. **Create Firebase Admin service** for Flask
3. **Implement Firebase Auth verification** middleware
5. **Create Firestore service layer** for Flask

### Phase 2: Auth Migration (Week 2)
1. **Unify auth** - Firebase as source of truth
2. **Flask middleware** to verify Firebase ID tokens
3. **Migrate auth endpoints** to Firebase Admin
4. **Update Flutter** to use Firebase Auth + Flask API

### Phase 3: Data Migration (Week 3)
1. **Create Firestore service classes** for each domain
2. **Migrate models** from SQLAlchemy to Firestore
3. **Migrate API endpoints** one by one
4. **Test each endpoint** thoroughly

### Phase 4: Frontend Integration (Week 4)
1. **Update Flutter** to use new auth + API
2. **Verify web templates** work with new API
3. **Cross-platform sync testing**

### Phase 5: Cleanup & Deploy (Week 5)
1. Remove PostgreSQL code
2. Remove unused React app
3. Deploy to Render with Firestore
4. End-to-end testing

---

## 11. IMMEDIATE ACTION REQUIRED

### Immediate (Today)
1. **Fix Render DATABASE_URL** - Use correct Supabase connection string
2. **Remove `healthtrack-web/`** React app (unused duplicate)
3. **Fix Flutter test** - Update import from `healthtrack_clean` to `healthtrack`
4. **Fix `health_modules_api.py`** - Remove undefined `vision_model`

### This Week
1. Create Firebase Admin service for Flask
2. Implement Firebase ID token verification middleware
3. Migrate auth API to Firebase Admin
4. Create Firestore service layer

### Next Week
1. Migrate all API endpoints to Firestore
2. Update Flutter app to use Firebase Auth + Flask API
3. Test cross-platform sync

---

## 12. FILES TO MODIFY / CREATE / DELETE

### Files to DELETE
- `/c/health_app_main/healthtrack-web/` (entire directory - unused React app)
- `/c/health_app_main/migrations/` (PostgreSQL migrations - after verification)
- `/c/health_app_main/models.py` (replace with Firestore models)
- `/c/health_app_main/migrations/` (Alembic migrations)

### Files to MODIFY
| File | Changes |
|------|---------|
| `app.py` | Remove SQLAlchemy, add Firebase Admin init |
| `config.py` | Remove DATABASE_URL, add Firebase config |
| `extensions.py` | Remove SQLAlchemy, add Firebase Admin |
| `models.py` | Replace with Firestore models/services |
| `auth_api.py` | Migrate to Firebase Admin auth |
| `tracker_api.py` | Migrate to Firestore |
| All API routes | Migrate to Firestore services |
| `healthtrack_clean/lib/services/firebase_service.dart` | Update for new structure |
| `healthtrack_clean/lib/services/api_service.dart` | Update auth headers |
| `healthtrack_clean/lib/services/auth_service.dart` | Use Firebase Auth |
| `firebase/firestore.rules` | Update for new structure |
| `config.py` | Remove DATABASE_URL, add Firebase config |
| `.env` | Update with production values |

### Files to CREATE
| File | Purpose |
|------|---------|
| `services/firebase_admin.py` | Firebase Admin initialization |
| `services/firestore_service.py` | Firestore CRUD operations |
| `services/auth_service.py` | Firebase token verification |
| `services/user_service.py` | User profile management |
| `services/health_metric_service.py` | Health metrics CRUD |
| `services/medicine_service.py` | Medicine CRUD |
| `services/appointment_service.py` | Appointment CRUD |
| `services/document_service.py` | Document management |
| `services/family_service.py` | Family sharing |
| `services/notification_service.py` | Notifications |
| `services/ai_service.py` | Gemini AI integration |
| `middleware/auth_middleware.py` | Firebase token verification |
| `scripts/migrate_to_firestore.py` | Data migration script |

---

## 14. FIRESTORE COLLECTION STRUCTURE (PROPOSED)

```
users/{uid}
├── profile (document)
├── goals (document)
├── settings (document)
├── subscription (document)
├── emergency_card (document)
├── health_metrics/{metricId}
│   ├── type: "bp" | "weight" | "water" | "sugar" | "sleep" | "heart_rate" | "steps"
│   ├── value1, value2, value3 (number)
│   ├── unit (string)
│   ├── recorded_at (timestamp)
│   ├── source (string)
│   └── notes (string)
├── sleep_records/{recordId}
├── exercise_logs/{logId}
├── step_logs/{logId}
├── heart_rate_logs/{logId}
├── medicines/{medicineId}
│   ├── logs/{logId}
│   ├── schedules/{scheduleId}
│   └── stock/{stockId}
├── lab_tests/{testId}
├── doctor_visits/{visitId}
├── appointments/{apptId}
├── documents/{docId}
├── family_members/{memberId}
│   ├── health_metrics/{metricId}
│   ├── medicines/{medicineId}
│   ├── appointments/{apptId}
│   └── documents/{docId}
├── notifications/{notificationId}
├── reminders/{reminderId}
├── alerts/{alertId}
├── health_timeline/{eventId}
├── habits/{habitId}
│   └── logs/{logId}
├── health_scores/{scoreId}
├── emergency_card (document)
├── trusted_contacts/{contactId}
├── subscriptions/{subId}
├── health_timeline/{eventId}
├── ai_reports/{reportId}
└── notifications/{notificationId}
```

### Shared Collections (read-only for users)
- `exercise_library/` - Exercise definitions
- `recipes/` - Recipe database
- `health_conditions/` - Condition definitions

---

## 15. FIRESTORE SECURITY RULES (UPDATED)

Key principles:
1. **All user data under `/users/{uid}/`** - scoped to authenticated user
2. **Family access** via `isFamilyMemberAuthorized()` function
3. **Admin access** via `isAdmin()` custom claim
4. **No direct client access** to protected collections unless explicitly needed
4. **Server-only** access via Admin SDK for sensitive operations

---

## 16. RENDER DEPLOYMENT CONFIGURATION

### Required Environment Variables
```bash
# Core
SECRET_KEY=<generated>
JWT_SECRET_KEY=<generated>
FLASK_ENV=production

# Firebase
FIREBASE_PROJECT_ID=health-tracker-2-0
FIREBASE_CREDENTIALS_BASE64=<base64_encoded_service_account>
GEMINI_API_KEY=<from Google AI Studio>

# Database (REMOVED - no PostgreSQL)
# DATABASE_URL=  # REMOVED

# CORS
CORS_ORIGINS=https://health-app-tracker-maa.onrender.com

# Security
SESSION_COOKIE_SECURE=True
WTF_CSRF_SSL_STRICT=True
SESSION_COOKIE_SAMESITE=Lax
```

### Render Configuration
```yaml
# render.yaml
services:
  - type: web
    name: healthtrack-api
    runtime: python
    buildCommand: "pip install -r requirements.txt"
    startCommand: "gunicorn --workers 4 --bind 0.0.0.0:$PORT wsgi:app"
    envVars:
      - key: DATABASE_URL
        fromDatabase: healthtrack-db
    autoDeploy: true
```

---

## 17. NEXT STEPS - IMPLEMENTATION ORDER

### Immediate (Today)
1. ✅ Fix Render `DATABASE_URL` with correct Supabase connection string
2. ✅ Remove `healthtrack-web/` React app
3. ✅ Fix Flutter test import (`healthtrack_clean` → `healthtrack`)
4. ✅ Fix `health_modules_api.py` - remove undefined `vision_model`

### Week 1: Foundation
1. Create Firebase Admin service (`services/firebase_admin.py`)
2. Create Firestore service base class
3. Implement Firebase ID token verification middleware
4. Update `config.py` - remove DATABASE_URL, add Firebase config
5. Update `app.py` - remove SQLAlchemy, initialize Firebase Admin

### Week 2: Auth Migration
1. Migrate `auth_api.py` to Firebase Admin
2. Create `/api/v1/auth/verify` endpoint for Flutter
3. Update Flutter `auth_service.dart` to use Firebase Auth
4. Add Firebase ID token verification middleware to Flask

### Week 3-4: API Migration
1. Create Firestore service classes for each domain
2. Migrate `tracker_api.py` → Firestore
3. Migrate `medicine_api.py` → Firestore
4. Migrate all remaining API routes
5. Update Flutter `api_service.dart` for new endpoints

### Week 5: Frontend & Testing
1. Update Flutter `api_service.dart` for new auth
2. Update Flutter `auth_service.dart` for Firebase Auth
3. Test web templates with new API
4. Test Flutter app with new auth + API
5. Cross-platform sync testing

### Week 6: Cleanup & Deploy
1. Remove SQLAlchemy models
2. Remove Alembic migrations
3. Remove `healthtrack-web/` (already done)
4. Deploy to Render with Firestore
5. End-to-end testing

---

## 18. TESTING CHECKLIST

### Backend Tests
- [ ] Flask startup with Firebase
- [ ] Firebase Admin initialization
- [ ] Firestore read/write
- [ ] Firebase ID token verification
- [ ] All CRUD endpoints
- [ ] Error handling
- [ ] Rate limiting

### Web Tests
- [ ] Login/Register
- [ ] Dashboard loads
- [ ] Data entry forms
- [ ] Charts render
- [ ] Forms submit
- [ ] Error handling

### Flutter Tests
- [ ] Login/Register
- [ ] Dashboard
- [ ] All trackers
- [ ] Offline mode
- [ ] Sync on reconnect
- [ ] Push notifications

### Cross-Platform
- [ ] Register on web → login on Android
- [ ] Add BP on Android → see on web
- [ ] Edit on web → see on Android
- [ ] User isolation verified

---

**Report Generated:** 2025-11-25  
**Next Action:** Fix Render DATABASE_URL and begin Phase 1 implementation