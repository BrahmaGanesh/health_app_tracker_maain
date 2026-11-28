# ============================================================
# ADAPTIVE HEALTH MANAGEMENT PLATFORM
# routes/bp_routes.py — Blood Pressure Tracker
# ============================================================

from flask import (
    Blueprint, render_template, redirect,
    url_for, flash, request, jsonify
)
from flask_login import login_required, current_user
from datetime import datetime, date, timedelta, timezone

from models import HealthMetric, Alert

bp_bp = Blueprint("bp", __name__)


# ── BP STATUS HELPER ─────────────────────────────────────────
def get_bp_status(systolic, diastolic):
    s, d = float(systolic or 0), float(diastolic or 0)
    if s < 120 and d < 80:    return "Normal",       "normal"
    elif s < 130 and d < 80:  return "Elevated",     "elevated"
    elif s < 140 or d < 90:   return "High Stage 1", "high"
    elif s < 180 or d < 120:  return "High Stage 2", "high"
    else:                      return "Crisis",       "critical"


def check_and_create_alerts(user_id, systolic, diastolic):
    """Auto-create alert if BP is dangerously high."""
    s, d = float(systolic), float(diastolic)
    if s >= 180 or d >= 120:
        existing = (Alert.get_all(filters={"user_id": user_id, "alert_type": "emergency", "category": "bp", "is_dismissed": False}, limit=1) or [None])[0]
        if not existing:
            alert = Alert(
                user_id=user_id,
                alert_type="emergency",
                category="bp",
                title="🚨 BP Crisis Level Detected",
                message=f"Your BP reading of {int(s)}/{int(d)} mmHg is at crisis level (above 180/120). "
                        f"Rest immediately, take your medicine, and see a doctor today.",
                action_text="Go to BP Tracker",
                action_url="/bp",
                trigger_value=s
            )
            alert.save()
            # db.session.commit()  # Firestore auto-commits
    elif s >= 160 or d >= 100:
        existing = (Alert.get_all(filters={"user_id": user_id, "alert_type": "warning", "category": "bp", "is_dismissed": False}, limit=1) or [None])[0]
        if not existing:
            alert = Alert(
                user_id=user_id,
                alert_type="warning",
                category="bp",
                title="⚠️ High BP Detected",
                message=f"Your BP reading of {int(s)}/{int(d)} mmHg is significantly elevated. "
                        f"Review your salt intake, ensure medicine is taken, and track regularly.",
                trigger_value=s
            )
            alert.save()
            # db.session.commit()  # Firestore auto-commits


# ============================================================
# BP TRACKER — MAIN PAGE
# ============================================================

@bp_bp.route("/")
@login_required
def tracker():
    today = date.today()
    user  = current_user

    # ── Latest reading ────────────────────────────────────────
    latest_list = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "bp"},
        order_by="-recorded_at",
        limit=1
    )
    latest = latest_list[0] if latest_list else None

    latest_status = "No Reading"
    if latest:
        latest_status, _ = get_bp_status(latest.value1, latest.value2)

    # ── Morning BP (first reading today) ─────────────────────
    morning_bp_list = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "bp", "recorded_at_date": today},
        order_by="recorded_at",
        limit=1
    )
    morning_bp = morning_bp_list[0] if morning_bp_list else None

    morning_bp_str = (
        f"{int(morning_bp.value1)}/{int(morning_bp.value2)}"
        if morning_bp else "—"
    )

    # ── Evening BP (last reading today after 3pm) ─────────────
    evening_bp_list = HealthMetric.get_all(
        filters={"user_id": user.id, "metric_type": "bp", "recorded_at_date": today, "recorded_at_hour_gte": 15},
        order_by="-recorded_at",
        limit=1
    )
    evening_bp = evening_bp_list[0] if evening_bp_list else None

    evening_bp_str = (
        f"{int(evening_bp.value1)}/{int(evening_bp.value2)}"
        if evening_bp else "—"
    )

    # ── Weekly chart data ─────────────────────────────────────
    seven_days = []
    for i in range(6, -1, -1):
        day_d    = today - timedelta(days=i)
        day_rdgs = HealthMetric.get_all(filters={"user_id": user.id, "metric_type": "bp", "recorded_at_date": day_d})

        if day_rdgs:
            avg_sys   = round(sum(r.value1 for r in day_rdgs if r.value1) / len(day_rdgs), 0)
            avg_dia   = round(sum(r.value2 for r in day_rdgs if r.value2) / len(day_rdgs), 0)
            avg_pulse = round(sum(r.value3 for r in day_rdgs if r.value3) / len(day_rdgs), 0) if any(r.value3 for r in day_rdgs) else None
        else:
            avg_sys = avg_dia = avg_pulse = None

        seven_days.append({
            "day":   day_d.strftime("%a"),
            "sys":   avg_sys,
            "dia":   avg_dia,
            "pulse": avg_pulse
        })

    # ── All readings (history) ────────────────────────────────
    readings = HealthMetric.get_all(filters={"user_id": user.id, "metric_type": "bp"}, order_by="-recorded_at", limit=50)

    # ── Streak ────────────────────────────────────────────────
    streak = 0
    check  = today
    for _ in range(365):
        exists = (HealthMetric.get_all(filters={"user_id": user.id, "metric_type": "bp", "recorded_at_date": check}, limit=1) or [None])[0]
        if exists:
            streak += 1
            check  -= timedelta(days=1)
        else:
            break

    # ── 30-day stats ──────────────────────────────────────────
    thirty_ago = datetime.utcnow() - timedelta(days=30)
    recent_30  = HealthMetric.get_all(filters={"user_id": user.id, "metric_type": "bp", "recorded_at_gte": thirty_ago})

    avg_sys_30 = avg_dia_30 = None
    days_normal = days_high = 0

    if recent_30:
        avg_sys_30 = round(sum(r.value1 for r in recent_30 if r.value1) / len(recent_30), 0)
        avg_dia_30 = round(sum(r.value2 for r in recent_30 if r.value2) / len(recent_30), 0)
        for r in recent_30:
            _, cat = get_bp_status(r.value1, r.value2)
            if cat == "normal":   days_normal += 1
            elif cat in ("high", "critical"): days_high += 1

    # ── Goals ─────────────────────────────────────────────────
    goals = user.goals

    return render_template(
        "bp/tracker.html",
        latest=latest,
        latest_status=latest_status,
        morning_bp=morning_bp_str,
        evening_bp=evening_bp_str,
        weekly_bp=seven_days,
        readings=readings,
        streak=streak,
        avg_sys_30=avg_sys_30,
        avg_dia_30=avg_dia_30,
        days_normal=days_normal,
        days_high=days_high,
        goals=goals,
        today=today,
    )


