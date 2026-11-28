# routes/api/appointment_api.py — Complete Appointment Module API
from flask import Blueprint, request, jsonify, current_app
from flask_jwt_extended import jwt_required, get_jwt_identity
from datetime import date, datetime, timedelta
from models import User, now_ist, today_ist
from models import Appointment, UserSubscription, HealthTimelineEvent

appointment_api_bp = Blueprint("appointment_api", __name__)


# ── Plan helpers ───────────────────────────────────────────────────
def _plan(uid):
    sub_list = UserSubscription.get_all(filters={"user_id": uid}, limit=1)
    sub = sub_list[0] if sub_list else None
    return sub.plan if sub and sub.is_active else "free"


def _limit(uid):
    plan = _plan(uid)
    lim = Appointment.PLAN_LIMITS.get(plan, 2)
    return lim  # None = unlimited


def _can_add(uid):
    lim = _limit(uid)
    if lim is None:
        return True
    count = len(Appointment.get_all(
        filters={"user_id": uid, "status": "upcoming"}
    ))
    return count < lim


def _is_family(uid):
    return _plan(uid) == "family"


# ════════════════════════════════════════════════════════════════
# DASHBOARD
# ═════════════════════════════════════════════════════════════════

appointment_api_bp = Blueprint("appointment_api", __name__)


@appointment_api_bp.route("/dashboard", methods=["GET"])
@jwt_required()
def dashboard():
    uid = get_jwt_identity()
    today = today_ist()
    week_end = today + timedelta(days=7)
    member_id = request.args.get("member_id", type=int)

    filters = {"user_id": uid, "status": "upcoming"}
    if member_id:
        filters["member_id"] = member_id

    appts = Appointment.get_all(filters=filters, order_by="appointment_date")

    # Auto-mark overdue
    for a in appts:
        if a.is_overdue:
            a.status = "missed"

    upcoming  = [a.to_dict() for a in appts if a.status == "upcoming"]
    completed = [a.to_dict() for a in appts if a.status == "completed"]
    missed_list= [a.to_dict() for a in appts if a.status == "missed"]
    cancelled = [a.to_dict() for a in appts if a.status == "cancelled"]

    return jsonify({"success": True,
        "upcoming": upcoming,
        "completed": completed,
        "missed": missed_list,
        "cancelled": cancelled,
        "plan": _plan(uid), "limit": _limit(uid), "can_add": _can_add(uid),
    })


# ═════════════════════════════════════════════════════════════════
# ADD
# ═════════════════════════════════════════════════════════════════

@appointment_api_bp.route("/", methods=["POST"])
@jwt_required()
def add_appointment():
    uid = get_jwt_identity()

    if not _can_add(uid):
        plan = _plan(uid)
        lim = _limit(uid)
        return jsonify({
            "success": False,
            "message": f"🔒 {plan.title()} plan allows {lim} active appointments. Upgrade for unlimited.",
            "upgrade_required": True, "limit": lim,
        }), 403

    d = request.get_json() or {}
    if not d.get("title") or not d.get("appointment_date"):
        return jsonify({"success": False, "message": "Title and date are required"}), 400

    def _date(v):
        if not v: return today_ist()
        try: return date.fromisoformat(str(v)[:10])
        except: return today_ist()

    appt = Appointment(
        user_id=uid,
        title=d["title"].strip(),
        appointment_type=d.get("appointment_type", "doctor"),
        doctor_name=(d.get("doctor_name") or "").strip() or None,
        hospital_name=(d.get("hospital_name") or "").strip() or None,
        appointment_date=_date(d["appointment_date"]),
        appointment_time=d.get("appointment_time"),
        location=(d.get("location") or "").strip() or None,
        notes=(d.get("notes") or "").strip() or None,
        status="upcoming",
        reminder_1day=bool(d.get("reminder_1day", True)),
        reminder_1hour=bool(d.get("reminder_1hour", True)),
        reminder_at_time=bool(d.get("reminder_at_time", True)),
        reminder_custom_mins=d.get("reminder_custom_mins"),
        reminder_email=bool(d.get("reminder_email", False)) and _is_family(uid),
        member_id=d.get("member_id"),
    )
    appt.save()

    # Timeline event
    HealthTimelineEvent(
        user_id=uid, event_type="appointment", event_date=appt.appointment_date,
        title=f"{appt.type_icon} {appt.title}",
        description=f"{appt.hospital_name or ''} · {appt.appt_time or ''}",
        icon=appt.type_icon, member_id=appt.member_id,
    ).save()

    # Schedule reminders
    _schedule_reminders(uid, appt)

    return jsonify({"success": True, "message": f"📅 Appointment added", "data": appt.to_dict()}), 201


