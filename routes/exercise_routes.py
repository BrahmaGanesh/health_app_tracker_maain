# routes/exercise_routes.py — Exercise Hub Website
from flask import Blueprint, render_template, redirect, url_for, flash, request, jsonify
from flask_login import login_required, current_user
from datetime import date, timedelta, datetime
from extensions import db
from models import ExerciseLog, StepLog, ExerciseLibrary

exercise_bp = Blueprint("exercise", __name__)

@exercise_bp.route("/")
@login_required
def dashboard():
    today = date.today()
    user  = current_user
    logs_today = ExerciseLog.query.filter_by(user_id=user.id, log_date=today).all()
    total_mins = sum(l.duration_minutes or 0 for l in logs_today)
    total_cal  = sum(l.calories_burned or 0 for l in logs_today)
    target_mins= user.goals.target_exercise_mins if user.goals else 30

    week_logs  = ExerciseLog.query.filter(
        ExerciseLog.user_id  == user.id,
        ExerciseLog.log_date >= today - timedelta(days=6)
    ).order_by(ExerciseLog.log_date.desc()).all()

    steps_today = StepLog.query.filter_by(user_id=user.id, log_date=today).first()
    featured    = ExerciseLibrary.query.filter_by(is_featured=True).limit(6).all()

    return render_template("exercise/dashboard.html",
        logs_today=logs_today, total_mins=total_mins, total_cal=total_cal,
        target_mins=target_mins, week_logs=week_logs,
        steps_today=steps_today, featured=featured, today=today)

@exercise_bp.route("/log", methods=["POST"])
@login_required
def log_exercise():
    user = current_user
    name = request.form.get("exercise_name","").strip()
    if not name:
        flash("Exercise name required.", "danger")
        return redirect(url_for("exercise.dashboard"))
    duration = request.form.get("duration_minutes")
    ex_type  = request.form.get("exercise_type","cardio")
    calories = request.form.get("calories_burned")
    if not calories and duration:
        w = user.health_profile.current_weight_kg if user.health_profile else 70
        met_map = {"cardio":7.0,"strength":5.0,"yoga":3.0,"flexibility":3.5,"breathing":2.0,"other":4.0}
        met = met_map.get(ex_type, 5.0)
        calories = int(met * w * float(duration) / 60)
    log = ExerciseLog(
        user_id=user.id, log_date=date.today(),
        exercise_name=name, exercise_type=ex_type,
        duration_minutes=int(duration) if duration else None,
        calories_burned=int(calories) if calories else None,
        sets=request.form.get("sets") or None,
        reps=request.form.get("reps") or None,
        intensity=request.form.get("intensity","moderate"),
        notes=request.form.get("notes",""),
        recorded_at=datetime.utcnow(),
    )
    db.session.add(log)
    db.session.commit()
    flash(f"✅ {name} logged! {calories} cal burned.", "success")
    return redirect(url_for("exercise.dashboard"))

@exercise_bp.route("/steps", methods=["POST"])
@login_required
def log_steps():
    user  = current_user
    steps = int(request.form.get("steps", 0))
    h = user.health_profile.height_cm if user.health_profile else 170
    w = user.health_profile.current_weight_kg if user.health_profile else 70
    dist  = round(steps * (h * 0.414 / 100) / 1000, 2)
    cals  = int((steps / 100) * (3.5 * w * 3.5 / 200))
    goal  = user.goals.target_steps if user.goals else 8000
    sl = StepLog.query.filter_by(user_id=user.id, log_date=date.today()).first()
    if sl:
        sl.steps = steps; sl.distance_km = dist; sl.calories_burned = cals; sl.goal_achieved = steps >= goal
    else:
        sl = StepLog(user_id=user.id, log_date=date.today(), steps=steps, distance_km=dist, calories_burned=cals, goal_steps=goal, goal_achieved=steps>=goal)
        db.session.add(sl)
    db.session.commit()
    flash(f"👟 {steps:,} steps logged — {dist}km — {cals} cal burned!", "success")
    return redirect(url_for("exercise.dashboard"))

@exercise_bp.route("/stopwatch")
@login_required
def stopwatch():
    return render_template("exercise/stopwatch.html")

@exercise_bp.route("/steps_live")
@login_required
def steps_live():
    return render_template("exercise/steps_live.html")

@exercise_bp.route("/breathing")
@login_required
def breathing():
    return render_template("exercise/breathing.html")

@exercise_bp.route("/library")
@login_required
def library():
    category   = request.args.get("category","all")
    difficulty = request.args.get("difficulty","all")
    bp_safe    = request.args.get("bp_safe","")
    q = ExerciseLibrary.query
    if category   != "all": q = q.filter(ExerciseLibrary.category   == category)
    if difficulty  != "all": q = q.filter(ExerciseLibrary.difficulty  == difficulty)
    if bp_safe:              q = q.filter(ExerciseLibrary.bp_safe     == True)
    exercises  = q.order_by(ExerciseLibrary.name).all()
    categories = sorted(set(e.category for e in ExerciseLibrary.query.all() if e.category))
    return render_template("exercise/library.html", exercises=exercises, categories=categories,
                           selected_category=category, selected_difficulty=difficulty)

@exercise_bp.route("/delete/<int:log_id>")
@login_required
def delete_log(log_id):
    log = ExerciseLog.query.filter_by(id=log_id, user_id=current_user.id).first_or_404()
    db.session.delete(log)
    db.session.commit()
    flash("Exercise log deleted.", "info")
    return redirect(url_for("exercise.dashboard"))