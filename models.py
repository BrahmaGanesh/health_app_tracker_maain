# ============================================================
# HEALTH TRACKER PLATFORM — FINAL COMPLETE VERSION
# models.py — All Database Models (Website + APK Shared)
# ============================================================

from datetime import datetime, date, timezone, timedelta
from flask_login import UserMixin
from extensions import db, bcrypt
import json

# ============================================================
# LIVE TIME (IST)
# ============================================================

IST = timezone(timedelta(hours=5, minutes=30))

def now_ist():
    """Current live datetime (timezone-aware, IST)."""
    return datetime.now(IST)

def today_ist():
    """Current live date (IST)."""
    return now_ist().date()


# ============================================================
# USER & AUTH
# ============================================================

class User(UserMixin, db.Model):
    __tablename__ = "users"

    id                   = db.Column(db.Integer, primary_key=True)
    name                 = db.Column(db.String(120), nullable=False)
    email                = db.Column(db.String(180), unique=True, nullable=False, index=True)
    password_hash        = db.Column(db.String(255), nullable=False)
    is_active            = db.Column(db.Boolean, default=True)
    is_verified          = db.Column(db.Boolean, default=False)
    is_admin             = db.Column(db.Boolean, default=False)
    onboarding_done      = db.Column(db.Boolean, default=False)
    dark_mode            = db.Column(db.Boolean, default=False)
    profile_photo        = db.Column(db.String(500), nullable=True)

    verification_token   = db.Column(db.String(200), nullable=True)
    reset_token          = db.Column(db.String(200), nullable=True)
    reset_token_expiry   = db.Column(db.DateTime, nullable=True)

    fcm_token            = db.Column(db.String(500), nullable=True)
    web_push_sub         = db.Column(db.Text, nullable=True)

    google_id            = db.Column(db.String(200), nullable=True, index=True)
    google_email         = db.Column(db.String(200), nullable=True)
    google_access_token  = db.Column(db.Text, nullable=True)
    google_refresh_token = db.Column(db.Text, nullable=True)
    auth_provider        = db.Column(db.String(20), default="email")

    created_at           = db.Column(db.DateTime, default=now_ist)
    last_login           = db.Column(db.DateTime, nullable=True)
    last_updated         = db.Column(db.DateTime, default=now_ist, onupdate=now_ist)

    health_profile       = db.relationship("UserHealthProfile", backref="user", uselist=False, cascade="all, delete-orphan")
    conditions           = db.relationship("UserCondition", backref="user", cascade="all, delete-orphan")
    goals                = db.relationship("UserGoal", backref="user", uselist=False, cascade="all, delete-orphan")
    health_metrics       = db.relationship("HealthMetric", backref="user", cascade="all, delete-orphan", lazy="dynamic")
    meal_plans           = db.relationship("MealPlan", backref="user", cascade="all, delete-orphan", lazy="dynamic")
    favorites            = db.relationship("Favorite", backref="user", cascade="all, delete-orphan")
    grocery_items        = db.relationship("GroceryItem", backref="user", cascade="all, delete-orphan", lazy="dynamic")
    alerts               = db.relationship("Alert", backref="user", cascade="all, delete-orphan", lazy="dynamic")
    medicines            = db.relationship("Medicine", backref="user", cascade="all, delete-orphan")
    nutrition_logs       = db.relationship("NutritionDailyLog", backref="user", cascade="all, delete-orphan", lazy="dynamic")
    weekly_insights      = db.relationship("WeeklyInsight", backref="user", cascade="all, delete-orphan", lazy="dynamic")
    family_members       = db.relationship("FamilyMember", backref="owner", cascade="all, delete-orphan")
    sleep_logs           = db.relationship("SleepLog", backref="user", cascade="all, delete-orphan", lazy="dynamic")
    exercise_logs        = db.relationship("ExerciseLog", backref="user", cascade="all, delete-orphan", lazy="dynamic")
    step_logs            = db.relationship("StepLog", backref="user", cascade="all, delete-orphan", lazy="dynamic")
    heart_rate_logs      = db.relationship("HeartRateLog", backref="user", cascade="all, delete-orphan", lazy="dynamic")
    habit_logs           = db.relationship("HabitLog", backref="user", cascade="all, delete-orphan", lazy="dynamic")
    documents            = db.relationship("Document", backref="user", cascade="all, delete-orphan", lazy="dynamic")
    email_report_config  = db.relationship("EmailReportConfig", backref="user", uselist=False, cascade="all, delete-orphan")
    notifications        = db.relationship("Notification", backref="user", cascade="all, delete-orphan", lazy="dynamic")
    reminders            = db.relationship("Reminder", backref="user", cascade="all, delete-orphan")
    backups              = db.relationship("Backup", backref="user", cascade="all, delete-orphan", lazy="dynamic")
    health_scores        = db.relationship("DailyHealthScore", backref="user", cascade="all, delete-orphan", lazy="dynamic")

    def set_password(self, password):
        self.password_hash = bcrypt.generate_password_hash(password).decode("utf-8")

    def check_password(self, password):
        return bcrypt.check_password_hash(self.password_hash, password)

    @property
    def bmi(self):
        if not self.health_profile:
            return None
        h = self.health_profile.height_cm
        w = self.health_profile.current_weight_kg
        if not h or not w:
            return None
        return round(w / ((h / 100) ** 2), 1)

    @property
    def bmi_status(self):
        b = self.bmi
        if b is None:
            return "Unknown"
        if b < 18.5:
            return "Underweight"
        elif b < 25:
            return "Normal"
        elif b < 30:
            return "Overweight"
        elif b < 35:
            return "Obese I"
        elif b < 40:
            return "Obese II"
        return "Obese III"

    @property
    def age(self):
        if not self.health_profile or not self.health_profile.date_of_birth:
            return None
        t = today_ist()
        d = self.health_profile.date_of_birth
        return t.year - d.year - ((t.month, t.day) < (d.month, d.day))

    @property
    def daily_calorie_target(self):
        p = self.health_profile
        if not p:
            return 2000
        w = p.current_weight_kg or 70
        h = p.height_cm or 170
        a = self.age or 30
        g = p.gender or "female"
        bmr = (10 * w + 6.25 * h - 5 * a + 5) if g == "male" else (10 * w + 6.25 * h - 5 * a - 161)
        fm = {"sedentary": 1.2, "light": 1.375, "moderate": 1.55, "active": 1.725, "very_active": 1.9}
        tdee = bmr * fm.get(p.activity_level or "sedentary", 1.2)
        gl = self.goals
        if gl:
            if gl.primary_goal == "weight_loss":
                sm = {"slow": 250, "normal": 500, "fast": 750}
                return max(1200, int(tdee - sm.get(gl.goal_speed or "normal", 500)))
            elif gl.primary_goal == "weight_gain":
                return int(tdee + 400)
        return int(tdee)

    @property
    def daily_protein_target(self):
        if not self.health_profile:
            return 80
        w = self.health_profile.current_weight_kg or 70
        if "High Blood Pressure" in self.condition_names:
            return int(w * 1.0)
        if any("Weight Loss" in n for n in self.condition_names):
            return int(w * 1.4)
        return int(w * 1.0)

    @property
    def condition_names(self):
        return [uc.condition.name for uc in self.conditions]

    @property
    def has_bp(self):
        return "High Blood Pressure" in self.condition_names

    @property
    def has_diabetes(self):
        return any("Diabetes" in n for n in self.condition_names)

    @property
    def has_weight_loss(self):
        return any("Weight Loss" in n for n in self.condition_names)

    def to_dict(self):
        return {
            "id": self.id,
            "name": self.name,
            "email": self.email,
            "is_verified": self.is_verified,
            "dark_mode": self.dark_mode,
            "profile_photo": self.profile_photo,
            "bmi": self.bmi,
            "bmi_status": self.bmi_status,
            "age": self.age,
            "daily_calorie_target": self.daily_calorie_target,
            "daily_protein_target": self.daily_protein_target,
            "conditions": self.condition_names,
            "onboarding_done": self.onboarding_done,
            "auth_provider": self.auth_provider,
            "google_email": self.google_email,
        }


