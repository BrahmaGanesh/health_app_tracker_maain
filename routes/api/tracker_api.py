# ============================================================
# routes/api/tracker_api.py — All Health Trackers API (APK)
# BP, Weight, Water, Sugar, Sleep, Steps, Heart Rate
# EXACT timestamps saved on every entry
# ============================================================


from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_current_user
from datetime import datetime, date, timedelta
from zoneinfo import ZoneInfo
from sqlalchemy import func


from extensions import db
from models import HealthMetric, SleepLog, StepLog, HeartRateLog, Alert


tracker_api_bp = Blueprint("tracker_api", __name__)


IST = ZoneInfo("Asia/Kolkata")


def now_ist():
    return datetime.now(IST)


def today_ist():
    return now_ist().date()


def ok(data=None, msg="Success", code=200):
    r = {"success": True, "message": msg}
    if data is not None:
        r["data"] = data
    return jsonify(r), code


def err(msg="Error", code=400):
    return jsonify({"success": False, "message": msg}), code


# ── HELPER: fire push alert for bad readings ──────────────────
def _check_and_push(user, metric_type, value_1, value_2=None):
    """Auto-create alert and push notification for threshold violations."""
    from utils.firebase_push import send_push_to_user
    from utils.reminder_engine import create_alert_notification

    if metric_type == "bp" and value_1 and value_2:
        s, d = float(value_1), float(value_2)
        if s >= 180 or d >= 120:
            create_alert_notification(
                user, "emergency", "bp",
                "🚨 BP Crisis Detected",
                f"BP {int(s)}/{int(d)} mmHg is at CRISIS level. Rest and see a doctor immediately.",
                sound="urgent"
            )
        elif s >= 160 or d >= 100:
            create_alert_notification(
                user, "warning", "bp",
                "⚠️ High BP Reading",
                f"BP {int(s)}/{int(d)} mmHg is significantly elevated. Review medicine and salt intake.",
                sound="health_alert"
            )

    elif metric_type == "sugar" and value_1:
        if float(value_1) >= 200:
            create_alert_notification(
                user, "warning", "sugar",
                "⚠️ High Blood Sugar",
                f"Fasting sugar {int(float(value_1))} mg/dL is high. Consult your doctor.",
                sound="health_alert"
            )


# ════════════════════════════════════════════════════════════
# BLOOD PRESSURE
# ════════════════════════════════════════════════════════════


@tracker_api_bp.route("/bp", methods=["POST"])
@jwt_required()
def add_bp():
    user = get_current_user()
    data = request.get_json() or {}

    systolic = data.get("systolic")
    diastolic = data.get("diastolic")
    pulse = data.get("pulse")
    notes = data.get("notes", "")

    try:
        sys_val = float(systolic)
        dia_val = float(diastolic)
        if not (60 <= sys_val <= 250):
            return err("Systolic must be 60–250")
        if not (40 <= dia_val <= 150):
            return err("Diastolic must be 40–150")
    except (TypeError, ValueError):
        return err("Valid systolic and diastolic required", 422)

    pulse_val = None
    if pulse:
        try:
            pulse_val = float(pulse)
        except (TypeError, ValueError):
            pass

    m = HealthMetric(
        user_id=user.id,
        metric_type="bp",
        value_1=sys_val,
        value_2=dia_val,
        value_3=pulse_val,
        unit="mmHg",
        notes=notes or None,
        source="manual",
        recorded_at=now_ist()
    )
    db.session.add(m)
    db.session.commit()

    _check_and_push(user, "bp", sys_val, dia_val)

    return ok(m.to_dict(), "BP reading saved", 201)


