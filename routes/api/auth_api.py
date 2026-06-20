# ============================================================
# routes/api/auth_api.py — JWT Auth API for APK
# ============================================================

from flask import Blueprint, request, jsonify
from flask_jwt_extended import (
    create_access_token,
    create_refresh_token,
    jwt_required,
    get_jwt_identity
)
from datetime import datetime, timedelta
import secrets

from extensions import csrf, db
from models import User, UserHealthProfile, UserGoal, seed_health_conditions
from flask_mail import Message
# from app import mail

auth_api_bp = Blueprint("auth_api", __name__)

# ------------------------------------------------------------
# RESPONSE HELPERS
# ------------------------------------------------------------
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


# ============================================================
# REGISTER
# ============================================================
@auth_api_bp.route("/register", methods=["POST"])
@csrf.exempt
def register():
    data = request.get_json(force=True, silent=True)

    if not data:
        return api_error("Invalid JSON body", 400)

    name = data.get("name", "").strip()
    email = data.get("email", "").strip().lower()
    password = data.get("password", "")

    errors = {}

    if len(name) < 2:
        errors["name"] = "Name must be at least 2 characters"

    if "@" not in email:
        errors["email"] = "Valid email required"

    if User.query.filter_by(email=email).first():
        errors["email"] = "Email already registered"

    if len(password) < 6:
        errors["password"] = "Password must be at least 6 characters"

    if errors:
        return api_error("Validation failed", 422, errors)

    try:
        user = User(name=name, email=email, is_verified=False)
        user.set_password(password)

        db.session.add(user)
        db.session.flush()

        db.session.add(UserHealthProfile(user_id=user.id))
        db.session.add(UserGoal(user_id=user.id))

        db.session.commit()
        seed_health_conditions()

        access_token = create_access_token(identity=str(user.id))
        refresh_token = create_refresh_token(identity=str(user.id))

        return api_success({
            "user": user.to_dict(),
            "access_token": access_token,
            "refresh_token": refresh_token
        }, "Registration successful", 201)

    except Exception as e:
        db.session.rollback()
        return api_error(f"Registration failed: {str(e)}", 500)


# ============================================================
# LOGIN
# ============================================================
@auth_api_bp.route("/login", methods=["POST"])
@csrf.exempt
def login():
    data = request.get_json(force=True, silent=True)
    print("HEADERS:", dict(request.headers))
    print("RAW DATA:", request.data)
    print("IS JSON:", request.is_json)

    if not data:
        return api_error("Invalid JSON body", 400)

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

    if fcm_token:
        user.fcm_token = fcm_token

    user.last_login = datetime.utcnow()
    db.session.commit()

    access_token = create_access_token(identity=str(user.id))
    refresh_token = create_refresh_token(identity=str(user.id))

    return api_success({
        "user": user.to_dict(),
        "access_token": access_token,
        "refresh_token": refresh_token,
        "profile": user.health_profile.to_dict() if user.health_profile else None,
        "goals": user.goals.to_dict() if user.goals else None,
    }, "Login successful")


# ============================================================
# REFRESH TOKEN
# ============================================================
@auth_api_bp.route("/refresh", methods=["POST"])
@jwt_required(refresh=True)
def refresh():
    user_id = get_jwt_identity()
    access_token = create_access_token(identity=str(user_id))

    return api_success({"access_token": access_token}, "Token refreshed")


# ============================================================
# ME (CURRENT USER)
# ============================================================
@auth_api_bp.route("/me", methods=["GET"])
@jwt_required()
def me():
    user_id = get_jwt_identity()
    user = User.query.get(user_id)

    if not user:
        return api_error("User not found", 404)

    return api_success({
        "user": user.to_dict(),
        "profile": user.health_profile.to_dict() if user.health_profile else None,
        "goals": user.goals.to_dict() if user.goals else None,
        "conditions": user.condition_names,
    })


# ============================================================
# FCM TOKEN UPDATE
# ============================================================
@auth_api_bp.route("/fcm-token", methods=["POST"])
@jwt_required()
def update_fcm_token():
    user_id = get_jwt_identity()
    user = User.query.get(user_id)

    data = request.get_json(force=True, silent=True) or {}
    token = data.get("fcm_token", "")

    if not token:
        return api_error("FCM token required", 400)

    user.fcm_token = token
    db.session.commit()

    return api_success(message="FCM token updated")


# ============================================================
# FORGOT PASSWORD
# ============================================================
@auth_api_bp.route("/forgot-password", methods=["POST"])
@csrf.exempt
def forgot_password():
    data = request.get_json(force=True, silent=True) or {}
    email = data.get("email", "").strip().lower()

    if not email:
        return api_error("Email required", 400)

    user = User.query.filter_by(email=email).first()

    if user:
        token = secrets.token_urlsafe(32)
        user.reset_token = token
        user.reset_token_expiry = datetime.utcnow() + timedelta(hours=2)
        db.session.commit()

        try:
            msg = Message(
                subject="Reset Password",
                recipients=[email],
                html=f"<p>Your reset code:</p><h3>{token}</h3>"
            )
            mail.send(msg)
        except:
            pass

    return api_success(message="If email exists, reset link sent")


# ============================================================
# RESET PASSWORD
# ============================================================
@auth_api_bp.route("/reset-password", methods=["POST"])
@csrf.exempt
def reset_password():
    data = request.get_json(force=True, silent=True) or {}

    token = data.get("token", "")
    email = data.get("email", "").strip().lower()
    password = data.get("password", "")

    if not token or not email or not password:
        return api_error("Missing fields", 400)

    user = User.query.filter_by(email=email, reset_token=token).first()

    if not user:
        return api_error("Invalid token", 400)

    if user.reset_token_expiry and user.reset_token_expiry < datetime.utcnow():
        return api_error("Token expired", 400)

    user.set_password(password)
    user.reset_token = None
    user.reset_token_expiry = None

    db.session.commit()

    return api_success(message="Password reset successful")


# ============================================================
# LOGOUT
# ============================================================
@auth_api_bp.route("/logout", methods=["POST"])
@jwt_required()
def logout():
    user_id = get_jwt_identity()
    user = User.query.get(user_id)

    if user:
        user.fcm_token = None
        db.session.commit()

    return api_success(message="Logged out successfully")


# ============================================================
# CHANGE PASSWORD
# ============================================================
@auth_api_bp.route("/change-password", methods=["POST"])
@jwt_required()
def change_password():
    user_id = get_jwt_identity()
    user = User.query.get(user_id)

    data = request.get_json(force=True, silent=True) or {}

    current_pw = data.get("current_password", "")
    new_pw = data.get("new_password", "")

    if not user.check_password(current_pw):
        return api_error("Current password wrong", 401)

    if len(new_pw) < 6:
        return api_error("Password too short", 400)

    user.set_password(new_pw)
    db.session.commit()

    return api_success(message="Password changed successfully")