# ============================================================
# routes/api/dashboard_api.py — Dashboard API for APK
# ============================================================

from flask import Blueprint, jsonify
from flask_jwt_extended import jwt_required, get_current_user
from datetime import datetime, date, timedelta
from sqlalchemy import func

from extensions import db
from models import (
    HealthMetric, MealPlan, MealItem, NutritionDailyLog,
    Alert, WeeklyInsight,
    SleepLog, StepLog, DailyHealthScore, Medicine, MedicineLog
)

# Import new module models separately
# from models_new_modules import

dashboard_api_bp = Blueprint("dashboard_api", __name__)


def ok(data=None, msg="Success", code=200):
    r = {"success": True, "message": msg}
    if data is not None: r["data"] = data
    return jsonify(r), code


@dashboard_api_bp.route("/", methods=["GET"])
@jwt_required()
def dashboard():
    user  = get_current_user()
    today = date.today()
    now   = datetime.utcnow()

    # ── Latest BP ─────────────────────────────────────────────
    latest_bp = HealthMetric.query.filter_by(
        user_id=user.id, metric_type="bp"
    ).order_by(HealthMetric.recorded_at.desc()).first()

    bp_7day = HealthMetric.query.filter(
        HealthMetric.user_id    == user.id,
        HealthMetric.metric_type == "bp",
        HealthMetric.recorded_at >= now - timedelta(days=7)
    ).order_by(HealthMetric.recorded_at.asc()).all()

    avg_sys_7 = avg_dia_7 = None
    if bp_7day:
        avg_sys_7 = round(sum(r.value_1 for r in bp_7day if r.value_1) / len(bp_7day), 0)
        avg_dia_7 = round(sum(r.value_2 for r in bp_7day if r.value_2) / len(bp_7day), 0)

    # BP tracking streak
    bp_streak = _compute_streak(user.id, "bp")

    # ── Latest Weight ─────────────────────────────────────────
    latest_weight = HealthMetric.query.filter_by(
        user_id=user.id, metric_type="weight"
    ).order_by(HealthMetric.recorded_at.desc()).first()

    # ── Water today ───────────────────────────────────────────
    water_today = HealthMetric.query.filter(
        HealthMetric.user_id     == user.id,
        HealthMetric.metric_type == "water",
        func.date(HealthMetric.recorded_at) == today
    ).with_entities(func.sum(HealthMetric.value_1)).scalar() or 0

    water_target = user.goals.target_water_litres if user.goals else 2.5
    water_pct    = min(100, int(float(water_today) / water_target * 100)) if water_target else 0

    # ── Steps today ───────────────────────────────────────────
    steps_today = StepLog.query.filter_by(user_id=user.id, log_date=today).first()
    steps_target = user.goals.target_steps if user.goals else 8000

    # ── Sleep last night ──────────────────────────────────────
    sleep_today = SleepLog.query.filter_by(user_id=user.id, log_date=today).first()
    sleep_yesterday = SleepLog.query.filter_by(
        user_id=user.id, log_date=today - timedelta(days=1)
    ).first()
    sleep_record = sleep_today or sleep_yesterday

    # ── Today's meals ─────────────────────────────────────────
    active_plan = MealPlan.query.filter_by(
        user_id=user.id, is_active=True
    ).order_by(MealPlan.generated_at.desc()).first()

    today_meals   = []
    meals_done    = 0
    meals_total   = 0
    meals_pct     = 0

    if active_plan:
        day_name = today.strftime("%A")
        items = MealItem.query.filter_by(
            plan_id=active_plan.id, day=day_name
        ).order_by(MealItem.slot_order.asc()).all()
        for item in items:
            today_meals.append({
                "id":         item.id,
                "meal_slot":  item.meal_slot,
                "slot_order": item.slot_order,
                "completed":  item.completed,
                "recipe": {
                    "id":       item.recipe.id,
                    "name":     item.recipe.name,
                    "calories": item.recipe.calories,
                    "protein":  item.recipe.protein,
                    "category": item.recipe.category,
                }
            })
        meals_done  = sum(1 for m in today_meals if m["completed"])
        meals_total = len(today_meals)
        meals_pct   = int(meals_done / meals_total * 100) if meals_total else 0

    # ── Nutrition today ───────────────────────────────────────
    nutrition_today = NutritionDailyLog.query.filter_by(
        user_id=user.id, log_date=today
    ).first()

    # ── Alerts (unread) ───────────────────────────────────────
    active_alerts = Alert.query.filter_by(
        user_id=user.id, is_read=False, is_dismissed=False
    ).order_by(Alert.created_at.desc()).limit(5).all()

    # ── Medicines today ───────────────────────────────────────
    meds_today = []
    meds_today = []

    for med in user.medicines:
        if not med.is_active:
            continue

        log = MedicineLog.query.filter_by(
            medicine_id=med.id,
            log_date=today
        ).first()

        meds_today.append({
            "id": med.id,
            "name": med.name,
            "dosage": med.dosage,
            "timing": med.timing,
            "taken": log.taken if log else False,
        })

    meds_taken = sum(1 for m in meds_today if m["taken"])

    # ── Weekly insights ───────────────────────────────────────
    week_start = today - timedelta(days=today.weekday())
    insights   = WeeklyInsight.query.filter_by(
        user_id=user.id, week_start=week_start
    ).order_by(WeeklyInsight.priority.asc()).limit(3).all()

    insights_data = [
        {
            "text":      i.insight_text,
            "icon":      i.icon,
            "direction": i.direction,
            "metric":    i.metric_type,
            "priority":  i.priority,
        }
        for i in insights
    ]

    # If no insights, generate live
    if not insights_data:
        insights_data = _live_insights(user, latest_bp, nutrition_today)

    # ── Health score today ────────────────────────────────────
    score_today = DailyHealthScore.query.filter_by(
        user_id=user.id, score_date=today
    ).first()

    # ── 7-day chart data ──────────────────────────────────────
    bp_chart = [
        {"day": r.recorded_at.strftime("%a"), "sys": r.value_1, "dia": r.value_2}
        for r in bp_7day
    ]

    hour = datetime.now().hour
    if hour < 12:   greeting = "Good morning"
    elif hour < 17: greeting = "Good afternoon"
    else:           greeting = "Good evening"

    return ok({
        "greeting":     f"{greeting}, {user.name}",
        "date":         str(today),
        "day_name":     today.strftime("%A, %d %B %Y"),

        "bp": {
            "latest":   latest_bp.to_dict() if latest_bp else None,
            "status":   latest_bp.bp_status if latest_bp else "No Reading",
            "avg_sys_7": avg_sys_7,
            "avg_dia_7": avg_dia_7,
            "streak":   bp_streak,
            "chart":    bp_chart,
        },

        "weight": {
            "latest": latest_weight.to_dict() if latest_weight else None,
            "bmi":    user.bmi,
            "bmi_status": user.bmi_status,
        },

        "water": {
            "today_total": round(float(water_today), 2),
            "target":      water_target,
            "pct":         water_pct,
        },

        "steps": {
            "count":    steps_today.steps if steps_today else 0,
            "calories": steps_today.calories_burned if steps_today else 0,
            "distance": steps_today.distance_km if steps_today else 0,
            "target":   steps_target,
            "pct":      min(100, int((steps_today.steps if steps_today else 0) / steps_target * 100)),
        },

        "sleep": sleep_record.to_dict() if sleep_record else None,

        "meals": {
            "items":       today_meals,
            "done":        meals_done,
            "total":       meals_total,
            "pct":         meals_pct,
            "has_plan":    active_plan is not None,
        },

        "nutrition": nutrition_today.to_dict() if nutrition_today else None,

        "medicines": {
            "list":  meds_today,
            "taken": meds_taken,
            "total": len(meds_today),
        },

        "alerts": [a.to_dict() for a in active_alerts],
        "alert_count": len(active_alerts),

        "insights": insights_data,

        "health_score": score_today.to_dict() if score_today else None,

        "targets": {
            "calories":     user.daily_calorie_target,
            "protein":      user.daily_protein_target,
            "water":        water_target,
            "steps":        steps_target,
            "sleep_hours":  user.goals.target_sleep_hours if user.goals else 7.5,
            "exercise_mins": user.goals.target_exercise_mins if user.goals else 30,
            "bp_target":    f"{user.goals.target_bp_systolic}/{user.goals.target_bp_diastolic}" if user.goals else "130/80",
        },

        "conditions": user.condition_names,
        "has_bp":       user.has_bp,
        "has_diabetes": user.has_diabetes,
    })


