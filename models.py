# models.py
# Firestore-compatible models for Flask + Firebase Auth.
# Data is stored in Cloud Firestore. This file does not use SQLAlchemy.

from datetime import datetime, date, timezone, timedelta
import json

from flask_login import UserMixin


# ---------------------------------------------------------------------------
# Timezone helpers
# ---------------------------------------------------------------------------

IST = timezone(timedelta(hours=5, minutes=30))


def now_ist():
    """Return the current datetime in Indian Standard Time."""
    return datetime.now(IST)


def today_ist():
    """Return today's date in Indian Standard Time."""
    return now_ist().date()


# ---------------------------------------------------------------------------
# Generic Firestore model base
# ---------------------------------------------------------------------------

class FirestoreModel:
    """
    Base model for Firestore documents.

    It accepts either:
        Model({"id": "123", "name": "Test"})
    or:
        Model(id="123", name="Test")

    Unknown fields are preserved, so route code can access fields such as:
        item.user_id
        item.title
        item.created_at
    even if they are not explicitly declared below.
    """

    COLLECTION = None
    DEFAULTS = {}

    def __init__(self, data=None, **kwargs):
        incoming = dict(data or {})
        incoming.update(kwargs)

        self._data = {**self.DEFAULTS, **incoming}
        self.id = self._data.get("id", "")

    def __getattr__(self, name):
        """
        Called only when a normal attribute is not found.
        Returns the value from the Firestore document data.
        """
        data = self.__dict__.get("_data", {})

        if name in data:
            return data[name]

        raise AttributeError(
            f"{self.__class__.__name__} has no attribute '{name}'"
        )

    def to_dict(self):
        """Return a JSON-safe dictionary for Firestore and templates."""
        result = {}

        for key, value in self._data.items():
            if isinstance(value, datetime):
                result[key] = value.isoformat()
            elif isinstance(value, date):
                result[key] = value.isoformat()
            else:
                result[key] = value

        result["id"] = self.id
        return result

    def update(self, updates=None, **kwargs):
        """Update local model fields. Call save_document() to persist."""
        updates = updates or {}
        self._data.update(updates)
        self._data.update(kwargs)

        if "id" in self._data:
            self.id = self._data["id"]

    def get(self, key, default=None):
        """Get a field value from the model data."""
        return self._data.get(key, default)

    # =====================
    # Firestore Query Methods
    # =====================

    @classmethod
    def get_by_id(cls, document_id):
        """Get a document by its ID from Firestore.

        Args:
            document_id: The document ID to retrieve

        Returns:
            cls instance or None if not found
        """
        from services.firebase_admin import get_firebase_admin
        firebase_admin = get_firebase_admin()
        doc_ref = firebase_admin.firestore.collection(cls.COLLECTION).document(document_id)
        doc = doc_ref.get()
        if doc.exists:
            data = doc.to_dict() or {}
            data["id"] = doc.id
            return cls(data)
        return None

    @classmethod
    def get_all(cls, filters=None, order_by=None, limit=None):
        """Get all documents from the collection with optional filtering and ordering.

        Args:
            filters: dict of {field: value} for equality filtering
            order_by: field name to sort by (ascending)
            limit: maximum number of results

        Returns:
            list of cls instances
        """
        from services.firebase_admin import get_firebase_admin
        firebase_admin = get_firebase_admin()
        collection_ref = firebase_admin.firestore.collection(cls.COLLECTION)

        results = []
        seen_ids = set()

        docs = collection_ref.stream()
        for doc in docs:
            data = doc.to_dict()
            data['id'] = doc.id

            # Skip duplicates
            if data['id'] in seen_ids:
                continue
            seen_ids.add(data['id'])

            # Apply equality filters
            if filters:
                skip = False
                for field, f_value in filters.items():
                    val = data.get(field)
                    if val != f_value:
                        skip = True
                        break
                if skip:
                    continue

            results.append(cls(data))

        # Apply ordering (Python-side sort)
        if order_by:
            results.sort(key=lambda x: getattr(x, order_by, None) or '')

        # Apply limit
        if limit and len(results) > limit:
            results = results[:limit]

        return results

    @classmethod
    def get_by_field(cls, field, value, order_by=None):
        """Get documents where a field equals a specific value.

        Args:
            field: The field name to filter by
            value: The value to match
            order_by: Optional field name to sort results by

        Returns:
            list of cls instances matching the filter
        """
        from services.firebase_admin import get_firebase_admin
        firebase_admin = get_firebase_admin()
        collection_ref = firebase_admin.firestore.collection(cls.COLLECTION)

        results = []
        docs = collection_ref.stream()

        for doc in docs:
            data = doc.to_dict()
            data['id'] = doc.id

            if data.get(field) == value:
                results.append(cls(data))

        # Apply ordering if requested
        if order_by:
            results.sort(key=lambda x: getattr(x, order_by, None) or '')

        return results

    @classmethod
    def count(cls, filters=None):
        """Count documents in the collection matching optional filters.

        Args:
            filters: dict of {field: value} for equality filtering

        Returns:
            integer count of matching documents
        """
        from services.firebase_admin import get_firebase_admin
        import firebase_admin.firestore as firestore_module

        firebase_admin = get_firebase_admin()
        collection_ref = firebase_admin.firestore.collection(cls.COLLECTION)

        # Use Firestore's count() aggregation if available
        try:
            query = collection_ref
            if filters:
                for field, f_value in filters.items():
                    query = query.where(field, '==', f_value)
            count_result = query.count().get()
            return count_result[0][0].value if count_result else 0
        except Exception:
            # Fallback: count manually
            count = 0
            docs = collection_ref.stream()
            for _ in docs:
                count += 1
            return count

    @classmethod
    def exists(cls, document_id):
        """Check if a document exists in the collection.

        Args:
            document_id: The document ID to check

        Returns:
            bool: True if document exists, False otherwise
        """
        from services.firebase_admin import get_firebase_admin
        firebase_admin = get_firebase_admin()
        doc_ref = firebase_admin.firestore.collection(cls.COLLECTION).document(document_id)
        doc = doc_ref.get()
        return doc.exists

    @classmethod
    def find_one(cls, filters):
        """Find the first document matching the given filters.

        Args:
            filters: dict of {field: value} for equality filtering

        Returns:
            cls instance or None if not found
        """
        results = cls.get_all(filters=filters, limit=1)
        return results[0] if results else None

    @classmethod
    def get_one(cls, filters=None):
        """Alias for find_one - get a single document matching filters."""
        return cls.find_one(filters)

    @classmethod
    def get_by_id_or_404(cls, document_id):
        """Get a document by ID or raise 404-like error.

        Args:
            document_id: The document ID to retrieve

        Returns:
            cls instance

        Raises:
            ValueError: If document not found (routes should handle with 404)
        """
        result = cls.get_by_id(document_id)
        if result is None:
            raise ValueError(f"{cls.__name__} with id {document_id} not found")
        return result

    def save(self):
        """Save the document to Firestore.

        Creates a new document if id is empty, or updates existing document.
        """
        from services.firebase_admin import get_firebase_admin
        import datetime

        firebase_admin = get_firebase_admin()

        data = dict(self._data) if hasattr(self, '_data') else {}
        if hasattr(self, 'to_dict'):
            data = self.to_dict()

        # Remove None values to avoid overwriting with nulls
        data = {k: v for k, v in data.items() if v is not None}

        # Set timestamps
        now = datetime.datetime.utcnow()
        if 'created_at' not in data:
            data['created_at'] = now
        data['updated_at'] = now

        # Save to Firestore
        if self.id:
            doc_ref = firebase_admin.firestore.collection(self.COLLECTION).document(self.id)
            doc_ref.set(data)
        else:
            # Create new document with auto ID
            doc_ref = firebase_admin.firestore.collection(self.COLLECTION).document()
            doc_ref.set(data)
            self.id = doc_ref.id
            self._data['id'] = self.id

        return self