@tracker_api_bp.route("/bp", methods=["GET"])
@jwt_required()
def get_bp():
    user = get_current_user()
    days = int(request.args.get("days", 7))
    since = now_ist() - timedelta(days=days)

    readings = HealthMetric.query.filter(
        HealthMetric.user_id == user.id,
        HealthMetric.metric_type == "bp",
        HealthMetric.recorded_at >= since
    ).order_by(HealthMetric.recorded_at.desc()).all()

    latest = readings[0] if readings else None

    avg_sys = avg_dia = None
    if readings:
        sys_vals = [r.value_1 for r in readings if r.value_1 is not None]
        dia_vals = [r.value_2 for r in readings if r.value_2 is not None]
        if sys_vals:
            avg_sys = round(sum(sys_vals) / len(sys_vals), 0)
        if dia_vals:
            avg_dia = round(sum(dia_vals) / len(dia_vals), 0)

    return ok({
        "readings": [r.to_dict() for r in readings],
        "latest": latest.to_dict() if latest else None,
        "avg_sys": avg_sys,
        "avg_dia": avg_dia,
        "count": len(readings),
        "days": days,
    })


@tracker_api_bp.route("/bp/<int:metric_id>", methods=["DELETE"])
@jwt_required()
def delete_bp(metric_id):
    user = get_current_user()
    m = HealthMetric.query.filter_by(
        id=metric_id,
        user_id=user.id,
        metric_type="bp"
    ).first()
    if not m:
        return err("Reading not found", 404)
    db.session.delete(m)
    db.session.commit()
    return ok(msg="BP reading deleted")


# ════════════════════════════════════════════════════════════
# WEIGHT
# ════════════════════════════════════════════════════════════


@tracker_api_bp.route("/weight", methods=["POST"])
@jwt_required()
def add_weight():
    user = get_current_user()
    data = request.get_json() or {}

    try:
        w = float(data.get("weight_kg", 0))
        if not (20 <= w <= 300):
            return err("Weight must be 20–300 kg")
    except (TypeError, ValueError):
        return err("Valid weight required", 422)

    m = HealthMetric(
        user_id=user.id,
        metric_type="weight",
        value_1=w,
        unit="kg",
        notes=data.get("notes", "") or None,
        source="manual",
        recorded_at=now_ist()
    )
    db.session.add(m)

    if user.health_profile:
        user.health_profile.current_weight_kg = w

    db.session.commit()
    return ok(m.to_dict(), "Weight saved", 201)


@tracker_api_bp.route("/weight", methods=["GET"])
@jwt_required()
def get_weight():
    user = get_current_user()
    days = int(request.args.get("days", 30))
    since = now_ist() - timedelta(days=days)

    readings = HealthMetric.query.filter(
        HealthMetric.user_id == user.id,
        HealthMetric.metric_type == "weight",
        HealthMetric.recorded_at >= since
    ).order_by(HealthMetric.recorded_at.asc()).all()

    latest = HealthMetric.query.filter_by(
        user_id=user.id,
        metric_type="weight"
    ).order_by(HealthMetric.recorded_at.desc()).first()

    change = None
    if len(readings) >= 2:
        change = round(readings[-1].value_1 - readings[0].value_1, 1)

    goals = user.goals
    progress_pct = 0
    if goals and goals.target_weight_kg and goals.start_weight_kg and latest:
        diff = goals.start_weight_kg - goals.target_weight_kg
        done = goals.start_weight_kg - latest.value_1
        if diff != 0:
            progress_pct = max(0, min(100, int(done / diff * 100)))

    return ok({
        "readings": [r.to_dict() for r in readings],
        "latest": latest.to_dict() if latest else None,
        "change": change,
        "target_weight": goals.target_weight_kg if goals else None,
        "progress_pct": progress_pct,
        "bmi": user.bmi,
        "bmi_status": user.bmi_status,
    })


# ════════════════════════════════════════════════════════════
# WATER
# ════════════════════════════════════════════════════════════


