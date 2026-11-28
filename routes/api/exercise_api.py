# ============================================================
# routes/api/exercise_api.py — Exercise, Steps, Breathing API
# ============================================================

from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_current_user
from datetime import date, timedelta, datetime

from models import ExerciseLog, ExerciseLibrary

exercise_api_bp = Blueprint("exercise_api", __name__)


def ok(data=None, msg="Success", code=200):
    r = {"success": True, "message": msg}
    if data is not None: r["data"] = data
    return jsonify(r), code


def err(msg="Error", code=400):
    return jsonify({"success": False, "message": msg}), code


# ── LOG EXERCISE ──────────────────────────────────────────────
@exercise_api_bp.route("/log", methods=["POST"])
@jwt_required()
def log_exercise():
    user = get_current_user()
    data = request.get_json() or {}

    name     = data.get("exercise_name", "").strip()
    ex_type  = data.get("exercise_type", "cardio")
    duration = data.get("duration_minutes")
    calories = data.get("calories_burned")
    sets     = data.get("sets")
    reps     = data.get("reps")
    weight   = data.get("weight_used_kg")
    distance = data.get("distance_km")
    hr       = data.get("avg_heart_rate")
    intensity= data.get("intensity", "moderate")
    notes    = data.get("notes", "")

    if not name: return err("Exercise name required", 422)

    # Auto-calculate calories if not provided
    if not calories and duration:
        w = user.health_profile.current_weight_kg if user.health_profile else 70
        met_map = {
            "cardio": 7.0, "strength": 5.0, "yoga": 3.0,
            "flexibility": 3.5, "sports": 8.0, "breathing": 2.0, "other": 4.0
        }
        met      = met_map.get(ex_type, 5.0)
        calories = int(met * w * float(duration) / 60)

    log = ExerciseLog(
        user_id          = user.id,
        log_date         = date.today(),
        exercise_name    = name,
        exercise_type    = ex_type,
        duration_minutes = int(duration) if duration else None,
        calories_burned  = calories,
        sets             = int(sets) if sets else None,
        reps             = int(reps) if reps else None,
        weight_used_kg   = float(weight) if weight else None,
        distance_km      = float(distance) if distance else None,
        avg_heart_rate   = int(hr) if hr else None,
        intensity        = intensity,
        notes            = notes or None,
        recorded_at      = datetime.utcnow(),
    )
    log.save()
    return ok(log.to_dict(), "Exercise logged", 201)


# ── GET EXERCISE HISTORY ──────────────────────────────────────
@exercise_api_bp.route("/history", methods=["GET"])
@jwt_required()
def get_history():
    user  = get_current_user()
    days  = int(request.args.get("days", 7))
    since = date.today() - timedelta(days=days)

    logs = ExerciseLog.get_all(
        filters={"user_id": user.id, "log_date_gte": since},
        order_by="-log_date"
    )

    # Totals
    total_mins = sum(l.duration_minutes or 0 for l in logs)
    total_cal  = sum(l.calories_burned or 0 for l in logs)
    total_dist = round(sum(l.distance_km or 0 for l in logs), 2)

    target_mins = user.goals.target_exercise_mins if user.goals else 30
    today_logs  = [l for l in logs if l.log_date == date.today()]
    today_mins  = sum(l.duration_minutes or 0 for l in today_logs)

    return ok({
        "logs":       [l.to_dict() for l in logs],
        "today_mins": today_mins,
        "total_mins": total_mins,
        "total_cal":  total_cal,
        "total_dist": total_dist,
        "target_mins": target_mins,
    })


# ── TODAY'S EXERCISE ──────────────────────────────────────────
@exercise_api_bp.route("/today", methods=["GET"])
@jwt_required()
def get_today():
    user = get_current_user()
    today = date.today()

    logs = ExerciseLog.get_all(
        filters={"user_id": user.id, "log_date": today},
        order_by="-recorded_at"
    )

    total_mins = sum(l.duration_minutes or 0 for l in logs)
    total_cal  = sum(l.calories_burned or 0 for l in logs)

    target_mins = user.goals.target_exercise_mins if user.goals else 30
    pct = min(100, int((sum(l.duration_minutes or 0 for l in logs) / max(1, target_mins)) * 100))

    return ok({
        "logs": [l.to_dict() for l in logs],
        "total_mins": sum(l.duration_minutes or 0 for l in logs),
        "total_cal": sum(l.calories_burned or 0 for l in logs),
        "target_mins": target_mins,
        "pct": pct,
    })