# ============================================================
# HEALTH PROFILE
# ============================================================

class UserHealthProfile(db.Model):
    __tablename__ = "user_health_profiles"

    id                = db.Column(db.Integer, primary_key=True)
    user_id           = db.Column(db.Integer, db.ForeignKey("users.id"), unique=True, nullable=False)
    gender            = db.Column(db.String(20), nullable=True)
    date_of_birth     = db.Column(db.Date, nullable=True)
    height_cm         = db.Column(db.Float, nullable=True)
    current_weight_kg = db.Column(db.Float, nullable=True)
    activity_level    = db.Column(db.String(30), default="sedentary")
    diet_preference   = db.Column(db.String(30), default="vegetarian")
    onboarding_step   = db.Column(db.Integer, default=1)
    blood_group       = db.Column(db.String(10), nullable=True)
    emergency_contact = db.Column(db.String(200), nullable=True)
    created_at        = db.Column(db.DateTime, default=now_ist)
    updated_at        = db.Column(db.DateTime, default=now_ist, onupdate=now_ist)

    def to_dict(self):
        return {
            "gender": self.gender,
            "date_of_birth": str(self.date_of_birth) if self.date_of_birth else None,
            "height_cm": self.height_cm,
            "current_weight_kg": self.current_weight_kg,
            "activity_level": self.activity_level,
            "diet_preference": self.diet_preference,
            "blood_group": self.blood_group,
            "emergency_contact": self.emergency_contact,
        }


class HealthCondition(db.Model):
    __tablename__ = "health_conditions"

    id          = db.Column(db.Integer, primary_key=True)
    name        = db.Column(db.String(100), unique=True, nullable=False)
    description = db.Column(db.Text, nullable=True)
    icon        = db.Column(db.String(10), default="🏥")
    category    = db.Column(db.String(50), nullable=True)

    users       = db.relationship("UserCondition", backref="condition", cascade="all, delete-orphan")


class UserCondition(db.Model):
    __tablename__ = "user_conditions"

    id             = db.Column(db.Integer, primary_key=True)
    user_id        = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    condition_id   = db.Column(db.Integer, db.ForeignKey("health_conditions.id"), nullable=False)
    severity       = db.Column(db.String(20), default="moderate")
    diagnosed_at   = db.Column(db.Date, nullable=True)
    notes          = db.Column(db.Text, nullable=True)
    created_at     = db.Column(db.DateTime, default=now_ist)

    __table_args__ = (db.UniqueConstraint("user_id", "condition_id"),)


class UserGoal(db.Model):
    __tablename__ = "user_goals"

    id                   = db.Column(db.Integer, primary_key=True)
    user_id              = db.Column(db.Integer, db.ForeignKey("users.id"), unique=True, nullable=False)
    target_weight_kg     = db.Column(db.Float, nullable=True)
    start_weight_kg      = db.Column(db.Float, nullable=True)
    goal_speed           = db.Column(db.String(20), default="normal")
    target_calories      = db.Column(db.Integer, nullable=True)
    target_protein_g     = db.Column(db.Integer, nullable=True)
    target_water_litres  = db.Column(db.Float, default=2.5)
    target_steps         = db.Column(db.Integer, default=8000)
    target_sleep_hours   = db.Column(db.Float, default=7.5)
    target_exercise_mins = db.Column(db.Integer, default=30)
    target_bp_systolic   = db.Column(db.Integer, default=130)
    target_bp_diastolic  = db.Column(db.Integer, default=80)
    target_fasting_sugar = db.Column(db.Float, nullable=True)
    primary_goal         = db.Column(db.String(50), default="healthy_lifestyle")
    goal_start_date      = db.Column(db.Date, default=today_ist)
    goal_review_date     = db.Column(db.Date, nullable=True)
    created_at           = db.Column(db.DateTime, default=now_ist)
    updated_at           = db.Column(db.DateTime, default=now_ist, onupdate=now_ist)

    def to_dict(self):
        return {
            "target_weight_kg": self.target_weight_kg,
            "start_weight_kg": self.start_weight_kg,
            "goal_speed": self.goal_speed,
            "target_water_litres": self.target_water_litres,
            "target_steps": self.target_steps,
            "target_sleep_hours": self.target_sleep_hours,
            "target_exercise_mins": self.target_exercise_mins,
            "target_bp_systolic": self.target_bp_systolic,
            "target_bp_diastolic": self.target_bp_diastolic,
            "primary_goal": self.primary_goal,
        }


