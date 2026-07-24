# ============================================================
# routes/api/notification_api.py — Push Notifications + Reminders
# ============================================================

from datetime import datetime, date, timedelta
import json

from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity

from extensions import db
from models import Notification, Reminder, User

notification_api_bp = Blueprint("notification_api", __name__)


def ok(data=None, msg="Success", code=200):
    response = {
        "success": True,
        "message": msg,
    }
    if data is not None:
        response["data"] = data
    return jsonify(response), code


def err(msg="Error", code=400):
    return jsonify({"success": False, "message": msg}), code


def _current_user():
    uid = get_jwt_identity()
    user = User.query.get(uid)
    return user


def _parse_bool(value, default=False):
    if isinstance(value, bool):
        return value
    if value is None:
        return default
    return str(value).strip().lower() in ("true", "1", "yes", "on")


def _parse_int(value, default, min_value=None, max_value=None):
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        parsed = default

    if min_value is not None and parsed < min_value:
        parsed = min_value
    if max_value is not None and parsed > max_value:
        parsed = max_value

    return parsed


def _parse_time_str(value, default="08:00"):
    value = (value or default).strip()
    try:
        datetime.strptime(value, "%H:%M")
        return value
    except ValueError:
        return default


# ── GET ALL NOTIFICATIONS ─────────────────────────────────────
@notification_api_bp.route("/", methods=["GET"])
@jwt_required()
def get_notifications():
    user = _current_user()
    if not user:
        return err("User not found", 404)

    page = _parse_int(request.args.get("page", 1), 1, min_value=1)
    per_page = 20
    unread_only = request.args.get("unread_only", "false").lower() == "true"

    q = Notification.query.filter_by(user_id=user.id)
    if unread_only:
        q = q.filter_by(is_read=False)

    notifs = q.order_by(Notification.created_at.desc()).paginate(
        page=page, per_page=per_page, error_out=False
    )

    unread_count = Notification.query.filter_by(
        user_id=user.id, is_read=False
    ).count()

    return ok({
        "notifications": [n.to_dict() for n in notifs.items],
        "unread_count": unread_count,
        "total": notifs.total,
        "page": page,
        "has_more": notifs.has_next,
    })


# ── MARK READ ─────────────────────────────────────────────────
@notification_api_bp.route("/<int:notif_id>/read", methods=["POST"])
@jwt_required()
def mark_read(notif_id):
    user = _current_user()
    if not user:
        return err("User not found", 404)

    notif = Notification.query.filter_by(id=notif_id, user_id=user.id).first()
    if not notif:
        return err("Notification not found", 404)

    notif.is_read = True
    db.session.commit()
    return ok(msg="Marked as read")


# ── MARK ALL READ ─────────────────────────────────────────────
@notification_api_bp.route("/read-all", methods=["POST"])
@jwt_required()
def mark_all_read():
    user = _current_user()
    if not user:
        return err("User not found", 404)

    Notification.query.filter_by(user_id=user.id, is_read=False).update(
        {"is_read": True},
        synchronize_session=False
    )
    db.session.commit()
    return ok(msg="All notifications marked as read")


# ── UNREAD COUNT ──────────────────────────────────────────────
@notification_api_bp.route("/unread-count", methods=["GET"])
@jwt_required()
def unread_count():
    user = _current_user()
    if not user:
        return err("User not found", 404)

    count = Notification.query.filter_by(user_id=user.id, is_read=False).count()
    return ok({"count": count})


# ══════════════════════════════════════════════════════════════
# REMINDERS — CRUD
# ══════════════════════════════════════════════════════════════

# ── GET ALL REMINDERS ─────────────────────────────────────────
@notification_api_bp.route("/reminders", methods=["GET"])
@jwt_required()
def get_reminders():
    user = _current_user()
    if not user:
        return err("User not found", 404)

    reminders = Reminder.query.filter_by(user_id=user.id).order_by(Reminder.id.desc()).all()

    result = []
    for rem in reminders:
        if hasattr(rem, "reset_daily"):
            rem.reset_daily()
        result.append(rem.to_dict())

    db.session.commit()
    return ok({"reminders": result})


