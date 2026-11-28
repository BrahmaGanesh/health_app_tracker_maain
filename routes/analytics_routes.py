# ============================================================
# ANALYTICS ROUTES
# ============================================================

from flask import (
    Blueprint, render_template, redirect,
    url_for, flash, request, jsonify
)
from flask_login import login_required, current_user
from datetime import datetime, date, timedelta
from statistics import mean

from models import (
    HealthMetric, NutritionDailyLog, WeeklyInsight,
    MealPlan, MealItem, HealthCondition
)

analytics_bp = Blueprint("analytics", __name__)


# ── HELPERS ────────────────────────────────────────────────────

def _compute_bp_stats(user, since):
    """Compute BP statistics for the given period."""
    bp_readings = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "bp", "recorded_at_gte": since},
        order_by="recorded_at"
    )

    if not bp_readings:
        return {
            "chart": [],
            "avg_sys": None,
            "avg_dia": None,
            "days_normal": 0,
            "days_high": 0,
            "streak": 0,
        }

    bp_chart = [
        {
            "day": r.recorded_at.strftime("%d %b"),
            "sys": r.value1,
            "dia": r.value2,
            "pulse": r.value3,
        }
        for r in bp_readings
    ]

    sys_vals = [r.value1 for r in bp_readings if r.value1]
    dia_vals = [r.value2 for r in bp_readings if r.value2]
    avg_sys = round(mean(sys_vals), 1) if sys_vals else None
    avg_dia = round(mean(dia_vals), 1) if dia_vals else None

    days_normal = days_high = 0
    for r in bp_readings:
        if r.value1 and r.value2:
            s, d = r.value1, r.value2
            if s < 120 and d < 80:
                days_normal += 1
            elif s >= 140 or d >= 90:
                days_high += 1

    # Streak (consecutive days with readings)
    streak = 0
    check_date = date.today()
    for _ in range(365):
        exists = HealthMetric.get_all(
            filters={"user_id": current_user.id, "metric_type": "bp", "recorded_at_date": check_date},
            limit=1
        )
        if exists:
            streak += 1
            check_date -= timedelta(days=1)
        else:
            break

    return {
        "chart": bp_chart,
        "avg_sys": avg_sys,
        "avg_dia": avg_dia,
        "days_normal": days_normal,
        "days_high": days_high,
        "streak": streak,
    }


def _compute_weight_stats(user, since):
    """Compute weight statistics for the given period."""
    weight_readings = HealthMetric.get_all(
        filters={"user_id": current_user.id, "metric_type": "weight", "recorded_at_gte": since},
        order_by="recorded_at"
    )

    if not weight_readings:
        return {"chart": [], "latest_weight": None, "change_60": None}

    weight_chart = [
        {"day": r.recorded_at.strftime("%d %b"), "weight": r.value1}
        for r in weight_readings
    ]

    latest_weight = weight_readings[0] if weight_readings else None

    # 60-day change
    sixty_ago = datetime.utcnow() - timedelta(days=60)
    early = [r for r in weight_readings if r.recorded_at <= sixty_ago]
    late = [r for r in weight_readings if r.recorded_at > sixty_ago]

    wt_change_60 = None
    if early and late:
        early_avg = mean(r.value1 for r in early if r.value1)
        late_avg = mean(r.value1 for r in late if r.value1)
        wt_change_60 = round(late_avg - early_avg, 1)

    return {
        "chart": weight_chart,
        "latest_weight": weight_readings[0] if weight_readings else None,
        "change_60": wt_change_60,
    }


def _compute_nutrition_stats(user, since):
    """Compute nutrition statistics for the given period."""
    logs = NutritionDailyLog.get_all(
        filters={"user_id": current_user.id, "log_date_gte": since},
        order_by="log_date"
    )

    if not logs:
        return {"chart": [], "avg_cal_14": None, "avg_pro_14": None}

    nutrition_chart = [
        {
            "day": l.log_date.strftime("%d %b"),
            "calories": l.total_calories,
            "protein": l.total_protein,
        }
        for l in logs
    ]

    avg_cal_14 = round(sum(l.total_calories for l in logs) / len(logs), 1)
    avg_pro_14 = round(sum(l.total_protein for l in logs) / len(logs), 1)

    return {
        "chart": nutrition_chart,
        "avg_cal_14": avg_cal_14,
        "avg_pro_14": avg_pro_14,
    }


def _compute_water_stats(user, since):
    """Compute water intake statistics for the given period."""
    logs = NutritionDailyLog.get_all(
        filters={"user_id": current_user.id, "log_date_gte": since},
        order_by="log_date"
    )

    if not logs:
        return {"chart": [], "water_7": None}

    water_7 = [
        {"day": l.log_date.strftime("%d %b"), "water": l.total_water}
        for l in logs
    ]

    return {
        "chart": water_7,
        "water_7": water_7,
    }