# ============================================================
# HEALTH METRICS — UNIFIED TRACKER
# ============================================================

class HealthMetric(db.Model):
    __tablename__ = "health_metrics"

    id          = db.Column(db.Integer, primary_key=True)
    user_id     = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    metric_type = db.Column(db.String(30), nullable=False, index=True)
    value_1     = db.Column(db.Float, nullable=True)
    value_2     = db.Column(db.Float, nullable=True)
    value_3     = db.Column(db.Float, nullable=True)
    unit        = db.Column(db.String(20), nullable=True)
    source      = db.Column(db.String(20), default="manual")
    notes       = db.Column(db.Text, nullable=True)
    recorded_at = db.Column(db.DateTime, default=now_ist, index=True)

    @property
    def bp_status(self):
        if self.metric_type != "bp":
            return None
        s, d = self.value_1 or 0, self.value_2 or 0
        if s < 120 and d < 80:
            return "Normal"
        elif s < 130 and d < 80:
            return "Elevated"
        elif s < 140 or d < 90:
            return "High Stage 1"
        elif s < 180 or d < 120:
            return "High Stage 2"
        return "Crisis"

    def to_dict(self):
        return {
            "id": self.id,
            "metric_type": self.metric_type,
            "value_1": self.value_1,
            "value_2": self.value_2,
            "value_3": self.value_3,
            "unit": self.unit,
            "notes": self.notes,
            "recorded_at": self.recorded_at.isoformat(),
            "recorded_time": self.recorded_at.strftime("%I:%M %p"),
            "recorded_date": self.recorded_at.strftime("%d %b %Y"),
        }


# ============================================================
# SLEEP TRACKING
# ============================================================

class SleepLog(db.Model):
    __tablename__ = "sleep_logs"

    id              = db.Column(db.Integer, primary_key=True)
    user_id         = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    log_date        = db.Column(db.Date, default=today_ist, index=True)
    sleep_time      = db.Column(db.String(10), nullable=True)
    wake_time       = db.Column(db.String(10), nullable=True)
    duration_hours  = db.Column(db.Float, nullable=True)
    quality         = db.Column(db.Integer, nullable=True)
    deep_sleep_hrs  = db.Column(db.Float, nullable=True)
    interruptions   = db.Column(db.Integer, default=0)
    mood_on_wake    = db.Column(db.String(20), nullable=True)
    notes           = db.Column(db.Text, nullable=True)
    recorded_at     = db.Column(db.DateTime, default=now_ist, onupdate=now_ist)

    __table_args__  = (db.UniqueConstraint("user_id", "log_date"),)

    @property
    def quality_label(self):
        return {1: "Very Poor", 2: "Poor", 3: "Fair", 4: "Good", 5: "Excellent"}.get(self.quality, "Not rated")

    def to_dict(self):
        return {
            "id": self.id,
            "log_date": str(self.log_date),
            "sleep_time": self.sleep_time,
            "wake_time": self.wake_time,
            "duration_hours": self.duration_hours,
            "quality": self.quality,
            "quality_label": self.quality_label,
            "mood_on_wake": self.mood_on_wake,
            "interruptions": self.interruptions,
            "notes": self.notes,
        }


# ============================================================
# EXERCISE & STEPS
# ============================================================

class ExerciseLog(db.Model):
    __tablename__ = "exercise_logs"

    id               = db.Column(db.Integer, primary_key=True)
    user_id          = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    log_date         = db.Column(db.Date, default=today_ist, index=True)
    exercise_name    = db.Column(db.String(200), nullable=False)
    exercise_type    = db.Column(db.String(30), nullable=True)
    duration_minutes = db.Column(db.Integer, nullable=True)
    calories_burned  = db.Column(db.Integer, nullable=True)
    sets             = db.Column(db.Integer, nullable=True)
    reps             = db.Column(db.Integer, nullable=True)
    weight_used_kg   = db.Column(db.Float, nullable=True)
    distance_km      = db.Column(db.Float, nullable=True)
    avg_heart_rate   = db.Column(db.Integer, nullable=True)
    intensity        = db.Column(db.String(20), default="moderate")
    notes            = db.Column(db.Text, nullable=True)
    recorded_at      = db.Column(db.DateTime, default=now_ist, onupdate=now_ist)

    def to_dict(self):
        return {
            "id": self.id,
            "log_date": str(self.log_date),
            "exercise_name": self.exercise_name,
            "exercise_type": self.exercise_type,
            "duration_minutes": self.duration_minutes,
            "calories_burned": self.calories_burned,
            "sets": self.sets,
            "reps": self.reps,
            "distance_km": self.distance_km,
            "intensity": self.intensity,
            "recorded_at": self.recorded_at.isoformat(),
        }


class StepLog(db.Model):
    __tablename__ = "step_logs"

    id              = db.Column(db.Integer, primary_key=True)
    user_id         = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    log_date        = db.Column(db.Date, default=today_ist, index=True)
    steps           = db.Column(db.Integer, default=0)
    distance_km     = db.Column(db.Float, nullable=True)
    calories_burned = db.Column(db.Integer, nullable=True)
    goal_steps      = db.Column(db.Integer, default=8000)
    goal_achieved   = db.Column(db.Boolean, default=False)
    recorded_at     = db.Column(db.DateTime, default=now_ist, onupdate=now_ist)

    __table_args__  = (db.UniqueConstraint("user_id", "log_date"),)

    def compute_calories(self, weight_kg=70):
        if not self.steps:
            return 0
        return int((self.steps / 100) * (3.5 * weight_kg * 3.5 / 200))

    def compute_distance(self, height_cm=170):
        if not self.steps:
            return 0
        return round(self.steps * (height_cm * 0.414 / 100) / 1000, 2)

    def to_dict(self):
        return {
            "id": self.id,
            "log_date": str(self.log_date),
            "steps": self.steps,
            "distance_km": self.distance_km,
            "calories_burned": self.calories_burned,
            "goal_steps": self.goal_steps,
            "goal_achieved": self.goal_achieved,
        }


