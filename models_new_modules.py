# ============================================================
# models_new_modules.py — New Feature Models
# Add these to models.py (or import separately in app.py)
# Modules: Medicine, Lab Tests, Doctor Visits, Appointments,
#          Habits, Emergency Card, Trusted Contacts, Subscriptions
# ============================================================
# ============================================================
# models_new_modules.py — New Feature Models
# ============================================================

from datetime import datetime, date
from extensions import db
from models import now_ist, today_ist   # reuse IST helpers


# ════════════════════════════════════════════════════════════════
# MODULE 4 — MEDICINE MANAGEMENT
# ════════════════════════════════════════════════════════════════

class MedicineLog(db.Model):
    __tablename__ = "medicines"
    id                = db.Column(db.Integer, primary_key=True)
    user_id           = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    member_id         = db.Column(db.Integer, db.ForeignKey("family_members.id"), nullable=True)

    name              = db.Column(db.String(200), nullable=False)
    generic_name      = db.Column(db.String(200), nullable=True)
    dosage            = db.Column(db.String(100), nullable=True)   # "500mg"
    unit              = db.Column(db.String(50),  nullable=True)   # tablet / ml / drops
    timing            = db.Column(db.String(50),  nullable=True)   # morning/afternoon/evening/night
    frequency         = db.Column(db.String(50),  default="daily") # daily/alternate/weekly
    with_food         = db.Column(db.String(50),  default="doesn't_matter")
    condition_name    = db.Column(db.String(200), nullable=True)   # e.g. "Hypertension"
    prescribed_by     = db.Column(db.String(200), nullable=True)
    start_date        = db.Column(db.Date,        nullable=True)
    end_date          = db.Column(db.Date,        nullable=True)   # None = ongoing
    stock_count       = db.Column(db.Integer,     default=0)
    low_stock_alert   = db.Column(db.Integer,     default=5)       # alert when <= this
    is_active         = db.Column(db.Boolean,     default=True)
    created_at        = db.Column(db.DateTime,    default=now_ist)
    updated_at        = db.Column(db.DateTime,    default=now_ist, onupdate=now_ist)

    logs = db.relationship("MedicineLog", backref="medicine", lazy="dynamic", cascade="all, delete-orphan")

    def to_dict(self):
        return {
            "id": self.id, "name": self.name, "generic_name": self.generic_name,
            "dosage": self.dosage, "unit": self.unit, "timing": self.timing,
            "frequency": self.frequency, "with_food": self.with_food,
            "condition_name": self.condition_name, "prescribed_by": self.prescribed_by,
            "start_date": str(self.start_date) if self.start_date else None,
            "end_date": str(self.end_date) if self.end_date else None,
            "stock_count": self.stock_count, "low_stock_alert": self.low_stock_alert,
            "is_active": self.is_active, "member_id": self.member_id,
            "taken_today": self._is_taken_today(),
            "adherence_pct": round(self._adherence_30d(), 1),
        }

    def _is_taken_today(self):
        today = today_ist()
        log = self.logs.filter_by(log_date=today).first()
        return log.taken if log else False

    def _adherence_30d(self):
        from datetime import timedelta
        since = today_ist() - timedelta(days=30)
        logs = self.logs.filter(MedicineLog.log_date >= since).all()
        if not logs: return 0
        return (sum(1 for l in logs if l.taken) / len(logs)) * 100


class MedicineLog(db.Model):
    __tablename__ = "medicine_logs"
    id          = db.Column(db.Integer, primary_key=True)
    medicine_id = db.Column(db.Integer, db.ForeignKey("medicines.id"), nullable=False)
    log_date    = db.Column(db.Date,    nullable=False, default=today_ist)
    taken       = db.Column(db.Boolean, default=False)
    logged_at   = db.Column(db.DateTime, default=now_ist)
    __table_args__ = (db.UniqueConstraint("medicine_id", "log_date"),)


# ════════════════════════════════════════════════════════════════
# MODULE 8 — LAB TEST TRACKER
# ════════════════════════════════════════════════════════════════