def _compute_streak(user_id, metric_type):
    streak   = 0
    check_dt = date.today()
    for _ in range(365):
        exists = HealthMetric.query.filter(
            HealthMetric.user_id    == user_id,
            HealthMetric.metric_type == metric_type,
            func.date(HealthMetric.recorded_at) == check_dt
        ).first()
        if exists:
            streak  += 1
            check_dt -= timedelta(days=1)
        else:
            break
    return streak


def _live_insights(user, latest_bp, nutrition):
    insights = []

    if latest_bp and user.has_bp:
        s = latest_bp.value_1 or 0
        d = latest_bp.value_2 or 0
        if s >= 160:
            insights.append({"text": f"BP {int(s)}/{int(d)} mmHg needs attention. Review salt intake and medicine.", "icon": "📈", "direction": "worsening", "metric": "bp", "priority": 1})
        elif s < 130 and d < 80:
            insights.append({"text": f"BP {int(s)}/{int(d)} mmHg is in normal range. Excellent progress.", "icon": "📉", "direction": "improving", "metric": "bp", "priority": 1})
        else:
            insights.append({"text": f"BP {int(s)}/{int(d)} mmHg — continue daily monitoring twice a day.", "icon": "📊", "direction": "stable", "metric": "bp", "priority": 2})

    if nutrition:
        cal = nutrition.total_calories or 0
        tgt = user.daily_calorie_target
        pct = int(cal / tgt * 100) if tgt else 0
        if pct < 50:
            insights.append({"text": f"Only {cal} kcal consumed so far. Complete all 5 meal slots today.", "icon": "🍽️", "direction": "worsening", "metric": "nutrition", "priority": 2})
        else:
            insights.append({"text": f"Good nutrition — {cal}/{tgt} kcal logged. Keep going.", "icon": "🥗", "direction": "stable", "metric": "nutrition", "priority": 3})

    return insights[:3]