# ---------------------------------------------------------------------------
# User and authentication
# ---------------------------------------------------------------------------

class User(UserMixin):
    """Firestore-compatible user model for Flask-Login."""

    COLLECTION = "users"

    def __init__(self, user_data=None, **kwargs):
        data = dict(user_data or {})
        data.update(kwargs)

        self.id = data.get("id") or data.get("uid") or ""
        self.uid = self.id

        self.name = data.get("name", "")
        self.email = data.get("email", "")
        self.display_name = data.get("display_name", "") or self.name
        self.phone = data.get("phone", "")
        self.profile_photo = data.get("profile_photo")
        self.photo_url = data.get("photo_url") or self.profile_photo

        self._is_active = data.get("is_active", data.get("active", True))
        self.is_verified = data.get("is_verified", False)
        self.auth_provider = data.get("auth_provider", "email")

        self.family_member_limit = data.get("family_member_limit", 2)
        self.plan = data.get("plan", "free")
        self.subscription_status = data.get("subscription_status", "free")

        self.google_id = data.get("google_id")
        self.google_email = data.get("google_email")
        self.google_access_token = data.get("google_access_token")
        self.google_refresh_token = data.get("google_refresh_token")

        self.fcm_token = data.get("fcm_token")
        self.web_push_sub = data.get("web_push_sub")

        self.created_at = data.get("created_at")
        self.updated_at = data.get("updated_at")

        self._data = data

    @property
    def is_active(self):
        return self._is_active

    @is_active.setter
    def is_active(self, value):
        self._is_active = value

    def save(self):
        """Save user data to Firestore."""
        from services.firebase_admin import get_firebase_admin
        import datetime

        db = get_firebase_admin().firestore
        data = dict(self._data) if hasattr(self, '_data') else {}

        # Remove None values to avoid overwriting with nulls
        data = {k: v for k, v in data.items() if v is not None}

        # Set timestamps
        now = datetime.datetime.utcnow()
        if 'created_at' not in data:
            data['created_at'] = now
        data['updated_at'] = now

        # Save to Firestore
        if self.id:
            doc_ref = db.collection(self.COLLECTION).document(self.id)
            doc_ref.set(data)
        else:
            doc_ref = db.collection(self.COLLECTION).document()
            doc_ref.set(data)
            self.id = doc_ref.id
            self._data['id'] = self.id

        return self

    # Admin check - users with "admin" plan or email domain are admins
    @property
    def is_admin(self):
        """Check if user has admin privileges."""
        # Check plan first, then fall back to email domain
        return self.plan == "admin" or self.email.endswith("@admin.com") if self.email else False

    @property
    def goals(self):
        """Return user goals, loading from Firestore if needed."""
        goals_id = self._data.get("goals_id")
        if goals_id:
            from models import UserGoal
            from services.firebase_admin import get_firebase_admin
            firebase_admin = get_firebase_admin()
            doc = firebase_admin.firestore.collection(UserGoal.COLLECTION).document(goals_id).get()
            if doc.exists:
                data = doc.to_dict() or {}
                data["id"] = doc.id
                return UserGoal(data)
        # Return default goals
        from models import UserGoal
        return UserGoal({"user_id": self.id})

    @property
    def daily_calorie_target(self):
        """Return daily calorie target, loading from Firestore if needed."""
        calorie_id = self._data.get("daily_calorie_target_id")
        if calorie_id:
            from services.firebase_admin import get_firebase_admin
            firebase_admin = get_firebase_admin()
            doc = firebase_admin.firestore.collection("user_daily_targets").document(calorie_id).get()
            if doc.exists:
                data = doc.to_dict() or {}
                return data.get("calories", 2000)
        return 2000  # Default target

    @property
    def daily_protein_target(self):
        """Return daily protein target, loading from Firestore if needed."""
        protein_id = self._data.get("daily_protein_target_id")
        if protein_id:
            from services.firebase_admin import get_firebase_admin
            firebase_admin = get_firebase_admin()
            doc = firebase_admin.firestore.collection("user_daily_targets").document(protein_id).get()
            if doc.exists:
                data = doc.to_dict() or {}
                return data.get("protein", 80)
        return 80  # Default target

    @property
    def condition_names(self):
        """Return list of condition names associated with this user."""
        condition_ids = self._data.get("condition_ids", [])
        return list(condition_ids) if condition_ids else []

    @property
    def onboarding_done(self):
        """Return list of condition names associated with this user."""
        condition_ids = self._data.get("condition_ids", [])
        return list(condition_ids) if condition_ids else []

    @property
    def onboarding_done(self):
        """Check if user has completed onboarding."""
        return self._data.get("onboarding_done", False)

    @onboarding_done.setter
    def onboarding_done(self, value):
        self._data["onboarding_done"] = bool(value)
        self.updated_at = datetime.now(IST)

    @property
    def health_profile(self):
        """Return list of condition names associated with this user.

        Conditions are stored in the UserCondition collection, but this
        property provides a convenient list of condition names from both
        the user's conditions and health profile.
        """
        # Get condition IDs from UserCondition records
        condition_ids = self._data.get("condition_ids", [])
        if not condition_ids:
            return []
        # Return condition names - in a real app we'd query HealthCondition
        # For now, return the IDs as names or empty list
        return list(condition_ids) if condition_ids else []

    @property
    def onboarding_done(self):
        """Check if user has completed onboarding."""
        return self._data.get("onboarding_done", False)

    @onboarding_done.setter
    def onboarding_done(self, value):
        self._data["onboarding_done"] = bool(value)
        self.updated_at = datetime.now(IST)

    @property
    def health_profile(self):
        """Check if user has completed onboarding."""
        return self._data.get("onboarding_done", False)

    @onboarding_done.setter
    def onboarding_done(self, value):
        self._data["onboarding_done"] = bool(value)
        self.updated_at = datetime.now(IST)

    @property
    def health_profile(self):
        """Fetch the user's health profile from Firestore."""
        from models import UserHealthProfile
        # Try to get the health profile document
        profile_id = self._data.get("health_profile_id")
        if profile_id:
            try:
                doc = db.collection(UserHealthProfile.COLLECTION).document(profile_id).get()
                if doc.exists:
                    data = doc.to_dict() or {}
                    data["id"] = doc.id
                    return UserHealthProfile(data)
            except Exception:
                pass
        # Return a default health profile if none exists
        return UserHealthProfile({"user_id": self.id, "onboarding_step": 1})

    @property
    def email_report_config(self):
        """Fetch the user's email report config from Firestore."""
        from models import EmailReportConfig
        from services.firebase_admin import get_firebase_admin
        config_id = self._data.get("email_report_config_id")
        if config_id:
            try:
                firebase_admin = get_firebase_admin()
                doc = firebase_admin.firestore.collection(EmailReportConfig.COLLECTION).document(config_id).get()
                if doc.exists:
                    data = doc.to_dict() or {}
                    data["id"] = doc.id
                    return EmailReportConfig(data)
            except Exception:
                pass
        # Return a default config if none exists
        return EmailReportConfig({"user_id": self.id})

    def get_id(self):
        """Flask-Login requires a string user ID."""
        return str(self.id)

    def to_dict(self):
        return {
            "id": self.id,
            "uid": self.uid,
            "name": self.name,
            "email": self.email,
            "display_name": self.display_name,
            "phone": self.phone,
            "profile_photo": self.profile_photo,
            "photo_url": self.photo_url,
            "is_active": self.is_active,
            "is_verified": self.is_verified,
            "auth_provider": self.auth_provider,
            "family_member_limit": self.family_member_limit,
            "plan": self.plan,
            "subscription_status": self.subscription_status,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
        }

    def set_password(self, password):
        """Passwords are managed by Firebase Authentication."""
        return None

    def check_password(self, password):
        """Password verification is handled by Firebase Authentication."""
        return True


