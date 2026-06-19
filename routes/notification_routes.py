# routes/notification_routes.py — In-App Notifications Website
from flask import Blueprint, render_template, redirect, url_for, flash, request, jsonify
from flask_login import login_required, current_user
from flask_jwt_extended import create_access_token
from datetime import datetime
from extensions import db
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
    page   = int(request.args.get("page", 1))
    notifs = Notification.query.filter_by(user_id=current_user.id).order_by(
        Notification.created_at.desc()
    ).paginate(page=page, per_page=30, error_out=False)
    unread = Notification.query.filter_by(user_id=current_user.id, is_read=False).count()
    reminders = Reminder.query.filter_by(user_id=current_user.id).all()
    return render_template("notifications/index.html",
                           notifs=notifs, unread=unread, reminders=reminders)

@notification_bp.route("/read-all")
@login_required
def read_all():
    Notification.query.filter_by(user_id=current_user.id, is_read=False).update({"is_read": True})
    db.session.commit()
    flash("All notifications marked as read.", "success")
    return redirect(url_for("notifications.index"))

@notification_bp.route("/read/<int:nid>")
@login_required
def read_one(nid):
    n = Notification.query.filter_by(id=nid, user_id=current_user.id).first_or_404()
    n.is_read = True
    db.session.commit()
    return redirect(url_for("notifications.index"))

@notification_bp.route("/count")
@login_required
def count():
    c = Notification.query.filter_by(user_id=current_user.id, is_read=False).count()
    return jsonify({"count": c})

# ── REMINDERS ─────────────────────────────────────────────────
@notification_bp.route("/reminders")
@login_required
def reminders():
    from datetime import date
    rems = Reminder.query.filter_by(user_id=current_user.id).all()
    for r in rems:
        r.reset_daily()
    db.session.commit()
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
    db.session.add(r)
    db.session.commit()
    flash(f"✅ Reminder '{title}' created!", "success")
    return redirect(url_for("notifications.reminders"))

@notification_bp.route("/reminders/<int:rem_id>/toggle")
@login_required
def toggle_reminder(rem_id):
    r = Reminder.query.filter_by(id=rem_id, user_id=current_user.id).first_or_404()
    r.is_active = not r.is_active
    db.session.commit()
    flash(f"Reminder {'enabled' if r.is_active else 'disabled'}.", "info")
    return redirect(url_for("notifications.reminders"))

@notification_bp.route("/reminders/<int:rem_id>/done")
@login_required
def done_reminder(rem_id):
    from datetime import date
    r = Reminder.query.filter_by(id=rem_id, user_id=current_user.id).first_or_404()
    r.is_done_today   = True
    r.done_reset_date = date.today()
    db.session.commit()
    flash(f"✅ '{r.title}' marked done for today!", "success")
    return redirect(url_for("notifications.reminders"))

@notification_bp.route("/reminders/<int:rem_id>/delete")
@login_required
def delete_reminder(rem_id):
    r = Reminder.query.filter_by(id=rem_id, user_id=current_user.id).first_or_404()
    db.session.delete(r)
    db.session.commit()
    flash("Reminder deleted.", "info")
    return redirect(url_for("notifications.reminders"))

@notification_bp.route("/reminders/setup-defaults")
@login_required
def setup_defaults():
    existing = Reminder.query.filter_by(user_id=current_user.id).count()
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
        db.session.add(r)
    db.session.commit()
    flash(f"✅ {len(defaults)} default reminders created with sound!", "success")
    return redirect(url_for("notifications.reminders"))