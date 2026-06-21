# ============================================================
# HEALTH TRACKER PLATFORM — FINAL COMPLETE VERSION
# config.py — Application Configuration
# ============================================================

import os
from datetime import timedelta
from dotenv import load_dotenv

load_dotenv()


class Config:
    # ── Core ─────────────────────────────────────────────────
    SECRET_KEY              = os.environ.get("SECRET_KEY", "dev-secret-change-in-prod")
    APP_NAME                = os.environ.get("APP_NAME", "HealthTrack")
    APP_TAGLINE             = os.environ.get("APP_TAGLINE", "Your Adaptive Health Recovery Platform")
    APP_VERSION             = os.environ.get("APP_VERSION", "2.0.0")

    # ── Database ──────────────────────────────────────────────
    _db_url = os.environ.get("DATABASE_URL", "sqlite:///health_tracker.db")

    # Render PostgreSQL compatibility
    if _db_url.startswith("postgres://"):
        _db_url = _db_url.replace("postgres://", "postgresql://", 1)

    if _db_url.startswith("postgresql://") and "sslmode=" not in _db_url:
        separator = "&" if "?" in _db_url else "?"
        _db_url = f"{_db_url}{separator}sslmode=require"

    SQLALCHEMY_DATABASE_URI = _db_url
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_ECHO = False

    SQLALCHEMY_ENGINE_OPTIONS = {
        "pool_pre_ping": True,
        "pool_recycle": 300,
    }

    # ── JWT (for APK API auth) ────────────────────────────────
    JWT_SECRET_KEY              = os.environ.get("JWT_SECRET_KEY", "jwt-secret-change-in-prod")
    JWT_ACCESS_TOKEN_EXPIRES    = timedelta(days=30)
    JWT_REFRESH_TOKEN_EXPIRES   = timedelta(days=90)
    JWT_TOKEN_LOCATION          = ["headers"]
    JWT_HEADER_NAME             = "Authorization"
    JWT_HEADER_TYPE             = "Bearer"

    # ── Security ──────────────────────────────────────────────
    WTF_CSRF_ENABLED            = True
    SESSION_COOKIE_SECURE       = False
    SESSION_COOKIE_HTTPONLY     = True
    SESSION_COOKIE_SAMESITE     = "Lax"
    PERMANENT_SESSION_LIFETIME  = timedelta(days=30)
    REMEMBER_COOKIE_DURATION    = timedelta(days=30)

    # ── Mail ──────────────────────────────────────────────────
    MAIL_SERVER         = os.environ.get("MAIL_SERVER", "smtp.gmail.com")
    MAIL_PORT           = int(os.environ.get("MAIL_PORT", 587))
    MAIL_USE_TLS        = os.environ.get("MAIL_USE_TLS", "True") == "True"
    MAIL_USERNAME       = os.environ.get("MAIL_USERNAME", "")
    MAIL_PASSWORD       = os.environ.get("MAIL_PASSWORD", "")
    MAIL_DEFAULT_SENDER = os.environ.get("MAIL_DEFAULT_SENDER", "")

    # ── Google OAuth ───────────────────────────────────────────────
    # Get from: https://console.cloud.google.com → APIs & Services → Credentials
    GOOGLE_CLIENT_ID     = os.environ.get("GOOGLE_CLIENT_ID", "")
    GOOGLE_CLIENT_SECRET = os.environ.get("GOOGLE_CLIENT_SECRET", "")
    GOOGLE_REDIRECT_URI  = os.environ.get("GOOGLE_REDIRECT_URI", "http://localhost:5000/auth/google/callback")
    # Scopes: profile + email + gmail send (for sending reports via user's Gmail)
    GOOGLE_SCOPES = [
        "openid",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
        "https://www.googleapis.com/auth/gmail.send",  # send reports as user
    ]

    # ── Firebase (FCM Push Notifications) ─────────────────────
    FIREBASE_CREDENTIALS = os.environ.get("FIREBASE_CREDENTIALS", "firebase-credentials.json")
    FCM_SERVER_KEY       = os.environ.get("FCM_SERVER_KEY", "")

    # ── Web Push (VAPID) ──────────────────────────────────────
    VAPID_PUBLIC_KEY    = os.environ.get("VAPID_PUBLIC_KEY", "")
    VAPID_PRIVATE_KEY   = os.environ.get("VAPID_PRIVATE_KEY", "")
    VAPID_EMAIL         = os.environ.get("VAPID_EMAIL", "your@email.com")

    # ── Uploads ───────────────────────────────────────────────
    UPLOAD_FOLDER       = os.environ.get("UPLOAD_FOLDER", "static/uploads")
    DOCS_FOLDER         = os.environ.get("DOCS_FOLDER", "static/documents")
    MAX_CONTENT_LENGTH  = int(os.environ.get("MAX_CONTENT_LENGTH", 16 * 1024 * 1024))  # 16MB
    ALLOWED_EXTENSIONS  = {"png", "jpg", "jpeg", "gif", "webp", "pdf", "doc", "docx"}

    # ── Cache ─────────────────────────────────────────────────
    CACHE_TYPE              = os.environ.get("CACHE_TYPE", "SimpleCache")
    CACHE_DEFAULT_TIMEOUT   = int(os.environ.get("CACHE_DEFAULT_TIMEOUT", 300))

    # ── Health Constants ──────────────────────────────────────
    BP_NORMAL_SYS       = 120
    BP_NORMAL_DIA       = 80
    BP_ELEVATED_SYS     = 130
    BP_HIGH_SYS         = 140
    BP_HIGH_DIA         = 90
    BP_CRISIS_SYS       = 180
    BP_CRISIS_DIA       = 120
    SUGAR_NORMAL_FASTING = 100
    SUGAR_PREDIABETES   = 126
    BMI_NORMAL_MIN      = 18.5
    BMI_NORMAL_MAX      = 24.9
    DEFAULT_WATER       = 2.5
    DEFAULT_STEPS       = 8000
    DEFAULT_SLEEP       = 7.5
    DEFAULT_EXERCISE    = 30

    # ── Reminder Settings ─────────────────────────────────────
    REMINDER_REPEAT_INTERVAL_MINS   = 5    # Default repeat every 5 min
    REMINDER_MAX_REPEATS            = 10   # Max 10 times before stopping

    # ── Pagination ────────────────────────────────────────────
    RECORDS_PER_PAGE    = 20
    RECIPES_PER_PAGE    = 12

    # ── Scheduler Jobs ────────────────────────────────────────
    SCHEDULER_API_ENABLED = False
    JOBS = [
        {
            "id":       "reminder_engine",
            "func":     "utils.reminder_engine:run_reminder_check",
            "trigger":  "interval",
            "minutes":  1,   # Check every minute
        },
        {
            "id":       "daily_aggregation",
            "func":     "utils.scheduler:run_daily_aggregation",
            "trigger":  "cron",
            "hour":     0, "minute": 5,
        },
        {
            "id":       "weekly_insights",
            "func":     "utils.scheduler:run_weekly_insights",
            "trigger":  "cron",
            "day_of_week": "sun", "hour": 6,
        },
        {
            "id":       "email_reports",
            "func":     "utils.email_sender:run_scheduled_reports",
            "trigger":  "cron",
            "hour":     8, "minute": 0,
        },
        {
            "id":       "health_scores",
            "func":     "utils.health_score:compute_all_scores",
            "trigger":  "cron",
            "hour":     23, "minute": 55,
        },
    ]


class DevelopmentConfig(Config):
    DEBUG               = True
    TESTING             = False
    SQLALCHEMY_ECHO     = False


class ProductionConfig(Config):
    DEBUG                   = False
    TESTING                 = False
    SESSION_COOKIE_SECURE   = True
    SQLALCHEMY_ECHO         = False
    WTF_CSRF_SSL_STRICT     = True


class TestingConfig(Config):
    TESTING                     = True
    DEBUG                       = True
    SQLALCHEMY_DATABASE_URI     = "sqlite:///:memory:"
    WTF_CSRF_ENABLED            = False


config = {
    "development":  DevelopmentConfig,
    "production":   ProductionConfig,
    "testing":      TestingConfig,
    "default":      DevelopmentConfig,
}


def get_config():
    env = os.environ.get("FLASK_ENV", "development")
    return config.get(env, DevelopmentConfig)