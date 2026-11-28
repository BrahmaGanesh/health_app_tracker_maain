# ============================================================
# ADAPTIVE HEALTH MANAGEMENT PLATFORM
# routes/tracker_routes.py — Weight, Water, Sugar, Steps
# ============================================================

from flask import (
    Blueprint, render_template, redirect,
    url_for, flash, request, jsonify
)
from flask_login import login_required, current_user
from datetime import datetime, date, timedelta

from models import HealthMetric, UserHealthProfile

tracker_bp = Blueprint("tracker", __name__)


# ── HELPER: get readings for chart ───────────────────────────
def get_metric_history(user_id, metric_type, days=30):
    since = datetime.utcnow() - timedelta(days=days)
    return HealthMetric.get_all(
        filters={"user_id": user_id, "metric_type": metric_type, "recorded_at_gte": since},
        order_by="recorded_at"
    )


def get_latest(user_id, metric_type):
    result = HealthMetric.get_all(
        filters={"user_id": user_id, "metric_type": metric_type},
        order_by="-recorded_at",
        limit=1
    )
    return result[0] if result else None


# ============================================================
# WEIGHT TRACKER
# ============================================================

@tracker_bp.route("/weight", methods=["GET", "POST"])
@login_required
def weight():
    user  = current_user
    today = date.today()

    if request.method == "POST":
        weight_str = request.form.get("weight_kg", "")
        notes      = request.form.get("notes", "")

        try:
            w = float(weight_str)
            if not (20 <= w <= 300):
                raise ValueError
        except (ValueError, TypeError):
            flash("Please enter a valid weight between 20 and 300 kg.", "danger")
            return redirect(url_for("tracker.weight"))

        metric = HealthMetric(
            user_id     = user.id,
            metric_type = "weight",
            value1      = w,
            unit        = "kg",
            notes       = notes or None,
            source      = "manual"
        )
        metric.save()
        flash(f"Weight {w} kg logged.", "success")
        return redirect(url_for("tracker.weight"))

    # Get history
    history = get_metric_history(user.id, "weight", days=30)

    # Calculate stats
    weights = [h.value1 for h in history if h.value1 is not None]
    avg_weight = round(sum(weights) / len(weights), 1) if weights else None
    min_weight = min(weights) if weights else None
    max_weight = max(weights) if weights else None

    # 7-day change
    weight_7d_history = [h.value1 for h in history if h.value1 is not None]
    if len(weight_7d_history) >= 2:
        weight_7d_change = round(weight_7d_history[0] - weight_7d_history[-1], 1)
    else:
        weight_7d_change = None

    # BMI
    bmi = None
    profile = user.health_profile
    if profile and profile.height_cm and w:
        height_m = profile.height_cm / 100
        bmi = round(w / (height_m ** 2), 1)

    # Chart data for JavaScript
    chart_data = [{"date": h.recorded_at.strftime('%Y-%m-%d') if h.recorded_at else '', "weight": h.value1} for h in history if h.value1 is not None and h.recorded_at]
    target_weight = user.goals.target_weight_kg if user.goals else None

    return render_template(
        "tracker/weight.html",
        history=history,
        avg_weight=avg_weight,
        min_weight=min_weight,
        max_weight=max_weight,
        weight_7d_change=weight_7d_change,
        bmi=bmi,
        today=today,
        chart_data=chart_data,
        target_weight=target_weight,
    )


# ============================================================
# WATER TRACKER
# ============================================================

@tracker_bp.route("/water", methods=["GET", "POST"])
@login_required
def water():
    user  = current_user
    today = date.today()

    if request.method == "POST":
        amount_str = request.form.get("amount", "")
        notes      = request.form.get("notes", "")

        try:
            amount = float(amount_str)
            if not (0 < amount <= 10):
                raise ValueError
        except (ValueError, TypeError):
            flash("Please enter a valid amount (0.1 - 10 L).", "danger")
            return redirect(url_for("tracker.water"))

        metric = HealthMetric(
            user_id     = user.id,
            metric_type = "water",
            value1      = amount,
            unit        = "L",
            notes       = notes or None,
            source      = "manual"
        )
        metric.save()
        flash(f"Water intake {amount} L logged.", "success")
        return redirect(url_for("tracker.water"))

    # Today's total
    today_water_list = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "water", "recorded_at_date": today}
    )
    today_total = sum(h.value1 for h in today_water_list if h.value1)

    # 7-day history
    history = get_metric_history(user.id, "water", days=7)

    # Target
    profile = user.health_profile
    target = 2.5  # default
    if profile:
        goals = user.goals
        if goals and goals.target_water_litres:
            target = goals.target_water_litres

    water_pct = min(100, int((today_total / target) * 100)) if target else 0

    # Glasses calculation (250ml per glass)
    glasses_target = 10  # default 10 glasses = 2.5L
    glasses_done = int(today_total * 4)  # 4 glasses per litre

    # 7-day week data for chart
    week_data = []
    for i in range(6, -1, -1):
        d = today - timedelta(days=i)
        day_total = sum(h.value1 for h in history if h.recorded_at and h.recorded_at.date() == d)
        week_data.append({
            "day": d.strftime('%a'),
            "date": str(d),
            "litres": round(day_total, 2) if day_total else 0
        })

    return render_template(
        "tracker/water.html",
        today_total=today_total,
        history=history,
        target=target,
        pct=water_pct,
        today=today,
        glasses_target=glasses_target,
        glasses_done=glasses_done,
        week_data=week_data,
    )