@tracker_api_bp.route("/water", methods=["POST"])
@jwt_required()
def add_water():
    user = get_current_user()
    data = request.get_json() or {}

    try:
        amount = float(data.get("amount_litres", 0))
        if not (0.05 <= amount <= 5.0):
            return err("Amount must be 0.05–5.0 litres")
    except (TypeError, ValueError):
        return err("Valid amount required", 422)

    m = HealthMetric(
        user_id=user.id,
        metric_type="water",
        value_1=amount,
        unit="litres",
        source="manual",
        recorded_at=now_ist()
    )
    db.session.add(m)
    db.session.commit()
    return ok(m.to_dict(), f"{amount}L water logged", 201)


@tracker_api_bp.route("/water/today", methods=["GET"])
@jwt_required()
def get_water_today():
    user = get_current_user()
    today = today_ist()

    total = HealthMetric.query.filter(
        HealthMetric.user_id == user.id,
        HealthMetric.metric_type == "water",
        func.date(HealthMetric.recorded_at) == today
    ).with_entities(func.sum(HealthMetric.value_1)).scalar() or 0

    logs = HealthMetric.query.filter(
        HealthMetric.user_id == user.id,
        HealthMetric.metric_type == "water",
        func.date(HealthMetric.recorded_at) == today
    ).order_by(HealthMetric.recorded_at.desc()).all()

    target = user.goals.target_water_litres if user.goals else 2.5
    pct = min(100, int((total / target) * 100)) if target else 0

    week = []
    for i in range(6, -1, -1):
        d = today - timedelta(days=i)
        t = HealthMetric.query.filter(
            HealthMetric.user_id == user.id,
            HealthMetric.metric_type == "water",
            func.date(HealthMetric.recorded_at) == d
        ).with_entities(func.sum(HealthMetric.value_1)).scalar() or 0
        week.append({
            "day": d.strftime("%a"),
            "date": str(d),
            "litres": round(t, 2)
        })

    return ok({
        "today_total": round(total, 2),
        "target": target,
        "pct": pct,
        "goal_achieved": total >= target,
        "logs": [r.to_dict() for r in logs],
        "week": week,
    })


# ════════════════════════════════════════════════════════════
# BLOOD SUGAR
# ════════════════════════════════════════════════════════════


@tracker_api_bp.route("/sugar", methods=["POST"])
@jwt_required()
def add_sugar():
    user = get_current_user()
    data = request.get_json() or {}

    fasting = data.get("fasting")
    post_meal = data.get("post_meal")
    notes = data.get("notes", "")

    if not fasting and not post_meal:
        return err("At least one reading required", 422)

    f_val = p_val = None
    if fasting:
        try:
            f_val = float(fasting)
            if not (20 <= f_val <= 600):
                return err("Fasting sugar must be 20–600")
        except (TypeError, ValueError):
            return err("Invalid fasting value", 422)

    if post_meal:
        try:
            p_val = float(post_meal)
            if not (20 <= p_val <= 800):
                return err("Post-meal sugar must be 20–800")
        except (TypeError, ValueError):
            return err("Invalid post-meal value", 422)

    m = HealthMetric(
        user_id=user.id,
        metric_type="sugar",
        value_1=f_val,
        value_2=p_val,
        unit="mg_dL",
        notes=notes or None,
        source="manual",
        recorded_at=now_ist()
    )
    db.session.add(m)
    db.session.commit()

    _check_and_push(user, "sugar", f_val)

    return ok(m.to_dict(), "Sugar reading saved", 201)


@tracker_api_bp.route("/sugar", methods=["GET"])
@jwt_required()
def get_sugar():
    user = get_current_user()
    days = int(request.args.get("days", 30))
    since = now_ist() - timedelta(days=days)

    readings = HealthMetric.query.filter(
        HealthMetric.user_id == user.id,
        HealthMetric.metric_type == "sugar",
        HealthMetric.recorded_at >= since
    ).order_by(HealthMetric.recorded_at.desc()).all()

    latest = readings[0] if readings else None
    status = "No Reading"
    if latest and latest.value_1:
        f = latest.value_1
        if f < 100:
            status = "Normal"
        elif f < 126:
            status = "Pre-Diabetic"
        else:
            status = "Diabetes Range"

    return ok({
        "readings": [r.to_dict() for r in readings],
        "latest": latest.to_dict() if latest else None,
        "status": status,
    })


