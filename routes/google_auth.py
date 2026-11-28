# routes/google_auth.py — Firebase Auth Google Sign-In
# ============================================================
# Uses Firebase Authentication with Google provider instead of direct OAuth.
# Client (website/APK) handles Google sign-in via Firebase SDK,
# then sends the Firebase ID token to backend for verification.

import traceback
from flask import (
    Blueprint, redirect, url_for, request,
    session, flash, jsonify, current_app
)
from flask_login import login_user, current_user
from flask_jwt_extended import create_access_token, create_refresh_token
from datetime import datetime, timezone

from extensions import bcrypt, login_manager
from services.firebase_admin import get_firebase_admin, FirebaseAdminError
from services.user_service import get_user_service

google_auth_bp = Blueprint("google_auth", __name__)


# ── HELPERS ──────────────────────────────────────────────────────

def _upsert_firebase_user(uid, email, name, picture, auth_provider="google"):
    """
    Find or create a user from Firebase Auth data.
    Returns (user_data, is_new_user).
    """
    user_service = get_user_service()

    # Check if user exists by email in Firestore
    user_data = user_service.get_user_by_email(email)

    if user_data:
        # Update existing user
        user_data['firebase_uid'] = user_data.get('uid')
        user_data['auth_provider'] = 'google'
        user_data['is_verified'] = True
        user_data['last_login'] = datetime.now(timezone.utc)
        user_data['updated_at'] = datetime.now(timezone.utc)

        # Update in Firestore
        user_service.update_user(user_data['uid'], {
            'firebase_uid': user_data.get('uid'),
            'auth_provider': 'google',
            'is_verified': True,
            'last_login': datetime.now(timezone.utc),
            'updated_at': datetime.now(timezone.utc)
        })

        user_data['is_new'] = False
        return user_data, False

    else:
        # Create new user in Firestore
        uid = user_data.get('uid')  # Firebase UID from token
        user_service = get_user_service()
        user_data = {
            "uid": uid,
            "name": name,
            "email": email,
            "is_active": True,
            "is_verified": True,
            "is_admin": False,
            "family_member_limit": 2,
            "onboarding_done": False,
            "dark_mode": False,
            "profile_photo": None,
            "created_at": datetime.now(timezone.utc),
            "last_login": datetime.now(timezone.utc),
            "last_updated": datetime.now(timezone.utc),
            "auth_provider": "google",
            "google_id": None,
            "google_email": None,
            "google_access_token": None,
            "google_refresh_token": None,
            "fcm_token": None,
            "web_push_sub": None,
            "created_at": datetime.now(timezone.utc),
            "last_login": datetime.now(timezone.utc),
            "last_updated": datetime.now(timezone.utc),
        }

        # Create user in Firestore
        user_service.create_user(uid, email, name, auth_provider="google")

        # Create default health profile
        db = get_firebase_admin().firestore
        user_col = db.collection('users').document(uid)
        user_col.collection('profile').document('profile').set({
            "gender": None,
            "date_of_birth": None,
            "height_cm": None,
            "current_weight_kg": None,
            "activity_level": "sedentary",
            "diet_preference": "vegetarian",
            "onboarding_step": 1,
            "blood_group": None,
            "emergency_contact": None,
            "created_at": datetime.now(timezone.utc),
            "updated_at": datetime.now(timezone.utc)
        })

        # Create default goals
        user_col.collection('goals').document('goals').set({
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
            "goal_start_date": datetime.now(timezone.utc).date().isoformat(),
            "created_at": datetime.now(timezone.utc),
            "updated_at": datetime.now(timezone.utc)
        })

        # Create subscription
        user_col.collection('subscription').document('current').set({
            "plan": "free",
            "is_active": True,
            "created_at": datetime.now(timezone.utc)
        })

        # Create settings
        user_col.collection('settings').document('preferences').set({
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

        # Seed health conditions
        user_col.collection('health_conditions').document('seed').set({
            "seeded": True,
            "seeded_at": datetime.now(timezone.utc)
        })

        return user_data, True


# ─── WEBSITE — Step 1: Firebase handles Google sign-in on client ──────────────

@google_auth_bp.route("/auth/google")
def google_login():
    """
    Legacy endpoint - redirects to client-side Firebase sign-in.
    The client handles Google sign-in via Firebase SDK.
    """
    if current_user.is_authenticated:
        return redirect(url_for("main.dashboard"))

    # Check if Firebase is configured
    if not current_app.config.get("FIREBASE_API_KEY"):
        flash("Firebase is not configured.", "danger")
        return redirect(url_for("auth.login"))

    # Client handles Firebase Google sign-in
    # This endpoint just renders the login page or redirects
    from flask import render_template
    return render_template("auth/google_signin.html",
                           firebase_api_key=current_app.config.get("FIREBASE_API_KEY"),
                           auth_domain=current_app.config.get("FIREBASE_AUTH_DOMAIN"),
                           project_id=current_app.config.get("FIREBASE_PROJECT_ID"))


# ─── Firebase ID Token Verification Endpoint ──────────────────────────
# Called by website/APK after client-side Firebase Google sign-in

@google_auth_bp.route("/auth/firebase/google", methods=["POST"])
def firebase_google_login():
    """
    Verify Firebase ID token from client-side Google sign-in.
    Client handles Google sign-in via Firebase SDK, sends ID token to backend.
    """
    if current_user.is_authenticated:
        return jsonify({"success": True, "redirect": url_for("main.dashboard")})

    data = request.get_json() or {}
    id_token = data.get("idToken", "")
    fcm_token = data.get("fcmToken", "")

    if not id_token:
        return jsonify({"success": False, "message": "Firebase ID token required"}), 400

    try:
        firebase_admin = get_firebase_admin()
        if not firebase_admin._initialized:
            return jsonify({"success": False, "message": "Firebase not initialized"}), 503

        # Verify the Firebase ID token
        decoded_token = firebase_admin.verify_id_token(id_token)

        uid = decoded_token.get("uid")
        email = decoded_token.get("email")
        name = decoded_token.get("name", email.split("@")[0])
        picture = decoded_token.get("picture")

        if not uid or not email:
            return jsonify({"success": False, "message": "Invalid Firebase token"}), 401

        # Upsert user
        user_data, is_new = _upsert_firebase_user(
            uid, email, name, None
        )

        # Save FCM token if provided
        if fcm_token:
            user_service = get_user_service()
            user_service.update_fcm_token(user_data['uid'], fcm_token)

        # Create Flask-Login user
        from models import User
        user = User(user_data)
        login_user(user, remember=True)

        # Return success with redirect info
        return jsonify({
            "success": True,
            "message": "Welcome to HealthTrack! 🎉" if is_new else f"Welcome back, {user_data.get('name', 'User')}!",
            "data": {
                "user": user_data,
                "is_new_user": is_new,
                "redirect": url_for("profile.onboarding_step1") if is_new or not user.onboarding_done else url_for("main.dashboard")
            }
        }), 200

    except Exception as e:
        traceback.print_exc()
        return jsonify({"success": False, "message": f"Firebase authentication failed: {str(e)}"}), 500


# ─────────────────────────────────────────────────────────────────────
# APK API — POST /api/v1/auth/firebase
# Flutter sends Firebase ID token from google_sign_in package
# ═════════════════════════════════════════════════════════════════

@google_auth_bp.route("/api/v1/auth/firebase", methods=["POST"])
def api_firebase_login():
    """
    APK sends the Firebase ID token from Flutter's google_sign_in.
    We verify it server-side and return JWT tokens.
    """
    data = request.get_json() or {}
    id_token = data.get("idToken", "")
    fcm_token = data.get("fcmToken", "")

    if not id_token:
        return jsonify({"success": False, "message": "Firebase ID token required"}), 400

    try:
        firebase_admin = get_firebase_admin()
        if not firebase_admin._initialized:
            return jsonify({"success": False, "message": "Firebase not initialized"}), 503

        # Verify the Firebase ID token
        decoded_token = firebase_admin.verify_id_token(id_token)

        uid = decoded_token.get("uid")
        email = decoded_token.get("email")
        name = decoded_token.get("name", email.split("@")[0] if email else "User")
        picture = decoded_token.get("picture")

        if not uid or not email:
            return jsonify({"success": False, "message": "Invalid Firebase token"}), 401

        # Upsert user
        user_data, is_new = _upsert_firebase_user(
            uid, email, name, None
        )

        # Save FCM token if provided
        if fcm_token:
            user_service = get_user_service()
            user_service.update_fcm_token(user_data['uid'], fcm_token)

        access_token = create_access_token(identity=user_data['uid'])
        refresh_token = create_refresh_token(identity=user_data['uid'])

        return jsonify({
            "success": True,
            "message": "Welcome to HealthTrack! 🎉" if is_new else f"Welcome back, {user_data.get('name', 'User')}!",
            "data": {
                "user": user_data,
                "access_token": access_token,
                "refresh_token": refresh_token,
                "is_new_user": is_new,
            }
        }), 200

    except Exception as e:
        traceback.print_exc()
        return jsonify({
            "success": False,
            "message": f"Firebase authentication failed: {str(e)}"
        }), 500


# ─────────────────────────────────────────────────────────────────────
# GMAIL API — Send email using user's own Google account
# ════════════════════════════════════════════════════════════════

def send_email_via_gmail(user, subject, html_body, recipients):
    """
    Send an email using the user's own Gmail account via the Gmail API.
    This means reports arrive FROM the user's own email address.
    Requires: google_access_token stored on user.
    """
    if not user.get('google_access_token'):
        return False

    try:
        import base64
        from email.mime.multipart import MIMEMultipart
        from email.mime.text import MIMEText
        from google.oauth2.credentials import Credentials
        from googleapiclient.discovery import build
        from google.auth.transport.requests import Request

        # Rebuild credentials from stored token
        creds = Credentials(
            token=user['google_access_token'],
            refresh_token=user.get('google_refresh_token'),
            token_uri="https://oauth2.googleapis.com/token",
            client_id=current_app.config["GOOGLE_CLIENT_ID"],
            client_secret=current_app.config["GOOGLE_CLIENT_SECRET"],
        )

        # Auto-refresh if expired
        if creds.expired and creds.refresh_token:
            creds.refresh(Request())

        service = build("gmail", "v1", credentials=creds)

        for recipient in recipients:
            msg = MIMEMultipart("alternative")
            msg["Subject"] = subject
            msg["From"] = user['email']
            msg["To"] = recipient
            msg.attach(MIMEText(html_body, "html"))

            raw = base64.urlsafe_b64encode(msg.as_bytes()).decode()
            service.users().messages().send(userId="me", body={"raw": raw}).execute()

        return True

    except Exception as e:
        import logging
        logging.getLogger(__name__).error(f"Gmail API send failed: {e}")
        return False