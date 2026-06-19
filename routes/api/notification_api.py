# ============================================================
# routes/api/notification_api.py — Push Notifications + Reminders
# ============================================================

from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_current_user
from datetime import datetime, date, timedelta

from extensions import db
from models import Notification, Reminder

notification_api_bp = Blueprint("notification_api", __name__)


def ok(data=None, msg="Success", code=200):
    r = {"success": True, "message": msg}
    if data is not None: r["data"] = data
    return jsonify(r), code


def err(msg="Error", code=400):
    return jsonify({"success": False, "message": msg}), code


# ── GET ALL NOTIFICATIONS ─────────────────────────────────────
@notification_api_bp.route("/", methods=["GET"])
@jwt_required()
def get_notifications():
    user    = get_current_user()
    page    = int(request.args.get("page", 1))
    per_page= 20
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
        "unread_count":  unread_count,
        "total":         notifs.total,
        "page":          page,
        "has_more":      notifs.has_next,
    })


# ── MARK READ ─────────────────────────────────────────────────
@notification_api_bp.route("/<int:notif_id>/read", methods=["POST"])
@jwt_required()
def mark_read(notif_id):
    user  = get_current_user()
    notif = Notification.query.filter_by(id=notif_id, user_id=user.id).first()
    if not notif: return err("Notification not found", 404)
    notif.is_read = True
    db.session.commit()
    return ok(message="Marked as read")


# ── MARK ALL READ ─────────────────────────────────────────────
@notification_api_bp.route("/read-all", methods=["POST"])
@jwt_required()
def mark_all_read():
    user = get_current_user()
    Notification.query.filter_by(user_id=user.id, is_read=False).update({"is_read": True})
    db.session.commit()
    return ok(message="All notifications marked as read")


# ── UNREAD COUNT ──────────────────────────────────────────────
@notification_api_bp.route("/unread-count", methods=["GET"])
@jwt_required()
def unread_count():
    user  = get_current_user()
    count = Notification.query.filter_by(user_id=user.id, is_read=False).count()
    return ok({"count": count})


# ══════════════════════════════════════════════════════════════
# REMINDERS — CRUD
# ══════════════════════════════════════════════════════════════

# ── GET ALL REMINDERS ─────────────────────────────────────────
@notification_api_bp.route("/reminders", methods=["GET"])
@jwt_required()
def get_reminders():
    user      = get_current_user()
    reminders = Reminder.query.filter_by(user_id=user.id).all()
    today     = date.today()

    result = []
    for r in reminders:
        r.reset_daily()
        d = r.to_dict()
        result.append(d)

    db.session.commit()
    return ok({"reminders": result})


# ── CREATE REMINDER ───────────────────────────────────────────
@notification_api_bp.route("/reminders", methods=["POST"])
@jwt_required()
def create_reminder():
    user = get_current_user()
    data = request.get_json() or {}

    title    = data.get("title", "").strip()
    message  = data.get("message", "").strip()
    category = data.get("category", "custom")

    if not title:
        return err("Title is required", 422)

    reminder = Reminder(
        user_id              = user.id,
        title                = title,
        message              = message or title,
        category             = category,
        remind_time          = data.get("remind_time", "08:00"),
        is_daily             = data.get("is_daily", True),
        active_days          = data.get("active_days", "1,2,3,4,5,6,7"),
        repeat_interval_mins = int(data.get("repeat_interval_mins", 5)),
        max_repeats          = int(data.get("max_repeats", 10)),
        sound_enabled        = data.get("sound_enabled", True),
        sound_name           = data.get("sound_name", "health_alert"),
        is_active            = True,
    )
    db.session.add(reminder)
    db.session.commit()
    return ok(reminder.to_dict(), "Reminder created", 201)


# ── UPDATE REMINDER ───────────────────────────────────────────
@notification_api_bp.route("/reminders/<int:rem_id>", methods=["PUT"])
@jwt_required()
def update_reminder(rem_id):
    user = get_current_user()
    rem  = Reminder.query.filter_by(id=rem_id, user_id=user.id).first()
    if not rem: return err("Reminder not found", 404)

    data = request.get_json() or {}

    if "title"    in data: rem.title    = data["title"].strip()
    if "message"  in data: rem.message  = data["message"].strip()
    if "remind_time" in data: rem.remind_time = data["remind_time"]
    if "repeat_interval_mins" in data:
        rem.repeat_interval_mins = int(data["repeat_interval_mins"])
    if "sound_enabled" in data: rem.sound_enabled = bool(data["sound_enabled"])
    if "sound_name"    in data: rem.sound_name    = data["sound_name"]
    if "is_active"     in data: rem.is_active     = bool(data["is_active"])
    if "is_daily"      in data: rem.is_daily      = bool(data["is_daily"])
    if "active_days"   in data: rem.active_days   = data["active_days"]
    if "max_repeats"   in data: rem.max_repeats   = int(data["max_repeats"])

    rem.updated_at = datetime.utcnow()
    db.session.commit()
    return ok(rem.to_dict(), "Reminder updated")


# ── DELETE REMINDER ───────────────────────────────────────────
@notification_api_bp.route("/reminders/<int:rem_id>", methods=["DELETE"])
@jwt_required()
def delete_reminder(rem_id):
    user = get_current_user()
    rem  = Reminder.query.filter_by(id=rem_id, user_id=user.id).first()
    if not rem: return err("Reminder not found", 404)
    db.session.delete(rem)
    db.session.commit()
    return ok(message="Reminder deleted")


