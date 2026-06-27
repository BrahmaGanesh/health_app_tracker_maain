# ============================================================
# utils/predictor.py — Weight & BP Trend Prediction Engine
# Linear regression + moving average for health forecasting
# ============================================================

from datetime import date, timedelta


def predict_weight(user, days_ahead=30):
    """
    Predict weight using linear regression on last 30 days.
    Returns predicted weight and estimated goal date.
    """
    from models import HealthMetric
    from sqlalchemy import func

    readings = HealthMetric.query.filter(
        HealthMetric.user_id    == user.id,
        HealthMetric.metric_type == "weight",
        HealthMetric.recorded_at >= _days_ago(60)
    ).order_by(HealthMetric.recorded_at.asc()).all()

    if len(readings) < 3:
        return {"available": False, "reason": "Need at least 3 weight readings"}

    # Build (x=day_index, y=weight) pairs
    base = readings[0].recorded_at.date()
    points = [(
        (r.recorded_at.date() - base).days,
        r.value_1
    ) for r in readings if r.value_1]

    if len(points) < 3:
        return {"available": False, "reason": "Insufficient data"}

    m, b = _linear_regression(points)

    # Predict future weights
    last_x    = points[-1][0]
    predicted = []
    for d in range(1, days_ahead + 1, 7):
        x   = last_x + d
        w   = round(m * x + b, 1)
        dt  = base + timedelta(days=x)
        predicted.append({"date": str(dt), "weight": max(30, w)})

    # Estimate goal date
    goal_date   = None
    days_to_goal = None
    if user.goals and user.goals.target_weight_kg:
        target = user.goals.target_weight_kg
        curr   = points[-1][1]
        if m != 0 and ((m < 0 and curr > target) or (m > 0 and curr < target)):
            days_to_target = int((target - b) / m) - last_x
            if 0 < days_to_target < 730:
                goal_date    = str(base + timedelta(days=last_x + days_to_target))
                days_to_goal = days_to_target

    weekly_change = round(m * 7, 2)
    trend = "losing" if m < -0.01 else ("gaining" if m > 0.01 else "stable")

    return {
        "available":     True,
        "trend":         trend,
        "weekly_change": weekly_change,
        "predicted":     predicted,
        "goal_date":     goal_date,
        "days_to_goal":  days_to_goal,
        "confidence":    _r_squared(points, m, b),
        "current_weight": points[-1][1],
        "target_weight": user.goals.target_weight_kg if user.goals else None,
    }


def predict_bp(user, days_ahead=14):
    """
    Predict BP trend using moving average + linear regression.
    Returns systolic trend and estimated days to target.
    """
    from models import HealthMetric

    readings = HealthMetric.query.filter(
        HealthMetric.user_id    == user.id,
        HealthMetric.metric_type == "bp",
        HealthMetric.recorded_at >= _days_ago(60)
    ).order_by(HealthMetric.recorded_at.asc()).all()

    if len(readings) < 5:
        return {"available": False, "reason": "Need at least 5 BP readings"}

    base   = readings[0].recorded_at.date()
    sys_pts = [(
        (r.recorded_at.date() - base).days,
        r.value_1
    ) for r in readings if r.value_1]

    dia_pts = [(
        (r.recorded_at.date() - base).days,
        r.value_2
    ) for r in readings if r.value_2]

    if len(sys_pts) < 5:
        return {"available": False, "reason": "Insufficient BP data"}

    ms, bs = _linear_regression(sys_pts)
    md, bd = _linear_regression(dia_pts)

    last_x     = sys_pts[-1][0]
    predicted  = []
    for d in range(1, days_ahead + 1, 2):
        x   = last_x + d
        dt  = base + timedelta(days=x)
        predicted.append({
            "date":      str(dt),
            "sys":       max(80, round(ms * x + bs, 0)),
            "dia":       max(50, round(md * x + bd, 0)),
        })

    # Days to reach target
    target_sys = user.goals.target_bp_systolic if user.goals else 130
    days_to_target = None
    if ms < 0:
        curr_sys = sys_pts[-1][1]
        if curr_sys > target_sys:
            days_needed = int((target_sys - bs) / ms) - last_x
            if 0 < days_needed < 365:
                days_to_target = days_needed

    trend = "improving" if ms < -0.1 else ("worsening" if ms > 0.1 else "stable")

    # 7-day moving average
    recent_7 = sys_pts[-7:] if len(sys_pts) >= 7 else sys_pts
    avg_sys_7 = round(sum(p[1] for p in recent_7) / len(recent_7), 0)

    return {
        "available":      True,
        "trend":          trend,
        "daily_change":   round(ms, 2),
        "predicted":      predicted,
        "days_to_target": days_to_target,
        "target_sys":     target_sys,
        "avg_sys_7":      avg_sys_7,
        "current_sys":    sys_pts[-1][1],
        "current_dia":    dia_pts[-1][1] if dia_pts else None,
        "confidence":     _r_squared(sys_pts, ms, bs),
        "message":        _bp_prediction_message(trend, ms, days_to_target, target_sys),
    }


def predict_goal_completion(user):
    """
    Predict when the user will achieve their primary goal.
    """
    if not user.goals:
        return {"available": False}

    results = {}

    if user.goals.target_weight_kg:
        wt = predict_weight(user, days_ahead=180)
        results["weight"] = wt

    if user.has_bp:
        bp = predict_bp(user, days_ahead=60)
        results["bp"] = bp

    return {"available": True, "predictions": results}


# ── MATH HELPERS ──────────────────────────────────────────────

def _linear_regression(points):
    """Simple least squares linear regression. Returns (slope m, intercept b)."""
    n  = len(points)
    if n < 2: return 0, points[0][1] if points else 0
    sx  = sum(p[0] for p in points)
    sy  = sum(p[1] for p in points)
    sxy = sum(p[0] * p[1] for p in points)
    sxx = sum(p[0] ** 2 for p in points)
    denom = n * sxx - sx ** 2
    if denom == 0: return 0, sy / n
    m = (n * sxy - sx * sy) / denom
    b = (sy - m * sx) / n
    return m, b


def _r_squared(points, m, b):
    """Compute R² (coefficient of determination) as confidence score 0-100."""
    if len(points) < 2: return 0
    mean_y  = sum(p[1] for p in points) / len(points)
    ss_tot  = sum((p[1] - mean_y) ** 2 for p in points)
    ss_res  = sum((p[1] - (m * p[0] + b)) ** 2 for p in points)
    if ss_tot == 0: return 100
    r2 = max(0, min(1, 1 - ss_res / ss_tot))
    return round(r2 * 100, 0)


def _days_ago(n):
    from datetime import datetime
    return datetime.utcnow() - timedelta(days=n)


def _bp_prediction_message(trend, daily_change, days_to_target, target_sys):
    if trend == "improving":
        if days_to_target:
            return f"BP improving! Estimated {days_to_target} days to reach target of {target_sys} mmHg."
        return "BP trend is improving. Keep up the current routine."
    elif trend == "worsening":
        return "BP trend is increasing. Review sodium intake, medicine adherence, and stress levels."
    return f"BP is stable. Average daily change: {abs(daily_change):.1f} mmHg."