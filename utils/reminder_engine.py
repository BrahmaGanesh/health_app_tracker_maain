# ============================================================
# utils/reminder_engine.py — Smart Repeating Reminder Engine
# Runs every 1 minute via APScheduler
# Sends sound notifications until user marks done
# ============================================================

import logging
from datetime import datetime, date, timedelta

logger = logging.getLogger(__name__)


def run_reminder_check():
    """
    Called every 1 minute by scheduler.
    Checks all active reminders, sends push if time matches.
    Repeats every N minutes until user marks done.
    """
    from app import app, db
    with app.app_context():
        _process_reminders(db)


def _process_reminders(db):
    from models import Reminder, User
    from utils.firebase_push import send_push_to_user

    now      = datetime.now()
    today    = date.today()
    weekday  = today.isoweekday()  # 1=Mon, 7=Sun
    now_hhmm = now.strftime("%H:%M")

    # Get all active reminders
    reminders = Reminder.query.filter_by(is_active=True).all()

    for rem in reminders:
        try:
            # Reset done status for new day
            rem.reset_daily()

            # Skip if already done today
            if rem.is_done_today:
                continue

            # Check if today is an active day
            active_days = [int(d) for d in (rem.active_days or "1,2,3,4,5,6,7").split(",") if d.strip()]
            if weekday not in active_days:
                continue

            # Check if we should trigger
            should_trigger = False
            remind_hhmm    = rem.remind_time or "08:00"

            if rem.last_triggered_at is None:
                # First trigger: check if current time matches remind_time
                if now_hhmm == remind_hhmm:
                    should_trigger = True
            else:
                # Subsequent triggers: check if repeat interval has passed
                mins_since_last = (now - rem.last_triggered_at).total_seconds() / 60
                if mins_since_last >= rem.repeat_interval_mins:
                    # Also check: don't re-trigger before original remind_time
                    rem_hour, rem_min = map(int, remind_hhmm.split(":"))
                    rem_dt = now.replace(hour=rem_hour, minute=rem_min, second=0, microsecond=0)
                    if now >= rem_dt:
                        should_trigger = True

                    # Check max repeats
                    if rem.repeat_count_today >= rem.max_repeats:
                        should_trigger = False

            if not should_trigger:
                continue

            # Get user
            user = User.query.get(rem.user_id)
            if not user or not user.is_active:
                continue

            # Send push notification with sound
            sound = rem.sound_name if rem.sound_enabled else None
            push_sent = send_push_to_user(
                user  = user,
                title = rem.title,
                body  = rem.message,
                data  = {
                    "type":        "reminder",
                    "reminder_id": rem.id,
                    "category":    rem.category or "custom",
                    "sound":       sound or "health_alert",
                    "repeat_num":  rem.repeat_count_today + 1,
                },
                sound = sound or "health_alert"
            )

            # Save in-app notification
            _create_inapp_notification(db, user, rem, rem.repeat_count_today + 1)

            # Update tracker
            rem.last_triggered_at   = datetime.utcnow()
            rem.repeat_count_today  = (rem.repeat_count_today or 0) + 1

            logger.info(
                f"Reminder '{rem.title}' sent to user {user.id} "
                f"(repeat #{rem.repeat_count_today}, push={push_sent})"
            )

        except Exception as e:
            logger.error(f"Reminder {rem.id} error: {e}")
            continue

    try:
        db.session.commit()
    except Exception as e:
        db.session.rollback()
        logger.error(f"Reminder engine commit error: {e}")


def _create_inapp_notification(db, user, rem, repeat_num):
    """Save in-app notification so user sees it in the app."""
    from models import Notification

    # Don't spam in-app — only save first occurrence per day per reminder
    today = date.today()
    from sqlalchemy import func
    existing = Notification.query.filter(
        Notification.user_id    == user.id,
        Notification.reminder_id == rem.id,
        func.date(Notification.created_at) == today
    ).first()

    if existing and repeat_num > 1:
        return  # Already have one for today

    notif = Notification(
        user_id     = user.id,
        notif_type  = "reminder",
        category    = rem.category,
        title       = rem.title,
        message     = rem.message,
        icon        = _get_category_icon(rem.category),
        sound       = rem.sound_name if rem.sound_enabled else "none",
        delivered_via = "both",
        reminder_id = rem.id,
    )
    db.session.add(notif)


def _get_category_icon(category):
    icons = {
        "water":    "💧",
        "medicine": "💊",
        "bp":       "❤️",
        "exercise": "🏃",
        "sleep":    "😴",
        "sugar":    "🩺",
        "steps":    "👟",
        "custom":   "🔔",
    }
    return icons.get(category, "🔔")


def create_alert_notification(user, alert_type, category, title, message, sound="health_alert"):
    """
    Create an alert + notification + push for threshold violations.
    Called when BP/sugar/water goes out of range.
    """
    from app import db
    from models import Alert, Notification
    from utils.firebase_push import send_push_to_user
    from datetime import timedelta

    # Avoid duplicate alerts within 6 hours
    from sqlalchemy import func
    recent = Alert.query.filter(
        Alert.user_id    == user.id,
        Alert.alert_type == alert_type,
        Alert.category   == category,
        Alert.is_dismissed == False,
        Alert.created_at >= datetime.utcnow() - timedelta(hours=6)
    ).first()

    if recent:
        return

    # Create alert record
    alert = Alert(
        user_id     = user.id,
        alert_type  = alert_type,
        category    = category,
        title       = title,
        message     = message,
    )
    db.session.add(alert)

    # Create in-app notification
    notif = Notification(
        user_id      = user.id,
        notif_type   = "alert",
        category     = category,
        title        = title,
        message      = message,
        icon         = "🚨" if alert_type == "emergency" else "⚠️",
        sound        = sound,
        delivered_via = "both",
    )
    db.session.add(notif)

    try:
        db.session.commit()
    except Exception:
        db.session.rollback()
        return

    # Send push immediately
    send_push_to_user(
        user  = user,
        title = title,
        body  = message,
        data  = {"type": "alert", "category": category, "alert_type": alert_type},
        sound = sound
    )