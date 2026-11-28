# ============================================================
# routes/api/notification_api.py — Push Notifications + Reminders
# ============================================================

from datetime import datetime, date, timedelta
import json

from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity

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
    user = User.get_by_id(uid)
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
    user = get_current_user()
    if not user:
        return err("User not found", 404)

    page = int(request.args.get("page", 1)) or 1
    per_page = 20
    unread_only = request.args.get("unread_only", "false").lower() == "true"

    filters = {"user_id": user.id}
    if request.args.get("unread_only", "false").lower() == "true":
        filters["is_read"] = False

    notifs = Notification.get_all(
        filters=filters,
        order_by="-created_at",
        limit=20
    )

    unread_count = Notification.count(filters={"user_id": user.id, "is_read": False})

    return ok({
        "notifications": [n.to_dict() for n in notifs],
        "unread_count": unread_count,
    })


# ── MARK NOTIFICATION AS READ ──────────────────────────────────
@notification_api_bp.route("/<int:notif_id>/read", methods=["POST"])
@jwt_required()
def mark_read(notif_id):
    user = get_current_user()
    notif = Notification.get_by_id_or_404(notif_id)
    if notif.user_id != user.id:
        return err("Forbidden", 403)

    notif.is_read = True
    notif.read_at = datetime.utcnow()
    notif.save()

    return ok(notif.to_dict(), "Marked as read")


# ── MARK ALL AS READ ───────────────────────────────────────────
@notification_api_bp.route("/read-all", methods=["POST"])
@jwt_required()
def mark_all_read():
    user = get_current_user()
    notifs = Notification.get_all(filters={"user_id": user.id, "is_read": False})
    for n in notifs:
        n.is_read = True
        n.read_at = datetime.utcnow()
        n.save()

    return ok(None, "All marked as read")


# ── DELETE NOTIFICATION ────────────────────────────────────────
@notification_api_bp.route("/<int:notif_id>", methods=["DELETE"])
@jwt_required()
def delete_notification(notif_id):
    user = get_current_user()
    notif = Notification.get_by_id_or_404(notif_id)
    if notif.user_id != user.id:
        return err("Forbidden", 403)

    notif.delete()
    return ok(None, "Deleted")


# ── GET UNREAD COUNT ───────────────────────────────────────────
@notification_api_bp.route("/unread-count", methods=["GET"])
@jwt_required()
def get_unread_count():
    user = get_current_user()
    count = Notification.count(filters={"user_id": user.id, "is_read": False})
    return ok({"unread_count": count})


# ============================================================
# REMINDERS
# ============================================================

# ── GET ALL REMINDERS ──────────────────────────────────────────
@notification_api_bp.route("/reminders", methods=["GET"])
@jwt_required()
def get_reminders():
    user = get_current_user()
    reminders = Reminder.get_all(
        filters={"user_id": user.id, "is_active": True},
        order_by="-created_at"
    )
    return ok({"reminders": [r.to_dict() for r in reminders]})


# ── CREATE REMINDER ────────────────────────────────────────────
@notification_api_bp.route("/reminders", methods=["POST"])
@jwt_required()
def create_reminder():
    user = get_current_user()
    data = request.get_json() or {}

    title = (data.get("title") or "").strip()
    if not title:
        return err("Title required", 422)

    remind_time = _parse_time_str(data.get("remind_time"))
    repeat = data.get("repeat_interval_mins", 5)
    max_repeats = data.get("max_repeats", 10)
    sound = data.get("sound", "health_alert")
    sound_enabled = data.get("sound_enabled", True)

    r = Reminder(
        user_id=user.id,
        title=data.get("title", "").strip(),
        message=data.get("message") or data.get("title", "").strip(),
        category=data.get("category", "custom"),
        remind_time=data.get("remind_time", "08:00"),
        repeat_interval_mins=data.get("repeat_interval_mins", 5),
        max_repeats=data.get("max_repeats", 10),
        sound_enabled=data.get("sound_enabled", True),
        sound_name=data.get("sound_name", "health_alert"),
        is_active=True,
        is_daily=True,
    )
    r.save()
    return ok(r.to_dict(), "Reminder created", 201)


