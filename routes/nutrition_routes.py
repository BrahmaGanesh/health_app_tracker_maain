# ============================================================
# NUTRITION ROUTES
# ============================================================

from flask import (
    Blueprint, render_template, redirect,
    url_for, flash, request, jsonify
)
from flask_login import login_required, current_user
from datetime import date, datetime, timedelta

from models import (
    Recipe, MealPlan, MealItem, NutritionDailyLog,
    UserGoal, UserHealthProfile
)

nutrition_bp = Blueprint("nutrition", __name__)


# ============================================================
# HELPER: Compute today's nutrition
# ============================================================

def _compute_today_log(user, today):
    """
    Compute today's nutrition from completed meal items.
    Creates and saves NutritionDailyLog if data exists.
    """
    day_name    = today.strftime("%A")
    active_plan_list = MealPlan.get_all(
        filters={"user_id": user.id, "is_active": True},
        order_by="-generated_at",
        limit=1
    )
    active_plan = active_plan_list[0] if active_plan_list else None

    if not active_plan:
        return None

    items = MealItem.get_all(filters={"plan_id": active_plan.id, "day": today.strftime("%A")})

    totals = {
        "calories": 0, "protein": 0, "carbs": 0,
        "fats": 0, "fiber": 0, "sodium": 0
    }
    completed = planned = 0

    for item in items:
        planned += 1
        if item.completed:
            completed += 1
            r = item.recipe
            totals["calories"] += r.calories or 0
            totals["protein"]  += r.protein  or 0
            totals["carbs"]    += r.carbs    or 0
            totals["fats"]     += r.fats     or 0
            totals["fiber"]    += r.fiber    or 0
            totals["sodium"]   += r.sodium   or 0

    if not totals["calories"] and not totals["protein"]:
        return None

    # Save or update log
    log = NutritionDailyLog.get_one(filters={"user_id": user.id, "log_date": today})
    if log:
        log.total_calories = totals["calories"]
        log.total_protein  = totals["protein"]
        log.total_carbs    = totals["carbs"]
        log.total_fats     = totals["fats"]
        log.total_fiber    = totals["fiber"]
        log.total_sodium   = totals["sodium"]
        log.meals_completed = completed
        log.meals_planned  = planned
        log.save()
    else:
        log = NutritionDailyLog(
            user_id=user.id,
            log_date=today,
            total_calories=totals["calories"],
            total_protein=totals["protein"],
            total_carbs=totals["carbs"],
            total_fats=totals["fats"],
            total_fiber=totals["fiber"],
            total_sodium=totals["sodium"],
            meals_completed=completed,
            meals_planned=planned,
        )
        log.save()

    return log


# ============================================================
# DAILY NUTRITION LOG
# ============================================================

@nutrition_bp.route("/log")
@login_required
def daily_log():
    today = date.today()
    log = _compute_today_log(current_user, today)

    goals = current_user.goals
    calorie_target = goals.target_calories if goals else current_user.daily_calorie_target
    protein_target = goals.target_protein_g if goals else current_user.daily_protein_target
    water_target = goals.target_water_litres if goals else 2.5

    return render_template(
        "nutrition/log.html",
        log=log,
        calorie_target=calorie_target,
        protein_target=protein_target,
        water_target=water_target,
        today=today,
    )


# ============================================================
# NUTRITION HISTORY
# ============================================================

@nutrition_bp.route("/history")
@login_required
def history():
    logs = NutritionDailyLog.get_all(
        filters={"user_id": current_user.id},
        order_by="-log_date",
        limit=30
    )

    # Calculate averages
    if logs:
        avg_cal = sum(l.total_calories for l in logs) / len(logs)
        avg_pro = sum(l.total_protein for l in logs) / len(logs)
    else:
        avg_cal = avg_pro = 0

    return render_template(
        "nutrition/history.html",
        logs=logs,
        avg_cal=avg_cal,
        avg_pro=avg_pro,
    )


# ============================================================
# WATER TRACKING
# ============================================================

@nutrition_bp.route("/water", methods=["GET", "POST"])
@login_required
def water():
    today = date.today()
    log = NutritionDailyLog.get_one(filters={"user_id": current_user.id, "log_date": today})

    if request.method == "POST":
        amount = request.form.get("amount", 0, type=float)

        if log:
            log.total_water = (log.total_water or 0) + amount
        else:
            log = NutritionDailyLog(
                user_id=current_user.id,
                log_date=today,
                total_water=amount,
            )
        log.save()
        flash(f"Added {amount}L water.", "success")
        return redirect(url_for("nutrition.water"))

    total_water = log.total_water if log else 0
    water_target = current_user.goals.target_water_litres if current_user.goals else 2.5
    water_pct = min(100, int((total_water / water_target) * 100)) if water_target else 0

    return render_template(
        "nutrition/water.html",
        total_water=total_water,
        water_target=water_target,
        water_pct=water_pct,
    )