# ── CREATE REMINDER ───────────────────────────────────────────
@notification_api_bp.route("/reminders", methods=["POST"])
@jwt_required()
def create_reminder():
    user = _current_user()
    if not user:
        return err("User not found", 404)

    data = request.get_json() or {}

    title = (data.get("title") or "").strip()
    message = (data.get("message") or "").strip()
    category = (data.get("category") or "custom").strip()

    if not title:
        return err("Title is required", 422)

    reminder = Reminder(
        user_id=user.id,
        title=title,
        message=message or title,
        category=category,
        remind_time=_parse_time_str(data.get("remind_time", "08:00")),
        is_daily=_parse_bool(data.get("is_daily", True), True),
        active_days=(data.get("active_days") or "1,2,3,4,5,6,7"),
        repeat_interval_mins=_parse_int(data.get("repeat_interval_mins", 5), 5, min_value=1, max_value=1440),
        max_repeats=_parse_int(data.get("max_repeats", 10), 10, min_value=0, max_value=100),
        sound_enabled=_parse_bool(data.get("sound_enabled", True), True),
        sound_name=(data.get("sound_name") or "health_alert").strip(),
        is_active=True,
    )

    if hasattr(reminder, "created_at") and getattr(reminder, "created_at", None) is None:
        reminder.created_at = datetime.utcnow()
    if hasattr(reminder, "updated_at"):
        reminder.updated_at = datetime.utcnow()

    db.session.add(reminder)
    db.session.commit()
    return ok(reminder.to_dict(), msg="Reminder created", code=201)


# ── UPDATE REMINDER ───────────────────────────────────────────
@notification_api_bp.route("/reminders/<int:rem_id>", methods=["PUT"])
@jwt_required()
def update_reminder(rem_id):
    user = _current_user()
    if not user:
        return err("User not found", 404)

    rem = Reminder.query.filter_by(id=rem_id, user_id=user.id).first()
    if not rem:
        return err("Reminder not found", 404)

    data = request.get_json() or {}

    if "title" in data and data["title"] is not None:
        title = str(data["title"]).strip()
        if not title:
            return err("Title cannot be empty", 422)
        rem.title = title

    if "message" in data and data["message"] is not None:
        rem.message = str(data["message"]).strip()

    if "category" in data and data["category"] is not None:
        rem.category = str(data["category"]).strip()

    if "remind_time" in data:
        rem.remind_time = _parse_time_str(data.get("remind_time"), rem.remind_time or "08:00")

    if "repeat_interval_mins" in data:
        rem.repeat_interval_mins = _parse_int(
            data["repeat_interval_mins"],
            rem.repeat_interval_mins or 5,
            min_value=1,
            max_value=1440
        )

    if "sound_enabled" in data:
        rem.sound_enabled = _parse_bool(data["sound_enabled"], rem.sound_enabled)

    if "sound_name" in data and data["sound_name"] is not None:
        rem.sound_name = str(data["sound_name"]).strip()

    if "is_active" in data:
        rem.is_active = _parse_bool(data["is_active"], rem.is_active)

    if "is_daily" in data:
        rem.is_daily = _parse_bool(data["is_daily"], rem.is_daily)

    if "active_days" in data and data["active_days"] is not None:
        rem.active_days = str(data["active_days"])

    if "max_repeats" in data:
        rem.max_repeats = _parse_int(
            data["max_repeats"],
            rem.max_repeats or 10,
            min_value=0,
            max_value=100
        )

    if hasattr(rem, "updated_at"):
        rem.updated_at = datetime.utcnow()

    db.session.commit()
    return ok(rem.to_dict(), msg="Reminder updated")


# ── DELETE REMINDER ───────────────────────────────────────────
@notification_api_bp.route("/reminders/<int:rem_id>", methods=["DELETE"])
@jwt_required()
def delete_reminder(rem_id):
    user = _current_user()
    if not user:
        return err("User not found", 404)

    rem = Reminder.query.filter_by(id=rem_id, user_id=user.id).first()
    if not rem:
        return err("Reminder not found", 404)

    db.session.delete(rem)
    db.session.commit()
    return ok(msg="Reminder deleted")


# ── MARK REMINDER DONE TODAY ──────────────────────────────────
@notification_api_bp.route("/reminders/<int:rem_id>/done", methods=["POST"])
@jwt_required()
def mark_reminder_done(rem_id):
    user = _current_user()
    if not user:
        return err("User not found", 404)

    rem = Reminder.query.filter_by(id=rem_id, user_id=user.id).first()
    if not rem:
        return err("Reminder not found", 404)

    if hasattr(rem, "is_done_today"):
        rem.is_done_today = True
    if hasattr(rem, "done_reset_date"):
        rem.done_reset_date = date.today()
    if hasattr(rem, "updated_at"):
        rem.updated_at = datetime.utcnow()

    db.session.commit()
    return ok(msg=f"Reminder '{rem.title}' marked done for today. Well done! ✅")


# ── SNOOZE REMINDER ───────────────────────────────────────────
@notification_api_bp.route("/reminders/<int:rem_id>/snooze", methods=["POST"])
@jwt_required()
def snooze_reminder(rem_id):
    user = _current_user()
    if not user:
        return err("User not found", 404)

    rem = Reminder.query.filter_by(id=rem_id, user_id=user.id).first()
    if not rem:
        return err("Reminder not found", 404)

    data = request.get_json() or {}
    snooze_mins = _parse_int(data.get("minutes", 10), 10, min_value=1, max_value=1440)

    if hasattr(rem, "last_triggered_at"):
        rem.last_triggered_at = datetime.utcnow() + timedelta(minutes=snooze_mins)
    if hasattr(rem, "updated_at"):
        rem.updated_at = datetime.utcnow()

    db.session.commit()
    return ok(msg=f"Snoozed for {snooze_mins} minutes")