class HeartRateLog(db.Model):
    __tablename__ = "heart_rate_logs"

    id           = db.Column(db.Integer, primary_key=True)
    user_id      = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    bpm          = db.Column(db.Integer, nullable=False)
    reading_type = db.Column(db.String(20), default="resting")
    log_date     = db.Column(db.Date, default=today_ist)
    notes        = db.Column(db.Text, nullable=True)
    recorded_at  = db.Column(db.DateTime, default=now_ist, onupdate=now_ist)

    def to_dict(self):
        return {
            "id": self.id,
            "bpm": self.bpm,
            "reading_type": self.reading_type,
            "log_date": str(self.log_date),
            "recorded_at": self.recorded_at.isoformat(),
        }


class HabitLog(db.Model):
    __tablename__ = "habit_logs"

    id           = db.Column(db.Integer, primary_key=True)
    user_id      = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    habit_name   = db.Column(db.String(100), nullable=False)
    category     = db.Column(db.String(40), nullable=True)
    log_date     = db.Column(db.Date, default=today_ist, index=True)
    completed    = db.Column(db.Boolean, default=False)
    streak       = db.Column(db.Integer, default=0)
    target_value = db.Column(db.Float, nullable=True)
    actual_value = db.Column(db.Float, nullable=True)
    unit         = db.Column(db.String(20), nullable=True)
    notes        = db.Column(db.Text, nullable=True)
    created_at   = db.Column(db.DateTime, default=now_ist, onupdate=now_ist)


# ============================================================
# EXERCISE LIBRARY
# ============================================================

class ExerciseLibrary(db.Model):
    __tablename__ = "exercise_library"

    id               = db.Column(db.Integer, primary_key=True)
    name             = db.Column(db.String(200), nullable=False, index=True)
    category         = db.Column(db.String(50), nullable=True)
    muscle_group     = db.Column(db.String(100), nullable=True)
    difficulty       = db.Column(db.String(20), default="beginner")
    description      = db.Column(db.Text, nullable=True)
    instructions     = db.Column(db.Text, nullable=True)
    benefits         = db.Column(db.Text, nullable=True)
    image_url        = db.Column(db.String(500), nullable=True)
    duration_mins    = db.Column(db.Integer, nullable=True)
    calories_per_min = db.Column(db.Float, nullable=True)
    bp_safe          = db.Column(db.Boolean, default=True)
    diabetes_safe    = db.Column(db.Boolean, default=True)
    heart_safe       = db.Column(db.Boolean, default=True)
    beginner_safe    = db.Column(db.Boolean, default=True)
    equipment        = db.Column(db.String(100), nullable=True)
    is_featured      = db.Column(db.Boolean, default=False)
    created_at       = db.Column(db.DateTime, default=now_ist)

    def to_dict(self):
        return {
            "id": self.id,
            "name": self.name,
            "category": self.category,
            "muscle_group": self.muscle_group,
            "difficulty": self.difficulty,
            "description": self.description,
            "instructions": self.instructions,
            "benefits": self.benefits,
            "image_url": self.image_url,
            "duration_mins": self.duration_mins,
            "calories_per_min": self.calories_per_min,
            "bp_safe": self.bp_safe,
            "equipment": self.equipment,
            "is_featured": self.is_featured,
        }


# ============================================================
# FAMILY SYSTEM
# ============================================================

class FamilyMember(db.Model):
    __tablename__ = "family_members"

    id                  = db.Column(db.Integer, primary_key=True)
    owner_id            = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    name                = db.Column(db.String(120), nullable=False)
    relation            = db.Column(db.String(50), nullable=True)
    gender              = db.Column(db.String(20), nullable=True)
    date_of_birth       = db.Column(db.Date, nullable=True)
    height_cm           = db.Column(db.Float, nullable=True)
    current_weight_kg   = db.Column(db.Float, nullable=True)
    profile_photo       = db.Column(db.String(500), nullable=True)
    conditions_json     = db.Column(db.Text, default="[]")
    target_weight_kg    = db.Column(db.Float, nullable=True)
    target_bp_systolic  = db.Column(db.Integer, default=130)
    target_bp_diastolic = db.Column(db.Integer, default=80)
    target_water_litres = db.Column(db.Float, default=2.5)
    target_steps        = db.Column(db.Integer, default=8000)
    blood_group         = db.Column(db.String(10), nullable=True)
    emergency_contact   = db.Column(db.String(200), nullable=True)
    notes               = db.Column(db.Text, nullable=True)
    is_active           = db.Column(db.Boolean, default=True)
    created_at          = db.Column(db.DateTime, default=now_ist)

    health_metrics      = db.relationship("FamilyHealthMetric", backref="member", cascade="all, delete-orphan", lazy="dynamic")
    medicines           = db.relationship("FamilyMedicine", backref="member", cascade="all, delete-orphan")
    documents           = db.relationship("FamilyDocument", backref="member", cascade="all, delete-orphan", lazy="dynamic")

    @property
    def conditions(self):
        try:
            return json.loads(self.conditions_json or "[]")
        except Exception:
            return []

    @property
    def age(self):
        if not self.date_of_birth:
            return None
        t = today_ist()
        return t.year - self.date_of_birth.year - ((t.month, t.day) < (self.date_of_birth.month, self.date_of_birth.day))

    @property
    def bmi(self):
        if not self.height_cm or not self.current_weight_kg:
            return None
        return round(self.current_weight_kg / ((self.height_cm / 100) ** 2), 1)

    def to_dict(self):
        return {
            "id": self.id,
            "name": self.name,
            "relation": self.relation,
            "gender": self.gender,
            "age": self.age,
            "bmi": self.bmi,
            "height_cm": self.height_cm,
            "current_weight_kg": self.current_weight_kg,
            "blood_group": self.blood_group,
            "conditions": self.conditions,
            "profile_photo": self.profile_photo,
        }


