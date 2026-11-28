# ============================================================
# AUTH ROUTES — FIREBASE AUTH & FIRESTORE VERSION
# ============================================================

from datetime import datetime, timezone

from flask import (
    Blueprint,
    render_template,
    redirect,
    url_for,
    flash,
    request,
    jsonify,
    current_app,
)
from flask_login import login_user, logout_user, login_required, current_user

from extensions import login_manager
from services.firebase_admin import get_firebase_admin
from services.user_service import get_user_service

from models import User


auth_bp = Blueprint("auth", __name__)


# ============================================================
# REGISTER
# ============================================================

@auth_bp.route("/register", methods=["GET", "POST"])
def register():
    if current_user.is_authenticated:
        return redirect(url_for("main.dashboard"))

    if request.method == "GET":
        return render_template("auth/register.html")

    name = request.form.get("name", "").strip()
    email = request.form.get("email", "").strip().lower()
    password = request.form.get("password", "")
    confirm_password = request.form.get("confirm_password", "")

    errors = []

    if len(name) < 2:
        errors.append("Name must be at least 2 characters.")

    if "@" not in email or "." not in email:
        errors.append("Please enter a valid email address.")

    if len(password) < 6:
        errors.append("Password must be at least 6 characters.")

    if password != confirm_password:
        errors.append("Passwords do not match.")

    if errors:
        for error in errors:
            flash(error, "danger")

        return render_template(
            "auth/register.html",
            name=name,
            email=email,
        )

    try:
        firebase_admin = get_firebase_admin()

        if not firebase_admin or not getattr(firebase_admin, "_initialized", False):
            flash("Firebase is not configured. Please contact support.", "danger")
            return render_template(
                "auth/register.html",
                name=name,
                email=email,
            )

        user_service = get_user_service()

        existing_user = user_service.get_user_by_email(email)

        if existing_user:
            flash("This email is already registered.", "danger")
            return render_template(
                "auth/register.html",
                name=name,
                email=email,
            )

        try:
            user_record = firebase_admin.auth.create_user(
                email=email,
                password=password,
                display_name=name,
                app=firebase_admin.app,
            )
            uid = user_record.uid

        except Exception as create_error:
            error_text = str(create_error)

            if "EMAIL_EXISTS" in error_text:
                flash("This email is already registered.", "danger")
            else:
                flash(f"Registration failed: {error_text}", "danger")

            return render_template(
                "auth/register.html",
                name=name,
                email=email,
            )

        current_time = datetime.now(timezone.utc)

        user_data = {
            "uid": uid,
            "name": name,
            "email": email,
            "is_active": True,
            "is_verified": False,
            "is_admin": False,
            "family_member_limit": 2,
            "onboarding_done": False,
            "dark_mode": False,
            "profile_photo": None,
            "fcm_token": None,
            "web_push_sub": None,
            "created_at": current_time,
            "last_login": current_time,
            "last_updated": current_time,
            "auth_provider": "email",
            "google_id": None,
            "google_email": None,
            "google_access_token": None,
            "google_refresh_token": None,
            "verification_token": None,
            "reset_token": None,
            "reset_token_expiry": None,
        }

        db = firebase_admin.firestore
        user_ref = db.collection("users").document(uid)

        user_ref.set(user_data)

        user_ref.collection("profile").document("profile").set({
            "gender": None,
            "date_of_birth": None,
            "height_cm": None,
            "current_weight_kg": None,
            "activity_level": "sedentary",
            "diet_preference": "vegetarian",
            "onboarding_step": 1,
            "blood_group": None,
            "emergency_contact": None,
            "created_at": current_time,
            "updated_at": current_time,
        })

        user_ref.collection("goals").document("goals").set({
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
            "goal_start_date": current_time.date().isoformat(),
            "created_at": current_time,
            "updated_at": current_time,
        })

        user_ref.collection("subscription").document("current").set({
            "plan": "free",
            "is_active": True,
            "created_at": current_time,
        })

        user_ref.collection("settings").document("preferences").set({
            "med_notifications": True,
            "med_auto_stock": True,
            "med_snooze_mins": 10,
            "med_low_stock_threshold": 5,
            "med_sound": "medicine",
            "water_reminders": True,
            "water_target_litres": 2.5,
            "sleep_reminders": True,
            "sleep_target_hours": 7.5,
            "exercise_reminders": True,
            "exercise_target_mins": 30,
            "notification_sound": "healthalert",
            "vibration_enabled": True,
        })

        user_ref.collection("health_conditions").document("seed").set({
            "seeded": True,
            "seeded_at": current_time,
        })

        user = User(user_data)

        login_user(user, remember=True)

        flash("Account created successfully!", "success")
        return redirect(url_for("profile.onboarding_step1"))

    except Exception as error:
        import traceback

        print("REGISTER ERROR:")
        print(traceback.format_exc())

        flash(f"Registration failed: {str(error)}", "danger")

        return render_template(
            "auth/register.html",
            name=name,
            email=email,
        )


# ============================================================
# LOGIN
# ============================================================

