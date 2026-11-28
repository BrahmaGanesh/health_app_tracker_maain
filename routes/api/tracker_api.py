# ============================================================
# routes/api/tracker_api.py — Health Tracker API for APK
# ============================================================

from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_current_user
from datetime import datetime, date, timedelta

from models import (
    HealthMetric, StepLog, SleepLog, UserHealthProfile
)

from models import now_ist, today_ist

tracker_api_bp = Blueprint("tracker_api", __name__)


def ok(data=None, msg="Success", code=200):
    r = {"success": True, "message": msg}
    if data is not None:
        r["data"] = data
    return jsonify(r), code


def err(msg, code=400):
    return jsonify({"success": False, "message": msg}), code


def _hm_get(metric, idx, default=None):
    """Get metric value by index (value1, value2, value3)."""
    return getattr(metric, f"value{idx}", default)


# ============================================================
# BP ENDPOINTS
# ============================================================

@tracker_api_bp.route("/bp", methods=["POST"])
@jwt_required()
def add_bp():
    user = get_current_user()
    data = request.get_json() or {}

    try:
        systolic = int(data.get("systolic", 0))
        diastolic = int(data.get("diastolic", 0))
        pulse = data.get("pulse")
        if pulse is not None:
            pulse = int(pulse)
    except (TypeError, ValueError):
        return err("Systolic and diastolic are required integers", 422)

    if not (60 <= systolic <= 250) or not (30 <= diastolic <= 150):
        return err("Invalid BP values", 422)

    m = HealthMetric(
        user_id=user.id,
        metric_type="bp",
        value1=systolic,
        value2=diastolic,
        value3=pulse,
        unit="mmHg",
        source="manual"
    )
    m.save()
    # db.session.commit()  # Firestore auto-commits

    return ok(m.to_dict(), "BP saved", 201)


@tracker_api_bp.route("/bp", methods=["GET"])
@jwt_required()
def get_bp():
    user = get_current_user()
    days = request.args.get("days", 7, type=int) or 7
    since = now_ist() - timedelta(days=days)

    readings = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "bp", "recorded_at_gte": since},
        order_by="-recorded_at"
    )

    latest = readings[0] if readings else None

    avg_sys = avg_dia = None
    if readings:
        sys_vals = [_hm_get(r, 1) for r in readings if _hm_get(r, 1) is not None]
        dia_vals = [_hm_get(r, 2) for r in readings if _hm_get(r, 2) is not None]
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
    user = get_current_user()
    data = request.get_json() or {}

    try:
        systolic = int(data.get("systolic", 0))
        diastolic = int(data.get("diastolic", 0))
        pulse = data.get("pulse")
        if pulse is not None:
            pulse = int(pulse)
    except (TypeError, ValueError):
        return err("Systolic and diastolic are required integers", 422)

    if not (60 <= systolic <= 250) or not (30 <= diastolic <= 150):
        return err("Invalid BP values", 422)

    m = HealthMetric(
        user_id=user.id,
        metric_type="bp",
        value1=systolic,
        value2=diastolic,
        value3=pulse,
        unit="mmHg",
        source="manual"
    )
    m.save()
    # db.session.commit()  # Firestore auto-commits

    return ok(m.to_dict(), "BP saved", 201)


# ============================================================
# WEIGHT ENDPOINTS
# ============================================================

@tracker_api_bp.route("/weight", methods=["POST"])
@jwt_required()
def add_weight():
    user = get_current_user()
    data = request.get_json() or {}

    try:
        weight = float(data.get("weight_kg", 0))
        if not (20 <= weight <= 300):
            return err("Weight must be 20–300 kg", 422)
    except (TypeError, ValueError):
        return err("Valid weight required", 422)

    m = HealthMetric(
        user_id=user.id,
        metric_type="weight",
        value1=weight,
        unit="kg",
        source="manual"
    )
    m.save()
    # db.session.commit()  # Firestore auto-commits

    return ok(m.to_dict(), "Weight saved", 201)


@tracker_api_bp.route("/weight", methods=["GET"])
@jwt_required()
def get_weight():
    user = get_current_user()
    days = request.args.get("days", 30, type=int) or 30
    since = now_ist() - timedelta(days=days)

    readings = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "weight", "recorded_at_gte": since},
        order_by="recorded_at"
    )

    latest_list = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "weight"},
        order_by="-recorded_at",
        limit=1
    )
    latest = latest_list[0] if latest_list else None

    change = None
    if len(readings) >= 2:
        start_w = _hm_get(readings[0], 1)
        end_w = _hm_get(readings[-1], 1)
        if start_w is not None and end_w is not None:
            change = round(end_w - start_w, 1)

    goals = user.goals
    progress_pct = 0
    if goals and goals.target_weight_kg and goals.start_weight_kg and latest:
        latest_w = _hm_get(latest, 1)
        if latest_w is not None:
            diff = goals.start_weight_kg - goals.target_weight_kg
            done = goals.start_weight_kg - latest_w
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


