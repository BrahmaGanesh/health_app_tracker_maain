import os
from flask import Flask, render_template, jsonify, request
from werkzeug.middleware.proxy_fix import ProxyFix
from config import get_config

from extensions import (
    db, bcrypt, login_manager, migrate, mail,
    cache, cors, jwt, csrf
)

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
    app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1, x_prefix=1)

    config_class = config_class or get_config()
    app.config.from_object(config_class)

    # FIX: wrong usage of PREFERRED_URL_SCHEME (keep ONLY scheme, not full URL)
    app.config["PREFERRED_URL_SCHEME"] = "https"

    # --------------------------------------------------------
    # INIT EXTENSIONS
    # --------------------------------------------------------
    db.init_app(app)
    bcrypt.init_app(app)
    login_manager.init_app(app)
    migrate.init_app(app, db)
    mail.init_app(app)
    cache.init_app(app)

    jwt.init_app(app)
    cors.init_app(app)
    csrf.init_app(app)

    # --------------------------------------------------------
    # LOGIN MANAGER
    # --------------------------------------------------------
    login_manager.login_view = "auth.login"
    login_manager.session_protection = "strong"

    @login_manager.user_loader
    def load_user(user_id):
        from models import User
        return User.query.get(int(user_id))

    # --------------------------------------------------------
    # JWT CONFIG
    # --------------------------------------------------------
    @jwt.user_identity_loader
    def identity(user):
        return str(user.id) if hasattr(user, "id") else str(user)

    @jwt.user_lookup_loader
    def lookup(_jwt_header, jwt_data):
        from models import User
        identity = jwt_data["sub"]
        return User.query.get(int(identity))

    # --------------------------------------------------------
    # CSRF FIX (CLEAN + SAFE VERSION)
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


    csrf.exempt(auth_api_bp)
    csrf.exempt(dashboard_api_bp)
    csrf.exempt(tracker_api_bp)
    csrf.exempt(meal_api_bp)
    csrf.exempt(exercise_api_bp)
    csrf.exempt(notification_api_bp)
    csrf.exempt(family_api_bp)
    csrf.exempt(report_api_bp)



    app.register_blueprint(auth_api_bp, url_prefix="/api/v1/auth")
    app.register_blueprint(dashboard_api_bp, url_prefix="/api/v1/dashboard")
    app.register_blueprint(tracker_api_bp, url_prefix="/api/v1/tracker")
    app.register_blueprint(meal_api_bp, url_prefix="/api/v1/meals")
    app.register_blueprint(exercise_api_bp, url_prefix="/api/v1/exercise")
    app.register_blueprint(notification_api_bp, url_prefix="/api/v1/notifications")
    app.register_blueprint(family_api_bp, url_prefix="/api/v1/family")
    app.register_blueprint(report_api_bp, url_prefix="/api/v1/reports")

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
                from models import Alert, Notification

                unread_alerts = Alert.query.filter_by(
                    user_id=current_user.id,
                    is_read=False,
                    is_dismissed=False
                ).count()

                unread_notifs = Notification.query.filter_by(
                    user_id=current_user.id,
                    is_read=False
                ).count()

            except Exception:
                pass

        return {
            "app_name": app.config.get("APP_NAME", "HealthTrack"),
            "app_version": app.config.get("APP_VERSION", "2.0.0"),
            "unread_alerts": unread_alerts,
            "unread_notifs": unread_notifs
        }

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
            "version": app.config.get("APP_VERSION")
        })

    # --------------------------------------------------------
    # DB INIT
    # --------------------------------------------------------
    with app.app_context():
        try:
            db.create_all()
        except Exception as e:
            print("DB init error:", e)

    return app


app = create_app()

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=True)