class FamilyHealthMetric(db.Model):
    __tablename__ = "family_health_metrics"

    id          = db.Column(db.Integer, primary_key=True)
    member_id   = db.Column(db.Integer, db.ForeignKey("family_members.id"), nullable=False, index=True)
    metric_type = db.Column(db.String(30), nullable=False)
    value_1     = db.Column(db.Float, nullable=True)
    value_2     = db.Column(db.Float, nullable=True)
    value_3     = db.Column(db.Float, nullable=True)
    unit        = db.Column(db.String(20), nullable=True)
    notes       = db.Column(db.Text, nullable=True)
    recorded_at = db.Column(db.DateTime, default=now_ist, index=True)

    def to_dict(self):
        return {
            "id": self.id,
            "metric_type": self.metric_type,
            "value_1": self.value_1,
            "value_2": self.value_2,
            "recorded_at": self.recorded_at.isoformat(),
            "recorded_time": self.recorded_at.strftime("%I:%M %p"),
        }


class FamilyMedicine(db.Model):
    __tablename__ = "family_medicines"

    id         = db.Column(db.Integer, primary_key=True)
    member_id  = db.Column(db.Integer, db.ForeignKey("family_members.id"), nullable=False)
    name       = db.Column(db.String(200), nullable=False)
    dosage     = db.Column(db.String(100), nullable=True)
    timing     = db.Column(db.String(20), nullable=True)
    frequency  = db.Column(db.String(30), default="daily")
    active     = db.Column(db.Boolean, default=True)
    created_at = db.Column(db.DateTime, default=now_ist)


class FamilyDocument(db.Model):
    __tablename__ = "family_documents"

    id          = db.Column(db.Integer, primary_key=True)
    member_id   = db.Column(db.Integer, db.ForeignKey("family_members.id"), nullable=False)
    title       = db.Column(db.String(200), nullable=False)
    doc_type    = db.Column(db.String(50), nullable=True)
    file_path   = db.Column(db.String(500), nullable=True)
    uploaded_at = db.Column(db.DateTime, default=now_ist)


# ============================================================
# REMINDER SYSTEM
# ============================================================

class Reminder(db.Model):
    __tablename__ = "reminders"

    id                   = db.Column(db.Integer, primary_key=True)
    user_id              = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    title                = db.Column(db.String(200), nullable=False)
    message              = db.Column(db.Text, nullable=False)
    category             = db.Column(db.String(30), nullable=True)
    remind_time          = db.Column(db.String(10), nullable=True)
    is_daily             = db.Column(db.Boolean, default=True)
    active_days          = db.Column(db.String(50), default="1,2,3,4,5,6,7")
    repeat_interval_mins = db.Column(db.Integer, default=5)
    max_repeats          = db.Column(db.Integer, default=10)
    sound_enabled        = db.Column(db.Boolean, default=True)
    sound_name           = db.Column(db.String(50), default="health_alert")
    is_active            = db.Column(db.Boolean, default=True)
    last_triggered_at    = db.Column(db.DateTime, nullable=True)
    is_done_today        = db.Column(db.Boolean, default=False)
    done_reset_date      = db.Column(db.Date, nullable=True)
    repeat_count_today   = db.Column(db.Integer, default=0)
    created_at           = db.Column(db.DateTime, default=now_ist, onupdate=now_ist)
    updated_at           = db.Column(db.DateTime, default=now_ist, onupdate=now_ist)

    def reset_daily(self):
        today = today_ist()
        if self.done_reset_date != today:
            self.is_done_today = False
            self.repeat_count_today = 0
            self.done_reset_date = today

    def to_dict(self):
        return {
            "id": self.id,
            "title": self.title,
            "message": self.message,
            "category": self.category,
            "remind_time": self.remind_time,
            "repeat_interval_mins": self.repeat_interval_mins,
            "sound_enabled": self.sound_enabled,
            "sound_name": self.sound_name,
            "is_active": self.is_active,
            "is_done_today": self.is_done_today,
            "is_daily": self.is_daily,
        }


# ============================================================
# NOTIFICATION SYSTEM
# ============================================================

class Notification(db.Model):
    __tablename__ = "notifications"

    id            = db.Column(db.Integer, primary_key=True)
    user_id       = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    notif_type    = db.Column(db.String(30), nullable=False)
    category      = db.Column(db.String(30), nullable=True)
    title         = db.Column(db.String(200), nullable=False)
    message       = db.Column(db.Text, nullable=False)
    icon          = db.Column(db.String(10), default="🔔")
    sound         = db.Column(db.String(50), default="health_alert")
    action_url    = db.Column(db.String(200), nullable=True)
    is_read       = db.Column(db.Boolean, default=False)
    delivered_via = db.Column(db.String(20), default="inapp")
    reminder_id   = db.Column(db.Integer, db.ForeignKey("reminders.id"), nullable=True)
    scheduled_for = db.Column(db.DateTime, nullable=True)
    created_at    = db.Column(db.DateTime, default=now_ist, index=True)

    def to_dict(self):
        return {
            "id": self.id,
            "notif_type": self.notif_type,
            "category": self.category,
            "title": self.title,
            "message": self.message,
            "icon": self.icon,
            "is_read": self.is_read,
            "sound": self.sound,
            "created_at": self.created_at.isoformat(),
            "created_time": self.created_at.strftime("%I:%M %p"),
        }


# ============================================================
# RECIPE & MEAL SYSTEM
# ============================================================

