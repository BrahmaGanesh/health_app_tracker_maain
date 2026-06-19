# ============================================================
# routes/google_auth.py — Google OAuth Sign-In
# Handles both:
#   Website: /auth/google → redirect → /auth/google/callback
#   APK API: POST /api/v1/auth/google  (sends id_token from Flutter)
#
# After login, email reports can be sent via user's own Gmail
# using the stored OAuth access token — no SMTP needed!
# ============================================================

import secrets
from flask import (
    Blueprint, redirect, url_for, request,
    session, flash, jsonify, current_app
)
from flask_login import login_user, current_user
from flask_jwt_extended import create_access_token, create_refresh_token
from datetime import datetime

from extensions import db
from models import User, UserHealthProfile, UserGoal, seed_health_conditions

google_auth_bp = Blueprint("google_auth", __name__)


# ── HELPERS ────────────────────────────────────────────────────────

def _get_google_flow(redirect_uri=None):
    """Create Google OAuth flow using google-auth-oauthlib."""
    from google_auth_oauthlib.flow import Flow

    config = {
        "web": {
            "client_id":     current_app.config["GOOGLE_CLIENT_ID"],
            "client_secret": current_app.config["GOOGLE_CLIENT_SECRET"],
            "redirect_uris": [redirect_uri or current_app.config["GOOGLE_REDIRECT_URI"]],
            "auth_uri":  "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
        }
    }

    flow = Flow.from_client_config(
        config,
        scopes=current_app.config["GOOGLE_SCOPES"],
        redirect_uri=redirect_uri or current_app.config["GOOGLE_REDIRECT_URI"],
        autogenerate_code_verifier=False,
    )
    return flow


def _get_user_info(credentials):
    """Fetch Google profile using credentials."""
    from googleapiclient.discovery import build
    service = build("oauth2", "v2", credentials=credentials)
    return service.userinfo().get().execute()


def _upsert_google_user(google_id, email, name, picture, access_token, refresh_token=None):
    """
    Find or create a user from Google OAuth data.
    Returns (user, is_new_user).
    """
    # 1. Check by google_id
    user = User.query.filter_by(google_id=google_id).first()

    # 2. Check by email (link existing account)
    if not user:
        user = User.query.filter_by(email=email).first()

    is_new = user is None

    if is_new:
        # Create new user
        user = User(
            name=name,
            email=email,
            password_hash="google_oauth_no_password",  # no password for OAuth users
            is_active=True,
            is_verified=True,   # Google accounts are already verified
            auth_provider="google",
        )
        db.session.add(user)
        db.session.flush()
        db.session.add(UserHealthProfile(user_id=user.id))
        db.session.add(UserGoal(user_id=user.id))
        seed_health_conditions()

    # Update Google fields
    user.google_id           = google_id
    user.google_email        = email
    user.google_access_token = access_token
    if refresh_token:
        user.google_refresh_token = refresh_token
    if picture and not user.profile_photo:
        user.profile_photo = picture
    if user.auth_provider != "google":
        user.auth_provider = "google"
    if not user.is_verified:
        user.is_verified = True
    user.last_login = datetime.utcnow()

    db.session.commit()
    return user, is_new


# ════════════════════════════════════════════════════════════
# WEBSITE — Step 1: Redirect to Google
# ════════════════════════════════════════════════════════════

@google_auth_bp.route("/auth/google")
def google_login():
    """Redirect user to Google's OAuth consent screen."""
    if current_user.is_authenticated:
        return redirect(url_for("main.dashboard"))
    print(current_app.config["GOOGLE_REDIRECT_URI"])

    if not current_app.config.get("GOOGLE_CLIENT_ID"):
        flash("Google Sign-In is not configured.", "danger")
        return redirect(url_for("auth.login"))

    try:
        flow = _get_google_flow()
        authorization_url, state = flow.authorization_url(
            access_type="offline",      # gets refresh_token for Gmail API
            include_granted_scopes="true",
            prompt="select_account",
        )
        session["google_oauth_state"] = state
        session["code_verifier"] = flow.code_verifier
        return redirect(authorization_url)
    except Exception as e:
        flash(f"Google Sign-In failed: {str(e)}", "danger")
        return redirect(url_for("auth.login"))


# ════════════════════════════════════════════════════════════
# WEBSITE — Step 2: Google redirects back here
# ════════════════════════════════════════════════════════════