# ============================================================
# BLOOD SUGAR TRACKER
# ============================================================

@tracker_bp.route("/sugar", methods=["GET", "POST"])
@login_required
def sugar():
    user  = current_user
    today = date.today()

    if request.method == "POST":
        fasting_str  = request.form.get("fasting", "")
        post_meal_str = request.form.get("post_meal", "")
        notes        = request.form.get("notes", "")

        errors = []
        fasting = post_meal = None

        if fasting_str:
            try:
                fasting = float(fasting_str)
                if not (30 <= fasting <= 500):
                    errors.append("Fasting sugar must be between 30 and 500 mg/dL.")
            except (ValueError, TypeError):
                errors.append("Invalid fasting value.")

        if post_meal_str:
            try:
                post_meal = float(post_meal_str)
                if not (30 <= post_meal <= 500):
                    errors.append("Post-meal sugar must be between 30 and 500 mg/dL.")
            except (ValueError, TypeError):
                errors.append("Invalid post-meal value.")

        if errors:
            for e in errors:
                flash(e, "danger")
            return redirect(url_for("tracker.sugar"))

        if fasting is not None:
            metric = HealthMetric(
                user_id     = user.id,
                metric_type = "sugar",
                value1      = fasting,
                unit        = "mg/dL",
                notes       = notes or None,
                source      = "manual"
            )
            metric.save()

        if post_meal is not None:
            metric = HealthMetric(
                user_id     = user.id,
                metric_type = "sugar",
                value1      = post_meal,
                value2      = fasting,
                unit        = "mg/dL",
                notes       = notes or None,
                source      = "manual"
            )
            metric.save()

        flash("Blood sugar logged.", "success")
        return redirect(url_for("tracker.sugar"))

    # History
    history = get_metric_history(user.id, "sugar", days=30)

    # Latest fasting
    fasting_list = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "sugar", "value2_is_null": True},
        order_by="-recorded_at",
        limit=5
    )
    latest_fasting = fasting_list[0] if fasting_list else None

    # Chart data for JavaScript
    chart_data = [{"date": h.recorded_at.strftime('%Y-%m-%d') if h.recorded_at else '', "fasting": h.value1, "post_meal": h.value2} for h in history if (h.value1 is not None or h.value2 is not None) and h.recorded_at]

    return render_template(
        "tracker/sugar.html",
        history=history,
        latest_fasting=latest_fasting,
        today=today,
        chart_data=chart_data,
    )


# ============================================================
# STEPS TRACKER
# ============================================================

@tracker_bp.route("/steps", methods=["GET", "POST"])
@login_required
def steps():
    user  = current_user
    today = date.today()

    if request.method == "POST":
        steps_str = request.form.get("steps", "")
        notes     = request.form.get("notes", "")

        try:
            steps = int(steps_str)
            if not (0 <= steps <= 100000):
                raise ValueError
        except (ValueError, TypeError):
            flash("Please enter a valid step count (0 - 100,000).", "danger")
            return redirect(url_for("tracker.steps"))

        # Calculate distance and calories
        profile = user.health_profile
        h = profile.height_cm if profile and profile.height_cm else 170
        w = profile.current_weight_kg if profile and profile.current_weight_kg else 70
        stride_m = (h * 0.414) / 100
        distance_km = round(steps * stride_m / 1000, 2)
        calories = int((steps / 100) * (3.5 * w * 3.5 / 200))

        metric = HealthMetric(
            user_id     = user.id,
            metric_type = "steps",
            value1      = steps,
            value2      = distance_km,
            value3      = calories,
            unit        = "steps",
            notes       = notes or None,
            source      = "manual"
        )
        metric.save()
        flash(f"{steps} steps logged ({distance_km} km, ~{calories} cal).", "success")
        return redirect(url_for("tracker.steps"))

    # Today's total
    today_steps_list = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "steps", "recorded_at_date": today}
    )
    today_steps = sum(h.value1 for h in today_steps_list if h.value1)

    # 7-day history
    history = get_metric_history(user.id, "steps", days=7)

    # Target
    goals = user.goals
    target = goals.target_steps if goals and goals.target_steps else 8000
    steps_pct = min(100, int((today_steps / target) * 100)) if target else 0

    return render_template(
        "tracker/steps.html",
        today_steps=today_steps,
        history=history,
        target=target,
        steps_pct=steps_pct,
        today=today,
    )


# ============================================================
# DELETE METRIC
# ============================================================

@tracker_bp.route("/delete/<metric_id>")
@login_required
def delete_metric(metric_id):
    metric = HealthMetric.get_by_id_or_404(metric_id)
    if metric.user_id != current_user.id:
        from flask import abort
        abort(404)
    metric.delete()
    flash("Entry deleted.", "info")
    return redirect(request.referrer or url_for("tracker.weight"))