# services/health_metric_service.py — Health Metrics Firestore Service
# ============================================================

import logging
from datetime import datetime, timezone, timedelta
from typing import List, Optional, Dict, Any, Tuple
from google.cloud.firestore import FieldValue, Query
from google.cloud.firestore_v1.base_query import FieldFilter

from services.firestore_service import UserScopedService, FirestoreError

logger = logging.getLogger(__name__)


class HealthMetricService:
    """Service for managing health metrics in Firestore."""

    METRIC_TYPES = [
        'bp', 'weight', 'water', 'sugar', 'sleep', 'heart_rate', 'steps'
    ]

    def __init__(self, uid: str = None):
        self._uid = uid

    @property
    def _collection(self):
        from services.firebase_admin import get_firebase_admin
        db = get_firebase_admin().firestore
        uid = self._uid or self._get_uid_from_context()
        return db.collection('users').document(uid).collection('health_metrics')

    def _get_uid(self) -> str:
        """Get user ID from context or instance variable."""
        if self._uid:
            return self._uid
        try:
            from flask import g
            if hasattr(g, 'current_user') and g.current_user:
                return g.current_user['uid']
        except:
            pass
        raise ValueError("User ID not available")

    def _serialize_metric(self, data: dict, is_update: bool = False) -> dict:
        """Serialize metric data for Firestore."""
        from datetime import datetime, timezone

        data = data.copy()
        # Add timestamps
        if not hasattr(data, '_timestamps_added'):
            if 'recorded_at' not in data:
                data['recorded_at'] = datetime.now(timezone.utc)
            data['created_at'] = datetime.now(timezone.utc)
        data['updated_at'] = datetime.utcnow()
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

    # ── CRUD Operations ────────────────────────────────────────────────

    def create(self, metric_type: str, data: dict) -> str:
        """Create a new health metric."""
        if metric_type not in self.METRIC_TYPES:
            raise ValueError(f"Invalid metric type: {metric_type}")

        from services.firebase_admin import get_firebase_admin
        from datetime import datetime, timezone

        uid = self._get_uid()
        db = get_firebase_admin().firestore

        doc_ref = db.collection('users').document(self._get_uid()).collection('health_metrics').document()

        data = data.copy()
        data['metric_type'] = data.get('metric_type', 'unknown')
        data['recorded_at'] = datetime.now(timezone.utc)
        data['created_at'] = datetime.now(timezone.utc)
        data['updated_at'] = datetime.now(timezone.utc)

        doc_ref = db.collection('users').document(uid).collection('health_metrics').document()
        doc_ref.set(data)

        return doc_ref.id

    def get_by_type(self, metric_type: str, days: int = 7, limit: int = 100) -> List[dict]:
        """Get metrics by type within a date range."""
        from datetime import datetime, timezone, timedelta

        uid = self._get_uid()
        db = self.firebase_admin.firestore

        since = datetime.now(timezone.utc) - timedelta(days=days)

        query = (db.collection('users').document(self._get_uid())
                 .collection('health_metrics')
                 .where('metric_type', '==', metric_type)
                 .where('recorded_at', '>=', datetime.now() - timedelta(days=days))
                 .order_by('recorded_at', direction='DESCENDING')
                 .limit(100))

        docs = query.stream()
        results = []
        for doc in query.stream():
            data = doc.to_dict()
            data['id'] = doc.id
            results.append(self._deserialize(data))

        return results

    def get_latest(self, metric_type: str) -> Optional[dict]:
        """Get the latest metric of a given type."""
        results = self.get_by_type(metric_type, days=365, limit=1)
        return results[0] if results else None

    def get_by_date_range(self, metric_type: str, start_date: datetime, end_date: datetime) -> List[dict]:
        """Get metrics within a date range."""
        from datetime import timezone

        uid = self._get_uid()
        db = self.firebase_admin.firestore

        query = (db.collection('users').document(self._get_uid())
                 .collection('health_metrics')
                 .where('metric_type', '==', metric_type)
                 .where('recorded_at', '>=', start_date.replace(tzinfo=None))
                 .where('recorded_at', '<=', end_date.replace(tzinfo=None))
                 .order_by('recorded_at', direction='DESCENDING'))

        docs = query.stream()
        results = []
        for doc in query.stream():
            data = doc.to_dict()
            data['id'] = doc.id
            results.append(self._deserialize(data))

        return results

    def get_latest_by_type(self, metric_type: str) -> Optional[dict]:
        """Get the latest metric of a given type."""
        uid = self._get_uid()
        db = self.firebase_admin.firestore

        query = (db.collection('users').document(self._get_uid())
                 .collection('health_metrics')
                 .where('metric_type', '==', metric_type)
                 .order_by('recorded_at', direction='DESCENDING')
                 .limit(1))

        docs = list(query.stream())
        if docs:
            data = docs[0].to_dict()
            data['id'] = docs[0].id
            return self._deserialize(data)
        return None

    def delete(self, metric_id: str) -> bool:
        """Delete a health metric."""
        try:
            self.db.collection('users').document(self._get_uid()).collection('health_metrics').document(metric_id).delete()
            return True
        except Exception as e:
            logger.error(f"Delete failed: {e}")
            raise FirestoreError(f"Delete failed: {e}")

    def get_stats(self, metric_type: str, days: int = 7) -> dict:
        """Get statistics for a metric type over a period."""
        from datetime import datetime, timezone, timedelta
        from statistics import mean

        uid = self._get_uid()
        since = datetime.now() - timedelta(days=days)

        query = (self.db.collection('users').document(self._get_uid())
                 .collection('health_metrics')
                 .where('metric_type', '==', metric_type)
                 .where('recorded_at', '>=', datetime.now() - timedelta(days=days)))

        docs = query.stream()
        readings = []
        for doc in query.stream():
            data = doc.to_dict()
            if data.get('value1') is not None:
                readings.append(data['value1'])
            if data.get('value2') is not None:
                readings.append(data['value2'])

        if not readings:
            return {"count": 0, "avg": None, "min": None, "max": None}

        return {
            "count": len(readings),
            "avg": round(sum(readings) / len(readings), 1),
            "min": min(readings),
            "max": max(readings)
        }

    # ── Blood Pressure Specific ────────────────────────────────────────

    def add_bp(self, systolic: float, diastolic: float, pulse: float = None, notes: str = "") -> str:
        """Add a blood pressure reading."""
        return self.create('bp', {
            'metric_type': 'bp',
            'value1': systolic,
            'value2': diastolic,
            'value3': pulse,
            'unit': 'mmHg',
            'notes': notes,
            'source': 'manual'
        })

    def get_bp_stats(self, days: int = 7) -> dict:
        """Get BP statistics."""
        stats = self.get_stats('bp', days)
        if stats['count'] == 0:
            return {"count": 0}

        readings = self.get_by_type('bp', days=days)
        latest = readings[0] if readings else None

        return {
            "count": stats['count'],
            "avg_sys": stats['avg'],
            "avg_dia": stats.get('avg_dia'),  # Would need separate calculation
            "latest": self._deserialize(latest) if latest else None
        }

    # ── Weight Specific ──────────────────────────────────────────────

    def add_weight(self, weight_kg: float, notes: str = "") -> str:
        """Add a weight reading."""
        return self.create('weight', {
            'metric_type': 'weight',
            'value1': weight_kg,
            'unit': 'kg',
            'notes': notes,
            'source': 'manual'
        })

    def get_weight_stats(self, days: int = 30) -> dict:
        """Get weight statistics."""
        stats = self.get_stats('weight', days)
        readings = self.get_by_type('weight', days=days)
        latest = readings[0] if readings else None

        return {
            "count": stats['count'],
            "latest": self._deserialize(latest) if latest else None,
            "avg": stats['avg'],
            "change": self._calculate_weight_change(readings)
        }

    def _calculate_weight_change(self, readings: List[dict]) -> Optional[float]:
        """Calculate weight change over period."""
        if len(readings) < 2:
            return None
        # Readings are ordered DESC, so first is latest, last is oldest
        latest = readings[0].get('value1')
        oldest = readings[-1].get('value1')
        if latest is not None and oldest is not None:
            return round(oldest - latest, 1)  # Positive = weight loss
        return None

    # ── Water Specific ───────────────────────────────────────────────

    def add_water(self, litres: float) -> str:
        """Add water intake."""
        return self.create('water', {
            'metric_type': 'water',
            'value1': litres,
            'unit': 'litres',
            'source': 'manual'
        })

    def get_water_today(self) -> dict:
        """Get today's water intake."""
        from datetime import datetime, timezone, timedelta

        uid = self._get_uid()
        today = datetime.now().date()

        query = (self.db.collection('users').document(self._get_uid())
                 .collection('health_metrics')
                 .where('metric_type', '==', 'water')
                 .where('recorded_at', '>=', datetime.combine(datetime.now().date(), datetime.min.time()))
                 .where('recorded_at', '<=', datetime.combine(datetime.now().date(), datetime.max.time())))

        docs = query.stream()
        total = 0
        logs = []
        for doc in query.stream():
            data = doc.to_dict()
            data['id'] = doc.id
            total += data.get('value1', 0)
            logs.append(self._deserialize(data))

        target = 2.5  # Default target
        # Could fetch from user goals

        return {
            "today_total": round(total, 2),
            "target": target,
            "pct": min(100, int((total / target) * 100)) if target else 0,
            "logs": logs
        }

    # ── Blood Sugar Specific ─────────────────────────────────────────

    def add_sugar(self, fasting: float = None, post_meal: float = None, notes: str = "") -> str:
        """Add a blood sugar reading."""
        return self.create('sugar', {
            'metric_type': 'sugar',
            'value1': fasting,
            'value2': post_meal,
            'unit': 'mg/dL',
            'notes': notes,
            'source': 'manual'
        })

    def get_sugar_status(self, fasting: float) -> str:
        """Determine sugar status."""
        if fasting < 100:
            return "Normal"
        elif fasting < 126:
            return "Pre-Diabetic"
        else:
            return "Diabetes Range"

    # ── Sleep Specific ───────────────────────────────────────────────

    def add_sleep(self, sleep_time: str, wake_time: str, duration_hours: float = None,
                  quality: int = None, interruptions: int = 0,
                  mood_on_wake: str = "", notes: str = "", log_date: datetime = None) -> str:
        """Add a sleep log."""
        from datetime import datetime

        if not log_date:
            log_date = datetime.now().date()

        # Calculate duration if not provided
        if not duration_hours and sleep_time and wake_time:
            try:
                sh, sm = map(int, sleep_time.split(":"))
                wh, wm = map(int, wake_time.split(":"))
                sleep_mins = sh * 60 + sm
                wake_mins = wh * 60 + wm
                if wake_mins < sleep_mins:
                    wake_mins += 24 * 60
                duration_hours = round((wake_mins - sleep_mins) / 60, 1)
            except Exception:
                pass

        return self.create('sleep', {
            'metric_type': 'sleep',
            'value1': duration_hours,
            'value2': quality,
            'value3': interruptions,
            'unit': 'hours',
            'notes': notes,
            'sleep_time': sleep_time,
            'wake_time': wake_time,
            'mood_on_wake': mood_on_wake,
            'log_date': log_date.isoformat() if isinstance(log_date, datetime) else str(log_date),
            'source': 'manual'
        })

    # ── Steps Specific ───────────────────────────────────────────────

    def add_steps(self, steps: int, log_date: datetime = None) -> str:
        """Add step count."""
        from datetime import datetime, timezone

        if not log_date:
            log_date = datetime.now().date()

        uid = self._get_uid()

        # Calculate distance and calories
        # These would ideally come from user profile
        h = 170  # default height
        w = 70   # default weight
        stride_m = (h * 0.414) / 100
        distance_km = round(steps * stride_m / 1000, 2)
        calories = int((steps / 100) * (3.5 * w * 3.5 / 200))

        return self.create('steps', {
            'metric_type': 'steps',
            'value1': steps,
            'value2': distance_km,
            'value3': calories,
            'unit': 'steps',
            'log_date': log_date.isoformat() if isinstance(log_date, datetime) else str(log_date),
            'source': 'manual'
        })

    # ── Heart Rate Specific ──────────────────────────────────────────

    def add_heart_rate(self, bpm: int, reading_type: str = 'resting', notes: str = "") -> str:
        """Add heart rate reading."""
        return self.create('heart_rate', {
            'metric_type': 'heart_rate',
            'value1': bpm,
            'value2': reading_type,
            'unit': 'bpm',
            'notes': notes,
            'source': 'manual'
        })


# Helper functions
def get_health_metric_service(uid: str = None):
    """Get HealthMetricService instance."""
    return HealthMetricService(uid)