# ════════════════════════════════════════════════════════════
# SLEEP
# ════════════════════════════════════════════════════════════


@tracker_api_bp.route("/sleep", methods=["POST"])
@jwt_required()
def add_sleep():
    user = get_current_user()
    data = request.get_json() or {}

    sleep_time = data.get("sleep_time", "")
    wake_time = data.get("wake_time", "")
    duration_hours = data.get("duration_hours")
    quality = data.get("quality")
    interruptions = data.get("interruptions", 0)
    mood_on_wake = data.get("mood_on_wake", "")
    notes = data.get("notes", "")
    log_date_str = data.get("log_date", str(today_ist()))

    try:
        log_date = datetime.strptime(log_date_str, "%Y-%m-%d").date()
    except ValueError:
        log_date = today_ist()

    if not duration_hours and sleep_time and wake_time:
        try:
            sh, sm = map(int, sleep_time.split(":"))
            wh, wm = map(int, wake_time.split(":"))
            sleep_mins = sh * 60 + sm
            wake_mins = wh * 60 + wm
            if wake_mins < sleep_mins:
                wake_mins += 24 * 60
            duration_hours = round((wake_mins - sleep_mins) / 60, 1)
        except Exception:
            pass

    existing = SleepLog.query.filter_by(user_id=user.id, log_date=log_date).first()
    if existing:
        sl = existing
    else:
        sl = SleepLog(user_id=user.id, log_date=log_date)
        db.session.add(sl)

    sl.sleep_time = sleep_time or sl.sleep_time
    sl.wake_time = wake_time or sl.wake_time
    sl.duration_hours = float(duration_hours) if duration_hours else sl.duration_hours
    sl.quality = int(quality) if quality else sl.quality
    sl.interruptions = int(interruptions) if interruptions else sl.interruptions
    sl.mood_on_wake = mood_on_wake or sl.mood_on_wake
    sl.notes = notes or sl.notes

    db.session.commit()
    return ok(sl.to_dict(), "Sleep log saved", 201)


@tracker_api_bp.route("/sleep", methods=["GET"])
@jwt_required()
def get_sleep():
    user = get_current_user()
    days = int(request.args.get("days", 14))
    since = today_ist() - timedelta(days=days)

    logs = SleepLog.query.filter(
        SleepLog.user_id == user.id,
        SleepLog.log_date >= since
    ).order_by(SleepLog.log_date.desc()).all()

    avg_hrs = avg_quality = None
    if logs:
        hrs = [l.duration_hours for l in logs if l.duration_hours]
        quals = [l.quality for l in logs if l.quality]
        if hrs:
            avg_hrs = round(sum(hrs) / len(hrs), 1)
        if quals:
            avg_quality = round(sum(quals) / len(quals), 1)

    target = user.goals.target_sleep_hours if user.goals else 7.5

    return ok({
        "logs": [l.to_dict() for l in logs],
        "avg_hours": avg_hrs,
        "avg_quality": avg_quality,
        "target_hours": target,
        "today": logs[0].to_dict() if logs and logs[0].log_date == today_ist() else None,
    })


# ════════════════════════════════════════════════════════════
# STEPS
# ════════════════════════════════════════════════════════════