def _generate_insights(user, period_days=14):
    """Generate health insights for the user."""
    insights = []
    since = datetime.utcnow() - timedelta(days=period_days)

    # BP insights
    bp_readings = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "bp", "recorded_at_gte": since},
        order_by="recorded_at"
    )
    if bp_readings:
        latest = bp_readings[0]
        if latest.value1 and latest.value2:
            s, d = latest.value1, latest.value2
            if s >= 140 or d >= 90:
                insights.append({
                    "type": "warning",
                    "title": "Elevated Blood Pressure",
                    "message": f"Your latest BP {int(s)}/{int(d)} mmHg is elevated. Consider reducing sodium and reviewing medication.",
                    "priority": 1,
                })
            elif s < 120 and d < 80:
                insights.append({
                    "type": "success",
                    "title": "BP in Normal Range",
                    "message": f"Your latest BP {int(s)}/{int(d)} mmHg is in the normal range. Keep up the good work!",
                    "priority": 2,
                })

    # Weight trend
    weight_readings = HealthMetric.get_all(
        filters={"user_id": current_user.id, "metric_type": "weight", "recorded_at_gte": datetime.utcnow() - timedelta(days=period_days)},
        order_by="recorded_at"
    )
    if len(weight_readings) >= 2:
        first = weight_readings[-1].value1
        last = weight_readings[0].value1
        if first and last:
            change = round(last - first, 1)
            if change > 1:
                insights.append({
                    "type": "warning",
                    "title": "Weight Gain Trend",
                    "message": f"You've gained {abs(change)} kg over the last {period_days} days. Review diet and activity.",
                    "priority": 2,
                })
            elif change < -1:
                insights.append({
                    "type": "success",
                    "title": "Weight Loss Progress",
                    "message": f"You've lost {abs(change)} kg over the last {period_days} days. Great progress!",
                    "priority": 2,
                })

    # Nutrition
    nutri_logs = NutritionDailyLog.get_all(
        filters={"user_id": current_user.id, "log_date_gte": datetime.utcnow() - timedelta(days=period_days)},
        order_by="log_date"
    )
    if nutri_logs:
        avg_cal = sum(l.total_calories for l in nutri_logs if l.total_calories) / len(nutri_logs)
        target = current_user.daily_calorie_target
        if avg_cal > target * 1.2:
            insights.append({
                "type": "warning",
                "title": "High Calorie Intake",
                "message": f"Average {int(avg_cal)} kcal/day exceeds target of {target}. Consider portion control.",
                "priority": 3,
            })

    return insights


# ============================================================
# ANALYTICS DASHBOARD
# ============================================================

analytics_bp = Blueprint("analytics", __name__)


@analytics_bp.route("/")
@login_required
def index():
    today = date.today()
    user = current_user

    # Time ranges
    since_30 = datetime.utcnow() - timedelta(days=30)
    since_14 = datetime.utcnow() - timedelta(days=14)
    since_60 = datetime.utcnow() - timedelta(days=60)

    # BP stats
    bp_stats = _compute_bp_stats(user, since_30)
    bp_chart = bp_stats["chart"]
    avg_sys = bp_stats["avg_sys"]
    avg_dia = bp_stats["avg_dia"]
    days_normal = bp_stats["days_normal"]
    days_high = bp_stats["days_high"]
    bp_streak = bp_stats["streak"]

    # Weight stats
    wt_stats = _compute_weight_stats(user, since_60)
    weight_chart = wt_stats["chart"]
    latest_weight = wt_stats["latest_weight"]
    wt_change_60 = wt_stats["change_60"]

    # Nutrition stats
    nutri_stats = _compute_nutrition_stats(user, since_14)
    nutrition_chart = nutri_stats["chart"]
    avg_cal_14 = nutri_stats["avg_cal_14"]
    avg_pro_14 = nutri_stats["avg_pro_14"]

    # Water stats
    water_stats = _compute_water_stats(user, since_14)
    water_7 = water_stats["water_7"]

    # Meal adherence
    active_plan_list = MealPlan.get_all(filters={"user_id": user.id, "is_active": True}, limit=1)
    active_plan = active_plan_list[0] if active_plan_list else None

    meal_adherence = 0
    if active_plan:
        total_items = MealItem.count(filters={"plan_id": active_plan.id})
        completed_items = MealItem.count(filters={"plan_id": active_plan.id, "completed": True})
        if total_items:
            meal_adherence = int(completed_items / total_items * 100)

    # Weekly insights
    week_start = today - timedelta(days=today.weekday())
    insights_list = WeeklyInsight.get_all(
        filters={"user_id": user.id, "week_start": week_start},
        order_by="priority"
    )
    insights = insights_list if insights_list else _generate_insights(user, 14)

    # Score trend
    nutri_14 = NutritionDailyLog.get_all(
        filters={"user_id": current_user.id, "log_date_gte": datetime.utcnow() - timedelta(days=14)},
        order_by="log_date"
    )
    score_trend = [
        {"day": l.log_date.strftime("%d %b"), "score": l.health_score}
        for l in nutri_14 if l.health_score
    ]

    return render_template(
        "analytics/index.html",
        # BP
        bp_chart=bp_chart,
        avg_sys=avg_sys,
        avg_dia=avg_dia,
        days_normal=days_normal,
        days_high=days_high,
        bp_streak=bp_streak,
        # Weight
        weight_chart=weight_chart,
        latest_weight=latest_weight,
        wt_change_60=wt_change_60,
        # Nutrition
        nutrition_chart=nutrition_chart,
        avg_cal_14=avg_cal_14,
        avg_pro_14=avg_pro_14,
        # Water
        water_7=water_7,
        # Meals
        meal_adherence=meal_adherence,
        # Insights
        insights=insights,
        # Score
        score_trend=score_trend,
        # Targets
        calorie_target=current_user.daily_calorie_target,
        protein_target=current_user.daily_protein_target,
        water_target=current_user.goals.target_water_litres if current_user.goals else 2.5,
        today=today,
    )


