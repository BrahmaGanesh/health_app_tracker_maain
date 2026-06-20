# ============================================================
# routes/api/auth_api.py — JWT Auth API for APK
# ============================================================

from flask import Blueprint, request, jsonify
from flask_jwt_extended import (
    create_access_token, create_refresh_token,
    jwt_required, get_jwt_identity, get_current_user
)
from datetime import datetime, timedelta
import secrets

from extensions import db, bcrypt
from models import User, UserHealthProfile, UserGoal, seed_health_conditions

auth_api_bp = Blueprint("auth_api", __name__)


def api_success(data=None, message="Success", code=200):
    resp = {"success": True, "message": message}
    if data is not None:
        resp["data"] = data
    return jsonify(resp), code


def api_error(message="Error", code=400, errors=None):
    resp = {"success": False, "message": message}
    if errors:
        resp["errors"] = errors
    return jsonify(resp), code


# ── REGISTER ─────────────────────────────────────────────────
@auth_api_bp.route("/register", methods=["POST"])
def register():
    data = request.get_json(silent=True)

    print("========== REGISTER ==========")
    print(data)

    if data is None:
        return api_error("Invalid JSON", 400)

    name = data.get("name", "").strip()
    email = data.get("email", "").strip().lower()
    password = data.get("password", "")

    errors = {}

    if not name or len(name) < 2:
        errors["name"] = "Name must be at least 2 characters."

    if not email or "@" not in email:
        errors["email"] = "Valid email required."

    if User.query.filter_by(email=email).first():
        errors["email"] = "Email already registered."

    if not password or len(password) < 6:
        errors["password"] = "Password must be at least 6 characters."

    if errors:
        return api_error("Validation failed", 422, errors)

    try:
        user = User(name=name, email=email, is_verified=False)
        user.set_password(password)
        db.session.add(user)
        db.session.flush()

        profile = UserHealthProfile(user_id=user.id)
        db.session.add(profile)
        goals   = UserGoal(user_id=user.id)
        db.session.add(goals)
        db.session.commit()

        seed_health_conditions()

        access_token  = create_access_token(identity=user.id)
        refresh_token = create_refresh_token(identity=user.id)

        return api_success({
            "user":          user.to_dict(),
            "access_token":  access_token,
            "refresh_token": refresh_token,
        }, "Registration successful", 201)

    except Exception as e:
        db.session.rollback()
        return api_error(f"Registration failed: {str(e)}", 500)


# ── LOGIN ─────────────────────────────────────────────────────
@auth_api_bp.route("/login", methods=["POST"])
def login():
    data = request.get_json(silent=True)

    print("========== LOGIN ==========")
    print(data)

    if data is None:
        return api_error("Invalid JSON", 400)

    email = data.get("email", "").strip().lower()
    password = data.get("password", "")
    fcm_token = data.get("fcm_token", "")

    if not email or not password:
        return api_error("Email and password required", 400)

    user = User.query.filter_by(email=email).first()
    if not user or not user.check_password(password):
        return api_error("Invalid email or password", 401)
    if not user.is_active:
        return api_error("Account deactivated", 403)

    # Save FCM token for push notifications
    if fcm_token:
        user.fcm_token = fcm_token

    user.last_login = datetime.utcnow()
    db.session.commit()

    access_token  = create_access_token(identity=user.id)
    refresh_token = create_refresh_token(identity=user.id)

    return api_success({
        "user":          user.to_dict(),
        "access_token":  access_token,
        "refresh_token": refresh_token,
        "profile":       user.health_profile.to_dict() if user.health_profile else None,
        "goals":         user.goals.to_dict() if user.goals else None,
    }, "Login successful")


# ── REFRESH TOKEN ─────────────────────────────────────────────
@auth_api_bp.route("/refresh", methods=["POST"])
@jwt_required(refresh=True)
def refresh():
    user_id      = get_jwt_identity()
    access_token = create_access_token(identity=user_id)
    return api_success({"access_token": access_token}, "Token refreshed")


