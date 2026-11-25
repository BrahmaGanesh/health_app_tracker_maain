# services/firestore_service.py — Firestore Service Base Class
# ============================================================

import os
import json
import logging
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Union, TypeVar, Generic
from abc import ABC, abstractmethod
from functools import wraps

from google.cloud.firestore import Client, DocumentReference, DocumentSnapshot, Query, FieldFilter
from google.cloud.firestore_v1.base_query import FieldFilter as FirestoreFieldFilter
from google.cloud.firestore_v1.base_query import BaseQuery
from google.cloud.firestore import SERVER_TIMESTAMP, DELETE_FIELD, ArrayUnion, ArrayRemove, Increment

from services.firebase_admin import get_firebase_admin

logger = logging.getLogger(__name__)

T = TypeVar('T')


class FirestoreError(Exception):
    """Custom exception for Firestore operations."""
    pass


class BaseFirestoreService(ABC):
    """Base service class for Firestore operations."""

    def __init__(self, collection_name: str, uid: str = None):
        """
        Initialize service for a user's subcollection.

        Args:
            collection_name: Name of the subcollection under user's document
            uid: User ID (if None, will try to get from context)
        """
        self._collection_name = collection_name
        self._uid = uid
        self._client = None

    @property
    def client(self):
        """Get Firestore client."""
        if not hasattr(self, '_client') or self._client is None:
            firebase_admin = get_firebase_admin()
            if not firebase_admin._initialized:
                raise RuntimeError("Firebase Admin not initialized")
            self._client = firestore.client()
        return self._client

    @property
    def uid(self) -> str:
        """Get current user ID."""
        if self._uid:
            return self._uid
        # Try to get from Flask context (if available)
        try:
            from flask import g
            if hasattr(g, 'current_user') and g.current_user:
                return g.current_user.get('uid')
        except:
            pass
        raise ValueError("User ID not available. Pass uid to service or set in context.")

    @property
    def collection_ref(self):
        """Get the user's subcollection reference."""
        uid = self.uid
        return self.db.collection('users').document(uid).collection(self._collection_name)

    @property
    def db(self):
        """Get Firestore database client."""
        from services.firebase_admin import get_firebase_admin
        return get_firebase_admin().firestore

    def _add_timestamps(self, data: dict, is_update: bool = False) -> dict:
        """Add server timestamps to data."""
        from google.cloud.firestore import FieldValue
        now = datetime.now(timezone.utc)
        data['updated_at'] = datetime.now(timezone.utc)
        if not is_update:
            data['created_at'] = datetime.now(timezone.utc)
        return data

    def _serialize(self, data: dict) -> dict:
        """Serialize data for Firestore storage."""
        result = {}
        for key, value in data.items():
            if value is None:
                continue
            if isinstance(value, datetime):
                result[key] = value.replace(tzinfo=timezone.utc)
            elif isinstance(value, (list, dict)):
                result[key] = json.dumps(value) if not isinstance(value, (str, int, float, bool)) else value
            else:
                result[key] = value
        return result

    def _deserialize(self, data: dict) -> dict:
        """Deserialize data from Firestore."""
        result = {}
        for key, value in data.items():
            if isinstance(value, datetime):
                result[key] = value.replace(tzinfo=timezone.utc).isoformat()
            else:
                result[key] = value
        return result

    # ── CRUD Operations ────────────────────────────────────────────────

    def create(self, data: dict, doc_id: str = None) -> str:
        """Create a new document."""
        try:
            data = self._serialize(self._add_timestamps(data, is_update=False))
            if doc_id:
                doc_ref = self.collection_ref.document(doc_id)
                doc_ref.set(data)
                return doc_id
            else:
                doc_ref = self.collection_ref.document()
                doc_ref.set(data)
                return doc_ref.id
        except Exception as e:
            logger.error(f"Create failed: {e}")
            raise FirestoreError(f"Create failed: {e}")

    def get(self, doc_id: str) -> Optional[dict]:
        """Get a document by ID."""
        try:
            doc_ref = self.collection_ref.document(self._uid).collection(self._collection_name).document(doc_id)
            doc = doc_ref.get()
            if doc.exists:
                data = doc.to_dict()
                data['id'] = doc.id
                return self._deserialize(data)
            return None
        except Exception as e:
            logger.error(f"Get failed: {e}")
            raise FirestoreError(f"Get failed: {e}")

    def update(self, doc_id: str, data: dict) -> bool:
        """Update a document."""
        try:
            data = self._serialize(self._add_timestamps(data, is_update=True))
            doc_ref = self.collection_ref.document(doc_id)
            doc_ref.update(data)
            return True
        except Exception as e:
            logger.error(f"Update failed: {e}")
            raise FirestoreError(f"Update failed: {e}")

    def delete(self, doc_id: str) -> bool:
        """Delete a document (soft delete by default)."""
        try:
            doc_ref = self.collection_ref.document(doc_id)
            doc_ref.update({
                'deleted': True,
                'deleted_at': datetime.now(timezone.utc),
                'updated_at': datetime.now(timezone.utc)
            })
            return True
        except Exception as e:
            logger.error(f"Delete failed: {e}")
            raise FirestoreError(f"Delete failed: {e}")

    def hard_delete(self, doc_id: str) -> bool:
        """Permanently delete a document."""
        try:
            doc_ref = self.collection_ref.document(doc_id)
            doc_ref.delete()
            return True
        except Exception as e:
            logger.error(f"Hard delete failed: {e}")
            raise FirestoreError(f"Hard delete failed: {e}")

    def list(
        self,
        filters: List[tuple] = None,
        order_by: str = None,
        descending: bool = True,
        limit: int = 50,
        start_after: dict = None
    ) -> List[dict]:
        """
        List documents with optional filters.

        Args:
            filters: List of (field, operator, value) tuples
            order_by: Field to order by
            descending: Sort descending
            limit: Maximum results
            start_after: DocumentSnapshot to start after (for pagination)
        """
        try:
            query = self.collection_ref

            # Apply filters
            if filters:
                for field, op, value in filters:
                    query = query.where(filter=FirestoreFieldFilter(field, op, value))

            # Apply ordering
            if order_by:
                query = query.order_by(order_by, direction='DESCENDING' if descending else 'ASCENDING')

            # Apply pagination
            if start_after:
                query = query.start_after(start_after)

            query = query.limit(limit)

            docs = query.stream()
            results = []
            for doc in docs:
                data = doc.to_dict()
                data['id'] = doc.id
                results.append(self._deserialize(data))
            return results
        except Exception as e:
            logger.error(f"List failed: {e}")
            raise FirestoreError(f"List failed: {e}")

    def count(self, filters: List[tuple] = None) -> int:
        """Count documents matching filters."""
        try:
            query = self.collection_ref
            if filters:
                for field, op, value in filters:
                    query = query.where(filter=FirestoreFieldFilter(field, op, value))

            # Use aggregation query for count
            from google.cloud.firestore_v1.aggregation import Count
            agg_query = query.count()
            result = agg_query.get()[0][0].value
            return result
        except Exception as e:
            logger.error(f"Count failed: {e}")
            raise FirestoreError(f"Count failed: {e}")

    def query(self, filters: List[tuple] = None, order_by: str = None, descending: bool = True, limit: int = 50):
        """Return a query object for further chaining."""
        query = self.collection_ref
        if filters:
            for field, op, value in filters:
                query = query.where(filter=FirestoreFieldFilter(field, op, value))
        if order_by:
            query = query.order_by(order_by, direction='DESCENDING' if descending else 'ASCENDING')
        return query.limit(limit)

    def watch(self, on_change_callback):
        """Listen to real-time updates."""
        def on_snapshot(doc_snapshot, changes, read_time):
            for change in change:
                doc = change.document
                data = doc.to_dict()
                data['id'] = doc.id
                self._deserialize(data)
                # Call the callback with the change
                on_change_callback(change.type.name, data)

        return self.collection_ref.on_snapshot(on_snapshot)

    # ── Batch Operations ──────────────────────────────────────────────

    def batch_write(self, operations: List[dict]) -> List[str]:
        """
        Perform batch write operations.

        Args:
            operations: List of {operation: 'create'|'update'|'delete', doc_id: str, data: dict}
        """
        from google.cloud.firestore import WriteBatch

        batch = self.db.batch()
        doc_ids = []

        try:
            for op in operations:
                op_type = op.get('operation')
                doc_id = op.get('doc_id')
                data = op.get('data', {})

                doc_ref = self.collection_ref.document(doc_id) if doc_id else self.collection_ref.document()

                if op_type == 'create':
                    batch.set(doc_ref, self._serialize(self._add_timestamps(op.get('data', {}), is_update=False)))
                elif op_type == 'update':
                    batch.update(doc_ref, self._serialize(self._add_timestamps(op.get('data', {}), is_update=True)))
                elif op_type == 'delete':
                    batch.delete(doc_ref)

                if doc_id:
                    doc_ids.append(doc_id)
                else:
                    doc_ids.append(doc_ref.id)

            batch.commit()
            return doc_ids
        except Exception as e:
            logger.error(f"Batch write failed: {e}")
            raise FirestoreError(f"Batch write failed: {e}")

    # ── Helper Methods ────────────────────────────────────────────────

    def _deserialize(self, data: dict) -> dict:
        """Deserialize data from Firestore."""
        if not data:
            return {}
        result = {}
        for key, value in data.items():
            if isinstance(value, datetime):
                result[key] = value.replace(tzinfo=timezone.utc).isoformat()
            else:
                result[key] = value
        return result

    def _serialize(self, data: dict) -> dict:
        """Serialize data for Firestore storage."""
        result = {}
        for key, value in data.items():
            if value is None:
                continue
            if isinstance(value, datetime):
                result[key] = value.replace(tzinfo=timezone.utc)
            elif isinstance(value, (list, dict)):
                result[key] = value
            else:
                result[key] = value
        return result