# ── REGISTER WEB PUSH SUBSCRIPTION ───────────────────────────
@notification_api_bp.route("/web-push/subscribe", methods=["POST"])
@jwt_required()
def web_push_subscribe():
    user = _current_user()
    if not user:
        return err("User not found", 404)

    data = request.get_json() or {}
    subscription = data.get("subscription")

    if not subscription:
        return err("Subscription data required", 400)

    if not hasattr(user, "web_push_sub"):
        return err("User model does not support web push subscriptions", 500)

    user.web_push_sub = json.dumps(subscription)
    db.session.commit()
    return ok(msg="Web push subscription saved")


# ── SEND TEST NOTIFICATION ────────────────────────────────────
@notification_api_bp.route("/test", methods=["POST"])
@jwt_required()
def send_test():
    user = _current_user()
    if not user:
        return err("User not found", 404)

    from utils.firebase_push import send_push_to_user

    success = send_push_to_user(
        user=user,
        title="🏥 HealthTrack Test",
        body="Your notifications are working perfectly! 🎉",
        data={"type": "test"},
        sound="health_alert"
    )

    if success:
        return ok(msg="Test notification sent successfully!")
    return err("Failed to send — check FCM token or web push subscription", 500)


# ── DEFAULT REMINDERS SETUP ───────────────────────────────────
@notification_api_bp.route("/reminders/setup-defaults", methods=["POST"])
@jwt_required()
def setup_default_reminders():
    user = _current_user()
    if not user:
        return err("User not found", 404)

    existing = Reminder.query.filter_by(user_id=user.id).count()
    if existing > 0:
        return ok(msg="Reminders already configured")

    defaults = [
        {
            "title": "💊 Take Your Medicine",
            "message": "Time to take your morning medicine. Don't skip — consistency matters!",
            "category": "medicine",
            "remind_time": "08:00",
            "repeat_interval_mins": 5,
            "sound_name": "medicine",
        },
        {
            "title": "❤️ Morning BP Check",
            "message": "Log your morning blood pressure reading. Sit quietly for 5 minutes first.",
            "category": "bp",
            "remind_time": "07:30",
            "repeat_interval_mins": 5,
            "sound_name": "health_alert",
        },
        {
            "title": "❤️ Evening BP Check",
            "message": "Log your evening blood pressure reading before dinner.",
            "category": "bp",
            "remind_time": "19:00",
            "repeat_interval_mins": 5,
            "sound_name": "health_alert",
        },
        {
            "title": "💧 Drink Water",
            "message": "Stay hydrated! Drink a glass of water now.",
            "category": "water",
            "remind_time": "10:00",
            "repeat_interval_mins": 10,
            "sound_name": "water_drop",
        },
        {
            "title": "💧 Afternoon Water",
            "message": "Afternoon hydration check — have you had enough water today?",
            "category": "water",
            "remind_time": "14:00",
            "repeat_interval_mins": 10,
            "sound_name": "water_drop",
        },
        {
            "title": "💧 Evening Water",
            "message": "Evening hydration — drink your last water of the day.",
            "category": "water",
            "remind_time": "18:00",
            "repeat_interval_mins": 10,
            "sound_name": "water_drop",
        },
        {
            "title": "🏃 Exercise Time",
            "message": "30 minutes of light exercise helps lower BP naturally. Let's move!",
            "category": "exercise",
            "remind_time": "07:00",
            "repeat_interval_mins": 10,
            "sound_name": "gentle",
        },
        {
            "title": "😴 Bedtime Reminder",
            "message": "Wind down for sleep. 7–8 hours of sleep is essential for BP recovery.",
            "category": "sleep",
            "remind_time": "22:00",
            "repeat_interval_mins": 15,
            "sound_name": "gentle",
        },
    ]

    for item in defaults:
        r = Reminder(
            user_id=user.id,
            title=item["title"],
            message=item["message"],
            category=item["category"],
            remind_time=item["remind_time"],
            repeat_interval_mins=item.get("repeat_interval_mins", 5),
            max_repeats=10,
            sound_enabled=True,
            sound_name=item.get("sound_name", "health_alert"),
            is_active=True,
            is_daily=True,
            active_days="1,2,3,4,5,6,7",
        )

        if hasattr(r, "created_at") and getattr(r, "created_at", None) is None:
            r.created_at = datetime.utcnow()
        if hasattr(r, "updated_at"):
            r.updated_at = datetime.utcnow()

        db.session.add(r)

    db.session.commit()
    return ok(msg=f"{len(defaults)} default reminders created", code=201)