# ── LOG STEPS ─────────────────────────────────────────────────
@exercise_api_bp.route("/steps", methods=["POST"])
@jwt_required()
def log_steps():
    user = get_current_user()
    data = request.get_json() or {}

    try:
        steps = int(data.get("steps", 0))
        if not (0 <= steps <= 100000):
            return err("Steps must be 0–100,000", 422)
    except (TypeError, ValueError):
        return err("Valid steps required", 422)

    h = user.health_profile.height_cm if user.health_profile and user.health_profile.height_cm else 170
    w = user.health_profile.current_weight_kg if user.health_profile and user.health_profile.current_weight_kg else 70
    dist = round(steps * (h * 0.414 / 100) / 1000, 2)
    cals = int((steps / 100) * (3.5 * w * 3.5 / 200))

    sl = StepLog(
        user_id=user.id,
        log_date=date.today(),
        steps=steps,
        distance_km=dist,
        calories_burned=cals
    )
    sl.save()

    return ok(sl.to_dict(), "Steps saved", 201)


# ── GET STEPS ─────────────────────────────────────────────────
@exercise_api_bp.route("/steps", methods=["GET"])
@jwt_required()
def get_steps():
    user = get_current_user()
    days = request.args.get("days", 7, type=int) or 7
    since = date.today() - timedelta(days=days)

    logs = StepLog.get_all(
        filters={"user_id": user.id, "log_date_gte": since},
        order_by="-log_date"
    )

    goal = user.goals.target_steps if user.goals else 8000
    today_log_list = StepLog.get_all(
        filters={"user_id": user.id, "log_date": date.today()},
        limit=1
    )
    today_log = today_log_list[0] if today_log_list else None

    today_steps = today_log.steps if today_log else 0
    goal = user.goals.target_steps if user.goals else 8000
    today_pct = min(100, int(today_steps / goal * 100)) if goal else 0

    h = user.health_profile.height_cm if user.health_profile and user.health_profile.height_cm else 170
    w = user.health_profile.current_weight_kg if user.health_profile and user.health_profile.current_weight_kg else 70
    today_cal = int((today_steps / 100) * (3.5 * w * 3.5 / 200))
    today_dist = round(today_steps * (h * 0.414 / 100) / 1000, 2)

    return ok({
        "logs": [l.to_dict() for l in logs],
        "today_steps": today_steps,
        "today_pct": today_pct,
        "today_calories": today_cal,
        "today_distance": today_dist,
    })


# ── EXERCISE LIBRARY ──────────────────────────────────────────
@exercise_api_bp.route("/library", methods=["GET"])
@jwt_required()
def get_library():
    category = request.args.get("category", "")
    difficulty = request.args.get("difficulty", "")

    filters = {"is_active": True}
    if category:
        filters["category"] = category
    if difficulty:
        filters["difficulty"] = difficulty

    exercises = ExerciseLibrary.get_all(filters=filters, order_by="name")
    categories = sorted(set(e.category for e in ExerciseLibrary.get_all(filters={"is_active": True}) if e.category))

    return ok({
        "exercises": [e.to_dict() for e in exercises],
        "categories": categories,
    })


# ── LOG HEART RATE ────────────────────────────────────────────
@exercise_api_bp.route("/heart-rate", methods=["POST"])
@jwt_required()
def log_heart_rate():
    user = get_current_user()
    data = request.get_json() or {}

    try:
        bpm = int(data.get("bpm", 0))
        if not (30 <= bpm <= 220):
            return err("BPM must be 30–220", 422)
    except (TypeError, ValueError):
        return err("Valid BPM required", 422)

    hr_type = data.get("type", "resting")
    notes = data.get("notes")

    hr = HealthMetric(
        user_id=user.id,
        metric_type="heart_rate",
        value1=bpm,
        value2=hr_type,
        unit="bpm",
        notes=notes,
        source="manual"
    )
    hr.save()

    return ok(hr.to_dict(), "Heart rate saved", 201)


# ── GET HEART RATE ────────────────────────────────────────────
@exercise_api_bp.route("/heart-rate", methods=["GET"])
@jwt_required()
def get_heart_rate():
    user = get_current_user()
    days = request.args.get("days", 30, type=int) or 30
    since = date.today() - timedelta(days=days)

    readings = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "heart_rate", "recorded_at_gte": since},
        order_by="-recorded_at"
    )

    latest = readings[0] if readings else None

    return ok({
        "readings": [r.to_dict() for r in readings],
        "latest": latest.to_dict() if latest else None,
        "count": len(readings),
    })


# ── BREATHING EXERCISE ───────────────────────────────────────
@exercise_api_bp.route("/breathing", methods=["POST"])
@jwt_required()
def log_breathing():
    user = get_current_user()
    data = request.get_json() or {}

    technique = data.get("technique", "box")
    duration = data.get("duration_minutes", 5)
    cycles = data.get("cycles", 4)

    log = ExerciseLog(
        user_id=user.id,
        log_date=date.today(),
        exercise_name=f"Breathing: {technique}",
        exercise_type="breathing",
        duration_minutes=duration,
        calories_burned=0,
        notes=f"Technique: {technique}, Cycles: {cycles}",
        recorded_at=datetime.utcnow(),
    )
    log.save()

    return ok(log.to_dict(), "Breathing exercise logged", 201)