class Recipe(db.Model):
    __tablename__ = "recipes"

    id                   = db.Column(db.Integer, primary_key=True)
    name                 = db.Column(db.String(200), nullable=False, index=True)
    description          = db.Column(db.Text, nullable=True)
    image                = db.Column(db.String(500), nullable=True)
    category             = db.Column(db.String(50), nullable=True)
    meal_type            = db.Column(db.String(50), nullable=True)
    cooking_time         = db.Column(db.String(30), default="20 mins")
    servings             = db.Column(db.Integer, default=1)
    difficulty           = db.Column(db.String(20), default="easy")
    is_veg               = db.Column(db.Boolean, default=True)
    ingredients          = db.Column(db.Text, nullable=True)
    steps                = db.Column(db.Text, nullable=True)
    tags                 = db.Column(db.Text, nullable=True)
    health_benefits      = db.Column(db.Text, nullable=True)
    calories             = db.Column(db.Integer, default=0)
    protein              = db.Column(db.Float, default=0)
    carbs                = db.Column(db.Float, default=0)
    fats                 = db.Column(db.Float, default=0)
    fiber                = db.Column(db.Float, default=0)
    sugar                = db.Column(db.Float, default=0)
    sodium               = db.Column(db.Float, default=0)
    potassium            = db.Column(db.Float, default=0)
    cholesterol          = db.Column(db.Float, default=0)
    bp_friendly          = db.Column(db.Boolean, default=True)
    diabetes_friendly    = db.Column(db.Boolean, default=True)
    weight_loss_friendly = db.Column(db.Boolean, default=True)
    heart_friendly       = db.Column(db.Boolean, default=True)
    high_protein         = db.Column(db.Boolean, default=False)
    high_fiber           = db.Column(db.Boolean, default=False)
    low_sodium           = db.Column(db.Boolean, default=True)
    bp_score             = db.Column(db.Float, default=0.0)
    diabetes_score       = db.Column(db.Float, default=0.0)
    weight_loss_score    = db.Column(db.Float, default=0.0)
    nutrition_score      = db.Column(db.Float, default=0.0)
    created_at           = db.Column(db.DateTime, default=now_ist)

    favorites            = db.relationship("Favorite", backref="recipe", cascade="all, delete-orphan")
    meal_items           = db.relationship("MealItem", backref="recipe")

    def composite_score(self, conditions):
        w = {}
        if "High Blood Pressure" in conditions:
            w["bp"] = 0.40
        if any("Diabetes" in c for c in conditions):
            w["diabetes"] = 0.35
        if any("Weight Loss" in c for c in conditions):
            w["weight_loss"] = 0.25
        if not w:
            return self.nutrition_score or 50
        t = sum(w.values())
        s = 0
        if "bp" in w:
            s += (self.bp_score or 0) * (w["bp"] / t)
        if "diabetes" in w:
            s += (self.diabetes_score or 0) * (w["diabetes"] / t)
        if "weight_loss" in w:
            s += (self.weight_loss_score or 0) * (w["weight_loss"] / t)
        return round(s, 1)

    def to_dict(self):
        return {
            "id": self.id,
            "name": self.name,
            "category": self.category,
            "is_veg": self.is_veg,
            "calories": self.calories,
            "protein": self.protein,
            "carbs": self.carbs,
            "fats": self.fats,
            "fiber": self.fiber,
            "sodium": self.sodium,
            "potassium": self.potassium,
            "ingredients": self.ingredients,
            "health_benefits": self.health_benefits,
            "bp_friendly": self.bp_friendly,
            "bp_score": self.bp_score,
            "cooking_time": self.cooking_time,
        }


class Favorite(db.Model):
    __tablename__ = "favorites"

    id             = db.Column(db.Integer, primary_key=True)
    user_id        = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    recipe_id      = db.Column(db.Integer, db.ForeignKey("recipes.id"), nullable=False)
    saved_at       = db.Column(db.DateTime, default=now_ist)

    __table_args__ = (db.UniqueConstraint("user_id", "recipe_id"),)


class MealPlan(db.Model):
    __tablename__ = "meal_plans"

    id              = db.Column(db.Integer, primary_key=True)
    user_id         = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    week_start_date = db.Column(db.Date, nullable=False)
    generated_at    = db.Column(db.DateTime, default=now_ist)
    is_active       = db.Column(db.Boolean, default=True)
    notes           = db.Column(db.Text, nullable=True)

    items           = db.relationship("MealItem", backref="meal_plan", cascade="all, delete-orphan")


class MealItem(db.Model):
    __tablename__ = "meal_items"

    id           = db.Column(db.Integer, primary_key=True)
    plan_id      = db.Column(db.Integer, db.ForeignKey("meal_plans.id"), nullable=False)
    recipe_id    = db.Column(db.Integer, db.ForeignKey("recipes.id"), nullable=False)
    day          = db.Column(db.String(20), nullable=False)
    meal_slot    = db.Column(db.String(30), nullable=False)
    slot_order   = db.Column(db.Integer, default=0)
    completed    = db.Column(db.Boolean, default=False)
    completed_at = db.Column(db.DateTime, nullable=True)
    locked       = db.Column(db.Boolean, default=False)
    note         = db.Column(db.Text, nullable=True)
    created_at   = db.Column(db.DateTime, default=now_ist)


class GroceryItem(db.Model):
    __tablename__ = "grocery_items"

    id              = db.Column(db.Integer, primary_key=True)
    user_id         = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    week_start      = db.Column(db.Date, nullable=False)
    ingredient_name = db.Column(db.String(200), nullable=False)
    category        = db.Column(db.String(50), default="Other")
    quantity        = db.Column(db.String(50), nullable=True)
    purchased       = db.Column(db.Boolean, default=False)
    purchased_at    = db.Column(db.DateTime, nullable=True)
    created_at      = db.Column(db.DateTime, default=now_ist)


# ============================================================
# NUTRITION LOG
# ============================================================

class NutritionDailyLog(db.Model):
    __tablename__ = "nutrition_daily_logs"

    id              = db.Column(db.Integer, primary_key=True)
    user_id         = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    log_date        = db.Column(db.Date, nullable=False, index=True)
    total_calories  = db.Column(db.Integer, default=0)
    total_protein   = db.Column(db.Float, default=0)
    total_carbs     = db.Column(db.Float, default=0)
    total_fats      = db.Column(db.Float, default=0)
    total_fiber     = db.Column(db.Float, default=0)
    total_sodium    = db.Column(db.Float, default=0)
    total_potassium = db.Column(db.Float, default=0)
    total_water     = db.Column(db.Float, default=0)
    meals_completed = db.Column(db.Integer, default=0)
    meals_planned   = db.Column(db.Integer, default=5)
    health_score    = db.Column(db.Float, default=0)
    created_at      = db.Column(db.DateTime, default=now_ist)
    updated_at      = db.Column(db.DateTime, default=now_ist, onupdate=now_ist)

    __table_args__  = (db.UniqueConstraint("user_id", "log_date"),)

    def to_dict(self):
        return {
            "log_date": str(self.log_date),
            "total_calories": self.total_calories,
            "total_protein": self.total_protein,
            "total_carbs": self.total_carbs,
            "total_fats": self.total_fats,
            "total_fiber": self.total_fiber,
            "total_sodium": self.total_sodium,
            "total_water": self.total_water,
            "health_score": self.health_score,
        }