# ── MARK REMINDER DONE TODAY ──────────────────────────────────
@notification_api_bp.route("/reminders/<int:rem_id>/done", methods=["POST"])
@jwt_required()
def mark_reminder_done(rem_id):
    """
    User taps 'Done' — stop repeating for today.
    Resets automatically at midnight.
    """
    user = get_current_user()
    rem  = Reminder.query.filter_by(id=rem_id, user_id=user.id).first()
    if not rem: return err("Reminder not found", 404)

    rem.is_done_today   = True
    rem.done_reset_date = date.today()
    db.session.commit()

    return ok(message=f"Reminder '{rem.title}' marked done for today. Well done! ✅")


# ── SNOOZE REMINDER ───────────────────────────────────────────
@notification_api_bp.route("/reminders/<int:rem_id>/snooze", methods=["POST"])
@jwt_required()
def snooze_reminder(rem_id):
    """Snooze for X minutes."""
    user = get_current_user()
    rem  = Reminder.query.filter_by(id=rem_id, user_id=user.id).first()
    if not rem: return err("Reminder not found", 404)

    data        = request.get_json() or {}
    snooze_mins = int(data.get("minutes", 10))

    # Set last_triggered_at to now + snooze_mins
    # This prevents re-triggering until snooze expires
    rem.last_triggered_at = datetime.utcnow() + timedelta(minutes=snooze_mins)
    db.session.commit()

    return ok(message=f"Snoozed for {snooze_mins} minutes")


# ── REGISTER WEB PUSH SUBSCRIPTION ───────────────────────────
@notification_api_bp.route("/web-push/subscribe", methods=["POST"])
@jwt_required()
def web_push_subscribe():
    """Save browser's web push subscription for website notifications."""
    user = get_current_user()
    data = request.get_json() or {}

    subscription = data.get("subscription")
    if not subscription:
        return err("Subscription data required", 400)

    import json
    user.web_push_sub = json.dumps(subscription)
    db.session.commit()
    return ok(message="Web push subscription saved")


# ── SEND TEST NOTIFICATION ────────────────────────────────────
@notification_api_bp.route("/test", methods=["POST"])
@jwt_required()
def send_test():
    """Send a test push notification to verify setup."""
    user = get_current_user()
    from utils.firebase_push import send_push_to_user

    success = send_push_to_user(
        user=user,
        title="🏥 HealthTrack Test",
        body="Your notifications are working perfectly! 🎉",
        data={"type": "test"},
        sound="health_alert"
    )

    if success:
        return ok(message="Test notification sent successfully!")
    return err("Failed to send — check FCM token or web push subscription", 500)


# ── DEFAULT REMINDERS SETUP ───────────────────────────────────
@notification_api_bp.route("/reminders/setup-defaults", methods=["POST"])
@jwt_required()
def setup_default_reminders():
    """Create default reminders for new users."""
    user = get_current_user()

    # Check if already set up
    existing = Reminder.query.filter_by(user_id=user.id).count()
    if existing > 0:
        return ok(message="Reminders already configured")

    defaults = [
        {
            "title":   "💊 Take Your Medicine",
            "message": "Time to take your morning medicine. Don't skip — consistency matters!",
            "category": "medicine",
            "remind_time": "08:00",
            "repeat_interval_mins": 5,
            "sound_name": "medicine",
        },
        {
            "title":   "❤️ Morning BP Check",
            "message": "Log your morning blood pressure reading. Sit quietly for 5 minutes first.",
            "category": "bp",
            "remind_time": "07:30",
            "repeat_interval_mins": 5,
            "sound_name": "health_alert",
        },
        {
            "title":   "❤️ Evening BP Check",
            "message": "Log your evening blood pressure reading before dinner.",
            "category": "bp",
            "remind_time": "19:00",
            "repeat_interval_mins": 5,
            "sound_name": "health_alert",
        },
        {
            "title":   "💧 Drink Water",
            "message": "Stay hydrated! Drink a glass of water now.",
            "category": "water",
            "remind_time": "10:00",
            "repeat_interval_mins": 10,
            "sound_name": "water_drop",
        },
        {
            "title":   "💧 Afternoon Water",
            "message": "Afternoon hydration check — have you had enough water today?",
            "category": "water",
            "remind_time": "14:00",
            "repeat_interval_mins": 10,
            "sound_name": "water_drop",
        },
        {
            "title":   "💧 Evening Water",
            "message": "Evening hydration — drink your last water of the day.",
            "category": "water",
            "remind_time": "18:00",
            "repeat_interval_mins": 10,
            "sound_name": "water_drop",
        },
        {
            "title":   "🏃 Exercise Time",
            "message": "30 minutes of light exercise helps lower BP naturally. Let's move!",
            "category": "exercise",
            "remind_time": "07:00",
            "repeat_interval_mins": 10,
            "sound_name": "gentle",
        },
        {
            "title":   "😴 Bedtime Reminder",
            "message": "Wind down for sleep. 7–8 hours of sleep is essential for BP recovery.",
            "category": "sleep",
            "remind_time": "22:00",
            "repeat_interval_mins": 15,
            "sound_name": "gentle",
        },
    ]

    for d in defaults:
        r = Reminder(
            user_id              = user.id,
            title                = d["title"],
            message              = d["message"],
            category             = d["category"],
            remind_time          = d["remind_time"],
            repeat_interval_mins = d.get("repeat_interval_mins", 5),
            max_repeats          = 10,
            sound_enabled        = True,
            sound_name           = d.get("sound_name", "health_alert"),
            is_active            = True,
            is_daily             = True,
        )
        db.session.add(r)

    db.session.commit()
    return ok(message=f"{len(defaults)} default reminders created", code=201)