# ═════════════════════════════════════════════════════════════════
# UPDATE / STATUS ACTIONS
# ════════════════════════════════════════════════════════════════

@appointment_api_bp.route("/<int:aid>", methods=["PUT"])
@jwt_required()
def update_appointment(aid):
    uid = get_jwt_identity()
    appt = Appointment.get_by_id_or_404(aid)
    if appt.user_id != uid:
        return jsonify({"success": False, "message": "Forbidden"}), 403

    d = request.get_json() or {}

    for f in ["title", "appointment_type", "doctor_name", "hospital_name", "appointment_time",
              "location", "notes", "reminder_1day", "reminder_1hour", "reminder_at_time",
              "reminder_custom_mins", "reminder_email"]:
        if f in d:
            setattr(appt, f, d[f])

    if "appointment_date" in d:
        try:
            appt.appointment_date = date.fromisoformat(d["appointment_date"][:10])
        except:
            pass

    # Re-schedule reminders if date changed
    if "appointment_date" in d or "appointment_time" in d:
        _schedule_reminders(uid, appt)

    return jsonify({"success": True, "message": "Updated", "data": appt.to_dict()})


@appointment_api_bp.route("/<int:aid>/status", methods=["POST"])
@jwt_required()
def update_status(aid):
    uid = get_jwt_identity()
    appt = Appointment.get_by_id_or_404(aid)
    if appt.user_id != uid:
        return jsonify({"success": False, "message": "Forbidden"}), 403

    d = request.get_json() or {}
    action = d.get("action")   # complete / cancel / missed

    status_map = {"complete": "completed", "cancel": "cancelled", "missed": "missed"}
    new_status = status_map.get(action)
    if not new_status:
        return jsonify({"success": False, "message": f"Unknown action: {action}"}), 400

    appt.status = new_status
    appt.completed = (new_status == "completed")

    # Add timeline event
    if new_status == "completed":
        HealthTimelineEvent(
            user_id=uid, event_type="appointment", event_date=today_ist(),
            title=f"✅ Completed: {appt.title}",
            icon="✅", member_id=appt.member_id,
        ).save()

    # Send email for family appointments
    if appt.reminder_email and _is_family(uid):
        _send_appointment_email(uid, appt, new_status)

    msg_map = {"completed": "✅ Marked as completed", "cancelled": "⚪ Appointment cancelled", "missed": "🔴 Marked as missed"}
    return jsonify({"success": True, "message": msg_map.get(new_status, "Updated"), "data": appt.to_dict()})


# ══════════════════════════════════════════════════════════════════
# DELETE
# ═════════════════════════════════════════════════════════════════

@appointment_api_bp.route("/<int:aid>", methods=["DELETE"])
@jwt_required()
def delete_appointment(aid):
    uid = get_jwt_identity()
    appt = Appointment.get_by_id_or_404(aid)
    if appt.user_id != uid:
        return jsonify({"success": False, "message": "Forbidden"}), 403

    title = appt.title
    appt.delete()
    return jsonify({"success": True, "message": f"🗑️ {title} deleted"})


# ═════════════════════════════════════════════════════════════════
# SETTINGS
# ═════════════════════════════════════════════════════════════════

@appointment_api_bp.route("/settings", methods=["GET", "POST"])
@jwt_required()
def settings():
    from models import UserSettings
    uid = get_jwt_identity()

    if request.method == "GET":
        s = UserSettings.get_one(filters={"user_id": uid})
        return jsonify({"success": True, "data": {
            "reminders_enabled": getattr(s, "appt_reminders", True),
            "email_reminders":     getattr(s, "appt_email_reminders", False),
            "default_reminder_time": getattr(s, "appt_default_reminder", "1day"),
        }})

    d = request.get_json() or {}
    s = UserSettings.get_one(filters={"user_id": uid})
    if not s:
        from models import UserSettings
        s = UserSettings(user_id=uid)
        s.save()
    for field, attr in [("reminders_enabled", "appt_reminders"),
                        ("email_reminders", "appt_email_reminders"),
                        ("default_reminder_time", "appt_default_reminder")]:
        if field in d:
            setattr(s, attr, d[field])
    s.save()
    return jsonify({"success": True, "message": "Settings saved"})


