# services/auth_service.py — Firebase Authentication Service
# ============================================================

import os
import logging
from functools import wraps
from typing import Optional, Dict, Any
from datetime import datetime

from flask import request, jsonify, g, current_app
from flask_login import current_user as flask_current_user

from services.firebase_admin import get_firebase_admin, FirebaseAdminError

logger = logging.getLogger(__name__)


class AuthServiceError(Exception):
    """Custom exception for authentication errors."""
    pass


class AuthService:
    """Firebase Authentication service for server-side operations."""

    def __init__(self):
        self._firebase_admin = None

    @property
    def firebase_admin(self):
        if self._firebase_admin is None:
            self._firebase_admin = get_firebase_admin()
        return self._firebase_admin

    def verify_id_token(self, id_token: str) -> dict:
        """
        Verify a Firebase ID token.

        Args:
            id_token: Firebase ID token from client

        Returns:
            dict: Decoded token claims

        Raises:
            AuthServiceError: If token is invalid
        """
        try:
            return self.firebase_admin.verify_id_token(id_token)
        except Exception as e:
            logger.error(f"Token verification failed: {e}")
            raise AuthServiceError(f"Invalid token: {e}")

    def get_user(self, uid: str):
        """Get user by UID."""
        try:
            return self.firebase_admin.get_user(uid)
        except Exception as e:
            logger.error(f"Failed to get user: {e}")
            raise AuthServiceError(f"Failed to get user: {e}")

    def verify_user_exists(self, uid: str) -> bool:
        """Check if user exists."""
        return self.firebase_admin.verify_user_exists(uid)

    def get_user_profile(self, uid: str) -> dict:
        """Get user profile from Firestore."""
        from services.firestore_service import get_user_collection
        from services.firebase_admin import get_firebase_admin

        db = get_firebase_admin().firestore
        doc = db.collection('users').document(uid).get()
        if doc.exists:
            data = doc.to_dict()
            data['uid'] = doc.id
            return data
        return None

    def create_user_profile(self, uid: str, data: dict) -> bool:
        """Create user profile in Firestore."""
        from services.firebase_admin import get_firebase_admin
        db = self.firebase_admin.firestore
        data['created_at'] = datetime.utcnow()
        data['updated_at'] = datetime.utcnow()
        db.collection('users').document(uid).set(data)
        return True

    def update_user_profile(self, uid: str, data: dict) -> bool:
        """Update user profile in Firestore."""
        from services.firebase_admin import get_firebase_admin

        db = self.firebase_admin.firestore
        data['updated_at'] = datetime.utcnow()
        db.collection('users').document(uid).update(data)
        return True

    def create_user_with_email_password(self, email: str, password: str, name: str = None) -> str:
        """Create a new user with email and password."""
        try:
            uid = self.firebase_admin.create_user(email, password, name)
            return uid
        except Exception as e:
            logger.error(f"Failed to create user: {e}")
            raise


# Global instance
_auth_service = None


def get_auth_service() -> 'AuthService':
    """Get the global Auth service instance."""
    global _auth_service
    if _auth_service is None:
        _auth_service = AuthService()
    return _auth_service


# ─── Flask Middleware ────────────────────────────────────────────────

def require_firebase_auth(f):
    """
    Decorator to require Firebase ID token authentication for API routes.
    Stores verified user info in flask.g.current_user.
    """
    from functools import wraps
    from flask import request, jsonify, g

    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            auth_header = request.headers.get('Authorization', '')

            if not auth_header.startswith('Bearer '):
                return jsonify({
                    "success": False,
                    "error": "Missing or invalid Authorization header",
                    "code": "MISSING_AUTH_HEADER"
                }), 401

            id_token = auth_header.split('Bearer ')[1].strip()

            try:
                # Verify Firebase ID token
                from services.firebase_admin import get_firebase_admin
                firebase_admin = get_firebase_admin()
                decoded_token = firebase_admin.verify_id_token(request.headers.get('Authorization', '').split('Bearer ')[1])

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

                # Also set Flask-Login user for compatibility (if needed)
                # Note: This is for API routes only; web routes use Flask-Login

            except Exception as e:
                logger.warning(f"Token verification failed: {e}")
                return jsonify({
                    "success": False,
                    "error": "Invalid or expired token",
                    "code": "INVALID_TOKEN"
                }), 401

            return f(*args, **kwargs)

        return decorated_function

    return decorator


