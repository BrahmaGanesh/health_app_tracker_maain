# routes/notification_routes.py — In-App Notifications Website
from flask import Blueprint, render_template, redirect, url_for, flash, request, jsonify
from flask_login import login_required, current_user
from flask_jwt_extended import create_access_token
from datetime import datetime
from models import Notification, Reminder

notification_bp = Blueprint("notifications", __name__)

@notification_bp.route("/api-token")
@login_required
def api_token():
    """
    Issue a short-lived JWT for the currently logged-in (session) user,
    so website JS (notifications.js) can call /api/v1/* endpoints
    for polling, web-push subscription, and reminder actions.
    """
    token = create_access_token(identity=current_user.id)
    return jsonify({"access_token": token})


@notification_bp.route("/")
@login_required
def index():
    notifs = Notification.get_all(filters={"user_id": current_user.id}, order_by="-created_at")
    unread = Notification.count(filters={"user_id": current_user.id, "is_read": False})
    reminders = Reminder.get_all(filters={"user_id": current_user.id, "is_active": True})
    return render_template("notifications/index.html",
                           notifs=notifs, unread=unread, reminders=reminders)


@notification_bp.route("/read-all")
@login_required
def read_all():
    notifs = Notification.get_all(filters={"user_id": current_user.id, "is_read": False})
    for n in notifs:
        n.is_read = True
        n.read_at = datetime.utcnow()
        n.save()
    # db.session.commit()  # Firestore auto-commits
    return redirect(url_for("notifications.index"))


@notification_bp.route("/reminders")
@login_required
def reminders():
    rems = Reminder.get_all(filters={"user_id": current_user.id, "is_active": True})
    return render_template("notifications/reminders.html", reminders=rems)


@notification_bp.route("/reminders/add", methods=["POST"])
@login_required
def add_reminder():
    title    = request.form.get("title","").strip()
    message  = request.form.get("message","").strip()
    category = request.form.get("category","custom")
    if not title:
        flash("Title is required.", "danger")
        return redirect(url_for("notifications.reminders"))
    r = Reminder(
        user_id              = current_user.id,
        title                = title,
        message              = message or title,
        category             = category,
        remind_time          = request.form.get("remind_time","08:00"),
        repeat_interval_mins = int(request.form.get("repeat_interval_mins",5)),
        max_repeats          = int(request.form.get("max_repeats",10)),
        sound_enabled        = bool(request.form.get("sound_enabled",True)),
        sound_name           = request.form.get("sound_name","health_alert"),
        is_active            = True,
        is_daily             = bool(request.form.get("is_daily",True)),
    )
    r.save()
    # db.session.commit()  # Firestore auto-commits
    flash(f"✅ Reminder '{title}' created!", "success")
    return redirect(url_for("notifications.reminders"))


@notification_bp.route("/reminders/<int:rem_id>/toggle")
@login_required
def toggle_reminder(rem_id):
    r = Reminder.get_by_id_or_404(rem_id)
    if r.user_id != current_user.id:
        from flask import abort
        abort(403)
    r.is_active = not r.is_active
    r.save()
    # db.session.commit()  # Firestore auto-commits
    flash(f"Reminder {'enabled' if r.is_active else 'disabled'}.", "info")
    return redirect(url_for("notifications.reminders"))


@notification_bp.route("/reminders/<int:rem_id>/done")
@login_required
def done_reminder(rem_id):
    from datetime import date
    r = Reminder.get_by_id_or_404(rem_id)
    if r.user_id != current_user.id:
        from flask import abort
        abort(403)
    r.is_done_today   = True
    r.done_reset_date = date.today()
    r.save()
    # db.session.commit()  # Firestore auto-commits
    flash(f"✅ '{r.title}' marked done for today!", "success")
    return redirect(url_for("notifications.reminders"))


@notification_bp.route("/reminders/<int:rem_id>/delete")
@login_required
def delete_reminder(rem_id):
    r = Reminder.get_by_id_or_404(rem_id)
    if r.user_id != current_user.id:
        from flask import abort
        abort(403)
    r.delete()
    # db.session.commit()  # Firestore auto-commits
    flash("Reminder deleted.", "info")
    return redirect(url_for("notifications.reminders"))


@notification_bp.route("/reminders/setup-defaults")
@login_required
def setup_defaults():
    existing = Reminder.count(filters={"user_id": current_user.id})
    if existing > 0:
        flash("Reminders already set up.", "info")
        return redirect(url_for("notifications.reminders"))
    defaults = [
        {"title":"💊 Take Medicine",      "category":"medicine","remind_time":"08:00","interval":5, "sound":"medicine"},
        {"title":"❤️ Morning BP Check",   "category":"bp",      "remind_time":"07:30","interval":5, "sound":"health_alert"},
        {"title":"❤️ Evening BP Check",   "category":"bp",      "remind_time":"19:00","interval":5, "sound":"health_alert"},
        {"title":"💧 Drink Water",         "category":"water",   "remind_time":"10:00","interval":10,"sound":"water_drop"},
        {"title":"💧 Afternoon Water",     "category":"water",   "remind_time":"14:00","interval":10,"sound":"water_drop"},
        {"title":"💧 Evening Water",       "category":"water",   "remind_time":"18:00","interval":10,"sound":"water_drop"},
        {"title":"🏃 Exercise Time",       "category":"exercise","remind_time":"07:00","interval":10,"sound":"gentle"},
        {"title":"😴 Bedtime Reminder",    "category":"sleep",   "remind_time":"22:00","interval":15,"sound":"gentle"},
    ]
    for d in defaults:
        r = Reminder(
            user_id=current_user.id, title=d["title"],
            message=d["title"], category=d["category"],
            remind_time=d["remind_time"],
            repeat_interval_mins=d["interval"],
            max_repeats=10, sound_enabled=True,
            sound_name=d["sound"], is_active=True, is_daily=True,
        )
        r.save()
    # db.session.commit()  # Firestore auto-commits
    flash(f"✅ {len(defaults)} default reminders created with sound!", "success")
    return redirect(url_for("notifications.reminders"))