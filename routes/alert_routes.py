# ============================================================
# ADAPTIVE HEALTH MANAGEMENT PLATFORM
# routes/alert_routes.py — Alert Engine & Management
# ============================================================

from flask import Blueprint, render_template, redirect, url_for, flash, jsonify
from flask_login import login_required, current_user
from datetime import datetime, date, timedelta, timezone

from models import Alert, HealthMetric, NutritionDailyLog

alert_bp = Blueprint("alert", __name__)


# ============================================================
# ALERT LIST PAGE
# ============================================================

@alert_bp.route("/")
@login_required
def index():
    user = current_user

    # All unread
    unread = Alert.get_all(
        filters={"user_id": user.id, "is_read": False, "is_dismissed": False},
        order_by="-created_at"
    )

    # Recent read (last 30 days)
    read = Alert.get_all(
        filters={"user_id": user.id, "is_read": True},
        order_by="-created_at",
        limit=30
    )

    # Auto-generate alerts for this user
    _run_alert_engine(user)

    # Refresh unread
    unread = Alert.get_all(
        filters={"user_id": user.id, "is_read": False, "is_dismissed": False},
        order_by="-created_at"
    )

    return render_template(
        "alerts/index.html",
        unread=unread,
        read=read,
        today=date.today(),
    )


# ============================================================
# MARK ALERT AS READ
# ============================================================

@alert_bp.route("/read/<alert_id>")
@login_required
def mark_read(alert_id):
    alert = Alert.get_by_id_or_404(alert_id)
    if alert.user_id != current_user.id:
        from flask import abort
        abort(403)

    alert.is_read = True
    alert.read_at = datetime.now(timezone.utc)
    alert.save()
    return redirect(url_for("alert.index"))

# MARK ALL ALERTS AS READ
# ============================================================

@alert_bp.route("/mark_all_read")
@login_required
def mark_all_read():
    alerts = Alert.get_all(filters={"user_id": current_user.id, "is_read": False})
    for alert in alerts:
        alert.is_read = True
        alert.read_at = datetime.now(timezone.utc)
        alert.save()
    return redirect(url_for("alert.index"))

# DISMISS ALL ALERTS
# ============================================================

@alert_bp.route("/dismiss_all")
@login_required
def dismiss_all():
    alerts = Alert.get_all(filters={"user_id": current_user.id, "is_dismissed": False})
    for alert in alerts:
        alert.is_dismissed = True
        alert.save()
    return redirect(url_for("alert.index"))

# ============================================================
# MARK ALERT AS DISMISSED
# ============================================================

@alert_bp.route("/dismiss/<alert_id>")
@login_required
def dismiss(alert_id):
    alert = Alert.get_by_id_or_404(alert_id)
    if alert.user_id != current_user.id:
        from flask import abort
        abort(403)

    alert.is_dismissed = True
    alert.save()
    return redirect(url_for("alert.index"))


# ============================================================
# ALERT ENGINE
# ============================================================

def _run_alert_engine(user):
    """Check user's health metrics and create alerts as needed."""
    today = date.today()

    # ── BP Crisis Alert ────────────────────────────────────────
    latest_bp = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "bp"},
        order_by="-recorded_at",
        limit=1
    )
    latest_bp = latest_bp[0] if latest_bp else None
    if latest_bp and latest_bp.value1 and latest_bp.value2:
        s, d = latest_bp.value1, latest_bp.value2
        if s >= 180 or d >= 120:
            _create_alert_if_new(user.id, "emergency", "bp",
                "🚨 BP Crisis Level Detected",
                f"Your BP reading of {int(s)}/{int(d)} mmHg is at crisis level (above 180/120). "
                f"Rest immediately, take your medicine, and see a doctor today.",
                trigger_value=s, expire_hours=24)
        elif s >= 140 or d >= 90:
            _create_alert_if_new(user.id, "warning", "bp",
                "⚠️ High Blood Pressure",
                f"Your BP reading of {int(s)}/{int(d)} mmHg is elevated. Review salt intake and medication.",
                trigger_value=s, expire_hours=48)

    # ── Weight Stagnation Alert ────────────────────────────────
    wt_last_14 = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "weight"},
        order_by="-recorded_at",
        limit=14
    )
    if len(wt_last_14) >= 2:
        first_w = wt_last_14[0].value1
        last_w = wt_last_14[-1].value1
        if abs(first_w - last_w) < 0.3:
            _create_alert_if_new(user.id, "info", "weight",
                "⚖️ Weight Plateau",
                "Your weight hasn't changed significantly in 2 weeks. "
                "Consider adjusting calorie intake or increasing activity.",
                expire_hours=72)

    # ── Hydration Reminder ─────────────────────────────────────
    today_water = NutritionDailyLog.get_one(
        filters={"user_id": user.id, "log_date": date.today()}
    )
    if today_water and today_water.total_water:
        target = 2.5
        if user.goals and user.goals.target_water_litres:
            target = user.goals.target_water_litres
        if today_water.total_water < target * 0.5:
            _create_alert_if_new(user.id, "reminder", "water",
                "💧 Hydration Reminder",
                f"You've only had {today_water.total_water}L of water today. "
                f"Target is {target}L. Time for a glass of water!",
                expire_hours=24)

    # ── Sleep Duration Alert ───────────────────────────────────
    sleep_today = HealthMetric.get_all(
        filters={"user_id": current_user.id, "metric_type": "sleep", "recorded_at_date": date.today()},
        order_by="-recorded_at",
        limit=1
    )
    sleep_today = sleep_today[0] if sleep_today else None
    if sleep_today and sleep_today.value1:
        if sleep_today.value1 < 6:
            _create_alert_if_new(user.id, "warning", "sleep",
                "😴 Low Sleep Duration",
                f"You only got {sleep_today.value1} hours of sleep. "
                f"Aim for 7-9 hours for optimal health.",
                expire_hours=24)

    # ── Step Goal Reminder ─────────────────────────────────────
    today_steps = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "steps", "recorded_at_date": date.today()}
    )
    today_steps_total = sum(h.value1 for h in today_steps if h.value1)
    goals = user.goals
    step_target = goals.target_steps if goals and goals.target_steps else 8000
    if today_steps_total < step_target * 0.3:
        _create_alert_if_new(user.id, "reminder", "steps",
            "👟 Step Goal Reminder",
            f"You're at {today_steps_total} steps today. Target: {step_target}. "
            "Time for a walk!",
            expire_hours=12)


def _create_alert_if_new(user_id, alert_type, category, title, message,
                         trigger_value=None, expire_hours=None):
    """
    Create alert only if no active alert of same type+category exists.
    Prevents duplicate alerts.
    """
    from datetime import timedelta as td

    existing = Alert.get_all(
        filters={
            "user_id": user_id,
            "alert_type": alert_type,
            "category": category,
            "is_dismissed": False,
        },
        limit=1
    )
    existing = existing[0] if existing else None

    if existing:
        created_at = existing.created_at
        if isinstance(created_at, str):
            created_at = datetime.fromisoformat(created_at)
        if created_at >= datetime.now(timezone.utc) - td(hours=expire_hours or 24):
            return  # Already exists, skip

    expires = datetime.now(timezone.utc) + td(hours=expire_hours) if expire_hours else None

    alert = Alert(
        user_id=user_id,
        alert_type=alert_type,
        category=category,
        title=title,
        message=message,
        trigger_value=trigger_value,
        expires_at=expires
    )
    alert.save()