# ---------------------------------------------------------------------------
# User profile, goals and settings
# ---------------------------------------------------------------------------

class UserHealthProfile(FirestoreModel):
    COLLECTION = "user_health_profiles"

    DEFAULTS = {
        "gender": None,
        "date_of_birth": None,
        "height_cm": None,
        "current_weight_kg": None,
        "activity_level": "sedentary",
        "diet_preference": "vegetarian",
        "blood_group": None,
        "emergency_contact": None,
    }

    def get(self, key, default=None):
        """Dictionary-style getter for health profile fields."""
        return self._data.get(key, default)


class UserGoal(FirestoreModel):
    COLLECTION = "user_goals"

    DEFAULTS = {
        "target_weight_kg": None,
        "start_weight_kg": None,
        "goal_speed": "normal",
        "target_calories": None,
        "target_protein_g": None,
        "target_water_litres": 2.5,
        "target_steps": 8000,
        "target_sleep_hours": 7.5,
        "target_exercise_mins": 30,
        "target_bp_systolic": 130,
        "target_bp_diastolic": 80,
        "target_fasting_sugar": None,
        "primary_goal": "healthy_lifestyle",
        "goal_start_date": None,
        "goal_review_date": None,
    }

    def __init__(self, data=None, **kwargs):
        super().__init__(data, **kwargs)
        # Set defaults
        for key, value in self.DEFAULTS.items():
            if key not in self._data or self._data.get(key) is None:
                self._data[key] = value

    def get(self, key, default=None):
        """Get a field value from goals."""
        return self._data.get(key, default)


