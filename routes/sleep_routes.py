# routes/sleep_routes.py — Sleep Tracker Website
from flask import Blueprint, render_template, redirect, url_for, flash, request
from flask_login import login_required, current_user
from datetime import date, timedelta, datetime
from extensions import db
from models import SleepLog

sleep_bp = Blueprint("sleep", __name__)

@sleep_bp.route("/", methods=["GET","POST"])
@login_required
def tracker():
    user  = current_user
    today = date.today()

    if request.method == "POST":
        sleep_time  = request.form.get("sleep_time","")
        wake_time   = request.form.get("wake_time","")
        quality     = request.form.get("quality")
        interruptions = request.form.get("interruptions", 0)
        mood_on_wake  = request.form.get("mood_on_wake","")
        notes         = request.form.get("notes","")

        duration = None
        if sleep_time and wake_time:
            try:
                sh, sm = map(int, sleep_time.split(":"))
                wh, wm = map(int, wake_time.split(":"))
                sleep_mins = sh * 60 + sm
                wake_mins  = wh * 60 + wm
                if wake_mins < sleep_mins: wake_mins += 24 * 60
                duration = round((wake_mins - sleep_mins) / 60, 1)
            except Exception:
                pass

        sl = SleepLog.query.filter_by(user_id=user.id, log_date=today).first()
        if not sl:
            sl = SleepLog(user_id=user.id, log_date=today)
            db.session.add(sl)
        sl.sleep_time     = sleep_time
        sl.wake_time      = wake_time
        sl.duration_hours = duration
        sl.quality        = int(quality) if quality else None
        sl.interruptions  = int(interruptions)
        sl.mood_on_wake   = mood_on_wake
        sl.notes          = notes
        db.session.commit()
        flash(f"😴 Sleep logged — {duration}hrs, quality: {sl.quality_label}", "success")
        return redirect(url_for("sleep.tracker"))

    # History
    logs_14 = SleepLog.query.filter(
        SleepLog.user_id  == user.id,
        SleepLog.log_date >= today - timedelta(days=13)
    ).order_by(SleepLog.log_date.desc()).all()

    today_log  = SleepLog.query.filter_by(user_id=user.id, log_date=today).first()
    target_hrs = user.goals.target_sleep_hours if user.goals else 7.5

    hrs_list  = [l.duration_hours for l in logs_14 if l.duration_hours]
    avg_sleep = round(sum(hrs_list) / len(hrs_list), 1) if hrs_list else None
    qual_list = [l.quality for l in logs_14 if l.quality]
    avg_qual  = round(sum(qual_list) / len(qual_list), 1) if qual_list else None

    good_nights = sum(1 for h in hrs_list if h >= target_hrs)

    chart_data = [{"day": l.log_date.strftime("%a %d"), "hours": l.duration_hours, "quality": l.quality} for l in reversed(logs_14)]

    return render_template("sleep/tracker.html",
        today_log=today_log, logs_14=logs_14,
        avg_sleep=avg_sleep, avg_quality=avg_qual,
        target_hrs=target_hrs, good_nights=good_nights,
        chart_data=chart_data, today=today)

@sleep_bp.route("/delete/<int:log_id>")
@login_required
def delete_log(log_id):
    log = SleepLog.query.filter_by(id=log_id, user_id=current_user.id).first_or_404()
    db.session.delete(log)
    db.session.commit()
    flash("Sleep log deleted.", "info")
    return redirect(url_for("sleep.tracker"))

