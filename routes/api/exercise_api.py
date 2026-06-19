# ============================================================
# routes/api/exercise_api.py — Exercise, Steps, Breathing API
# ============================================================

from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_current_user
from datetime import date, timedelta, datetime

from extensions import db
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
    db.session.add(log)
    db.session.commit()
    return ok(log.to_dict(), "Exercise logged", 201)


# ── GET EXERCISE HISTORY ──────────────────────────────────────
@exercise_api_bp.route("/history", methods=["GET"])
@jwt_required()
def get_history():
    user  = get_current_user()
    days  = int(request.args.get("days", 7))
    since = date.today() - timedelta(days=days)

    logs = ExerciseLog.query.filter(
        ExerciseLog.user_id  == user.id,
        ExerciseLog.log_date >= since
    ).order_by(ExerciseLog.log_date.desc(), ExerciseLog.recorded_at.desc()).all()

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
        "target_mins": target_mins,
        "today_pct":   min(100, int(today_mins / target_mins * 100)) if target_mins else 0,
        "total_mins":  total_mins,
        "total_calories": total_cal,
        "total_distance": total_dist,
        "days":        days,
    })


# ── DELETE EXERCISE LOG ───────────────────────────────────────
@exercise_api_bp.route("/log/<int:log_id>", methods=["DELETE"])
@jwt_required()
def delete_log(log_id):
    user = get_current_user()
    log  = ExerciseLog.query.filter_by(id=log_id, user_id=user.id).first()
    if not log: return err("Not found", 404)
    db.session.delete(log)
    db.session.commit()
    return ok(message="Exercise log deleted")


# ── EXERCISE LIBRARY ──────────────────────────────────────────
@exercise_api_bp.route("/library", methods=["GET"])
@jwt_required()
def get_library():
    user      = get_current_user()
    category  = request.args.get("category", "all")
    difficulty= request.args.get("difficulty", "all")
    bp_safe   = request.args.get("bp_safe", "false").lower() == "true"
    featured  = request.args.get("featured", "false").lower() == "true"

    q = ExerciseLibrary.query
    if category != "all": q = q.filter(ExerciseLibrary.category == category)
    if difficulty != "all": q = q.filter(ExerciseLibrary.difficulty == difficulty)
    if bp_safe: q = q.filter(ExerciseLibrary.bp_safe == True)
    if featured: q = q.filter(ExerciseLibrary.is_featured == True)

    exercises = q.order_by(ExerciseLibrary.name).all()
    cats = sorted(set(e.category for e in ExerciseLibrary.query.with_entities(ExerciseLibrary.category).distinct().all() if e.category))

    return ok({
        "exercises":  [e.to_dict() for e in exercises],
        "categories": cats,
        "count":      len(exercises),
    })