# ============================================================
# ALERT SYSTEM
# ============================================================

class Alert(db.Model):
    __tablename__ = "alerts"

    id           = db.Column(db.Integer, primary_key=True)
    user_id      = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    alert_type   = db.Column(db.String(20), nullable=False)
    category     = db.Column(db.String(30), nullable=True)
    title        = db.Column(db.String(200), nullable=False)
    message      = db.Column(db.Text, nullable=False)
    action_text  = db.Column(db.String(100), nullable=True)
    action_url   = db.Column(db.String(200), nullable=True)
    trigger_value= db.Column(db.Float, nullable=True)
    is_read      = db.Column(db.Boolean, default=False)
    is_dismissed = db.Column(db.Boolean, default=False)
    created_at   = db.Column(db.DateTime, default=now_ist, index=True)
    expires_at   = db.Column(db.DateTime, nullable=True)

    def to_dict(self):
        return {
            "id": self.id,
            "alert_type": self.alert_type,
            "category": self.category,
            "title": self.title,
            "message": self.message,
            "is_read": self.is_read,
            "is_dismissed": self.is_dismissed,
            "created_at": self.created_at.isoformat(),
        }


# ============================================================
# MEDICINE SYSTEM
# ============================================================

class Medicine(db.Model):
    __tablename__ = "medicines"

    id         = db.Column(db.Integer, primary_key=True)
    user_id    = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    name       = db.Column(db.String(200), nullable=False)
    dosage     = db.Column(db.String(100), nullable=True)
    timing     = db.Column(db.String(20), nullable=True)
    frequency  = db.Column(db.String(30), default="daily")
    with_food  = db.Column(db.String(20), default="doesn't_matter")
    condition  = db.Column(db.String(100), nullable=True)
    active     = db.Column(db.Boolean, default=True)
    start_date = db.Column(db.Date, default=today_ist)
    notes      = db.Column(db.Text, nullable=True)
    created_at = db.Column(db.DateTime, default=now_ist)

    logs       = db.relationship("MedicineLog", backref="medicine", cascade="all, delete-orphan")

    def to_dict(self):
        return {
            "id": self.id,
            "name": self.name,
            "dosage": self.dosage,
            "timing": self.timing,
            "frequency": self.frequency,
            "with_food": self.with_food,
            "condition": self.condition,
            "active": self.active,
        }


class MedicineLog(db.Model):
    __tablename__ = "medicine_logs"

    id             = db.Column(db.Integer, primary_key=True)
    medicine_id    = db.Column(db.Integer, db.ForeignKey("medicines.id"), nullable=False)
    user_id        = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    taken          = db.Column(db.Boolean, default=False)
    log_date       = db.Column(db.Date, default=today_ist, index=True)
    logged_at      = db.Column(db.DateTime, default=now_ist)
    notes          = db.Column(db.Text, nullable=True)

    __table_args__ = (db.UniqueConstraint("medicine_id", "log_date"),)


# ============================================================
# DOCUMENT VAULT
# ============================================================

class Document(db.Model):
    __tablename__ = "documents"

    id            = db.Column(db.Integer, primary_key=True)
    user_id       = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    title         = db.Column(db.String(200), nullable=False)
    doc_type      = db.Column(db.String(50), nullable=False)
    file_name     = db.Column(db.String(300), nullable=False)
    file_path     = db.Column(db.String(500), nullable=False)
    file_size_kb  = db.Column(db.Integer, nullable=True)
    mime_type     = db.Column(db.String(100), nullable=True)
    doctor_name   = db.Column(db.String(200), nullable=True)
    hospital_name = db.Column(db.String(200), nullable=True)
    report_date   = db.Column(db.Date, nullable=True)
    expiry_date   = db.Column(db.Date, nullable=True)
    tags          = db.Column(db.Text, nullable=True)
    notes         = db.Column(db.Text, nullable=True)
    is_important  = db.Column(db.Boolean, default=False)
    uploaded_at   = db.Column(db.DateTime, default=now_ist)

    @property
    def type_icon(self):
        return {
            "lab_report": "🧪",
            "prescription": "💊",
            "insurance": "🛡️",
            "xray": "🦴",
            "ecg": "❤️",
            "mri": "🧠",
            "vaccination": "💉",
            "other": "📄",
        }.get(self.doc_type, "📄")

    def to_dict(self):
        return {
            "id": self.id,
            "title": self.title,
            "doc_type": self.doc_type,
            "type_icon": self.type_icon,
            "file_name": self.file_name,
            "doctor_name": self.doctor_name,
            "hospital_name": self.hospital_name,
            "report_date": str(self.report_date) if self.report_date else None,
            "is_important": self.is_important,
            "uploaded_at": self.uploaded_at.isoformat(),
        }


# ============================================================
# EMAIL REPORT CONFIG
# ============================================================

class EmailReportConfig(db.Model):
    __tablename__ = "email_report_configs"

    id                   = db.Column(db.Integer, primary_key=True)
    user_id              = db.Column(db.Integer, db.ForeignKey("users.id"), unique=True, nullable=False)
    is_enabled           = db.Column(db.Boolean, default=False)
    frequency            = db.Column(db.String(20), default="weekly")
    custom_days          = db.Column(db.Integer, default=7)
    send_time            = db.Column(db.String(10), default="08:00")
    email_recipients     = db.Column(db.Text, default="")
    report_period_days   = db.Column(db.Integer, default=7)
    include_weight       = db.Column(db.Boolean, default=True)
    include_bp           = db.Column(db.Boolean, default=True)
    include_water        = db.Column(db.Boolean, default=True)
    include_sleep        = db.Column(db.Boolean, default=True)
    include_steps        = db.Column(db.Boolean, default=True)
    include_exercise     = db.Column(db.Boolean, default=True)
    include_sugar        = db.Column(db.Boolean, default=True)
    include_nutrition    = db.Column(db.Boolean, default=True)
    include_suggestions  = db.Column(db.Boolean, default=True)
    include_achievements = db.Column(db.Boolean, default=True)
    last_sent_at         = db.Column(db.DateTime, nullable=True)
    next_send_at         = db.Column(db.DateTime, nullable=True)
    total_sent           = db.Column(db.Integer, default=0)
    created_at           = db.Column(db.DateTime, default=now_ist)
    updated_at           = db.Column(db.DateTime, default=now_ist, onupdate=now_ist)

    @property
    def recipient_list(self):
        if not self.email_recipients:
            return []
        return [e.strip() for e in self.email_recipients.split(",") if e.strip()]