@tracker_api_bp.route("/steps", methods=["POST"])
@jwt_required()
def add_steps():
    user = get_current_user()
    data = request.get_json() or {}

    try:
        steps = int(data.get("steps", 0))
        if steps < 0:
            return err("Steps cannot be negative")
    except (TypeError, ValueError):
        return err("Valid steps count required", 422)

    log_date_str = data.get("log_date", str(today_ist()))
    try:
        log_date = datetime.strptime(log_date_str, "%Y-%m-%d").date()
    except ValueError:
        log_date = today_ist()

    h = user.health_profile.height_cm if user.health_profile and user.health_profile.height_cm else 170
    w = user.health_profile.current_weight_kg if user.health_profile and user.health_profile.current_weight_kg else 70
    stride_m = (h * 0.414) / 100
    distance_km = round(steps * stride_m / 1000, 2)
    calories = int((steps / 100) * (3.5 * w * 3.5 / 200))

    goal_steps = user.goals.target_steps if user.goals else 8000

    existing = StepLog.query.filter_by(user_id=user.id, log_date=log_date).first()
    if existing:
        sl = existing
        sl.steps = steps
    else:
        sl = StepLog(user_id=user.id, log_date=log_date, goal_steps=goal_steps)
        db.session.add(sl)

    sl.steps = steps
    sl.distance_km = distance_km
    sl.calories_burned = calories
    sl.goal_achieved = steps >= goal_steps

    db.session.commit()
    return ok(sl.to_dict(), "Steps saved", 201)


@tracker_api_bp.route("/steps", methods=["GET"])
@jwt_required()
def get_steps():
    user = get_current_user()
    days = int(request.args.get("days", 7))
    since = today_ist() - timedelta(days=days)

    logs = StepLog.query.filter(
        StepLog.user_id == user.id,
        StepLog.log_date >= since
    ).order_by(StepLog.log_date.desc()).all()

    goal = user.goals.target_steps if user.goals else 8000
    today_log = StepLog.query.filter_by(
        user_id=user.id,
        log_date=today_ist()
    ).first()

    today_steps = today_log.steps if today_log else 0
    today_pct = min(100, int(today_steps / goal * 100)) if goal else 0

    h = user.health_profile.height_cm if user.health_profile else 170
    w = user.health_profile.current_weight_kg if user.health_profile else 70
    today_cal = int((today_steps / 100) * (3.5 * w * 3.5 / 200))
    today_dist = round(today_steps * (h * 0.414 / 100) / 1000, 2)

    return ok({
        "logs": [l.to_dict() for l in logs],
        "today_steps": today_steps,
        "today_pct": today_pct,
        "today_calories": today_cal,
        "today_distance": today_dist,
        "goal_steps": goal,
        "goal_achieved": today_steps >= goal,
    })


# ════════════════════════════════════════════════════════════
# HEART RATE
# ════════════════════════════════════════════════════════════


@tracker_api_bp.route("/heart-rate", methods=["POST"])
@jwt_required()
def add_heart_rate():
    user = get_current_user()
    data = request.get_json() or {}

    try:
        bpm = int(data.get("bpm", 0))
        if not (30 <= bpm <= 220):
            return err("BPM must be 30–220")
    except (TypeError, ValueError):
        return err("Valid BPM required", 422)

    reading_type = data.get("reading_type", "resting")
    notes = data.get("notes", "")

    hr = HeartRateLog(
        user_id=user.id,
        bpm=bpm,
        reading_type=reading_type,
        log_date=today_ist(),
        notes=notes or None,
        recorded_at=now_ist()
    )
    db.session.add(hr)
    db.session.commit()
    return ok(hr.to_dict(), "Heart rate saved", 201)


@tracker_api_bp.route("/heart-rate", methods=["GET"])
@jwt_required()
def get_heart_rate():
    user = get_current_user()
    days = int(request.args.get("days", 7))
    since = today_ist() - timedelta(days=days)

    logs = HeartRateLog.query.filter(
        HeartRateLog.user_id == user.id,
        HeartRateLog.log_date >= since
    ).order_by(HeartRateLog.recorded_at.desc()).all()

    resting = [l for l in logs if l.reading_type == "resting"]
    avg_resting = round(sum(l.bpm for l in resting) / len(resting), 0) if resting else None

    return ok({
        "logs": [l.to_dict() for l in logs],
        "avg_resting": avg_resting,
        "latest": logs[0].to_dict() if logs else None,
    })