class UserSettings(FirestoreModel):
    COLLECTION = "user_settings"

    DEFAULTS = {
        "notifications_enabled": True,
        "email_notifications_enabled": True,
        "push_notifications_enabled": True,
        "medicine_reminders_enabled": True,
        "appointment_reminders_enabled": True,
        "water_reminders_enabled": True,
        "sleep_reminders_enabled": True,
        "exercise_reminders_enabled": True,
        "language": "en",
        "timezone": "Asia/Kolkata",
        "theme": "light",
    }


class UserSubscription(FirestoreModel):
    COLLECTION = "user_subscriptions"

    DEFAULTS = {
        "plan": "free",
        "status": "active",
        "start_date": None,
        "end_date": None,
        "auto_renew": False,
        "payment_status": "unpaid",
        "payment_method": None,
        "amount": 0.0,
        "currency": "INR",
    }


class TrustedContact(FirestoreModel):
    COLLECTION = "trusted_contacts"

    DEFAULTS = {
        "name": "",
        "relationship": "",
        "phone": "",
        "email": "",
        "is_primary": False,
        "can_view_health_data": False,
        "can_receive_alerts": False,
    }


class EmergencyCard(FirestoreModel):
    COLLECTION = "emergency_cards"

    DEFAULTS = {
        "blood_group": None,
        "allergies": [],
        "chronic_conditions": [],
        "medications": [],
        "emergency_contact_name": None,
        "emergency_contact_phone": None,
        "doctor_name": None,
        "doctor_phone": None,
        "insurance_provider": None,
        "insurance_number": None,
        "notes": None,
    }


