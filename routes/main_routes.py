from flask import Blueprint, render_template, redirect, url_for
from flask_login import login_required, current_user
from datetime import datetime, date, timedelta
from functools import lru_cache

from services.user_service import get_user_service
from services.health_metric_service import HealthMetricService

main_bp = Blueprint("main", __name__)


def _metric_value(metric, which=1):
    """Extract metric value by index."""
    return getattr(metric, f"value{which}", None)


@main_bp.route("/")
def home():
    if current_user.is_authenticated:
        if current_user.is_admin:
            return redirect(url_for("business.dashboard"))
        if not current_user.onboarding_done:
            step = current_user.health_profile.get('onboarding_step', 1) if current_user.health_profile else 1
            return redirect(url_for(f"profile.onboarding_step{step}"))
        return redirect(url_for("main.dashboard"))
    return redirect(url_for("auth.login"))


@main_bp.route("/dashboard")
@login_required
def dashboard():
    if current_user.is_admin:
        return redirect(url_for("business.dashboard"))

    today = date.today()
    user = current_user
    conditions = user.condition_names

    # Initialize services
    user_service = get_user_service()
    health_metric_service = HealthMetricService(current_user.id)

    # BP metrics
    latest_bp = health_metric_service.get_latest('bp')
    bp_7day = health_metric_service.get_by_type('bp', days=7, limit=100)

    bp_chart_data = [
        {
            "day": m['recorded_at'][:10] if isinstance(m.get('recorded_at'), str) else m['recorded_at'].strftime("%a") if hasattr(m.get('recorded_at'), 'strftime') else str(m.get('recorded_at')),
            "sys": _metric_value(m, 1),
            "dia": _metric_value(m, 2),
            "pulse": _metric_value(m, 3),
        }
        for m in bp_7day
    ] if bp_7day else []

    latest_bp_status = "No Reading"
    if latest_bp:
        s = _metric_value(latest_bp, 1) or 0
        d = _metric_value(latest_bp, 2) or 0
        if s < 120 and d < 80:
            latest_bp_status = "Normal"
        elif s < 130 and d < 80:
            latest_bp_status = "Elevated"
        elif s < 140 or d < 90:
            latest_bp_status = "High Stage 1"
        elif s < 180 or d < 120:
            latest_bp_status = "High Stage 2"
        else:
            latest_bp_status = "Crisis"

    bp_streak = _compute_streak(current_user.id, "bp")

    latest_weight = HealthMetricService(current_user.id).get_latest('weight')

    today = date.today()
    user = current_user
    conditions = user.condition_names

    # Today's water
    water_today_data = health_metric_service.get_water_today()
    water_today = water_today_data.get('today_total', 0)
    water_target = user.goals.get('target_water_litres', 2.5) if user.goals else 2.5
    water_pct = water_today_data.get('pct', min(100, int((water_today / water_target) * 100))) if water_target else 0

    # Today's nutrition
    nutrition_service = get_user_service()
    # We'll need a nutrition service - for now use placeholder
    today_nutrition = None

    # Meal plan
    active_plan = None  # Would need meal service
    today_meals = []
    meals_done = 0
    meals_total = 0
    meals_pct = 0

    # Alerts
    active_alerts = []  # Would come from alerts service

    # Insights
    insights = _generate_live_insights(current_user, latest_bp, None)

    # Medicines
    medicines_today = []
    meds_taken = 0
    meds_total = 0

    # Latest sugar
    latest_sugar = None
    if 'Diabetes' in conditions:
        latest_sugar = HealthMetricService(current_user.id).get_latest('sugar')

    # Weight progress
    weight_to_go = None
    weight_progress = 0
    goals = getattr(current_user, 'goals', None)

    return render_template(
        "dashboard/index.html",
        user=current_user,
        conditions=conditions,
        latest_bp=latest_bp,
        latest_bp_status=latest_bp_status,
        bp_chart_data=bp_chart_data,
        bp_streak=0,  # _compute_streak(user.id, "bp")
        avg_sys_7=None,
        avg_dia_7=None,
        latest_weight=health_metric_service.get_latest('weight'),
        weight_chart=[],  # Would need weight history
        weight_to_go=None,
        weight_progress=0,
        today_water=water_today,
        water_target=water_target,
        water_pct=0,
        today_nutrition=None,
        calorie_target=2000,
        protein_target=80,
        today_meals=[],
        meals_done=0,
        meals_total=0,
        meals_pct=0,
        day_name=datetime.now().strftime("%A"),
        active_alerts=[],
        insights=[],
        medicines_today=[],
        meds_taken=0,
        meds_total=0,
        latest_sugar=None,
        goals=None,
        today=date.today(),
    )


def _compute_streak(user_id, metric_type):
    """Compute streak for a metric type."""
    # Simplified - would need Firestore queries
    return 0


def _generate_live_insights(user, latest_bp, today_nutrition):
    insights = []

    if latest_bp and 'High Blood Pressure' in user.condition_names:
        s = _metric_value(latest_bp, 1) or 0
        d = _metric_value(latest_bp, 2) or 0
        if s < 120 and d < 80:
            insights.append({"icon": "📉", "text": f"BP {int(s)}/{int(d)} mmHg is in normal range. Excellent progress.", "direction": "improving", "priority": 1, "metric_type": "bp"})
        elif s >= 140 or d >= 90:
            insights.append({"icon": "📈", "text": f"BP {int(s)}/{int(d)} mmHg is elevated. Review salt intake and medicine.", "direction": "worsening", "priority": 1, "metric_type": "bp"})
        else:
            insights.append({"icon": "📊", "text": f"BP {int(s)}/{int(d)} mmHg — continue daily monitoring.", "direction": "stable", "priority": 2, "metric_type": "bp"})

    return insights[:3]


def _metric_value(metric, which=1):
    """Extract metric value by index."""
    return metric.get(f'value{which}', None)