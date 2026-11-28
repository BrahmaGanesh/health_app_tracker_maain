# services/user_service.py — Firestore User Service
# ============================================================

import os
import logging
from datetime import datetime, timezone
from typing import Optional, Dict, Any, List
from google.cloud.firestore import Client, DocumentReference, DocumentSnapshot, FieldFilter
from google.cloud.firestore_v1.base_query import FieldFilter

from services.firebase_admin import get_firebase_admin

logger = logging.getLogger(__name__)


class FirestoreUserService:
    """Firestore-based user service replacing SQLAlchemy User model."""

    def __init__(self):
        self._db = None

    @property
    def db(self):
        from services.firebase_admin import get_firebase_admin
        if not self._db:
            firebase_admin = get_firebase_admin()
            if not firebase_admin._initialized:
                raise RuntimeError("Firebase Admin not initialized")
            self._db = firebase_admin.firestore
        return self._db

    def _get_user_ref(self, uid: str):
        """Get user document reference."""
        return self.db.collection('users').document(uid)

    def _get_user_collection(self, uid: str):
        """Get user's subcollection reference."""
        return self.db.collection('users').document(uid)

    def _serialize(self, data: dict) -> dict:
        """Serialize data for Firestore."""
        from datetime import datetime, timezone
        data = data.copy()
        if 'created_at' not in data:
            data['created_at'] = datetime.now(timezone.utc)
        data['updated_at'] = datetime.now(timezone.utc)
        return data

    def _deserialize(self, data: dict) -> dict:
        """Deserialize data from Firestore."""
        result = {}
        for key, value in data.items():
            if hasattr(value, 'isoformat'):  # datetime
                result[key] = value.isoformat()
            else:
                result[key] = value
        return result

    # ── User CRUD Operations ────────────────────────────────────────────────

    def create_user(self, uid: str, email: str, name: str, password: str = None,
                    auth_provider: str = "email", **kwargs) -> Dict:
        """Create a new user document in Firestore."""
        from datetime import datetime, timezone

        user_data = {
            "name": kwargs.get("name", "").strip(),
            "email": kwargs.get("email", "").strip().lower(),
            "is_active": True,
            "is_verified": False,
            "is_admin": False,
            "family_member_limit": 2,
            "onboarding_done": False,
            "dark_mode": False,
            "profile_photo": None,
            "auth_provider": "email",
            "google_email": None,
            "google_id": None,
            "google_access_token": None,
            "google_refresh_token": None,
            "fcm_token": None,
            "web_push_sub": None,
            "created_at": datetime.now(timezone.utc),
            "last_login": datetime.now(timezone.utc),
            "last_updated": datetime.now(timezone.utc),
            "fcm_token": None,
            "web_push_sub": None,
            "verification_token": None,
            "reset_token": None,
            "reset_token_expiry": None,
            "fcm_token": None,
            "web_push_sub": None,
            "verification_token": None,
            "reset_token": None,
            "reset_token_expiry": None,
        }

        # Update with provided data
        if data := kwargs:
            user_data.update({
                "name": kwargs.get("name", "").strip(),
                "email": kwargs.get("email", "").strip().lower(),
                "is_active": True,
                "is_verified": False,
                "is_admin": False,
                "family_member_limit": 2,
                "onboarding_done": False,
                "dark_mode": False,
                "profile_photo": None,
                "auth_provider": "email",
                "google_email": None,
                "google_id": None,
                "google_access_token": None,
                "google_refresh_token": None,
                "fcm_token": None,
                "web_push_sub": None,
                "created_at": datetime.utcnow(),
                "last_login": datetime.utcnow(),
                "last_updated": datetime.utcnow(),
            })

        # Override with provided values
        user_data.update({
            "name": name,
            "email": email,
        })

        # Add password hash if provided (for compatibility)
        if password:
            # We don't store passwords in Firestore, they're in Firebase Auth
            pass

        doc_ref = self.db.collection('users').document()
        doc_ref.set(user_data)
        return doc_ref.id

    def get_user_by_email(self, email: str) -> Optional[Dict]:
        """Get user by email."""
        try:
            users_ref = self.db.collection('users')
            query = users_ref.where(filter=FieldFilter('email', '==', email.lower())).limit(1)
            docs = list(query.stream())
            if docs:
                doc = docs[0]
                data = doc.to_dict()
                data['uid'] = doc.id
                return data
            return None
        except Exception as e:
            logger.error(f"Error getting user by email: {e}")
            return None

    def get_user_by_uid(self, uid: str) -> Optional[Dict]:
        """Get user by UID."""
        try:
            doc = self.db.collection('users').document(uid).get()
            if doc.exists:
                data = doc.to_dict()
                data['uid'] = doc.id
                return data
            return None
        except Exception as e:
            logger.error(f"Error getting user by UID: {e}")
            return None

    def get_user_by_email(self, email: str) -> Optional[Dict]:
        """Get user by email."""
        try:
            users_ref = self.db.collection('users')
            query = users_ref.where(filter=FieldFilter('email', '==', email.lower())).limit(1)
            docs = list(query.stream())
            if docs:
                doc = docs[0]
                data = doc.to_dict()
                data['uid'] = doc.id
                return data
            return None
        except Exception as e:
            logger.error(f"Error getting user by email: {e}")
            return None

    def update_user(self, uid: str, data: dict) -> bool:
        """Update user profile."""
        try:
            from datetime import datetime, timezone
            data = data.copy()
            data['updated_at'] = datetime.now(timezone.utc)
            self.db.collection('users').document(uid).update(data)
            return True
        except Exception as e:
            logger.error(f"Update user failed: {e}")
            return False

    def update_last_login(self, uid: str) -> bool:
        """Update last login timestamp."""
        try:
            from datetime import datetime, timezone
            self.db.collection('users').document(uid).update({
                'last_login': datetime.now(timezone.utc),
                'last_updated': datetime.now(timezone.utc)
            })
            return True
        except Exception as e:
            logger.error(f"Update last login failed: {e}")
            return False

    def update_fcm_token(self, uid: str, fcm_token: str) -> bool:
        """Update FCM token."""
        try:
            from datetime import datetime, timezone
            self.db.collection('users').document(uid).update({
                'fcm_token': fcm_token,
                'last_updated': datetime.now(timezone.utc)
            })
            return True
        except Exception as e:
            logger.error(f"Update FCM token failed: {e}")
            return False

    def update_password(self, uid: str, new_password_hash: str) -> bool:
        """Update password hash."""
        # Note: Passwords are stored in Firebase Auth, not Firestore
        # This is a placeholder for any Firestore-stored password data
        try:
            from datetime import datetime, timezone
            self.db.collection('users').document(uid).update({
                'password_hash': new_password_hash,
                'last_updated': datetime.now(timezone.utc)
            })
            return True
        except Exception as e:
            logger.error(f"Update password failed: {e}")
            return False

    def get_user_by_email(self, email: str) -> Optional[Dict]:
        """Get user by email."""
        try:
            users_ref = self.db.collection('users')
            query = users_ref.where(filter=FieldFilter('email', '==', email.lower())).limit(1)
            docs = list(query.stream())
            if docs:
                doc = docs[0]
                data = doc.to_dict()
                data['uid'] = doc.id
                return data
            return None
        except Exception as e:
            logger.error(f"Error getting user by email: {e}")
            return None

    def get_user_by_uid(self, uid: str) -> Optional[Dict]:
        """Get user by UID."""
        try:
            doc = self.db.collection('users').document(uid).get()
            if doc.exists:
                data = doc.to_dict()
                data['uid'] = doc.id
                return data
            return None
        except Exception as e:
            logger.error(f"Error getting user by UID: {e}")
            return None

    def update_user(self, uid: str, data: dict) -> bool:
        """Update user profile."""
        try:
            from datetime import datetime, timezone
            data = data.copy()
            data['updated_at'] = datetime.now(timezone.utc)
            self.db.collection('users').document(uid).update(data)
            return True
        except Exception as e:
            logger.error(f"Update user failed: {e}")
            return False

    def update_last_login(self, uid: str) -> bool:
        """Update last login timestamp."""
        try:
            from datetime import datetime, timezone
            self.db.collection('users').document(uid).update({
                'last_login': datetime.now(timezone.utc),
                'last_updated': datetime.now(timezone.utc)
            })
            return True
        except Exception as e:
            logger.error(f"Update last login failed: {e}")
            return False

    def update_fcm_token(self, uid: str, fcm_token: str) -> bool:
        """Update FCM token."""
        try:
            from datetime import datetime, timezone
            self.db.collection('users').document(uid).update({
                'fcm_token': fcm_token,
                'last_updated': datetime.now(timezone.utc)
            })
            return True
        except Exception as e:
            logger.error(f"Update FCM token failed: {e}")
            return False

    def delete_user(self, uid: str) -> bool:
        """Delete user (soft delete)."""
        try:
            from datetime import datetime, timezone
            self.db.collection('users').document(uid).update({
                'is_active': False,
                'deleted_at': datetime.now(timezone.utc),
                'updated_at': datetime.now(timezone.utc)
            })
            return True
        except Exception as e:
            logger.error(f"Delete user failed: {e}")
            return False


# Global instance
_user_service = None


def get_user_service() -> FirestoreUserService:
    """Get the global Firestore user service instance."""
    global _user_service
    if _user_service is None:
        _user_service = FirestoreUserService()
    return _user_service


# ─── Convenience Functions ────────────────────────────────────────────────

def get_user_collection(uid: str):
    """Get user's subcollection reference."""
    from services.firebase_admin import get_firebase_admin
    db = get_firebase_admin().firestore
    return db.collection('users').document(uid)


def get_user_collection_ref(uid: str, collection: str):
    """Get a user's subcollection reference."""
    from services.firebase_admin import get_firebase_admin
    db = get_firebase_admin().firestore
    return db.collection('users').document(uid).collection(collection)


# ─── Service Instance ──────────────────────────────────────────────────

_user_service = None

def get_user_service() -> FirestoreUserService:
    """Get the global Firestore user service instance."""
    global _user_service
    if _user_service is None:
        _user_service = FirestoreUserService()
    return _user_service