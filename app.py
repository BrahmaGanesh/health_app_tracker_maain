# ============================================================
# HEALTH TRACKER PLATFORM — FINAL COMPLETE MERGED VERSION
# app.py — Flask Application Factory (Website + API for APK)
# Migrated to Firebase Cloud Firestore + Firebase Auth
# ============================================================
from dotenv import load_dotenv
import os
from datetime import datetime
from zoneinfo import ZoneInfo

from flask import Flask, render_template, jsonify, request, g, current_app
from werkzeug.middleware.proxy_fix import ProxyFix

from config import get_config
from extensions import (
    bcrypt, login_manager, migrate, mail,
    cache, cors, jwt, csrf, db
)
from models import User

load_dotenv()

print("Current directory:", os.getcwd())
print(".env exists:", os.path.exists(".env"))
print("MAIL_USERNAME:", os.getenv("MAIL_USERNAME"))

load_dotenv(r"C:\health_app_main\.env", override=True)

# ------------------------------------------------------------
# HELPER
# ------------------------------------------------------------
def _is_api_request():
    return request.path.startswith("/api/")


# ------------------------------------------------------------
# APP FACTORY
# ------------------------------------------------------------
def create_app(config_class=None):
    app = Flask(__name__)

    # Proxy fix (Render / deployment safe)
    app.wsgi_app = ProxyFix(
        app.wsgi_app,
        x_for=1,
        x_proto=1,
        x_host=1,
        x_prefix=1,
    )

    config_class = config_class or get_config()
    app.config.from_object(config_class)

    app.config["PREFERRED_URL_SCHEME"] = "https"

    # --------------------------------------------------------
    # INIT EXTENSIONS
    # --------------------------------------------------------
    bcrypt.init_app(app)
    login_manager.init_app(app)
    # migrate.init_app(app, db)  # SQLAlchemy removed - using Firestore
    mail.init_app(app)
    cache.init_app(app)

    # Get allowed origins from environment (comma-separated)
    # Default to localhost for development, restrict for production
    allowed_origins_str = os.environ.get("CORS_ORIGINS", "")
    if allowed_origins_str:
        allowed_origins = [o.strip() for o in allowed_origins_str.split(",") if o.strip()]
    else:
        # Development defaults - restrict these in production
        allowed_origins = [
            "http://localhost:3000",
            "http://localhost:5000",
            "https://localhost:3000",
            "https://*.netlify.app",
            "https://*.vercel.app"
        ]

    cors.init_app(
        app,
        resources={
            r"/api/*": {
                "origins": allowed_origins,
                "methods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
                "allow_headers": ["Content-Type", "Authorization", "X-CSRFToken"],
            }
        },
    )

    jwt.init_app(app)
    csrf.init_app(app)

    # --------------------------------------------------------
    # FIREBASE ADMIN INITIALIZATION
    # --------------------------------------------------------
    def initialize_firebase():
        """Initialize Firebase Admin SDK."""
        try:
            from services.firebase_admin import init_firebase_admin
            credentials_base64 = app.config.get("FIREBASE_CREDENTIALS_BASE64", "")
            project_id = app.config.get("FIREBASE_PROJECT_ID", "health-tracker-2-0")

            if not app.config.get("FIREBASE_CREDENTIALS_BASE64") and not os.path.exists("firebase-credentials.json"):
                app.logger.warning("Firebase credentials not configured. Firebase features will be disabled.")
                return False

            service = init_firebase_admin(
                credentials_base64=app.config.get("FIREBASE_CREDENTIALS_BASE64", "") or None,
                project_id=app.config.get("FIREBASE_PROJECT_ID", "health-tracker-2-0")
            )
            app.logger.info("✓ Firebase Admin SDK initialized successfully")
            return True
        except Exception as e:
            app.logger.error(f"Firebase initialization failed: {e}")
            return False

    # Initialize Firebase on app creation
    with app.app_context():
        firebase_initialized = initialize_firebase()
        app.config['FIREBASE_INITIALIZED'] = firebase_initialized

    # --------------------------------------------------------
    # JWT CONFIG
    # --------------------------------------------------------
    @jwt.user_identity_loader
    def identity(user):
        return str(user.id) if hasattr(user, "id") else str(user)

    @jwt.user_lookup_loader
    def lookup(_jwt_header, jwt_data):
        # For JWT tokens, we use Firebase UID
        identity = jwt_data["sub"]
        return {"uid": identity}

    @jwt.unauthorized_loader
    def unauthorized(reason):
        return jsonify({
            "error": "Authorization required",
            "reason": reason
        }), 401

    @jwt.expired_token_loader
    def expired_token(_header, _payload):
        return jsonify({
            "error": "Token expired",
            "code": "TOKEN_EXPIRED"
        }), 401

    # --------------------------------------------------------
    # CSRF FOR API
    # --------------------------------------------------------
    @app.before_request
    def disable_csrf_for_api():
        if request.path.startswith("/api/v1/"):
            setattr(request, "_dont_enforce_csrf_checks", True)

    # --------------------------------------------------------
    # FIREBASE AUTH MIDDLEWARE
    # --------------------------------------------------------
    @app.before_request
    def verify_firebase_token():
        """Verify Firebase ID token for API routes."""
        if request.path.startswith("/api/v1/"):
            auth_header = request.headers.get('Authorization', '')

            if auth_header.startswith('Bearer '):
                id_token = auth_header.split('Bearer ')[1].strip()

                try:
                    from services.firebase_admin import get_firebase_admin
                    firebase_admin = get_firebase_admin()

                    # Verify Firebase ID token
                    decoded_token = firebase_admin.verify_id_token(id_token)

                    # Store user info in Flask g object
                    g.current_user = {
                        'uid': decoded_token['uid'],
                        'email': decoded_token.get('email'),
                        'email_verified': decoded_token.get('email_verified', False),
                        'name': decoded_token.get('name'),
                        'picture': decoded_token.get('picture'),
                        'auth_time': decoded_token.get('auth_time'),
                        'token_claims': decoded_token
                    }
                except Exception as e:
                    return jsonify({
                        "success": False,
                        "error": "Invalid or expired token",
                        "code": "INVALID_TOKEN"
                    }), 401

    # --------------------------------------------------------
    # LOGIN MANAGER (Firestore-backed web authentication)
    # --------------------------------------------------------
    login_manager.login_view = "auth.login"
    login_manager.login_message = "Please log in to access this page."
    login_manager.login_message_category = "info"
    login_manager.session_protection = "strong"

    @login_manager.user_loader
    def load_user(user_id):
        try:
            from services.firebase_admin import get_firebase_admin
            firebase_admin = get_firebase_admin()
            db = firebase_admin.firestore

            doc = db.collection(User.COLLECTION).document(user_id).get()

            if not doc.exists:
                return None

            user_data = doc.to_dict() or {}

            user_data["id"] = user_id

            user = User(user_data)

            if not user.is_active:
                return None

            return user

        except Exception:
            current_app.logger.exception(
                "Failed to load Flask-Login user: %s", user_id
            )
            return None

    # --------------------------------------------------------
    # CSRF FOR API
    # --------------------------------------------------------
    @app.before_request
    def disable_csrf_for_api():
        if request.path.startswith("/api/v1/"):
            setattr(request, "_dont_enforce_csrf_checks", True)

    # --------------------------------------------------------
    # WEB BLUEPRINTS
    # --------------------------------------------------------
    from routes.auth_routes import auth_bp
    from routes.google_auth import google_auth_bp
    from routes.main_routes import main_bp
    from routes.profile_routes import profile_bp
    from routes.bp_routes import bp_bp
    from routes.meal_routes import meal_bp
    from routes.nutrition_routes import nutrition_bp
    from routes.tracker_routes import tracker_bp
    from routes.analytics_routes import analytics_bp
    from routes.alert_routes import alert_bp
    from routes.family_routes import family_bp
    from routes.exercise_routes import exercise_bp
    from routes.sleep_routes import sleep_bp
    from routes.report_routes import report_bp
    from routes.email_report_routes import email_report_bp
    from routes.document_routes import document_bp
    from routes.admin_routes import admin_bp
    from routes.notification_routes import notification_bp
    from routes.business_routes import business_bp

    app.register_blueprint(auth_bp, url_prefix="/auth")
    app.register_blueprint(google_auth_bp)
    app.register_blueprint(main_bp, url_prefix="/")
    app.register_blueprint(profile_bp, url_prefix="/profile")
    app.register_blueprint(bp_bp, url_prefix="/bp")
    app.register_blueprint(meal_bp, url_prefix="/meal")
    app.register_blueprint(nutrition_bp, url_prefix="/nutrition")
    app.register_blueprint(tracker_bp, url_prefix="/tracker")
    app.register_blueprint(analytics_bp, url_prefix="/analytics")
    app.register_blueprint(alert_bp, url_prefix="/alerts")
    app.register_blueprint(family_bp, url_prefix="/family")
    app.register_blueprint(exercise_bp, url_prefix="/exercise")
    app.register_blueprint(sleep_bp, url_prefix="/sleep")
    app.register_blueprint(report_bp, url_prefix="/reports")
    app.register_blueprint(email_report_bp, url_prefix="/reports/email")
    app.register_blueprint(document_bp, url_prefix="/documents")
    app.register_blueprint(admin_bp, url_prefix="/admin")
    app.register_blueprint(notification_bp, url_prefix="/notifications")
    app.register_blueprint(business_bp)

    # --------------------------------------------------------
    # API BLUEPRINTS
    # --------------------------------------------------------
    from routes.api.auth_api import auth_api_bp
    from routes.api.dashboard_api import dashboard_api_bp
    from routes.api.tracker_api import tracker_api_bp
    from routes.api.meal_api import meal_api_bp
    from routes.api.exercise_api import exercise_api_bp
    from routes.api.notification_api import notification_api_bp
    from routes.api.family_api import family_api_bp
    from routes.api.report_api import report_api_bp
    from routes.api.medicine_api import medicine_api_bp
    from routes.api.health_modules_api import modules_api_bp
    from routes.api.ai_assistant_api import ai_bp
    from routes.api.document_api import document_api_bp
    from routes.api.lab_api import lab_api_bp
    from routes.api.appointment_api import appointment_api_bp
    from routes.api.timeline_api import timeline_api_bp

    csrf.exempt(auth_api_bp)
    csrf.exempt(dashboard_api_bp)
    csrf.exempt(tracker_api_bp)
    csrf.exempt(meal_api_bp)
    csrf.exempt(exercise_api_bp)
    csrf.exempt(notification_api_bp)
    csrf.exempt(family_api_bp)
    csrf.exempt(report_api_bp)
    csrf.exempt(medicine_api_bp)
    csrf.exempt(modules_api_bp)
    csrf.exempt(ai_bp)
    csrf.exempt(document_api_bp)
    csrf.exempt(lab_api_bp)
    csrf.exempt(appointment_api_bp)
    csrf.exempt(timeline_api_bp)
    csrf.exempt(google_auth_bp)

    app.register_blueprint(auth_api_bp, url_prefix="/api/v1/auth")
    app.register_blueprint(dashboard_api_bp, url_prefix="/api/v1/dashboard")
    app.register_blueprint(tracker_api_bp, url_prefix="/api/v1/tracker")
    app.register_blueprint(meal_api_bp, url_prefix="/api/v1/meals")
    app.register_blueprint(exercise_api_bp, url_prefix="/api/v1/exercise")
    app.register_blueprint(notification_api_bp, url_prefix="/api/v1/notifications")
    app.register_blueprint(family_api_bp, url_prefix="/api/v1/family")
    app.register_blueprint(report_api_bp, url_prefix="/api/v1/reports")
    app.register_blueprint(medicine_api_bp, url_prefix="/api/v1/medicines")
    app.register_blueprint(modules_api_bp, url_prefix="/api/v1")
    app.register_blueprint(ai_bp, url_prefix="/api/v1/ai-assistant")
    app.register_blueprint(document_api_bp, url_prefix="/api/v1/documents")
    app.register_blueprint(lab_api_bp, url_prefix="/api/v1/lab-tests")
    app.register_blueprint(appointment_api_bp, url_prefix="/api/v1/appointments")
    app.register_blueprint(timeline_api_bp, url_prefix="/api/v1/timeline")

    # --------------------------------------------------------
    # GLOBAL TEMPLATE VARIABLES
    # --------------------------------------------------------
    @app.context_processor
    def inject_globals():
        from flask_login import current_user

        unread_alerts = 0
        unread_notifs = 0

        if current_user.is_authenticated:
            try:
                # These would need to be migrated to Firestore
                # For now, return 0 to avoid errors
                unread_alerts = 0
                unread_notifs = 0
            except Exception:
                pass

        return {
            "app_name": app.config.get("APP_NAME", "HealthTrack"),
            "app_version": app.config.get("APP_VERSION", "2.0.0"),
            "unread_alerts": unread_alerts,
            "unread_notifs": unread_notifs
        }

    # --------------------------------------------------------
    # TEMPLATE FILTERS
    # --------------------------------------------------------
    def _parse_datetime(value):
        """Parse datetime from various formats (datetime, Timestamp, string)."""
        if value is None:
            return None
        if isinstance(value, datetime):
            return value
        if hasattr(value, 'to_datetime'):  # Firestore Timestamp
            return value.to_datetime()
        if isinstance(value, str):
            try:
                return datetime.fromisoformat(value.replace('Z', '+00:00'))
            except ValueError:
                pass
        return None

    @app.template_filter("datetime_format")
    def datetime_format(value, fmt="%d %b %Y"):
        dt = _parse_datetime(value)
        if dt is None:
            return "—"
        return dt.strftime(fmt)

    @app.template_filter("time_format")
    def time_format(value):
        dt = _parse_datetime(value)
        if dt is None:
            return "—"
        return dt.strftime("%I:%M %p")

    @app.template_filter("safe_strftime")
    def safe_strftime(value, fmt="%d %b %Y"):
        dt = _parse_datetime(value)
        if dt is None:
            return "—"
        return dt.strftime(fmt)

    @app.template_filter("round2")
    def round2(value):
        try:
            return round(float(value), 1)
        except Exception:
            return 0

    @app.template_filter("bmi_status")
    def bmi_status_filter(bmi):
        if bmi is None:
            return "Unknown"

        bmi = float(bmi)
        if bmi < 18.5:
            return "Underweight"
        elif bmi < 25.0:
            return "Normal"
        elif bmi < 30.0:
            return "Overweight"
        elif bmi < 35.0:
            return "Obese I"
        elif bmi < 40.0:
            return "Obese II"
        return "Obese III"

    # --------------------------------------------------------
    # ERROR HANDLERS
    # --------------------------------------------------------
    @app.errorhandler(404)
    def not_found(e):
        if _is_api_request():
            return jsonify({"success": False, "error": "Not found"}), 404
        return render_template("errors/404.html"), 404

    @app.errorhandler(500)
    def server_error(e):
        if _is_api_request():
            return jsonify({"success": False, "error": "Server error"}), 500
        return render_template("errors/500.html"), 500

    @app.errorhandler(403)
    def forbidden(e):
        if _is_api_request():
            return jsonify({"success": False, "error": "Forbidden"}), 403
        return render_template("errors/403.html"), 403

    # --------------------------------------------------------
    # HEALTH CHECK
    # --------------------------------------------------------
    @app.route("/api/v1/health")
    def health():
        return jsonify({
            "status": "ok",
            "app": app.config.get("APP_NAME"),
            "version": app.config.get("APP_VERSION"),
            "firebase_initialized": app.config.get('FIREBASE_INITIALIZED', False)
        })

    return app


# ------------------------------------------------------------
# ENTRY POINT
# ------------------------------------------------------------
app = create_app()

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=True)