# ── UPDATE REMINDER ────────────────────────────────────────────
@notification_api_bp.route("/reminders/<int:rem_id>", methods=["PUT"])
@jwt_required()
def update_reminder(rem_id):
    user = get_current_user()
    r = Reminder.get_by_id_or_404(rem_id)
    if r.user_id != user.id:
        return err("Forbidden", 403)

    data = request.get_json() or {}
    if "title" in data:
        r.title = data["title"].strip()
    if "message" in data:
        r.message = data["message"]
    if "category" in data:
        r.category = data["category"]
    if "remind_time" in data:
        r.remind_time = _parse_time_str(data["remind_time"])
    if "repeat_interval_mins" in data:
        r.repeat_interval_mins = data["repeat_interval_mins"]
    if "max_repeats" in data:
        r.max_repeats = data["max_repeats"]
    if "sound" in data:
        r.sound_name = data["sound"]
    if "sound_enabled" in data:
        r.sound_enabled = data["sound_enabled"]
    if "is_active" in data:
        r.is_active = data["is_active"]
    if "is_daily" in data:
        r.is_daily = data["is_daily"]

    r.save()
    return ok(r.to_dict(), "Reminder updated")


# ── TOGGLE REMINDER ACTIVE ──────────────────────────────────────
@notification_api_bp.route("/reminders/<int:rem_id>/toggle", methods=["POST"])
@jwt_required()
def toggle_reminder(rem_id):
    user = get_current_user()
    r = Reminder.get_by_id_or_404(rem_id)
    if r.user_id != user.id:
        return err("Forbidden", 403)

    r.is_active = not r.is_active
    r.save()
    return ok(r.to_dict(), f"Reminder {'enabled' if r.is_active else 'disabled'}")


# ── DELETE REMINDER ────────────────────────────────────────────
@notification_api_bp.route("/reminders/<int:rem_id>", methods=["DELETE"])
@jwt_required()
def delete_reminder(rem_id):
    user = get_current_user()
    r = Reminder.get_by_id_or_404(rem_id)
    if r.user_id != user.id:
        return err("Forbidden", 403)
    r.delete()
    return ok(None, "Reminder deleted")


# ── DEFAULT REMINDERS ──────────────────────────────────────────
@notification_api_bp.route("/reminders/setup-defaults", methods=["POST"])
@jwt_required()
def setup_default_reminders():
    user = get_current_user()
    existing = Reminder.count(filters={"user_id": user.id, "is_active": True})
    if existing > 0:
        return ok(None, "Reminders already set up")

    defaults = [
        {"title": "💊 Take Medicine", "category": "medicine", "remind_time": "08:00", "interval": 5, "sound": "medicine"},
        {"title": "❤️ Morning BP Check", "category": "bp", "remind_time": "07:30", "interval": 5, "sound": "health_alert"},
        {"title": "❤️ Evening BP Check", "category": "bp", "remind_time": "19:00", "interval": 5, "sound": "health_alert"},
        {"title": "💧 Drink Water", "category": "water", "remind_time": "10:00", "interval": 10, "sound": "water_drop"},
        {"title": "💧 Afternoon Water", "category": "water", "remind_time": "14:00", "interval": 10, "sound": "water_drop"},
        {"title": "💧 Evening Water", "category": "water", "remind_time": "18:00", "interval": 10, "sound": "water_drop"},
        {"title": "🏃 Exercise Time", "category": "exercise", "remind_time": "07:00", "interval": 10, "sound": "gentle"},
        {"title": "😴 Bedtime Reminder", "category": "sleep", "remind_time": "22:00", "interval": 15, "sound": "gentle"},
    ]

    for d in defaults:
        r = Reminder(
            user_id=get_current_user().id,
            title=d["title"],
            message=d["title"],
            category=d["category"],
            remind_time=d["remind_time"],
            repeat_interval_mins=d["interval"],
            max_repeats=10,
            sound_enabled=True,
            sound_name=d["sound"],
            is_active=True,
            is_daily=True,
        )
        r.save()

    return ok(None, f"{len(defaults)} default reminders created")