# ============================================================
# WATER ENDPOINTS
# ============================================================

@tracker_api_bp.route("/water/today", methods=["GET"])
@jwt_required()
def get_water_today():
    user = get_current_user()
    today = today_ist()

    water_today_list = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "water", "recorded_at_date": today}
    )
    total = sum(h.value1 for h in water_today_list if h.value1)

    logs = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "water", "recorded_at_date": today},
        order_by="-recorded_at"
    )

    target = user.goals.target_water_litres if user.goals else 2.5
    pct = min(100, int((float(total) / target) * 100)) if target else 0

    week = []
    for i in range(6, -1, -1):
        d = today - timedelta(days=i)
        water_d_list = HealthMetric.get_all(
            filters={"user_id": user.id, "metric_type": "water", "recorded_at_date": d}
        )
        t = sum(h.value1 for h in water_d_list if h.value1)

        week.append({
            "day": d.strftime("%a"),
            "date": str(d),
            "litres": round(float(t), 2)
        })

    return ok({
        "today_total": round(float(total), 2),
        "target": target,
        "pct": pct,
        "goal_achieved": float(total) >= target,
        "logs": [r.to_dict() for r in logs],
        "week": week,
    })


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
        value1=amount,
        unit="L",
        source="manual"
    )
    m.save()
    # db.session.commit()  # Firestore auto-commits

    return ok(m.to_dict(), "Water saved", 201)


# ============================================================
# SUGAR ENDPOINTS
# ============================================================

@tracker_api_bp.route("/sugar", methods=["POST"])
@jwt_required()
def add_sugar():
    user = get_current_user()
    data = request.get_json() or {}

    fasting = data.get("fasting")
    post_meal = data.get("post_meal")

    if fasting is None and post_meal is None:
        return err("At least one of fasting or post_meal required", 422)

    m = HealthMetric(
        user_id=user.id,
        metric_type="sugar",
        value1=fasting,
        value2=post_meal,
        unit="mg/dL",
        source="manual"
    )
    m.save()
    # db.session.commit()  # Firestore auto-commits

    return ok(m.to_dict(), "Sugar saved", 201)


@tracker_api_bp.route("/sugar", methods=["GET"])
@jwt_required()
def get_sugar():
    user = get_current_user()
    days = request.args.get("days", 30, type=int) or 30
    since = today_ist() - timedelta(days=days)

    readings = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "sugar", "recorded_at_gte": since},
        order_by="-recorded_at"
    )

    latest = readings[0] if readings else None

    return ok({
        "readings": [r.to_dict() for r in readings],
        "latest": latest.to_dict() if latest else None,
        "count": len(readings),
    })


# ============================================================
# SLEEP ENDPOINTS
# ============================================================

@tracker_api_bp.route("/sleep", methods=["GET"])
@jwt_required()
def get_sleep():
    user = get_current_user()
    days = request.args.get("days", 14, type=int) or 14
    since = today_ist() - timedelta(days=days)

    logs = SleepLog.get_all(
        filters={"user_id": user.id, "log_date_gte": since},
        order_by="-log_date"
    )

    avg_hrs = avg_quality = None
    if logs:
        hrs = [l.duration_hours for l in logs if l.duration_hours is not None]
        quals = [l.quality for l in logs if l.quality is not None]
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


@tracker_api_bp.route("/sleep", methods=["POST"])
@jwt_required()
def add_sleep():
    user = get_current_user()
    data = request.get_json() or {}

    try:
        sleep_time = data.get("sleep_time")
        wake_time = data.get("wake_time")
        quality = int(data.get("quality", 0)) if data.get("quality") else None
        interruptions = int(data.get("interruptions", 0))
        duration = float(data.get("duration_hours", 0)) if data.get("duration_hours") else None
        notes = data.get("notes")
        log_date = data.get("log_date")
        if log_date:
            log_date = datetime.strptime(log_date, "%Y-%m-%d").date()
        else:
            log_date = date.today()

        if not duration and sleep_time and wake_time:
            sh, sm = map(int, sleep_time.split(":"))
            wh, wm = map(int, wake_time.split(":"))
            sleep_mins = sh * 60 + sm
            wake_mins = wh * 60 + wm
            if wake_mins < sleep_mins:
                wake_mins += 24 * 60
            duration = round((wake_mins - sleep_mins) / 60, 1)

        sl = SleepLog(
            user_id=user.id,
            log_date=log_date,
            sleep_time=sleep_time,
            wake_time=wake_time,
            duration_hours=duration,
            quality=quality,
            interruptions=interruptions,
            notes=data.get("notes"),
        )
        sl.save()
        # db.session.commit()  # Firestore auto-commits

        return ok(sl.to_dict(), "Sleep saved", 201)
    except Exception as e:
        return err(f"Invalid data: {e}", 422)


# ============================================================
# STEPS ENDPOINTS
# ============================================================