class LabTest(db.Model):
    __tablename__ = "lab_tests"
    id          = db.Column(db.Integer, primary_key=True)
    user_id     = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    member_id   = db.Column(db.Integer, db.ForeignKey("family_members.id"), nullable=True)

    test_type   = db.Column(db.String(100), nullable=False)  # blood_sugar / hba1c / cholesterol / etc.
    value       = db.Column(db.Float, nullable=False)
    unit        = db.Column(db.String(50), nullable=True)
    lab_name    = db.Column(db.String(200), nullable=True)
    test_date   = db.Column(db.Date, nullable=False, default=today_ist)
    notes       = db.Column(db.Text, nullable=True)
    created_at  = db.Column(db.DateTime, default=now_ist)

    @property
    def status(self):
        return self._compute_status()

    def _compute_status(self):
        ranges = {
            "blood_sugar":  {"Normal": (0, 99), "Pre-Diabetic": (100, 125), "Diabetic": (126, 9999)},
            "hba1c":        {"Normal": (0, 5.6), "Pre-Diabetic": (5.7, 6.4), "Diabetic": (6.5, 99)},
            "cholesterol":  {"Normal": (0, 199), "Borderline": (200, 239), "High": (240, 9999)},
            "hemoglobin":   {"Low": (0, 11.9), "Normal": (12, 17.5), "High": (17.6, 99)},
        }
        r = ranges.get(self.test_type, {})
        for label, (lo, hi) in r.items():
            if lo <= self.value <= hi:
                return label
        return "Unknown"

    def to_dict(self):
        return {
            "id": self.id, "test_type": self.test_type, "value": self.value,
            "unit": self.unit, "lab_name": self.lab_name,
            "test_date": str(self.test_date), "notes": self.notes,
            "status": self.status, "member_id": self.member_id,
        }


# ════════════════════════════════════════════════════════════════
# MODULE 9 — DOCTOR VISITS
# ════════════════════════════════════════════════════════════════

class DoctorVisit(db.Model):
    __tablename__ = "doctor_visits"
    id              = db.Column(db.Integer, primary_key=True)
    user_id         = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    member_id       = db.Column(db.Integer, db.ForeignKey("family_members.id"), nullable=True)

    visit_date      = db.Column(db.Date, nullable=False, default=today_ist)
    doctor_name     = db.Column(db.String(200), nullable=True)
    hospital        = db.Column(db.String(300), nullable=True)
    specialization  = db.Column(db.String(100), nullable=True)
    diagnosis       = db.Column(db.Text, nullable=True)
    prescription    = db.Column(db.Text, nullable=True)
    follow_up_date  = db.Column(db.Date, nullable=True)
    cost            = db.Column(db.Float, nullable=True)
    notes           = db.Column(db.Text, nullable=True)
    created_at      = db.Column(db.DateTime, default=now_ist)

    def to_dict(self):
        return {
            "id": self.id, "visit_date": str(self.visit_date),
            "doctor_name": self.doctor_name, "hospital": self.hospital,
            "specialization": self.specialization, "diagnosis": self.diagnosis,
            "prescription": self.prescription,
            "follow_up_date": str(self.follow_up_date) if self.follow_up_date else None,
            "cost": self.cost, "notes": self.notes, "member_id": self.member_id,
        }


# ════════════════════════════════════════════════════════════════
# MODULE 10 — APPOINTMENT MANAGER
# ════════════════════════════════════════════════════════════════

class Appointment(db.Model):
    __tablename__ = "appointments"
    id                  = db.Column(db.Integer, primary_key=True)
    user_id             = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    member_id           = db.Column(db.Integer, db.ForeignKey("family_members.id"), nullable=True)

    title               = db.Column(db.String(300), nullable=False)
    appointment_type    = db.Column(db.String(50), default="doctor")  # doctor/lab/vaccination/other
    appointment_date    = db.Column(db.Date, nullable=False)
    appointment_time    = db.Column(db.String(10), nullable=True)      # "10:30"
    location            = db.Column(db.String(300), nullable=True)
    notes               = db.Column(db.Text, nullable=True)
    completed           = db.Column(db.Boolean, default=False)
    reminder_sent       = db.Column(db.Boolean, default=False)
    created_at          = db.Column(db.DateTime, default=now_ist)

    def to_dict(self):
        return {
            "id": self.id, "title": self.title, "appointment_type": self.appointment_type,
            "appointment_date": str(self.appointment_date),
            "appointment_time": self.appointment_time, "location": self.location,
            "notes": self.notes, "completed": self.completed, "member_id": self.member_id,
            "days_until": (self.appointment_date - today_ist()).days if not self.completed else None,
        }


# ════════════════════════════════════════════════════════════════
# MODULE 14 — EMERGENCY CARD
# ════════════════════════════════════════════════════════════════