# ═════════════════════════════════════════════════════════════════
# PRIVATE HELPERS
# ═════════════════════════════════════════════════════════════════

def _plan(uid):
    sub_list = UserSubscription.get_all(filters={"user_id": uid}, limit=1)
    sub = sub_list[0] if sub_list else None
    return sub.plan if sub and sub.is_active else "free"


def _limit(uid):
    plan = _plan(uid)
    lim = Appointment.PLAN_LIMITS.get(plan, 2)
    return lim  # None = unlimited


def _can_add(uid):
    lim = _limit(uid)
    if lim is None:
        return True
    count = len(Appointment.get_all(filters={"user_id": uid, "status": "upcoming"}))
    return count < lim


def _is_family(uid):
    return _plan(uid) == "family"


def _plan(uid):
    sub_list = UserSubscription.get_all(filters={"user_id": uid}, limit=1)
    sub = sub_list[0] if sub_list else None
    return sub.plan if sub and sub.is_active else "free"


def _limit(uid):
    plan = _plan(uid)
    lim = Appointment.PLAN_LIMITS.get(plan, 2)
    return lim  # None = unlimited


def _can_add(uid):
    lim = _limit(uid)
    if lim is None:
        return True
    count = len(Appointment.get_all(filters={"user_id": uid, "status": "upcoming"}))
    return count < lim


def _is_family(uid):
    return _plan(uid) == "family"


def _next_appt(user_id, member_id=None):
    today = today_ist()
    appts = Appointment.get_all(
        filters={"user_id": user_id, "status": "upcoming", "appointment_date_gte": today},
        order_by="appointment_date"
    )
    if member_id:
        appts = [a for a in appts if a.member_id == member_id]
    return appts[0] if appts else None


def _schedule_reminders(user_id, appt):
    """Create push notification reminders for the appointment."""
    from models import Reminder
    appt_dt = datetime.combine(appt.appointment_date, datetime.strptime(appt.appointment_time or "09:00", "%H:%M").time())
    base_msg = f"{appt.type_icon} {appt.title} — {appt.appointment_time or ''}"
    if appt.hospital_name:
        base_msg += f" at {appt.hospital_name}"

    reminders_to_create = []

    if appt.reminder_1day:
        remind_at = appt_dt - timedelta(days=1)
        if remind_at > datetime.now():
            reminders_to_create.append(("1 day before reminder", base_msg, remind_at))

    if appt.reminder_1hour:
        remind_at = appt_dt - timedelta(hours=1)
        if remind_at > datetime.now():
            reminders_to_create.append(("1 hour before reminder", base_msg, remind_at))

    if appt.reminder_at_time:
        reminders_to_create.append(("At appointment time", base_msg, appt_dt))

    if appt.reminder_custom_mins:
        remind_at = appt_dt - timedelta(minutes=appt.reminder_custom_mins)
        if remind_at > datetime.now():
            reminders_to_create.append((f"{appt.reminder_custom_mins}min before", base_msg, remind_at))

    for title, msg, remind_at in reminders_to_create:
        r = Reminder(
            user_id=user_id,
            title=f"📅 {appt.title}",
            message=msg,
            category="appointment",
            remind_time=remind_at.strftime("%H:%M"),
            is_active=True, is_daily=False, max_repeats=1,
            sound_name="health_alert",
        )
        r.save()


def _send_appointment_email(user_id, appt, status):
    """Send appointment status email to primary account (Family plan)."""
    try:
        user = User.get_by_id(user_id)
        if not user: return
        subject = f"📅 HealthTrack: {appt.title} — {status.title()}"
        body = f"""
<p>Hi {user.name},</p>
<p>An appointment has been <strong>{status}</strong>:</p>
<table border="1" cellpadding="8" style="border-collapse:collapse;font-family:sans-serif">
  <tr><td><b>Title</b></td><td>{appt.title}</td></tr>
  <tr><td><b>Type</b></td><td>{appt.type_label}</td></tr>
  <tr><td><b>Date</b></td><td>{appt.appointment_date} {appt.appt_time or ''}</td></tr>
  <tr><td><b>Doctor/Hospital</b></td><td>{appt.hospital_name or appt.doctor_name or '—'}</td></tr>
  <tr><td><b>Status</b></td><td>{appt.status_emoji} {status.title()}</td></tr>
</table>
<p>HealthTrack App</p>
"""
        from utils.email_sender import send_email
        send_email(user.email, subject, body)
    except Exception as e:
        current_app.logger.error(f"Appointment email error: {e}")