# ---------------------------------------------------------------------------
# Health tracking
# ---------------------------------------------------------------------------

class HealthMetric(FirestoreModel):
    COLLECTION = "health_metrics"

    DEFAULTS = {
        "metric_type": "",
        "value1": None,
        "value2": None,
        "value3": None,
        "unit": "",
        "source": "manual",
        "notes": None,
        "recorded_at": None,
    }

    @property
    def bp_status(self):
        if self.metric_type != "bp":
            return None

        systolic = self.value1 or 0
        diastolic = self.value2 or 0

        if systolic < 120 and diastolic < 80:
            return "Normal"
        if systolic < 130 and diastolic < 80:
            return "Elevated"
        if systolic < 140 or diastolic < 90:
            return "High Stage 1"
        if systolic < 180 or diastolic < 120:
            return "High Stage 2"

        return "Crisis"

    @property
    def recorded_at_dt(self):
        """Return recorded_at as a Python datetime object for template usage."""
        recorded_at = self._data.get("recorded_at")
        if not recorded_at:
            return None
        if isinstance(recorded_at, datetime):
            return recorded_at
        if hasattr(recorded_at, 'to_datetime'):
            # Firestore Timestamp object
            return recorded_at.to_datetime()
        if isinstance(recorded_at, str):
            # ISO format string
            try:
                return datetime.fromisoformat(recorded_at.replace('Z', '+00:00'))
            except ValueError:
                pass
        return None

    def to_dict(self):
        data = super().to_dict()

        recorded_at = self._data.get("recorded_at")

        # Handle different timestamp formats from Firestore
        dt = None
        if isinstance(recorded_at, datetime):
            dt = recorded_at
        elif hasattr(recorded_at, 'to_datetime'):
            # Firestore Timestamp object
            dt = recorded_at.to_datetime()
        elif isinstance(recorded_at, str):
            # ISO format string
            try:
                dt = datetime.fromisoformat(recorded_at.replace('Z', '+00:00'))
            except ValueError:
                pass

        if dt:
            data["recorded_at"] = dt.isoformat()
            data["recorded_time"] = dt.strftime("%I:%M %p")
            data["recorded_date"] = dt.strftime("%d %b %Y")
            data["recorded_datetime_ist"] = dt.strftime(
                "%d %b %Y, %I:%M %p IST"
            )
        else:
            data["recorded_time"] = ""
            data["recorded_date"] = ""
            data["recorded_datetime_ist"] = ""

        data["bp_status"] = self.bp_status
        return data


class FamilyHealthMetric(FirestoreModel):
    COLLECTION = "family_health_metrics"

    DEFAULTS = {
        "metric_type": "",
        "value1": None,
        "value2": None,
        "value3": None,
        "unit": "",
        "source": "manual",
        "notes": None,
        "recorded_at": None,
    }


class HeartRateLog(FirestoreModel):
    COLLECTION = "heart_rate_logs"

    DEFAULTS = {
        "heart_rate": None,
        "resting_heart_rate": None,
        "source": "manual",
        "notes": None,
        "recorded_at": None,
    }


class SleepLog(FirestoreModel):
    COLLECTION = "sleep_logs"

    DEFAULTS = {
        "sleep_hours": 0.0,
        "sleep_quality": "good",
        "bed_time": None,
        "wake_time": None,
        "notes": None,
        "log_date": None,
    }


class StepLog(FirestoreModel):
    COLLECTION = "step_logs"

    DEFAULTS = {
        "steps": 0,
        "distance_km": 0.0,
        "calories_burned": 0.0,
        "source": "manual",
        "log_date": None,
    }


class ExerciseLog(FirestoreModel):
    COLLECTION = "exercise_logs"

    DEFAULTS = {
        "exercise_type": "walking",
        "duration_minutes": 0,
        "calories_burned": 0.0,
        "intensity": "moderate",
        "notes": None,
        "log_date": None,
        "recorded_at": None,
    }