# ── 4-7-8 BREATHING CONFIG ────────────────────────────────────
@exercise_api_bp.route("/breathing/config", methods=["GET"])
@jwt_required()
def breathing_config():
    """Return breathing exercise configurations."""
    return ok({
        "exercises": [
            {
                "id":    "4-7-8",
                "name":  "4-7-8 Breathing",
                "desc":  "Inhale 4s → Hold 7s → Exhale 8s. Activates parasympathetic nervous system. Lowers BP naturally.",
                "benefits": ["Reduces anxiety", "Lowers blood pressure", "Promotes sleep", "Calms nervous system"],
                "phases": [
                    {"name": "Inhale",  "duration": 4,  "color": "#9fd3c7", "instruction": "Breathe in slowly through your nose"},
                    {"name": "Hold",    "duration": 7,  "color": "#f8da5b", "instruction": "Hold your breath gently"},
                    {"name": "Exhale",  "duration": 8,  "color": "#61b390", "instruction": "Exhale completely through your mouth"},
                ],
                "recommended_rounds": 4,
                "total_duration_secs": 76,
                "bp_benefit": "Can lower systolic BP by 5-10 mmHg",
            },
            {
                "id":    "box",
                "name":  "Box Breathing",
                "desc":  "Inhale 4s → Hold 4s → Exhale 4s → Hold 4s. Used by Navy SEALs for stress control.",
                "benefits": ["Reduces stress cortisol", "Improves focus", "Regulates nervous system"],
                "phases": [
                    {"name": "Inhale",      "duration": 4, "color": "#9fd3c7", "instruction": "Breathe in through nose"},
                    {"name": "Hold",        "duration": 4, "color": "#f8da5b", "instruction": "Hold"},
                    {"name": "Exhale",      "duration": 4, "color": "#61b390", "instruction": "Breathe out through mouth"},
                    {"name": "Hold Empty",  "duration": 4, "color": "#ebcbae", "instruction": "Hold empty"},
                ],
                "recommended_rounds": 5,
                "total_duration_secs": 80,
                "bp_benefit": "Reduces cortisol which raises BP",
            },
            {
                "id":    "deep",
                "name":  "Deep Belly Breathing",
                "desc":  "Inhale 5s → Exhale 5s. Diaphragmatic breathing improves oxygen and reduces BP.",
                "benefits": ["Improves oxygen levels", "Lowers resting HR", "Reduces BP"],
                "phases": [
                    {"name": "Inhale",  "duration": 5, "color": "#9fd3c7", "instruction": "Belly rises — breathe deep"},
                    {"name": "Exhale",  "duration": 5, "color": "#61b390", "instruction": "Belly falls — breathe out fully"},
                ],
                "recommended_rounds": 10,
                "total_duration_secs": 100,
                "bp_benefit": "Regular practice lowers systolic BP 3-4 mmHg",
            },
        ]
    })


# ── LOG BREATHING SESSION ─────────────────────────────────────
@exercise_api_bp.route("/breathing/log", methods=["POST"])
@jwt_required()
def log_breathing():
    user = get_current_user()
    data = request.get_json() or {}

    exercise_type = data.get("exercise_id", "4-7-8")
    rounds        = data.get("rounds_completed", 4)
    duration_secs = data.get("duration_seconds", 76)

    log = ExerciseLog(
        user_id          = user.id,
        log_date         = date.today(),
        exercise_name    = f"{exercise_type} Breathing",
        exercise_type    = "breathing",
        duration_minutes = max(1, duration_secs // 60),
        calories_burned  = max(1, duration_secs // 30),
        intensity        = "low",
        notes            = f"{rounds} rounds completed",
        recorded_at      = datetime.utcnow(),
    )
    db.session.add(log)
    db.session.commit()
    return ok(log.to_dict(), f"Breathing session saved — {rounds} rounds", 201)


# ── STOPWATCH RECORD ──────────────────────────────────────────
@exercise_api_bp.route("/stopwatch/save", methods=["POST"])
@jwt_required()
def save_stopwatch():
    """Save a timed exercise session from the stopwatch."""
    user = get_current_user()
    data = request.get_json() or {}

    duration_secs = int(data.get("duration_seconds", 0))
    exercise_name = data.get("exercise_name", "Timed Exercise")
    ex_type       = data.get("exercise_type", "cardio")

    if duration_secs < 30: return err("Session too short (minimum 30 seconds)", 400)

    w        = user.health_profile.current_weight_kg if user.health_profile else 70
    met      = 5.0
    calories = int(met * w * (duration_secs / 3600))

    log = ExerciseLog(
        user_id          = user.id,
        log_date         = date.today(),
        exercise_name    = exercise_name,
        exercise_type    = ex_type,
        duration_minutes = max(1, duration_secs // 60),
        calories_burned  = calories,
        notes            = f"Timed: {duration_secs}s",
        recorded_at      = datetime.utcnow(),
    )
    db.session.add(log)
    db.session.commit()
    return ok(log.to_dict(), "Session saved", 201)