def optional_firebase_auth(f):
    """
    Decorator for optional Firebase authentication.
    Sets g.current_user if token is valid, otherwise continues without auth.
    """
    from functools import wraps
    from flask import request, jsonify, g

    @wraps(f)
    def decorated_function(*args, **kwargs):
        auth_header = request.headers.get('Authorization', '')

        if auth_header.startswith('Bearer '):
            id_token = auth_header.split('Bearer ')[1].strip()

            try:
                from services.firebase_admin import get_firebase_admin
                firebase_admin = get_firebase_admin()
                decoded_token = firebase_admin.verify_id_token(request.headers.get('Authorization', '').split('Bearer ')[1])

                g.current_user = {
                    'uid': decoded_token['uid'],
                    'email': decoded_token.get('email'),
                    'email_verified': decoded_token.get('email_verified', False),
                    'name': decoded_token.get('name'),
                    'picture': decoded_token.get('picture'),
                }
            except Exception as e:
                logger.debug(f"Optional auth failed: {e}")
                g.current_user = None

        return f(*args, **kwargs)

    return decorated_function


def get_current_user() -> Optional[dict]:
    """Get current authenticated user from Flask g object."""
    from flask import g
    return getattr(g, 'current_user', None)


def require_same_user(uid_param: str = 'uid'):
    """
    Decorator to ensure user can only access their own data.
    Checks that the authenticated user matches the requested user ID.
    """
    from functools import wraps
    from flask import request, jsonify, g

    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            current_user = get_current_user()
            if not current_user:
                return jsonify({
                    "success": False,
                    "error": "Authentication required",
                    "code": "AUTH_REQUIRED"
                }), 401

            requested_uid = request.view_args.get(uid_param) or request.args.get(uid_param) or request.json.get(uid_param)

            if not requested_uid:
                return jsonify({
                    "success": False,
                    "error": "User ID required",
                    "code": "UID_REQUIRED"
                }), 400

            if current_user['uid'] != requested_uid:
                return jsonify({
                    "success": False,
                    "error": "Unauthorized: Cannot access other user's data",
                    "code": "UNAUTHORIZED"
                }), 403

            return f(*args, **kwargs)

        return decorated_function
    return decorator


def get_user_uid() -> Optional[str]:
    """Get current user's UID."""
    user = get_current_user()
    return user['uid'] if user else None


# ─── Hybrid Auth (Flask-Login + Firebase) ─────────────────────────

def get_current_user_hybrid() -> Optional[dict]:
    """
    Get current user supporting both Flask-Login (web) and Firebase (API).
    Returns user dict with uid, email, etc.
    """
    from flask import g
    from flask_login import current_user as flask_current_user

    # Check Flask g object (set by Firebase middleware)
    if hasattr(g, 'current_user') and g.current_user:
        return g.current_user

    # Check Flask-Login (web templates)
    if flask_current_user and flask_current_user.is_authenticated:
        return {
            'uid': str(flask_current_user.id),
            'email': flask_current_user.email,
            'name': flask_current_user.name,
            'is_flask_login': True
        }

    return None


def require_auth_hybrid(f):
    """
    Decorator supporting both Flask-Login (web) and Firebase (API) authentication.
    """
    from functools import wraps
    from flask import request, jsonify, g
    from flask_login import current_user as flask_current_user

    @wraps(f)
    def decorated_function(*args, **kwargs):
        # Check Firebase token first (API requests)
        auth_header = request.headers.get('Authorization', '')
        if auth_header.startswith('Bearer '):
            id_token = auth_header.split('Bearer ')[1].strip()
            try:
                from services.firebase_admin import get_firebase_admin
                firebase_admin = get_firebase_admin()
                decoded_token = firebase_admin.verify_id_token(id_token)

                g.current_user = {
                    'uid': decoded_token['uid'],
                    'email': decoded_token.get('email'),
                    'email_verified': decoded_token.get('email_verified', False),
                    'name': decoded_token.get('name'),
                    'picture': decoded_token.get('picture'),
                }
                return f(*args, **kwargs)
            except Exception as e:
                return jsonify({
                    "success": False,
                    "error": "Invalid or expired token",
                    "code": "INVALID_TOKEN"
                }), 401

        # Fall back to Flask-Login (web templates)
        if flask_current_user and flask_current_user.is_authenticated:
            g.current_user = {
                'uid': str(flask_current_user.id),
                'email': flask_current_user.email,
                'name': flask_current_user.name,
                'is_flask_login': True
            }
            return f(*args, **kwargs)

        return jsonify({
            "success": False,
            "error": "Authentication required",
            "code": "AUTH_REQUIRED"
        }), 401

    return decorated_function


# ─── Compatibility Helpers ────────────────────────────────────────

def get_current_user_id() -> Optional[str]:
    """Get current user ID from either auth system."""
    from flask import g
    user = getattr(g, 'current_user', None)
    if user:
        return user.get('uid')
    # Fallback to Flask-Login
    from flask_login import current_user
    if current_user and current_user.is_authenticated:
        return str(current_user.id)
    return None


def is_user_owner(resource_uid: str) -> bool:
    """Check if current user owns the resource."""
    current_uid = get_current_user_id()
    return current_uid == resource_uid