class ExerciseLibrary(FirestoreModel):
    COLLECTION = "exercise_library"

    DEFAULTS = {
        "name": "",
        "category": "general",
        "description": "",
        "instructions": [],
        "duration_minutes": 10,
        "calories_burned": 0.0,
        "difficulty": "easy",
        "is_active": True,
        "image_url": None,
        "video_url": None,
    }


class HabitLog(FirestoreModel):
    COLLECTION = "habit_logs"

    DEFAULTS = {
        "habit_type": "",
        "status": "pending",
        "value": None,
        "notes": None,
        "log_date": None,
        "completed_at": None,
    }


class DailyHealthScore(FirestoreModel):
    COLLECTION = "daily_health_scores"

    DEFAULTS = {
        "health_score": 0.0,
        "nutrition_score": 0.0,
        "activity_score": 0.0,
        "sleep_score": 0.0,
        "hydration_score": 0.0,
        "medication_score": 0.0,
        "log_date": None,
    }


class WeeklyInsight(FirestoreModel):
    COLLECTION = "weekly_insights"

    DEFAULTS = {
        "week_start_date": None,
        "week_end_date": None,
        "insight_type": "general",
        "title": "",
        "message": "",
        "score": 0.0,
        "metrics": {},
        "recommendations": [],
    }


class HealthTimelineEvent(FirestoreModel):
    COLLECTION = "health_timeline_events"

    DEFAULTS = {
        "event_type": "general",
        "title": "",
        "description": "",
        "event_date": None,
        "related_id": None,
        "related_type": None,
        "severity": "info",
    }


# ---------------------------------------------------------------------------
# Conditions, labs and doctor visits
# ---------------------------------------------------------------------------

class HealthCondition(FirestoreModel):
    COLLECTION = "health_conditions"

    DEFAULTS = {
        "name": "",
        "icon": "",
        "category": "",
        "description": "",
        "is_active": True,
    }


class UserCondition(FirestoreModel):
    COLLECTION = "user_conditions"

    DEFAULTS = {
        "condition_id": "",
        "severity": "moderate",
        "diagnosed_at": None,
        "notes": None,
    }


class LabTest(FirestoreModel):
    COLLECTION = "lab_tests"

    DEFAULTS = {
        "test_name": "",
        "test_category": "general",
        "result_value": None,
        "result_unit": "",
        "reference_range": None,
        "status": "pending",
        "is_abnormal": False,
        "lab_name": None,
        "doctor_name": None,
        "test_date": None,
        "report_url": None,
        "notes": None,
    }


class DoctorVisit(FirestoreModel):
    COLLECTION = "doctor_visits"

    DEFAULTS = {
        "doctor_name": "",
        "specialty": "",
        "clinic_name": None,
        "visit_date": None,
        "reason": None,
        "diagnosis": None,
        "treatment": None,
        "notes": None,
        "next_visit_date": None,
    }


class Appointment(FirestoreModel):
    COLLECTION = "appointments"

    DEFAULTS = {
        "doctor_name": "",
        "specialty": "",
        "clinic_name": None,
        "appointment_date": None,
        "appointment_time": None,
        "appointment_type": "in_person",
        "status": "scheduled",
        "reason": None,
        "notes": None,
        "reminder_enabled": True,
        "reminder_minutes_before": 60,
    }


# ---------------------------------------------------------------------------
# Medicines and reminders
# ---------------------------------------------------------------------------

class Medicine(FirestoreModel):
    COLLECTION = "medicines"

    DEFAULTS = {
        "member_id": None,
        "name": "",
        "generic_name": None,
        "dosage": None,
        "medicine_type": "tablet",
        "with_food": "after_food",
        "condition_name": None,
        "prescribed_by": None,
        "notes": None,
        "schedule_type": "morning",
        "custom_times_json": "[]",
        "start_date": None,
        "end_date": None,
        "is_active": True,
        "is_discontinued": False,
        "stock_count": 0,
        "low_stock_threshold": 5,
        "auto_reduce_stock": True,
        "reminder_enabled": True,
        "snooze_minutes": 10,
        "max_reminders": 3,
        "reminder_sound": "medicine",
        "caregiver_alert": False,
    }

    PLAN_LIMITS = {
        "free": 2,
        "normal": 2,
        "premium": 10,
        "family": 20,
    }

    TYPES = {
        "tablet": "Tablet",
        "capsule": "Capsule",
        "syrup": "Syrup",
        "injection": "Injection",
        "drops": "Drops",
        "inhaler": "Inhaler",
        "ointment": "Ointment",
        "powder": "Powder",
        "other": "Other",
    }

    SCHEDULE_TIMES = {
        "morning": "08:00",
        "afternoon": "13:00",
        "evening": "18:00",
        "night": "21:30",
    }

    @property
    def custom_times(self):
        try:
            return json.loads(self._data.get("custom_times_json") or "[]")
        except Exception:
            return []

    @property
    def reminder_times(self):
        if self._data.get("schedule_type") == "custom":
            return self.custom_times

        schedule_type = self._data.get("schedule_type", "morning")
        return [self.SCHEDULE_TIMES.get(schedule_type, "08:00")]

    def to_dict(self):
        data = super().to_dict()
        data["type_label"] = self.TYPES.get(
            self._data.get("medicine_type", "tablet"),
            "Tablet",
        )
        data["custom_times"] = self.custom_times
        data["reminder_times"] = self.reminder_times

        stock_count = self._data.get("stock_count", 0)
        threshold = self._data.get("low_stock_threshold", 5)

        data["low_stock_alert"] = stock_count <= threshold
        return data