# ════════════════════════════════════════════════════════════
# DELETE ANY METRIC
# ════════════════════════════════════════════════════════════


@tracker_api_bp.route("/<string:metric_type>/<int:metric_id>", methods=["DELETE"])
@jwt_required()
def delete_metric(metric_type, metric_id):
    user = get_current_user()
    m = HealthMetric.query.filter_by(
        id=metric_id,
        user_id=user.id,
        metric_type=metric_type
    ).first()
    if not m:
        return err("Entry not found", 404)
    db.session.delete(m)
    db.session.commit()
    return ok(msg="Entry deleted")


# ════════════════════════════════════════════════════════════
# SUMMARY (All metrics for dashboard)
# ════════════════════════════════════════════════════════════


@tracker_api_bp.route("/summary/today", methods=["GET"])
@jwt_required()
def today_summary():
    """Return all today's metrics in one call for APK dashboard."""
    user = get_current_user()
    today = today_ist()

    latest_bp = HealthMetric.query.filter_by(
        user_id=user.id,
        metric_type="bp"
    ).order_by(HealthMetric.recorded_at.desc()).first()

    latest_weight = HealthMetric.query.filter_by(
        user_id=user.id,
        metric_type="weight"
    ).order_by(HealthMetric.recorded_at.desc()).first()

    water_today = HealthMetric.query.filter(
        HealthMetric.user_id == user.id,
        HealthMetric.metric_type == "water",
        func.date(HealthMetric.recorded_at) == today
    ).with_entities(func.sum(HealthMetric.value_1)).scalar() or 0

    steps_today = StepLog.query.filter_by(user_id=user.id, log_date=today).first()
    sleep_today = SleepLog.query.filter_by(user_id=user.id, log_date=today).first()

    latest_sugar = HealthMetric.query.filter_by(
        user_id=user.id,
        metric_type="sugar"
    ).order_by(HealthMetric.recorded_at.desc()).first()

    goals = user.goals
    water_target = goals.target_water_litres if goals else 2.5
    steps_target = goals.target_steps if goals else 8000

    return ok({
        "date": str(today),
        "bp": {
            "latest": latest_bp.to_dict() if latest_bp else None,
            "status": latest_bp.bp_status if latest_bp else "No Reading",
        },
        "weight": {
            "latest": latest_weight.to_dict() if latest_weight else None,
            "bmi": user.bmi,
            "bmi_status": user.bmi_status,
        },
        "water": {
            "total": round(float(water_today), 2),
            "target": water_target,
            "pct": min(100, int(float(water_today) / water_target * 100)) if water_target else 0,
        },
        "steps": {
            "count": steps_today.steps if steps_today else 0,
            "calories": steps_today.calories_burned if steps_today else 0,
            "distance": steps_today.distance_km if steps_today else 0,
            "target": steps_target,
            "pct": min(100, int((steps_today.steps if steps_today else 0) / steps_target * 100)) if steps_target else 0,
        },
        "sleep": sleep_today.to_dict() if sleep_today else None,
        "sugar": latest_sugar.to_dict() if latest_sugar else None,
    })


# ════════════════════════════════════════════════════════════
# AI HEALTH CHAT
# ════════════════════════════════════════════════════════════


@tracker_api_bp.route("/ai/chat", methods=["POST"])
@jwt_required()
def ai_health_chat():
    from utils.gemini_ai import ask_gemini
    
    user = get_current_user()
    data = request.get_json() or {}
    message = data.get("message", "")
    
    if not message:
        return err("Message required", 422)
    
    # Extract conversation history
    history = data.get("history", [])
    
    # Pass user context for personalized responses
    response = ask_gemini(message, user=user, history=history)
    
    if response["success"]:
        return ok({
            "reply": response["reply"],
            "user_message": message
        })
    else:
        return err(response["reply"], 500)