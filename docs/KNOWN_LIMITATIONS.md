# HealthTrack 2.0 — Known Limitations

**Date:** 2025-11-25  
**Version:** Based on audit as of 2025-11-25

---

## Critical Limitations

### 1. Cross-Platform Authentication Not Unified
**Issue:** Web (Flask) and Android (Flutter) use separate authentication systems.
- **Web:** Flask session cookies + JWT via `auth_routes.py`/`auth_api.py`
- **Android:** Firebase Authentication SDK directly
- **Impact:** Users must log in separately on web and mobile
- **Root Cause:** Flask verifies passwords via SQLAlchemy; Flutter uses Firebase Auth SDK directly
- **Fix Required:** Add Firebase Admin SDK to Flask; verify Firebase ID tokens in `auth_api.py`

### 2. Data Synchronization Not Implemented
**Issue:** Flutter uses local SQLite + syncs to Flask API; Flask uses SQLAlchemy (SQLite/PostgreSQL)
- **Current State:** Flutter → Flask API (one-way via REST)
- **Missing:** Bi-directional sync, conflict resolution, real-time updates
- **Impact:** Data created on web not visible on Android until manual sync; vice versa
- **Fix Required:** Implement bi-directional sync via Flask API or migrate both to Firestore

### 3. Flutter Tests Require Firebase Mocking
**Issue:** `flutter test` fails with `[core/no-app] No Firebase App '[DEFAULT]' has been created`
- **Root Cause:** `Firebase.initializeApp()` not called in test environment
- **Impact:** Cannot run widget tests in CI/CD
- **Fix Required:** Add Firebase mock for tests or use `firebase_core` test utilities

### 4. Web Application Uses Separate Auth from Android
**Issue:** Web uses Flask session + Flask-Login; Android uses Firebase Auth
- **Impact:** No single sign-on; separate user management
- **Related to Limitation #1**

---

## Non-Critical Limitations

### 5. Flutter Deprecation Warnings (50+)
| Warning | Count | Fix |
|---------|-------|-----|
| `withOpacity` deprecated | ~30 | Replace with `.withValues()` |
| `activeColor` deprecated | ~5 | Use `activeThumbColor` |
| `value` deprecated on form fields | ~5 | Use `initialValue` |
| Unused imports/variables | ~15 | Clean up |

### 6. Kotlin Gradle Plugin Warnings (Non-blocking)
**Plugins affected:** `audioplayers_android`, `file_picker`, `flutter_tts`, `fluttertoast`, `pedometer`
- **Impact:** Build succeeds but warns about future incompatibility
- **Fix:** Upgrade plugins or wait for plugin authors to migrate

### 7. Flask Console Emoji Encoding
**Issue:** `charmap` codec errors when printing emojis to Windows console
- **Impact:** Cosmetic only - doesn't affect functionality
- **Fix:** Set `PYTHONIOENCODING=utf-8` or replace emojis in logs

### 8. Google Generative AI SDK Deprecated
**Issue:** `google.generativeai` package support ended; migrate to `google.genai`
- **Impact:** AI features work but on deprecated SDK
- **Fix:** Migrate to `google-genai` Python package

### 9. Firebase Messaging `subject` Deprecated
**Fixed:** Changed `_messaging.subject` → `FirebaseMessaging.onMessage`
- **Status:** ✅ Fixed in `firebase_service.dart`

### 9. Firestore `CollectionReference` Type Mismatch
**Fixed:** Changed return type from `CollectionReference` to `Query<Map<String, dynamic>>`
- **Status:** ✅ Fixed in `firebase_service.dart`

---

## Features Not Fully Tested

| Feature | Tested | Notes |
|---------|--------|-------|
| Google OAuth Login (Web) | ❌ | Flask has `google_auth.py` but not tested |
| Google Sign-In (Android) | ❌ | Flutter has `google_sign_in` but not tested |
| Document Upload (Web) | ❌ | Flask has `document_routes.py` but not tested |
| Document Upload (Android) | ❌ | Flutter has `documents_screen.dart` but not tested |
| Family Sharing Permissions | ❌ | Backend has logic but UI not tested |
| Push Notifications (Web) | ❌ | `firebase_push.py` exists but not tested |
| Push Notifications (Android) | ❌ | FCM configured but not tested |
| AI Health Assistant (Web) | ❌ | `gemini_ai.py` exists but not tested |
| AI Health Assistant (Android) | ❌ | `ai_assistant_screen.dart` exists but not tested |
| AI Camera (Food/Med) | ❌ | Exists in both but not tested |
| Cross-Platform Data Sync | ❌ | Not implemented |

---

## Files Requiring Attention

| File | Issue | Priority |
|------|-------|----------|
| `routes/api/auth_api.py` | Add Firebase Admin SDK token verification | Critical |
| `healthtrack_clean/lib/services/firebase_service.dart` | Fix test Firebase initialization | High |
| `healthtrack_clean/test/widget_test.dart` | Add Firebase mock | High |
| `routes/api/auth_api.py` | Add Firebase Admin SDK | Critical |
| `utils/gemini_ai.py` | Migrate to `google.genai` | Medium |
| `healthtrack_clean/lib/services/notification_service.dart` | Fix Firebase init in tests | High |
| Multiple Flutter files | Replace deprecated APIs | Low |

---

## Technical Debt

1. **Duplicate Code:** Some models duplicated between Flask SQLAlchemy and Flutter local models
2. **Inconsistent API Responses:** Some endpoints return `{"success": true, "data": {...}}`, others return direct data
3. **No API Versioning Strategy:** All endpoints under `/api/v1/` but no deprecation policy
4. **No Rate Limiting:** AI endpoints and auth endpoints lack rate limiting
5. **No API Documentation:** No OpenAPI/Swagger docs generated
6. **Mixed Timezone Handling:** Some code uses IST, some UTC, some local time

---

## Recommendations

### Immediate (Week 1)
1. Add Firebase Admin SDK to Flask `auth_api.py`
2. Mock Firebase in Flutter tests
3. Fix Flutter test initialization

### Short-term (Week 2-3)
1. Implement Flask ↔ Flutter data sync via REST API
2. Add unified auth with Firebase Admin SDK
3. Complete end-to-end sync testing

### Medium-term (Month 1)
1. Migrate Gemini AI to `google.genai`
2. Fix all Flutter deprecation warnings
3. Add rate limiting to AI/auth endpoints
4. Generate API documentation

### Long-term (Month 2-3)
1. Evaluate unified Firestore backend
2. Add comprehensive integration tests
3. Implement CI/CD pipeline
4. Add monitoring and error tracking