class FamilyMedicine(FirestoreModel):
    COLLECTION = "family_medicines"

    DEFAULTS = {
        "member_id": None,
        "name": "",
        "generic_name": None,
        "dosage": None,
        "medicine_type": "tablet",
        "with_food": "after_food",
        "condition_name": None,
        "prescribed_by": None,
        "notes": None,
        "schedule_type": "morning",
        "custom_times_json": "[]",
        "start_date": None,
        "end_date": None,
        "is_active": True,
        "is_discontinued": False,
        "stock_count": 0,
        "low_stock_threshold": 5,
        "reminder_enabled": True,
    }


class MedicineLog(FirestoreModel):
    COLLECTION = "medicine_logs"

    DEFAULTS = {
        "medicine_id": "",
        "log_date": None,
        "status": "pending",
        "taken": False,
        "scheduled_time": None,
        "logged_at": None,
        "photo_path": None,
        "ai_verified": False,
        "ai_result": None,
        "reminder_count": 0,
        "notes": None,
    }

    STATUS_EMOJI = {
        "pending": "🟡",
        "taken": "🔵",
        "ai_verified": "🟢",
        "missed": "🔴",
        "skipped": "⚪",
    }

    def to_dict(self):
        data = super().to_dict()
        status = self._data.get("status", "pending")
        data["status_emoji"] = self.STATUS_EMOJI.get(status, "🟡")
        return data


class Reminder(FirestoreModel):
    COLLECTION = "reminders"

    DEFAULTS = {
        "reminder_type": "general",
        "title": "",
        "message": "",
        "reminder_date": None,
        "reminder_time": None,
        "repeat_type": "none",
        "status": "pending",
        "is_completed": False,
        "completed_at": None,
        "related_id": None,
        "related_type": None,
    }


# ---------------------------------------------------------------------------
# Alerts and notifications
# ---------------------------------------------------------------------------

class Alert(FirestoreModel):
    COLLECTION = "alerts"

    DEFAULTS = {
        "alert_type": "",
        "category": "",
        "title": "",
        "message": "",
        "action_text": None,
        "action_url": None,
        "trigger_value": None,
        "is_read": False,
        "is_dismissed": False,
        "expires_at": None,
    }


class Notification(FirestoreModel):
    COLLECTION = "notifications"

    DEFAULTS = {
        "notification_type": "general",
        "title": "",
        "message": "",
        "category": "general",
        "action_text": None,
        "action_url": None,
        "is_read": False,
        "read_at": None,
        "is_dismissed": False,
        "expires_at": None,
    }


class AdminLog(FirestoreModel):
    COLLECTION = "admin_logs"

    DEFAULTS = {
        "action": "",
        "actor_id": None,
        "actor_email": None,
        "target_type": None,
        "target_id": None,
        "details": {},
        "ip_address": None,
        "user_agent": None,
    }


# ---------------------------------------------------------------------------
# Family
# ---------------------------------------------------------------------------

class FamilyMember(FirestoreModel):
    COLLECTION = "family_members"

    DEFAULTS = {
        "name": "",
        "relationship": "",
        "date_of_birth": None,
        "gender": None,
        "blood_group": None,
        "phone": None,
        "email": None,
        "profile_photo": None,
        "is_active": True,
        "health_profile": {},
    }


class FamilyDocument(FirestoreModel):
    COLLECTION = "family_documents"

    DEFAULTS = {
        "member_id": None,
        "title": "",
        "document_type": "other",
        "file_name": "",
        "file_url": None,
        "file_path": None,
        "file_size": 0,
        "mime_type": "",
        "notes": None,
        "issue_date": None,
        "expiry_date": None,
        "is_verified": False,
        "is_archived": False,
    }