# ── ME (get current user) ─────────────────────────────────────
@auth_api_bp.route("/me", methods=["GET"])
@jwt_required()
def me():
    user = get_current_user()
    if not user:
        return api_error("User not found", 404)
    return api_success({
        "user":    user.to_dict(),
        "profile": user.health_profile.to_dict() if user.health_profile else None,
        "goals":   user.goals.to_dict() if user.goals else None,
        "conditions": user.condition_names,
    })


# ── UPDATE FCM TOKEN ──────────────────────────────────────────
@auth_api_bp.route("/fcm-token", methods=["POST"])
@jwt_required()
def update_fcm_token():
    user      = get_current_user()
    data      = request.get_json() or {}
    fcm_token = data.get("fcm_token", "")

    if not fcm_token:
        return api_error("FCM token required", 400)

    user.fcm_token = fcm_token
    db.session.commit()
    return api_success(message="FCM token updated")


# ── FORGOT PASSWORD ────────────────────────────────────────────
@auth_api_bp.route("/forgot-password", methods=["POST"])
def forgot_password():
    from flask_mail import Message
    from app import mail

    data  = request.get_json() or {}
    email = data.get("email", "").strip().lower()

    if not email:
        return api_error("Email required", 400)

    user = User.query.filter_by(email=email).first()
    # Always return success to prevent email enumeration
    if user:
        token = secrets.token_urlsafe(32)
        user.reset_token        = token
        user.reset_token_expiry = datetime.utcnow() + timedelta(hours=2)
        db.session.commit()

        try:
            msg = Message(
                subject="Reset Your HealthTrack Password",
                recipients=[email],
                html=f"""
                <div style="font-family:sans-serif;max-width:500px;margin:0 auto;">
                  <h2 style="color:#142d4c;">🔑 Password Reset</h2>
                  <p>You requested a password reset for your HealthTrack account.</p>
                  <p><strong>Reset Token:</strong> <code style="background:#f0f4f8;padding:8px 12px;border-radius:6px;font-size:16px;">{token}</code></p>
                  <p>Enter this token in the app to reset your password. Valid for 2 hours.</p>
                  <p style="color:#999;font-size:12px;">If you did not request this, ignore this email.</p>
                </div>
                """
            )
            mail.send(msg)
        except Exception:
            pass

    return api_success(message="If that email is registered, a reset code has been sent.")


# ── RESET PASSWORD ─────────────────────────────────────────────
@auth_api_bp.route("/reset-password", methods=["POST"])
def reset_password():
    data     = request.get_json() or {}
    token    = data.get("token", "").strip()
    email    = data.get("email", "").strip().lower()
    password = data.get("password", "")

    if not token or not email or not password:
        return api_error("Token, email, and new password are required", 400)
    if len(password) < 6:
        return api_error("Password must be at least 6 characters", 400)

    user = User.query.filter_by(email=email, reset_token=token).first()
    if not user:
        return api_error("Invalid token or email", 400)
    if user.reset_token_expiry and user.reset_token_expiry < datetime.utcnow():
        return api_error("Token has expired. Request a new one.", 400)

    user.set_password(password)
    user.reset_token        = None
    user.reset_token_expiry = None
    db.session.commit()

    return api_success(message="Password reset successful. Please log in.")


# ── LOGOUT (clear FCM token) ──────────────────────────────────
@auth_api_bp.route("/logout", methods=["POST"])
@jwt_required()
def logout():
    user = get_current_user()
    if user:
        user.fcm_token = None
        db.session.commit()
    return api_success(message="Logged out successfully")


# ── CHANGE PASSWORD ────────────────────────────────────────────
@auth_api_bp.route("/change-password", methods=["POST"])
@jwt_required()
def change_password():
    user        = get_current_user()
    data        = request.get_json() or {}
    current_pw  = data.get("current_password", "")
    new_pw      = data.get("new_password", "")

    if not user.check_password(current_pw):
        return api_error("Current password is incorrect", 401)
    if len(new_pw) < 6:
        return api_error("New password must be at least 6 characters", 400)

    user.set_password(new_pw)
    db.session.commit()
    return api_success(message="Password changed successfully")