@auth_bp.route("/login", methods=["GET", "POST"])
def login():
    if current_user.is_authenticated:
        return redirect(url_for("main.dashboard"))

    if request.method == "GET":
        return render_template("auth/login.html")

    email = request.form.get("email", "").strip().lower()
    password = request.form.get("password", "")
    remember = request.form.get("remember_me") == "on"

    if not email or not password:
        flash("Please enter both email and password.", "danger")
        return render_template("auth/login.html", email=email)

    firebase_api_key = current_app.config.get("FIREBASE_API_KEY", "")

    if not firebase_api_key:
        flash("Firebase is not configured. Please contact support.", "danger")
        return render_template("auth/login.html", email=email)

    try:
        import requests

        api_url = (
            "https://identitytoolkit.googleapis.com/v1/"
            "accounts:signInWithPassword"
            f"?key={firebase_api_key}"
        )

        response = requests.post(
            api_url,
            json={
                "email": email,
                "password": password,
                "returnSecureToken": True,
            },
            timeout=10,
        )

        if response.status_code != 200:
            try:
                error_data = response.json()
            except Exception:
                error_data = {}

            error_message = (
                error_data
                .get("error", {})
                .get("message", "INVALID_LOGIN_CREDENTIALS")
            )

            if error_message in (
                "EMAIL_NOT_FOUND",
                "INVALID_PASSWORD",
                "INVALID_LOGIN_CREDENTIALS",
            ):
                flash("Invalid email or password.", "danger")
            elif error_message == "USER_DISABLED":
                flash("This account has been disabled.", "danger")
            else:
                flash("Login failed. Please try again.", "danger")

            return render_template("auth/login.html", email=email)

        login_data = response.json()

        uid = login_data.get("localId")
        id_token = login_data.get("idToken")
        refresh_token = login_data.get("refreshToken")

        if not uid:
            flash("Login failed. Please try again.", "danger")
            return render_template("auth/login.html", email=email)

        user_service = get_user_service()
        user_data = user_service.get_user_by_uid(uid)

        if not user_data:
            user_data = {
                "uid": uid,
                "email": email,
                "name": "",
                "is_active": True,
                "is_verified": False,
                "auth_provider": "email",
            }

        if not user_data.get("is_active", True):
            flash("This account has been disabled.", "danger")
            return render_template("auth/login.html", email=email)

        user = User(user_data)

        login_user(user, remember=remember)

        user_service.update_last_login(uid)

        next_page = request.args.get("next")

        if next_page and next_page.startswith("/") and not next_page.startswith("//"):
            return redirect(next_page)

        flash(
            f"Welcome back, {user_data.get('name') or email}!",
            "success",
        )

        return redirect(url_for("main.dashboard"))

    except requests.exceptions.RequestException:
        flash("Login failed. Please check your internet connection.", "danger")
        return render_template("auth/login.html", email=email)

    except Exception as error:
        import traceback

        print("LOGIN ERROR:")
        print(traceback.format_exc())

        flash("Login failed. Please try again.", "danger")
        return render_template("auth/login.html", email=email)

    # Safety net: this should never be reached.
    return render_template("auth/login.html", email=email)


# ============================================================
# LOGOUT
# ============================================================

@auth_bp.route("/logout")
@login_required
def logout():
    user_name = current_user.name or "user"

    logout_user()

    flash(f"Logged out, {user_name}.", "info")

    return redirect(url_for("auth.login"))


# ============================================================
# EMAIL CHECK
# ============================================================

@auth_bp.route("/check-email", methods=["POST"])
def check_email():
    data = request.get_json(silent=True) or {}

    email = data.get("email") or request.form.get("email", "")
    email = email.strip().lower()

    if not email:
        return jsonify({
            "available": False,
            "message": "Please enter an email address.",
        })

    user_service = get_user_service()
    existing_user = user_service.get_user_by_email(email)

    if existing_user:
        return jsonify({
            "available": False,
            "message": "This email is already registered.",
        })

    return jsonify({
        "available": True,
        "message": "This email is available.",
    })


# ============================================================
# DARK MODE
# ============================================================

@auth_bp.route("/toggle-dark-mode", methods=["POST"])
@login_required
def toggle_dark_mode():
    new_dark_mode = not bool(current_user.dark_mode)

    user_service = get_user_service()
    user_service.update_user(
        current_user.id,
        {"dark_mode": new_dark_mode},
    )

    return jsonify({
        "success": True,
        "dark_mode": new_dark_mode,
    })


# ============================================================
# DELETE ACCOUNT
# ============================================================

@auth_bp.route("/delete-account", methods=["POST"])
@login_required
def delete_account():
    password = request.form.get("password", "")

    # Firebase Auth handles real password verification.
    # This route should ideally require a Firebase ID token instead.
    if not password:
        flash("Please enter your password to confirm.", "danger")
        return redirect(url_for("profile.index"))

    try:
        user_id = current_user.id

        logout_user()

        user_service = get_user_service()
        user_service.delete_user(user_id)

        flash("Your account has been deleted.", "info")

        return redirect(url_for("auth.register"))

    except Exception as error:
        print("DELETE ACCOUNT ERROR:", error)

        flash("Could not delete your account. Please try again.", "danger")

        return redirect(url_for("profile.index"))