class UserScopedService(BaseFirestoreService):
    """Service for user-scoped collections under users/{uid}/."""

    def __init__(self, collection_name: str, uid: str = None):
        super().__init__(collection_name, uid)

    @property
    def collection_ref(self):
        """Get the user's subcollection reference."""
        from services.firebase_admin import get_firebase_admin
        db = get_firebase_admin().firestore
        uid = self.uid
        return db.collection('users').document(self._uid).collection(self._collection_name)


# Decorator for API routes requiring authentication
def require_auth(f):
    """Decorator to require Firebase ID token authentication."""
    from functools import wraps
    from flask import request, jsonify, g

    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get('Authorization', '')
        if not auth_header.startswith('Bearer '):
            return jsonify({"success": False, "error": "Missing or invalid Authorization header"}), 401

        id_token = auth_header.split('Bearer ')[1]
        try:
            from services.firebase_admin import get_firebase_admin
            firebase_admin = get_firebase_admin()
            decoded_token = firebase_admin.verify_id_token(request.headers.get('Authorization', '').split('Bearer ')[1])

            # Store user info in Flask g object
            g.current_user = {
                'uid': decoded_token['uid'],
                'email': decoded_token.get('email'),
                'email_verified': decoded_token.get('email_verified', False),
                'name': decoded_token.get('name'),
                'picture': decoded_token.get('picture')
            }
        except Exception as e:
            return jsonify({"success": False, "error": "Invalid or expired token"}), 401

        return f(*args, **kwargs)
    return decorated


# Convenience functions for common collections
def get_user_collection(uid: str, collection: str):
    """Get a user's subcollection reference."""
    from services.firebase_admin import get_firebase_admin
    db = get_firebase_admin().firestore
    return db.collection('users').document(uid).collection(collection)


def get_user_doc(uid: str):
    """Get user document reference."""
    from services.firebase_admin import get_firebase_admin
    db = get_firebase_admin().firestore
    return db.collection('users').document(uid)