class EmailReportLog(db.Model):
    __tablename__ = "email_report_logs"

    id            = db.Column(db.Integer, primary_key=True)
    user_id       = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    sent_at       = db.Column(db.DateTime, default=now_ist)
    recipients    = db.Column(db.Text, nullable=True)
    period_start  = db.Column(db.Date, nullable=True)
    period_end    = db.Column(db.Date, nullable=True)
    status        = db.Column(db.String(20), default="sent")
    error_message = db.Column(db.Text, nullable=True)
    health_score  = db.Column(db.Float, nullable=True)


# ============================================================
# HEALTH SCORE
# ============================================================

class DailyHealthScore(db.Model):
    __tablename__ = "daily_health_scores"

    id              = db.Column(db.Integer, primary_key=True)
    user_id         = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    score_date      = db.Column(db.Date, nullable=False, index=True)
    bp_score        = db.Column(db.Float, default=0)
    weight_score    = db.Column(db.Float, default=0)
    water_score     = db.Column(db.Float, default=0)
    sleep_score     = db.Column(db.Float, default=0)
    exercise_score  = db.Column(db.Float, default=0)
    nutrition_score = db.Column(db.Float, default=0)
    steps_score     = db.Column(db.Float, default=0)
    medicine_score  = db.Column(db.Float, default=0)
    total_score     = db.Column(db.Float, default=0)
    grade           = db.Column(db.String(20), nullable=True)
    computed_at     = db.Column(db.DateTime, default=now_ist)

    __table_args__  = (db.UniqueConstraint("user_id", "score_date"),)

    @property
    def grade_label(self):
        s = self.total_score or 0
        if s >= 90:
            return "Excellent"
        elif s >= 75:
            return "Good"
        elif s >= 60:
            return "Fair"
        elif s >= 40:
            return "Needs Attention"
        return "Critical"

    def to_dict(self):
        return {
            "score_date": str(self.score_date),
            "total_score": self.total_score,
            "grade": self.grade_label,
            "bp_score": self.bp_score,
            "water_score": self.water_score,
            "sleep_score": self.sleep_score,
            "exercise_score": self.exercise_score,
            "steps_score": self.steps_score,
            "medicine_score": self.medicine_score,
        }


# ============================================================
# BACKUP & ADMIN
# ============================================================

class Backup(db.Model):
    __tablename__ = "backups"

    id           = db.Column(db.Integer, primary_key=True)
    user_id      = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    backup_type  = db.Column(db.String(20), default="manual")
    file_name    = db.Column(db.String(300), nullable=True)
    file_path    = db.Column(db.String(500), nullable=True)
    file_size_kb = db.Column(db.Integer, nullable=True)
    format       = db.Column(db.String(20), default="json")
    status       = db.Column(db.String(20), default="completed")
    created_at   = db.Column(db.DateTime, default=now_ist, index=True)


class AdminLog(db.Model):
    __tablename__ = "admin_logs"

    id          = db.Column(db.Integer, primary_key=True)
    admin_id    = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True)
    action      = db.Column(db.String(200), nullable=False)
    target_type = db.Column(db.String(50), nullable=True)
    target_id   = db.Column(db.Integer, nullable=True)
    details     = db.Column(db.Text, nullable=True)
    ip_address  = db.Column(db.String(50), nullable=True)
    created_at  = db.Column(db.DateTime, default=now_ist, index=True)


class WeeklyInsight(db.Model):
    __tablename__ = "weekly_insights"

    id           = db.Column(db.Integer, primary_key=True)
    user_id      = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    week_start   = db.Column(db.Date, nullable=False, index=True)
    insight_text = db.Column(db.Text, nullable=False)
    metric_type  = db.Column(db.String(30), nullable=True)
    change_value = db.Column(db.Float, nullable=True)
    direction    = db.Column(db.String(20), nullable=True)
    priority     = db.Column(db.Integer, default=3)
    icon         = db.Column(db.String(10), default="📊")
    generated_at = db.Column(db.DateTime, default=now_ist)


# ============================================================
# SEED HELPERS
# ============================================================

def seed_health_conditions():
    conditions = [
        {"name": "High Blood Pressure", "icon": "❤️", "category": "cardiovascular"},
        {"name": "Type 2 Diabetes", "icon": "🩺", "category": "metabolic"},
        {"name": "Pre-Diabetes", "icon": "⚠️", "category": "metabolic"},
        {"name": "High Cholesterol", "icon": "🫀", "category": "cardiovascular"},
        {"name": "Weight Loss Goal", "icon": "⚖️", "category": "lifestyle"},
        {"name": "Weight Gain Goal", "icon": "💪", "category": "lifestyle"},
        {"name": "PCOS / PCOD", "icon": "🌸", "category": "hormonal"},
        {"name": "Thyroid (Hypothyroid)", "icon": "🦋", "category": "hormonal"},
        {"name": "Heart Disease", "icon": "💗", "category": "cardiovascular"},
        {"name": "Kidney Disease (CKD)", "icon": "🫘", "category": "metabolic"},
        {"name": "Sleep Apnea", "icon": "😴", "category": "lifestyle"},
        {"name": "Fatty Liver", "icon": "🫁", "category": "metabolic"},
        {"name": "Acid Reflux / IBS", "icon": "🔥", "category": "digestive"},
        {"name": "Healthy Lifestyle", "icon": "🌿", "category": "lifestyle"},
        {"name": "Post-Pregnancy", "icon": "👶", "category": "hormonal"},
        {"name": "Menopause", "icon": "🌺", "category": "hormonal"},
    ]

    for c in conditions:
        if not HealthCondition.query.filter_by(name=c["name"]).first():
            db.session.add(HealthCondition(**c))
    db.session.commit()