# ---------------------------------------------------------------------------
# Documents
# ---------------------------------------------------------------------------

class Document(FirestoreModel):
    COLLECTION = "documents"

    DEFAULTS = {
        "member_id": None,
        "title": "",
        "document_type": "other",
        "file_name": "",
        "file_url": None,
        "file_path": None,
        "file_size": 0,
        "mime_type": "",
        "notes": None,
        "issue_date": None,
        "expiry_date": None,
        "is_verified": False,
        "is_archived": False,
    }

    DOCUMENT_TYPES = {
        "prescription": "Prescription",
        "lab_report": "Lab Report",
        "scan": "Scan / Imaging",
        "discharge_summary": "Discharge Summary",
        "insurance": "Insurance Document",
        "vaccination": "Vaccination Record",
        "other": "Other",
    }

    @property
    def type_label(self):
        return self.DOCUMENT_TYPES.get(
            self._data.get("document_type", "other"),
            "Other",
        )

    def to_dict(self):
        data = super().to_dict()
        data["type_label"] = self.type_label
        return data


# ---------------------------------------------------------------------------
# Nutrition and meals
# ---------------------------------------------------------------------------

class Recipe(FirestoreModel):
    COLLECTION = "recipes"

    DEFAULTS = {
        "name": "",
        "description": "",
        "image": None,
        "category": None,
        "meal_type": None,
        "cooking_time": "20 mins",
        "servings": 1,
        "difficulty": "easy",
        "is_veg": True,
        "ingredients": [],
        "steps": [],
        "tags": [],
        "health_benefits": [],
        "calories": 0,
        "protein": 0,
        "carbs": 0,
        "fats": 0,
        "fiber": 0,
        "sugar": 0,
        "sodium": 0,
        "potassium": 0,
        "cholesterol": 0,
        "bp_friendly": True,
        "diabetes_friendly": True,
        "weight_loss_friendly": True,
        "heart_friendly": True,
        "high_protein": False,
        "high_fiber": False,
        "low_sodium": True,
        "bp_score": 0.0,
        "diabetes_score": 0.0,
        "weight_loss_score": 0.0,
        "nutrition_score": 0.0,
    }


class MealPlan(FirestoreModel):
    COLLECTION = "meal_plans"

    DEFAULTS = {
        "week_start_date": None,
        "generated_at": None,
        "is_active": True,
        "notes": None,
    }


class MealItem(FirestoreModel):
    COLLECTION = "meal_items"

    DEFAULTS = {
        "plan_id": "",
        "recipe_id": "",
        "day": None,
        "meal_slot": None,
        "slot_order": 0,
        "completed": False,
        "completed_at": None,
        "locked": False,
        "note": None,
    }


class Favorite(FirestoreModel):
    COLLECTION = "favorites"

    DEFAULTS = {
        "recipe_id": "",
        "saved_at": None,
    }


class GroceryItem(FirestoreModel):
    COLLECTION = "grocery_items"

    DEFAULTS = {
        "week_start": None,
        "ingredient_name": "",
        "category": "Other",
        "quantity": None,
        "purchased": False,
        "purchased_at": None,
    }


class NutritionDailyLog(FirestoreModel):
    COLLECTION = "nutrition_daily_logs"

    DEFAULTS = {
        "log_date": None,
        "total_calories": 0,
        "total_protein": 0,
        "total_carbs": 0,
        "total_fats": 0,
        "total_fiber": 0,
        "total_sodium": 0,
        "total_potassium": 0,
        "total_water": 0,
        "meals_completed": 0,
        "meals_planned": 5,
        "health_score": 0,
    }


# ---------------------------------------------------------------------------
# Email reports
# ---------------------------------------------------------------------------

class EmailReportConfig(FirestoreModel):
    COLLECTION = "email_report_configs"

    DEFAULTS = {
        "is_enabled": False,
        "frequency": "weekly",
        "custom_days": 7,
        "send_time": "08:00",
        "report_period_days": 7,
        "email_recipients": "",
        "include_weight": False,
        "include_bp": False,
        "include_water": False,
        "include_sleep": False,
        "include_steps": False,
        "include_exercise": False,
        "include_sugar": False,
        "include_suggestions": False,
        "include_achievements": False,
        "next_send_at": None,
    }


class EmailReportLog(FirestoreModel):
    COLLECTION = "email_report_logs"

    DEFAULTS = {
        "status": "sent",
        "recipients": "",
        "report_period_days": 7,
        "error_message": None,
        "sent_at": None,
    }