# ============================================================
# CHART DATA API — for dynamic range loading
# ============================================================

@analytics_bp.route("/bp-data")
@login_required
def bp_data():
    days = min(int(request.args.get("days", 30)), 90)
    since = datetime.utcnow() - timedelta(days=days)
    records = HealthMetric.get_all(
        filters={"user_id": current_user.id, "metric_type": "bp", "recorded_at_gte": since},
        order_by="recorded_at"
    )

    return jsonify([
        {"day": r.recorded_at.strftime("%d %b"), "sys": r.value1, "dia": r.value2, "pulse": r.value3}
        for r in records
    ])


@analytics_bp.route("/weight-data")
@login_required
def weight_data():
    days = min(int(request.args.get("days", 30)), 180)
    since = datetime.utcnow() - timedelta(days=days)
    records = HealthMetric.get_all(
        filters={"user_id": current_user.id, "metric_type": "weight", "recorded_at_gte": since},
        order_by="recorded_at"
    )
    return jsonify([{"day": r.recorded_at.strftime("%d %b"), "weight": r.value1} for r in records])


@analytics_bp.route("/nutrition-data")
@login_required
def nutrition_data():
    days = min(int(request.args.get("days", 14)), 90)
    since = datetime.utcnow() - timedelta(days=days)
    logs = NutritionDailyLog.get_all(
        filters={"user_id": current_user.id, "log_date_gte": since},
        order_by="log_date"
    )
    return jsonify([
        {"day": l.log_date.strftime("%d %b"), "calories": l.total_calories, "protein": l.total_protein}
        for l in logs
    ])


@analytics_bp.route("/water-data")
@login_required
def water_data():
    days = min(int(request.args.get("days", 7)), 90)
    since = datetime.utcnow() - timedelta(days=days)
    logs = NutritionDailyLog.get_all(
        filters={"user_id": current_user.id, "log_date_gte": since},
        order_by="log_date"
    )
    return jsonify([
        {"day": l.log_date.strftime("%d %b"), "water": l.total_water}
        for l in logs
    ])


@analytics_bp.route("/meal-adherence-data")
@login_required
def meal_adherence_data():
    days = min(int(request.args.get("days", 30)), 90)
    since = datetime.utcnow() - timedelta(days=days)

    active_plan_list = MealPlan.get_all(filters={"user_id": current_user.id, "is_active": True}, order_by="-week_start_date", limit=1)
    active_plan = active_plan_list[0] if active_plan_list else None

    if not active_plan:
        return jsonify([])

    data = []
    for day_offset in range(days):
        day = date.today() - timedelta(days=day_offset)
        day_name = day.strftime("%A")
        items = MealItem.get_all(filters={"plan_id": active_plan.id, "day": day_name})
        if items:
            completed = sum(1 for i in items if i.completed)
            total = len(items)
            data.append({"day": day.strftime("%d %b"), "adherence": int(completed / total * 100) if total else 0})
        else:
            data.append({"day": day.strftime("%d %b"), "adherence": 0})

    return jsonify(data)