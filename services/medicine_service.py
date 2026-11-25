# services/medicine_service.py — Medicine Firestore Service
# ============================================================

import logging
from datetime import datetime, timezone
from typing import List, Optional, Dict, Any
from google.cloud.firestore import FieldValue

from services.firestore_service import UserScopedService, FirestoreError
from services.firebase_admin import get_firebase_admin

logger = logging.getLogger(__name__)


class MedicineService:
    """Service for managing medicines in Firestore."""

    MEDICINE_TYPES = {
        "tablet": "Tablet",
        "capsule": "Capsule",
        "syrup": "Syrup",
        "injection": "Injection",
        "drops": "Drops",
        "inhaler": "Inhaler",
        "ointment": "Ointment",
        "powder": "Powder",
        "other": "Other",
    }

    SCHEDULE_TIMES = {
        "morning": "08:00",
        "afternoon": "13:00",
        "evening": "18:00",
        "night": "21:30",
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
        uid = self._uid or self._get_uid_from_context()
        return db.collection('users').document(uid).collection('medicines')

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

    # ── CRUD Operations ────────────────────────────────────────────────

    def create(self, data: dict) -> str:
        """Create a new medicine."""
        from services.firebase_admin import get_firebase_admin
        from datetime import datetime, timezone

        uid = self._get_uid()
        db = get_firebase_admin().firestore

        data = data.copy()
        data['user_id'] = self._get_uid()
        data['created_at'] = datetime.now(timezone.utc)
        data['updated_at'] = datetime.now(timezone.utc)
        data['is_active'] = data.get('is_active', True)
        data['is_discontinued'] = data.get('is_discontinued', False)
        data['stock_count'] = data.get('stock_count', 0)
        data['low_stock_threshold'] = data.get('low_stock_threshold', 5)
        data['auto_reduce_stock'] = data.get('auto_reduce_stock', True)
        data['reminder_enabled'] = data.get('reminder_enabled', True)
        data['snooze_minutes'] = data.get('snooze_minutes', 10)
        data['max_reminders'] = data.get('max_reminders', 3)
        data['reminder_sound'] = data.get('reminder_sound', 'medicine')
        data['caregiver_alert'] = data.get('caregiver_alert', False)

        doc_ref = db.collection('users').document(self._get_uid()).collection('medicines').document()
        doc_ref.set(data)

        return doc_ref.id

    def get_all(self, active_only: bool = True, member_id: str = None) -> List[dict]:
        """Get all medicines for user."""
        from services.firebase_admin import get_firebase_admin

        uid = self._get_uid()
        db = get_firebase_admin().firestore

        query = db.collection('users').document(self._get_uid()).collection('medicines')

        if active_only:
            query = query.where('is_active', '==', True)

        if member_id:
            query = query.where('member_id', '==', member_id)

        query = query.order_by('created_at', direction='DESCENDING')

        docs = query.stream()
        results = []
        for doc in query.stream():
            data = doc.to_dict()
            data['id'] = doc.id
            results.append(self._deserialize(data))

        return results

    def get(self, medicine_id: str) -> Optional[dict]:
        """Get a single medicine."""
        try:
            doc = self._get_uid().collection('medicines').document(medicine_id).get()
            if doc.exists:
                data = doc.to_dict()
                data['id'] = doc.id
                return self._deserialize(data)
            return None
        except Exception as e:
            logger.error(f"Get medicine failed: {e}")
            return None

    def update(self, medicine_id: str, data: dict) -> bool:
        """Update a medicine."""
        try:
            data = self._serialize(data, is_update=True)
            doc_ref = self._get_uid().collection('medicines').document(medicine_id)
            doc_ref.update(data)
            return True
        except Exception as e:
            logger.error(f"Update medicine failed: {e}")
            return False

    def delete(self, medicine_id: str) -> bool:
        """Soft delete a medicine."""
        try:
            doc_ref = self._get_uid().collection('medicines').document(medicine_id)
            doc_ref.update({
                'is_active': False,
                'is_discontinued': True,
                'updated_at': datetime.now(timezone.utc)
            })
            return True
        except Exception as e:
            logger.error(f"Delete medicine failed: {e}")
            return False

    def log_taken(self, medicine_id: str, taken: bool, scheduled_time: str = None) -> bool:
        """Log medicine as taken/not taken."""
        from datetime import datetime, timezone

        uid = self._get_uid()
        today = datetime.now(timezone.utc).date()
        date_str = today.isoformat()

        log_data = {
            'medicine_id': medicine_id,
            'log_date': date_str,
            'taken': taken,
            'scheduled_time': scheduled_time,
            'logged_at': datetime.now(timezone.utc),
            'status': 'taken' if taken else 'skipped',
            'synced': True
        }

        # Use a deterministic document ID to prevent duplicates
        doc_id = f"{medicine_id}_{date_str}{scheduled_time or ''}"

        try:
            doc_ref = self._get_uid().collection('medicine_logs').document(doc_id)
            doc_ref.set(log_data)

            # Auto-reduce stock if taken
            if taken:
                self._reduce_stock(medicine_id)

            return True
        except Exception as e:
            logger.error(f"Log medicine failed: {e}")
            return False

    def _reduce_stock(self, medicine_id: str):
        """Reduce stock count when medicine is taken."""
        try:
            med_doc = self._get_uid().collection('medicines').document(medicine_id).get()
            if med_doc.exists:
                med_data = med_doc.to_dict()
                stock_count = med_data.get('stock_count', 0)
                auto_reduce = med_data.get('auto_reduce_stock', True)

                if stock_count > 0 and auto_reduce:
                    new_count = stock_count - 1
                    self._get_uid().collection('medicines').document(medicine_id).update({
                        'stock_count': new_count,
                        'updated_at': datetime.now(timezone.utc)
                    })

                    # Check low stock
                    low_threshold = med_data.get('low_stock_threshold', 5)
                    if new_count <= low_threshold:
                        # Trigger low stock notification
                        self._send_low_stock_alert(medicine_id, new_count)

            return True
        except Exception as e:
            logger.error(f"Reduce stock failed: {e}")

    def _send_low_stock_alert(self, medicine_id: str, count: int):
        """Send low stock alert notification."""
        # This would integrate with notification service
        pass

    def get_adherence(self, medicine_id: str, days: int = 30) -> dict:
        """Get adherence statistics for a medicine."""
        from datetime import datetime, timezone, timedelta

        uid = self._get_uid()
        since = datetime.now(timezone.utc) - timedelta(days=days)

        logs_query = (self.db.collection('users').document(self._get_uid())
                      .collection('medicine_logs')
                      .where('medicine_id', '==', medicine_id)
                      .where('log_date', '>=', since.isoformat())
                      .order_by('log_date', direction='DESCENDING'))

        docs = logs_query.stream()
        logs = []
        for doc in logs_query.stream():
            data = doc.to_dict()
            data['id'] = doc.id
            logs.append(data)

        taken = [l for l in logs if l.get('status') in ('taken', 'ai_verified')]
        missed = [l for l in logs if l.get('status') == 'missed']
        skipped = [l for l in logs if l.get('status') == 'skipped']

        total = len(logs)
        taken_count = len(taken)
        adherence = round((taken_count / total) * 100, 1) if total > 0 else 0

        return {
            "logs": logs,
            "adherence_pct": adherence,
            "taken_count": len(taken),
            "missed_count": len(missed),
            "skipped_count": len(skipped),
            "total_scheduled": total
        }

    def get_reminder_times(self, medicine_id: str) -> List[str]:
        """Get reminder times for a medicine."""
        med = self.get(medicine_id)
        if not med:
            return []

        schedule_type = med.get('schedule_type', 'morning')
        if schedule_type == 'custom':
            return med.get('custom_times', [])
        return [self.SCHEDULE_TIMES.get(schedule_type, '08:00')]

    def check_low_stock(self) -> List[dict]:
        """Check all medicines for low stock."""
        meds = self.get_all(active_only=True)
        low_stock = []

        for med in meds:
            stock = med.get('stock_count', 0)
            threshold = med.get('low_stock_threshold', 5)
            if stock <= threshold:
                low_stock.append({
                    'id': med['id'],
                    'name': med['name'],
                    'stock_count': stock,
                    'threshold': threshold
                })

        return low_stock

    def get_medicines_for_reminder(self) -> List[dict]:
        """Get medicines that have reminders enabled and are active."""
        meds = self.get_all(active_only=True)
        reminder_meds = []

        for med in meds:
            if med.get('reminder_enabled'):
                med_copy = med.copy()
                med_copy['reminder_times'] = self.get_reminder_times(med['id'])
                reminder_meds.append(med_copy)

        return reminder_meds