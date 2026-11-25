# services/appointment_service.py — Appointment Firestore Service
# ============================================================

import logging
from datetime import datetime, timezone, timedelta
from typing import List, Optional, Dict, Any
from google.cloud.firestore import FieldValue

from services.firebase_admin import get_firebase_admin

logger = logging.getLogger(__name__)


class AppointmentService:
    """Service for managing appointments in Firestore."""

    APPOINTMENT_TYPES = {
        "doctor": ("👨‍⚕️", "Doctor Visit"),
        "lab": ("🧪", "Lab Test"),
        "vaccination": ("💉", "Vaccination"),
        "physiotherapy": ("🦴", "Physiotherapy"),
        "dental": ("🦷", "Dental"),
        "eye": ("👁️", "Eye Checkup"),
        "health_checkup": ("🏥", "Health Checkup"),
        "other": ("📅", "Other"),
    }

    STATUS_EMOJI = {
        "upcoming": "🟡",
        "completed": "🔵",
        "missed": "🔴",
        "cancelled": "⚪",
    }

    def __init__(self, uid: str = None):
        self._uid = uid

    @property
    def _get_uid(self) -> str:
        if self._uid:
            return self._uid
        try:
            from flask import g
            if hasattr(g, 'current_user') and g.current_user:
                return g.current_user['uid']
        except:
            pass
        raise ValueError("User ID not available")

    @property
    def _collection(self):
        from services.firebase_admin import get_firebase_admin
        db = get_firebase_admin().firestore
        uid = self._uid or self._get_uid()
        return db.collection('users').document(uid).collection('appointments')

    def _get_uid(self) -> str:
        if self._uid:
            return self._uid
        try:
            from flask import g
            if hasattr(g, 'current_user') and g.current_user:
                return g.current_user['uid']
        except:
            pass
        raise ValueError("User ID not available")

    def _serialize(self, data: dict, is_update: bool = False) -> dict:
        from datetime import datetime, timezone
        data = data.copy()
        if not data.get('created_at') and not data.get('updated_at'):
            data['created_at'] = datetime.now(timezone.utc)
        data['updated_at'] = datetime.now(timezone.utc)
        return data

    def _deserialize(self, data: dict) -> dict:
        result = {}
        for key, value in data.items():
            if hasattr(value, 'isoformat'):
                result[key] = value.isoformat()
            else:
                result[key] = value
        return result

    def create(self, data: dict) -> str:
        """Create a new appointment."""
        from services.firebase_admin import get_firebase_admin
        from datetime import datetime, timezone

        uid = self._get_uid()
        db = get_firebase_admin().firestore

        data = data.copy()
        data['user_id'] = self._get_uid()
        data['created_at'] = datetime.now(timezone.utc)
        data['updated_at'] = datetime.now(timezone.utc)
        data['completed'] = data.get('completed', False)
        data['status'] = data.get('status', 'upcoming')
        data['reminder_1day'] = data.get('reminder_1day', True)
        data['reminder_1hour'] = data.get('reminder_1hour', True)
        data['reminder_at_time'] = data.get('reminder_at_time', True)
        data['reminder_sent_1day'] = False
        data['reminder_sent_1hour'] = False

        doc_ref = db.collection('users').document(self._get_uid()).collection('appointments').document()
        doc_ref.set(data)

        return doc_ref.id

    def get_all(self, upcoming_only: bool = False, status: str = None, appt_type: str = None, member_id: str = None) -> List[dict]:
        """Get all appointments."""
        from services.firebase_admin import get_firebase_admin

        uid = self._get_uid()
        db = get_firebase_admin().firestore

        query = db.collection('users').document(self._get_uid()).collection('appointments')

        if member_id:
            query = query.where('member_id', '==', member_id)

        if upcoming_only:
            query = query.where('appointment_date', '>=', datetime.now().date().isoformat())
            query = query.where('completed', '==', False)

        if status:
            query = query.where('status', '==', status)

        if appt_type:
            query = query.where('appointment_type', '==', appt_type)

        query = query.order_by('appointment_date', direction='ASCENDING')

        docs = query.stream()
        results = []
        for doc in query.stream():
            data = doc.to_dict()
            data['id'] = doc.id
            results.append(self._deserialize(data))

        return results

    def get(self, appointment_id: str) -> Optional[dict]:
        """Get a single appointment."""
        try:
            doc = self._collection().document(appointment_id).get()
            if doc.exists:
                data = doc.to_dict()
                data['id'] = doc.id
                return self._deserialize(data)
            return None
        except Exception as e:
            logger.error(f"Get appointment failed: {e}")
            return None

    def update(self, appointment_id: str, data: dict) -> bool:
        """Update an appointment."""
        try:
            data = self._serialize(data, is_update=True)
            doc_ref = self._collection().document(appointment_id)
            doc_ref.update(data)
            return True
        except Exception as e:
            logger.error(f"Update appointment failed: {e}")
            return False

    def delete(self, appointment_id: str) -> bool:
        """Delete an appointment."""
        try:
            doc_ref = self._collection().document(appointment_id)
            doc_ref.delete()
            return True
        except Exception as e:
            logger.error(f"Delete appointment failed: {e}")
            return False

    def complete(self, appointment_id: str) -> bool:
        """Mark appointment as completed."""
        try:
            from datetime import datetime, timezone

            self._collection().document(appointment_id).update({
                'completed': True,
                'status': 'completed',
                'updated_at': datetime.now(timezone.utc)
            })

            # Add to timeline
            self._add_timeline_event('appointment_completed', datetime.now().date(), appointment_id)

            return True
        except Exception as e:
            logger.error(f"Complete appointment failed: {e}")
            return False

    def cancel(self, appointment_id: str) -> bool:
        """Cancel an appointment."""
        try:
            from datetime import datetime, timezone

            self._collection().document(appointment_id).update({
                'status': 'cancelled',
                'updated_at': datetime.now(timezone.utc)
            })
            return True
        except Exception as e:
            logger.error(f"Cancel appointment failed: {e}")
            return False

    def mark_missed(self, appointment_id: str) -> bool:
        """Mark appointment as missed."""
        try:
            from datetime import datetime, timezone

            self._collection().document(appointment_id).update({
                'status': 'missed',
                'updated_at': datetime.now(timezone.utc)
            })
            return True
        except Exception as e:
            logger.error(f"Mark missed failed: {e}")
            return False

    def get_dashboard(self, member_id: str = None) -> dict:
        """Get appointment dashboard data."""
        from datetime import datetime, timedelta

        today = datetime.now().date()
        week_later = today + timedelta(days=7)

        upcoming = self.get_all(upcoming_only=True, member_id=member_id)

        today_appts = [a for a in upcoming if a.get('appointment_date') == datetime.now().date().isoformat()]
        this_week = [a for a in upcoming if a.get('appointment_date', '') <= (datetime.now().date() + timedelta(days=7)).isoformat()]

        return {
            "total_upcoming": len(upcoming),
            "today": len(today_appts),
            "this_week": len(this_week),
            "appointments": upcoming[:10]  # Latest 10
        }

    def get_settings(self) -> dict:
        """Get appointment settings."""
        # In a full implementation, this would fetch from user settings
        return {
            "reminder_1day": True,
            "reminder_1hour": True,
            "reminder_at_time": True,
            "reminder_email": False,
        }

    def save_settings(self, data: dict) -> bool:
        """Save appointment settings."""
        # In a full implementation, this would save to user settings
        return True