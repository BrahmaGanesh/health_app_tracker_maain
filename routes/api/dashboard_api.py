# ============================================================
# routes/api/dashboard_api.py — Dashboard API for APK
# ============================================================

from flask import Blueprint, jsonify
from flask_jwt_extended import jwt_required, get_current_user
from datetime import datetime, date, timedelta

from models import (
    HealthMetric, MealPlan, MealItem, NutritionDailyLog,
    Alert, WeeklyInsight,
    SleepLog, StepLog, DailyHealthScore, Medicine, MedicineLog
)

dashboard_api_bp = Blueprint("dashboard_api", __name__)


def ok(data=None, msg="Success", code=200):
    r = {"success": True, "message": msg}
    if data is not None:
        r["data"] = data
    return jsonify(r), code


@dashboard_api_bp.route("/", methods=["GET"])
@jwt_required()
def dashboard():
    user = get_current_user()
    today = date.today()
    now = datetime.utcnow()

    latest_bp_list = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "bp"},
        order_by="-recorded_at",
        limit=1
    )
    latest_bp = latest_bp_list[0] if latest_bp_list else None

    bp_7day = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "bp", "recorded_at_gte": now - timedelta(days=7)},
        order_by="recorded_at"
    )

    avg_sys_7 = avg_dia_7 = None
    if bp_7day:
        sys_vals = [r.value1 for r in bp_7day if r.value1 is not None]
        dia_vals = [r.value2 for r in bp_7day if r.value2 is not None]
        if sys_vals:
            avg_sys_7 = round(sum(sys_vals) / len(sys_vals), 0)
        if dia_vals:
            avg_dia_7 = round(sum(dia_vals) / len(dia_vals), 0)

    bp_streak = _compute_streak(user.id, "bp")

    latest_weight = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "weight"},
        order_by="-recorded_at",
        limit=1
    )
    latest_weight = latest_weight[0] if latest_weight else None

    # Today's water
    water_today_list = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "water", "recorded_at_date": today}
    )
    water_today = sum(h.value1 for h in water_today_list if h.value1)

    water_target = 2.5
    # Could fetch from user.goals
    water_pct = min(100, int((water_today / water_target) * 100)) if water_target else 0

    # Today's nutrition
    log = NutritionDailyLog.get_one(filters={"user_id": user.id, "log_date": today})
    today_nutrition = log if log else None

    # Active meal plan
    active_plan_list = MealPlan.get_all(
        filters={"user_id": user.id, "is_active": True},
        order_by="-week_start_date",
        limit=1
    )
    active_plan = active_plan_list[0] if active_plan_list else None

    today_meals = []
    meals_done = 0
    meals_total = 0

    if active_plan:
        day_name = today.strftime("%A")
        items = MealItem.get_all(filters={"plan_id": active_plan.id, "day": today.strftime("%A")})
        today_meals = items
        meals_done = sum(1 for i in items if i.completed)
        meals_total = len(items)

    meals_pct = int((meals_done / meals_total) * 100) if meals_total else 0

    # Alerts
    active_alerts = Alert.get_all(
        filters={"user_id": user.id, "is_dismissed": False, "is_read": False},
        order_by="-created_at"
    )

    # Insights
    insights_list = WeeklyInsight.get_all(
        filters={"user_id": user.id, "week_start": today - timedelta(days=today.weekday())},
        order_by="priority"
    )
    insights = insights_list if insights_list else []

    # Medicines
    medicines_today = Medicine.get_all(
        filters={"user_id": user.id, "is_active": True}
    )
    meds_taken = 0
    meds_total = len(medicines_today)
    for med in medicines_today:
        log_today = MedicineLog.get_one(filters={"medicine_id": med.id, "log_date": date.today()})
        if log_today and log_today.taken:
            meds_taken += 1

    # Latest sugar
    latest_sugar = None
    if "Diabetes" in getattr(user, "condition_names", []):
        latest_sugar_list = HealthMetric.get_all(
            filters={"user_id": user.id, "metric_type": "sugar"},
            order_by="-recorded_at",
            limit=1
        )
        latest_sugar = latest_sugar_list[0] if latest_sugar_list else None

    # Weight progress
    weight_to_go = None
    weight_progress = 0
    goals = getattr(user, "goals", None)
    if goals and goals.target_weight_kg and latest_weight and latest_weight.value1:
        weight_to_go = round(latest_weight.value1 - goals.target_weight_kg, 1)
        if hasattr(user, "health_profile") and user.health_profile and user.health_profile.current_weight_kg:
            start = user.health_profile.current_weight_kg
            if start != goals.target_weight_kg:
                weight_progress = int((start - latest_weight.value1) / (start - goals.target_weight_kg) * 100)

    return ok({
        "bp": {
            "latest": latest_bp.to_dict() if latest_bp else None,
            "avg_sys_7": avg_sys_7,
            "avg_dia_7": avg_dia_7,
            "streak": bp_streak,
        },
        "weight": {
            "latest": latest_weight.to_dict() if latest_weight else None,
            "to_go": weight_to_go,
            "progress": weight_progress,
        },
        "water": {
            "today": water_today,
            "target": water_target,
            "percentage": water_pct,
        },
        "nutrition": {
            "today": today_nutrition.to_dict() if today_nutrition else None,
            "calorie_target": getattr(user, "daily_calorie_target", 2000),
            "protein_target": getattr(user, "daily_protein_target", 80),
        },
        "meals": {
            "today": [m.to_dict() for m in today_meals],
            "done": meals_done,
            "total": meals_total,
            "percentage": meals_pct,
        },
        "alerts": [a.to_dict() for a in active_alerts],
        "insights": [i.to_dict() for i in insights_list],
        "medicines": {
            "today": [m.to_dict() for m in medicines_today],
            "taken": meds_taken,
            "total": meds_total,
        },
        "sugar": {
            "latest": latest_sugar.to_dict() if latest_sugar else None,
        },
        "weight_progress": {
            "to_go": weight_to_go,
            "percentage": weight_progress,
        },
    })


def _compute_streak(user_id, metric_type):
    """Compute streak for a metric type."""
    streak = 0
    check_date = date.today()
    for _ in range(365):
        exists = HealthMetric.get_all(
            filters={"user_id": user_id, "metric_type": metric_type, "recorded_at_date": check_date},
            limit=1
        )
        if exists:
            streak += 1
            check_date -= timedelta(days=1)
        else:
            break
    return streak