# ============================================================
# NUTRIENT GOALS
# ============================================================

@nutrition_bp.route("/goals", methods=["GET", "POST"])
@login_required
def goals():
    goals = current_user.goals

    if request.method == "POST":
        if not goals:
            from models import UserGoal
            goals = UserGoal(user_id=current_user.id)

        try:
            if request.form.get("target_calories"):
                goals.target_calories = int(request.form.get("target_calories"))
            if request.form.get("target_protein_g"):
                goals.target_protein_g = int(request.form.get("target_protein_g"))
            if request.form.get("target_carbs_g"):
                goals.target_carbs_g = int(request.form.get("target_carbs_g"))
            if request.form.get("target_fats_g"):
                goals.target_fats_g = int(request.form.get("target_fats_g"))
            if request.form.get("target_water_litres"):
                goals.target_water_litres = float(request.form.get("target_water_litres"))

            goals.save()
            flash("Goals updated.", "success")
        except ValueError:
            flash("Invalid values.", "danger")

        return redirect(url_for("nutrition.goals"))

    calorie_target = goals.target_calories if goals else current_user.daily_calorie_target
    protein_target = goals.target_protein_g if goals else current_user.daily_protein_target
    water_target = goals.target_water_litres if goals else 2.5

    return render_template(
        "nutrition/goals.html",
        calorie_target=calorie_target,
        protein_target=protein_target,
        water_target=water_target,
    )


# ============================================================
# NUTRIENT ANALYSIS
# ============================================================

@nutrition_bp.route("/analysis")
@login_required
def analysis():
    # Get last 7 days of logs
    seven_days_ago = date.today() - timedelta(days=7)
    logs = NutritionDailyLog.get_all(
        filters={"user_id": current_user.id, "log_date_gte": seven_days_ago},
        order_by="-log_date"
    )

    # Get user targets early
    calorie_target = current_user.daily_calorie_target or 2000
    protein_target = current_user.daily_protein_target or 80

    if not logs:
        return render_template(
            "nutrition/dashboard.html",
            empty=True,
            cal_pct=0, pro_pct=0, fiber_pct=0,
            total_calories=0, total_protein=0, total_carbs=0,
            total_fats=0, total_fiber=0, total_sodium=0,
            sodium_pct=0,
            calorie_target=calorie_target,
            protein_target=protein_target,
            week_chart=[],
            sodium_data=[],
        )

    # Calculate trends
    calories = [l.total_calories for l in logs]
    protein = [l.total_protein for l in logs]
    carbs = [l.total_carbs for l in logs]
    avg_fat = sum(fats) / len(fats)
    avg_water = sum(water) / len(water)

    # Calculate percentages
    cal_pct = min(100, int((avg_cal / calorie_target) * 100)) if calorie_target else 0
    pro_pct = min(100, int((avg_pro / protein_target) * 100)) if protein_target else 0
    fiber_pct = min(100, int((sum(l.total_fiber for l in logs) / len(logs) / 30) * 100)) if logs else 0

    # Calculate today's totals for dashboard
    total_calories = sum(l.total_calories for l in logs) if logs else 0
    total_protein = sum(l.total_protein for l in logs) if logs else 0
    total_carbs = sum(l.total_carbs for l in logs) if logs else 0
    total_fats = sum(l.total_fats for l in logs) if logs else 0
    total_fiber = sum(l.total_fiber for l in logs) if logs else 0
    total_sodium = sum(l.total_sodium for l in logs) if logs else 0

    # Calculate sodium percentage
    sodium_pct = min(100, int((total_sodium / 2300) * 100))

    # 7-day chart data
    week_chart = [
        {
            "day": l.log_date.strftime("%a") if l.log_date else "",
            "calories": l.total_calories or 0,
            "protein": l.total_protein or 0,
            "carbs": l.total_carbs or 0,
            "fats": l.total_fats or 0,
        }
        for l in logs
    ]
    sodium_data = [
        {"day": l.log_date.strftime("%a") if l.log_date else "", "sodium": l.total_sodium or 0}
        for l in logs
    ]

    return render_template(
        "nutrition/dashboard.html",
        logs=logs,
        avg_cal=avg_cal,
        avg_pro=avg_pro,
        avg_carb=avg_carb,
        avg_fat=avg_fat,
        avg_water=avg_water,
        cal_pct=cal_pct,
        pro_pct=pro_pct,
        fiber_pct=fiber_pct,
        total_calories=total_calories,
        total_protein=total_protein,
        total_carbs=total_carbs,
        total_fats=total_fats,
        total_fiber=total_fiber,
        total_sodium=total_sodium,
        sodium_pct=sodium_pct,
        calorie_target=calorie_target,
        protein_target=protein_target,
        week_chart=week_chart,
        sodium_data=sodium_data,
    )