# services/firebase_admin.py — Firebase Admin SDK Initialization
# ============================================================

import os
import base64
import json
import logging
from functools import lru_cache

import firebase_admin
from firebase_admin import credentials, auth as firebase_auth, firestore

logger = logging.getLogger(__name__)


class FirebaseAdminError(Exception):
    """Custom exception for Firebase Admin errors."""
    pass


class FirebaseAdminService:
    """Firebase Admin SDK service for server-side operations."""

    _instance = None
    _app = None
    _firestore_client = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    def __init__(self):
        if not hasattr(self, '_initialized'):
            self._initialized = False
            self._app = None
            self._firestore_client = None

    def initialize(self, credentials_base64: str = None, project_id: str = None) -> bool:
        """
        Initialize Firebase Admin SDK.

        Args:
            credentials_base64: Base64 encoded service account JSON
            project_id: Firebase project ID

        Returns:
            bool: True if initialization successful
        """
        if self._initialized and self._app:
            logger.info("Firebase Admin already initialized")
            return True

        try:
            cred = None

            if credentials_base64:
                # Decode base64 encoded service account
                try:
                    cred_json = base64.b64decode(credentials_base64).decode('utf-8')
                    cred_dict = json.loads(cred_json)
                    cred = credentials.Certificate(cred_dict)
                    logger.info("Firebase credentials loaded from base64 env var")
                except Exception as e:
                    logger.error(f"Failed to decode base64 credentials: {e}")
                    raise FirebaseAdminError(f"Invalid base64 credentials: {e}")
            else:
                # Try to load from file path (for local development)
                cred_path = os.environ.get("FIREBASE_CREDENTIALS", "firebase-credentials.json")
                if os.path.exists(cred_path):
                    try:
                        cred = credentials.Certificate(cred_path)
                        logger.info(f"Firebase credentials loaded from file: {cred_path}")
                    except Exception as e:
                        logger.warning(f"Failed to load Firebase credentials from file: {e}")
                        logger.warning("Firebase features will be disabled.")
                        # Don't return False, just skip Firebase init
                        cred = None
                else:
                    logger.warning("No Firebase credentials found")
                    logger.warning("Firebase features will be disabled.")
                    return False

            if cred:
                # Initialize with project ID if provided
                options = {}
                if project_id:
                    options['projectId'] = project_id

                try:
                    self._app = firebase_admin.initialize_app(cred, options)
                    self._firestore_client = firestore.client(self._app)
                    self._initialized = True
                    logger.info("Firebase Admin SDK initialized successfully")
                    return True
                except Exception as e:
                    logger.warning(f"Firebase Admin initialization failed: {e}")
                    logger.warning("Firebase features will be disabled.")
                    return False

        except Exception as e:
            logger.error(f"Firebase Admin initialization failed: {e}")
            logger.warning("Firebase features will be disabled.")
            return False

    @property
    def app(self):
        """Get the Firebase app instance."""
        if not self._initialized:
            raise FirebaseAdminError("Firebase Admin not initialized")
        return self._app

    @property
    def firestore(self):
        """Get Firestore client."""
        if not self._initialized:
            raise FirebaseAdminError("Firebase Admin not initialized")
        return self._firestore_client

    @property
    def auth(self):
        """Get Firebase Auth."""
        if not self._initialized:
            raise FirebaseAdminError("Firebase Admin not initialized")
        return firebase_auth

    def verify_id_token(self, id_token: str, check_revoked: bool = True) -> dict:
        """
        Verify a Firebase ID token.

        Args:
            id_token: Firebase ID token from client
            check_revoked: Whether to check if token was revoked

        Returns:
            dict: Decoded token claims

        Raises:
            FirebaseAdminError: If token is invalid
        """
        if not self._initialized:
            raise FirebaseAdminError("Firebase Admin not initialized")

        try:
            decoded_token = firebase_auth.verify_id_token(
                id_token,
                app=self._app,
                check_revoked=check_revoked
            )
            return decoded_token
        except firebase_auth.ExpiredIdTokenError:
            raise FirebaseAdminError("Token expired")
        except firebase_auth.RevokedIdTokenError:
            raise FirebaseAdminError("Token revoked")
        except firebase_auth.InvalidIdTokenError as e:
            raise FirebaseAdminError(f"Invalid token: {e}")
        except Exception as e:
            raise FirebaseAdminError(f"Token verification failed: {e}")

    def get_user(self, uid: str):
        """Get user by UID."""
        if not self._initialized:
            raise FirebaseAdminError("Firebase Admin not initialized")
        try:
            return firebase_auth.get_user(uid, app=self._app)
        except Exception as e:
            raise FirebaseAdminError(f"Failed to get user: {e}")

    def create_user(self, email: str, password: str, display_name: str = None) -> str:
        """Create a new user."""
        if not self._initialized:
            raise FirebaseAdminError("Firebase Admin not initialized")
        try:
            user = firebase_auth.create_user(
                email=email,
                password=password,
                display_name=display_name,
                app=self._app
            )
            return user.uid
        except Exception as e:
            raise FirebaseAdminError(f"Failed to create user: {e}")

    def verify_user_exists(self, uid: str) -> bool:
        """Check if user exists."""
        try:
            self.get_user(uid)
            return True
        except:
            return False


# Global instance
_firebase_admin_service = None


def get_firebase_admin() -> FirebaseAdminService:
    """Get the global Firebase Admin service instance."""
    global _firebase_admin_service
    if _firebase_admin_service is None:
        _firebase_admin_service = FirebaseAdminService()
    return _firebase_admin_service


def init_firebase_admin(credentials_base64: str = None, project_id: str = None) -> FirebaseAdminService:
    """Initialize and return Firebase Admin service."""
    service = get_firebase_admin()
    service.initialize(credentials_base64, project_id)
    return service