@tracker_api_bp.route("/steps", methods=["GET"])
@jwt_required()
def get_steps():
    user = get_current_user()
    days = request.args.get("days", 7, type=int) or 7
    since = today_ist() - timedelta(days=days)

    logs = StepLog.get_all(
        filters={"user_id": user.id, "log_date_gte": since},
        order_by="-log_date"
    )

    goal = user.goals.target_steps if user.goals else 8000
    today_log_list = StepLog.get_all(
        filters={"user_id": user.id, "log_date": today_ist()},
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


@tracker_api_bp.route("/steps", methods=["POST"])
@jwt_required()
def add_steps():
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
        log_date=data.get("log_date", date.today()),
        steps=steps,
        distance_km=dist,
        calories_burned=cals
    )
    sl.save()
    # db.session.commit()  # Firestore auto-commits

    return ok(sl.to_dict(), "Steps saved", 201)


# ============================================================
# SUMMARY ENDPOINT
# ============================================================

@tracker_api_bp.route("/summary/today", methods=["GET"])
@jwt_required()
def today_summary():
    user = get_current_user()
    today = today_ist()

    latest_bp_list = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "bp"},
        order_by="-recorded_at",
        limit=1
    )
    latest_bp = latest_bp_list[0] if latest_bp_list else None

    latest_weight_list = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "weight"},
        order_by="-recorded_at",
        limit=1
    )
    latest_weight = latest_weight_list[0] if latest_weight_list else None

    water_today_list = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "water", "recorded_at_date": today}
    )
    water_today = sum(h.value1 for h in water_today_list if h.value1)

    steps_today_list = StepLog.get_all(
        filters={"user_id": user.id, "log_date": today},
        limit=1
    )
    steps_today = steps_today_list[0] if steps_today_list else None

    sleep_today_list = SleepLog.get_all(
        filters={"user_id": user.id, "log_date": today},
        limit=1
    )
    sleep_today = sleep_today_list[0] if sleep_today_list else None

    latest_sugar_list = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "sugar"},
        order_by="-recorded_at",
        limit=1
    )
    latest_sugar = latest_sugar_list[0] if latest_sugar_list else None

    goals = user.goals
    water_target = goals.target_water_litres if goals else 2.5
    steps_target = goals.target_steps if goals else 8000

    bp_status = "No Reading"
    if latest_bp:
        s = _hm_get(latest_bp, 1, 0) or 0
        d = _hm_get(latest_bp, 2, 0) or 0
        if s < 120 and d < 80: bp_status = "Normal"
        elif s < 130 and d < 80: bp_status = "Elevated"
        elif s < 140 or d < 90: bp_status = "High Stage 1"
        elif s < 180 or d < 120: bp_status = "High Stage 2"
        else: bp_status = "Crisis"

    weight_status = "No Reading"
    if latest_weight:
        weight_status = f"{latest_weight.value1} kg"

    sugar_status = "No Reading"
    if latest_sugar:
        f = _hm_get(latest_sugar, 1, 0) or 0
        if f < 100: sugar_status = "Normal"
        elif f < 126: sugar_status = "Pre-Diabetic"
        else: sugar_status = "Diabetes Range"

    steps_today = steps_today_list[0].steps if steps_today_list else 0
    steps_today_list = StepLog.get_all(filters={"user_id": user.id, "log_date": today}, limit=1)
    steps_today = steps_today_list[0].steps if steps_today_list else 0
    step_goal = user.goals.target_steps if user.goals else 8000

    water_target = user.goals.target_water_litres if user.goals else 2.5
    water_pct = min(100, int(water_today / water_target * 100)) if water_target else 0

    return ok({
        "bp": {
            "latest": latest_bp.to_dict() if latest_bp else None,
            "status": bp_status,
        },
        "weight": {
            "latest": latest_weight.to_dict() if latest_weight else None,
            "status": weight_status,
        },
        "water": {
            "today_total": round(water_today, 2),
            "target": water_target,
            "pct": water_pct,
        },
        "steps": {
            "today": today_steps,
            "target": steps_target,
            "pct": steps_pct,
        },
        "sleep": {
            "latest": sleep_today.to_dict() if sleep_today else None,
        },
        "sugar": {
            "latest": latest_sugar.to_dict() if latest_sugar else None,
            "status": sugar_status,
        },
    })


# ============================================================
# HEART RATE ENDPOINTS (Optional)
# ============================================================

@tracker_api_bp.route("/heart-rate", methods=["POST"])
@jwt_required()
def add_heart_rate():
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
    # db.session.commit()  # Firestore auto-commits

    return ok(hr.to_dict(), "Heart rate saved", 201)


@tracker_api_bp.route("/heart-rate", methods=["GET"])
@jwt_required()
def get_heart_rate():
    user = get_current_user()
    days = request.args.get("days", 30, type=int) or 30
    since = today_ist() - timedelta(days=days)

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