@google_auth_bp.route("/auth/google/callback")
def google_callback():
    """Handle Google OAuth callback — create/login user."""
    # Validate state to prevent CSRF
    state = session.pop("google_oauth_state", None)
    if not state or state != request.args.get("state"):
        flash("Invalid OAuth state. Please try again.", "danger")
        return redirect(url_for("auth.login"))

    if "error" in request.args:
        flash("Google Sign-In was cancelled.", "info")
        return redirect(url_for("auth.login"))

    try:
        flow = _get_google_flow()
        flow.fetch_token(authorization_response=request.url)
        credentials = flow.credentials

        user_info    = _get_user_info(credentials)
        google_id    = user_info.get("id")
        email        = user_info.get("email")
        name         = user_info.get("name", email.split("@")[0])
        picture      = user_info.get("picture")
        access_token = credentials.token
        refresh_token= credentials.refresh_token

        if not google_id or not email:
            flash("Could not retrieve Google account info.", "danger")
            return redirect(url_for("auth.login"))

        user, is_new = _upsert_google_user(
            google_id, email, name, picture, access_token, refresh_token
        )

        login_user(user, remember=True)

        if is_new or not user.onboarding_done:
            flash(f"Welcome to HealthTrack, {user.name}! 🎉 Let's set up your profile.", "success")
            return redirect(url_for("profile.onboarding_step1"))

        flash(f"Welcome back, {user.name}! 👋", "success")
        return redirect(url_for("main.dashboard"))

    except Exception as e:
        flash(f"Google Sign-In error: {str(e)}", "danger")
        return redirect(url_for("auth.login"))


# ════════════════════════════════════════════════════════════
# APK API — POST /api/v1/auth/google
# Flutter sends id_token from google_sign_in package
# ════════════════════════════════════════════════════════════

@google_auth_bp.route("/api/v1/auth/google", methods=["POST"])
def api_google_login():
    """
    APK sends the id_token from Flutter's google_sign_in.
    We verify it server-side and return JWT tokens.
    """
    data     = request.get_json() or {}
    id_token = data.get("id_token", "")
    fcm_token= data.get("fcm_token", "")

    if not id_token:
        return jsonify({"success": False, "message": "id_token required"}), 400

    if not current_app.config.get("GOOGLE_CLIENT_ID"):
        return jsonify({"success": False, "message": "Google Sign-In not configured on server"}), 503

    try:
        from google.oauth2 import id_token as google_id_token
        from google.auth.transport import requests as google_requests

        # Verify the id_token with Google
        idinfo = google_id_token.verify_oauth2_token(
            id_token,
            google_requests.Request(),
            current_app.config["GOOGLE_CLIENT_ID"],
        )

        google_id   = idinfo.get("sub")
        email       = idinfo.get("email")
        name        = idinfo.get("name", email.split("@")[0] if email else "User")
        picture     = idinfo.get("picture")

        if not google_id or not email:
            return jsonify({"success": False, "message": "Invalid Google token"}), 401

        # Note: APK flow doesn't get access_token for Gmail API
        # (that requires server-side flow); use empty string here
        user, is_new = _upsert_google_user(google_id, email, name, picture, "")

        # Save FCM token
        if fcm_token:
            user.fcm_token = fcm_token
            db.session.commit()

        access_token_jwt  = create_access_token(identity=user.id)
        refresh_token_jwt = create_refresh_token(identity=user.id)

        return jsonify({
            "success": True,
            "message": "Welcome to HealthTrack! 🎉" if is_new else f"Welcome back, {user.name}!",
            "data": {
                "user":           user.to_dict(),
                "access_token":   access_token_jwt,
                "refresh_token":  refresh_token_jwt,
                "is_new_user":    is_new,
                "profile":        user.health_profile.to_dict() if user.health_profile else None,
            }
        }), 200

    except ValueError as e:
        return jsonify({"success": False, "message": f"Invalid Google token: {str(e)}"}), 401
    except Exception as e:
        return jsonify({"success": False, "message": f"Sign-in failed: {str(e)}"}), 500


# ════════════════════════════════════════════════════════════
# GMAIL API — Send email using user's own Google account
# Called from utils/email_sender.py when auth_provider == "google"
# ════════════════════════════════════════════════════════════

def send_email_via_gmail(user, subject, html_body, recipients):
    """
    Send an email using the user's own Gmail account via the Gmail API.
    This means reports arrive FROM the user's own email address.
    Requires: google_access_token stored on user.

    Returns True on success, False on failure.
    """
    if not user.google_access_token:
        return False

    try:
        import base64
        from email.mime.multipart import MIMEMultipart
        from email.mime.text import MIMEText
        from google.oauth2.credentials import Credentials
        from googleapiclient.discovery import build

        # Rebuild credentials from stored token
        creds = Credentials(
            token=user.google_access_token,
            refresh_token=user.google_refresh_token,
            token_uri="https://oauth2.googleapis.com/token",
            client_id=current_app.config["GOOGLE_CLIENT_ID"],
            client_secret=current_app.config["GOOGLE_CLIENT_SECRET"],
        )

        # Auto-refresh if expired
        from google.auth.transport.requests import Request
        if creds.expired and creds.refresh_token:
            creds.refresh(Request())
            # Save new access token
            user.google_access_token = creds.token
            db.session.commit()

        service = build("gmail", "v1", credentials=creds)

        # Build the MIME message
        for recipient in recipients:
            msg = MIMEMultipart("alternative")
            msg["Subject"] = subject
            msg["From"]    = user.email
            msg["To"]      = recipient
            msg.attach(MIMEText(html_body, "html"))

            raw     = base64.urlsafe_b64encode(msg.as_bytes()).decode()
            service.users().messages().send(userId="me", body={"raw": raw}).execute()

        return True

    except Exception as e:
        import logging
        logging.getLogger(__name__).error(f"Gmail API send failed: {e}")
        return False