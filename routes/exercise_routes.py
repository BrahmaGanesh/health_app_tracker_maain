# routes/exercise_routes.py — Exercise Hub Website
from flask import Blueprint, render_template, redirect, url_for, flash, request, jsonify
from flask_login import login_required, current_user
from datetime import date, timedelta, datetime
from models import ExerciseLog, StepLog, ExerciseLibrary

exercise_bp = Blueprint("exercise", __name__)

@exercise_bp.route("/")
@login_required
def dashboard():
    today = date.today()
    user = current_user

    logs_today = ExerciseLog.get_all(filters={"user_id": user.id, "log_date": today})
    total_mins = sum(l.duration_minutes or 0 for l in logs_today)
    total_cal = sum(l.calories_burned or 0 for l in logs_today)
    target_mins = user.goals.target_exercise_mins if user.goals else 30

    week_ago = date.today() - timedelta(days=6)
    week_logs = ExerciseLog.get_all(
        filters={"user_id": user.id, "log_date_gte": week_ago},
        order_by="-log_date"
    )

    steps_today_list = StepLog.get_all(filters={"user_id": user.id, "log_date": today})
    steps_today = sum(s.steps or 0 for s in steps_today_list)

    # Featured exercises
    featured = ExerciseLibrary.get_all(filters={"is_active": True}, limit=5)

    return render_template(
        "exercise/dashboard.html",
        logs_today=logs_today,
        total_mins=total_mins,
        total_cal=total_cal,
        target_mins=target_mins,
        week_logs=week_logs,
        steps_today=steps_today,
        featured=featured,
        today=today
    )


@exercise_bp.route("/log", methods=["POST"])
@login_required
def log_exercise():
    user = current_user
    name = request.form.get("exercise_name", "").strip()
    if not name:
        flash("Exercise name is required.", "danger")
        return redirect(url_for("exercise.dashboard"))

    duration = request.form.get("duration_minutes")
    ex_type = request.form.get("exercise_type", "cardio")
    calories = request.form.get("calories_burned")

    if not calories and duration:
        w = user.health_profile.current_weight_kg if user.health_profile else 70
        met_map = {"cardio": 7.0, "strength": 5.0, "yoga": 3.0, "walking": 3.5}
        met = met_map.get(ex_type, 5.0)
        calories = int(met * w * float(duration) / 60)

    log = ExerciseLog(
        user_id=user.id, log_date=date.today(),
        exercise_name=name, exercise_type=ex_type,
        duration_minutes=int(duration) if duration else None,
        calories_burned=int(calories) if calories else None,
        sets=request.form.get("sets") or None,
        reps=request.form.get("reps") or None,
        intensity=request.form.get("intensity", "moderate"),
        notes=request.form.get("notes", ""),
        recorded_at=datetime.utcnow(),
    )
    log.save()
    # db.session.commit()  # Firestore auto-commits
    flash(f"✅ {name} logged! {calories} cal burned.", "success")
    return redirect(url_for("exercise.dashboard"))


@exercise_bp.route("/steps", methods=["POST"])
@login_required
def log_steps():
    user = current_user
    steps = int(request.form.get("steps", 0))
    h = user.health_profile.height_cm if user.health_profile else 170
    w = user.health_profile.current_weight_kg if user.health_profile else 70
    dist = round(steps * (h * 0.414 / 100) / 1000, 2)
    cals = int((steps / 100) * (3.5 * w * 3.5 / 200))
    goal = user.goals.target_steps if user.goals else 8000

    sl = StepLog(
        user_id=user.id,
        log_date=date.today(),
        steps=steps,
        distance_km=dist,
        calories_burned=cals
    )
    sl.save()
    flash(f"👟 {steps} steps logged ({dist} km, ~{cals} cal).", "success")
    return redirect(url_for("exercise.dashboard"))


@exercise_bp.route("/library")
@login_required
def library():
    category = request.args.get("category", "")
    difficulty = request.args.get("difficulty", "")

    filters = {"is_active": True}
    if category:
        filters["category"] = category
    if difficulty:
        filters["difficulty"] = difficulty

    exercises = ExerciseLibrary.get_all(filters=filters, order_by="name")
    categories = sorted(set(e.category for e in ExerciseLibrary.get_all(filters={"is_active": True}) if e.category))

    return render_template("exercise/library.html", exercises=exercises, categories=categories,
                           selected_category=category, selected_difficulty=difficulty)


@exercise_bp.route("/delete/<int:log_id>")
@login_required
def delete_log(log_id):
    log = ExerciseLog.get_by_id_or_404(log_id)
    if log.user_id != current_user.id:
        from flask import abort
        abort(403)
    log.delete()
    # db.session.commit()  # Firestore auto-commits
    flash("Exercise log deleted.", "info")
    return redirect(url_for("exercise.dashboard"))