# ============================================================
# ADD BP READING
# ============================================================

@bp_bp.route("/add", methods=["POST"])
@login_required
def add_bp():
    systolic  = request.form.get("systolic", "")
    diastolic = request.form.get("diastolic", "")
    pulse     = request.form.get("pulse", "")
    notes     = request.form.get("notes", "")

    # Validate
    errors = []
    sys_val = dia_val = pulse_val = None

    try:
        sys_val = float(systolic)
        if not (60 <= sys_val <= 250):
            errors.append("Systolic must be between 60 and 250.")
    except (ValueError, TypeError):
        errors.append("Please enter a valid systolic value.")

    try:
        dia_val = float(diastolic)
        if not (40 <= dia_val <= 150):
            errors.append("Diastolic must be between 40 and 150.")
    except (ValueError, TypeError):
        errors.append("Please enter a valid diastolic value.")

    if pulse:
        try:
            pulse_val = float(pulse)
            if not (30 <= pulse_val <= 220):
                errors.append("Pulse must be between 30 and 220.")
        except (ValueError, TypeError):
            errors.append("Please enter a valid pulse value.")

    if errors:
        for e in errors:
            flash(e, "danger")
        return redirect(url_for("bp.tracker"))

    # Save
    metric = HealthMetric(
        user_id      = current_user.id,
        metric_type  = "bp",
        value1       = sys_val,
        value2       = dia_val,
        value3       = pulse_val,
        unit         = "mmHg",
        notes        = notes or None,
        source       = "manual",
        recorded_at  = datetime.now(timezone.utc)
    )
    metric.save()
    # db.session.commit()  # Firestore auto-commits


    # Check for alerts
    check_and_create_alerts(current_user.id, sys_val, dia_val)

    status, _ = get_bp_status(sys_val, dia_val)
    flash(f"BP reading {int(sys_val)}/{int(dia_val)} saved. Status: {status}.", "success")
    return redirect(url_for("bp.tracker"))


# ============================================================
# DELETE BP READING
# ============================================================

@bp_bp.route("/delete/<bp_id>")
@login_required
def delete_bp(bp_id):
    metric = HealthMetric.get_by_id_or_404(bp_id)
    # Verify ownership
    if metric.user_id != current_user.id or metric.metric_type != "bp":
        from flask import abort
        abort(404)

    metric.delete()
    # db.session.commit()  # Firestore auto-commits
    flash("BP reading deleted.", "info")
    return redirect(url_for("bp.tracker"))


# ============================================================
# BP CHART DATA (AJAX — for dynamic date range)
# ============================================================

@bp_bp.route("/chart-data")
@login_required
def chart_data():
    """Return BP chart data as JSON for a given number of days."""
    days  = min(int(request.args.get("days", 7)), 90)
    today = date.today()
    data  = []

    for i in range(days - 1, -1, -1):
        d      = today - timedelta(days=i)
        rdgs   = HealthMetric.get_all(filters={"user_id": current_user.id, "metric_type": "bp", "recorded_at_date": d})

        if rdgs:
            data.append({
                "day":   d.strftime("%d %b"),
                "sys":   round(sum(r.value1 for r in rdgs if r.value1) / len(rdgs), 0),
                "dia":   round(sum(r.value2 for r in rdgs if r.value2) / len(rdgs), 0),
                "pulse": round(sum(r.value3 for r in rdgs if r.value3) / max(1, sum(1 for r in rdgs if r.value3)), 0) if any(r.value3 for r in rdgs) else None,
            })
        else:
            data.append({"day": d.strftime("%d %b"), "sys": None, "dia": None, "pulse": None})

    return jsonify(data)


# ============================================================
# EXPORT BP HISTORY (CSV)
# ============================================================

@bp_bp.route("/export")
@login_required
def export_bp():
    """Export BP history as CSV."""
    import csv
    import io
    from flask import make_response

    readings = HealthMetric.get_all(filters={"user_id": current_user.id, "metric_type": "bp"}, order_by="-recorded_at")

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["Date", "Time", "Systolic", "Diastolic", "Pulse", "Status", "Notes"])

    for r in readings:
        status, _ = get_bp_status(r.value1, r.value2)
        writer.writerow([
            r.recorded_at.strftime("%d %b %Y"),
            r.recorded_at.strftime("%I:%M %p"),
            int(r.value1) if r.value1 else "",
            int(r.value2) if r.value2 else "",
            int(r.value3) if r.value3 else "",
            status,
            r.notes or ""
        ])

    response = make_response(output.getvalue())
    response.headers["Content-Disposition"] = "attachment; filename=bp_history.csv"
    response.headers["Content-type"]        = "text/csv"
    return response