class EmergencyCard(db.Model):
    __tablename__ = "emergency_cards"
    id                  = db.Column(db.Integer, primary_key=True)
    user_id             = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, unique=True)
    blood_group         = db.Column(db.String(10), nullable=True)
    allergies           = db.Column(db.Text, nullable=True)
    emergency_contacts  = db.Column(db.Text, nullable=True)  # JSON string
    organ_donor         = db.Column(db.Boolean, default=False)
    additional_notes    = db.Column(db.Text, nullable=True)
    updated_at          = db.Column(db.DateTime, default=now_ist, onupdate=now_ist)

    def to_dict(self, user=None, conditions=None, medicines=None):
        return {
            "blood_group": self.blood_group,
            "allergies": self.allergies,
            "emergency_contacts": self.emergency_contacts,
            "organ_donor": self.organ_donor,
            "additional_notes": self.additional_notes,
            "name":       user.name if user else None,
            "age":        user.age if user else None,
            "gender":     user.health_profile.gender if user and user.health_profile else None,
            "conditions": conditions or [],
            "medicines":  medicines or [],
        }


# ════════════════════════════════════════════════════════════════
# MODULE 15 — EMERGENCY ALERT TRUSTED CONTACTS
# ════════════════════════════════════════════════════════════════

class TrustedContact(db.Model):
    __tablename__ = "trusted_contacts"
    id          = db.Column(db.Integer, primary_key=True)
    user_id     = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    name        = db.Column(db.String(200), nullable=False)
    phone       = db.Column(db.String(20),  nullable=True)
    email       = db.Column(db.String(200), nullable=True)
    relation    = db.Column(db.String(100), nullable=True)
    notify_bp_crisis    = db.Column(db.Boolean, default=True)
    notify_missed_meds  = db.Column(db.Boolean, default=False)
    created_at  = db.Column(db.DateTime, default=now_ist)

    def to_dict(self):
        return {
            "id": self.id, "name": self.name, "phone": self.phone,
            "email": self.email, "relation": self.relation,
            "notify_bp_crisis": self.notify_bp_crisis,
            "notify_missed_meds": self.notify_missed_meds,
        }



# ════════════════════════════════════════════════════════════════
# SUBSCRIPTION PLANS
# ════════════════════════════════════════════════════════════════

class UserSubscription(db.Model):
    __tablename__ = "user_subscriptions"
    id              = db.Column(db.Integer, primary_key=True)
    user_id         = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, unique=True)
    user = db.relationship(
        "User",
        backref=db.backref("subscription", uselist=False),
        lazy=True
    )
    plan            = db.Column(db.String(20), default="free")  # free / premium / family
    purchase_token  = db.Column(db.String(500), nullable=True)
    product_id      = db.Column(db.String(200), nullable=True)
    expires_at      = db.Column(db.DateTime, nullable=True)
    auto_renew      = db.Column(db.Boolean, default=True)
    created_at      = db.Column(db.DateTime, default=now_ist)
    updated_at      = db.Column(db.DateTime, default=now_ist, onupdate=now_ist)

    @property
    def is_active(self):
        if self.plan == "free": return True
        if not self.expires_at: return False
        return datetime.now() <= self.expires_at

    @property
    def is_premium(self):
        return self.plan in ("premium", "family") and self.is_active

    @property
    def is_family(self):
        return self.plan == "family" and self.is_active

    def to_dict(self):
        return {
            "plan": self.plan, "is_active": self.is_active,
            "is_premium": self.is_premium, "is_family": self.is_family,
            "expires_at": self.expires_at.isoformat() if self.expires_at else None,
            "auto_renew": self.auto_renew,
        }


# ════════════════════════════════════════════════════════════════
# HEALTH TIMELINE EVENTS
# ════════════════════════════════════════════════════════════════

class HealthTimelineEvent(db.Model):
    __tablename__ = "health_timeline_events"
    id          = db.Column(db.Integer, primary_key=True)
    user_id     = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    member_id   = db.Column(db.Integer, db.ForeignKey("family_members.id"), nullable=True)
    event_type  = db.Column(db.String(50), nullable=False)   # bp/weight/medicine/lab/visit/document/score
    event_date  = db.Column(db.Date, nullable=False, default=today_ist, index=True)
    title       = db.Column(db.String(300), nullable=False)
    description = db.Column(db.Text, nullable=True)
    icon        = db.Column(db.String(10), nullable=True)
    created_at  = db.Column(db.DateTime, default=now_ist)

    def to_dict(self):
        return {
            "id": self.id, "event_type": self.event_type,
            "event_date": str(self.event_date), "title": self.title,
            "description": self.description, "icon": self.icon,
            "member_id": self.member_id,
        }