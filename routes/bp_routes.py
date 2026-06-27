# ============================================================
# ADAPTIVE HEALTH MANAGEMENT PLATFORM
# routes/bp_routes.py — Blood Pressure Tracker
# ============================================================

from flask import (
    Blueprint, render_template, redirect,
    url_for, flash, request, jsonify, make_response
)
from flask_login import login_required, current_user
from datetime import datetime, date, timedelta
from sqlalchemy import func, extract
import csv
import io

from extensions import db
from models import HealthMetric, Alert

bp_bp = Blueprint("bp", __name__)


# ── BP STATUS HELPER ─────────────────────────────────────────
def get_bp_status(systolic, diastolic):
    s, d = float(systolic or 0), float(diastolic or 0)
    if s < 120 and d < 80:
        return "Normal", "normal"
    elif s < 130 and d < 80:
        return "Elevated", "elevated"
    elif s < 140 or d < 90:
        return "High Stage 1", "high"
    elif s < 180 or d < 120:
        return "High Stage 2", "high"
    else:
        return "Crisis", "critical"


def check_and_create_alerts(user_id, systolic, diastolic):
    """Auto-create alert if BP is dangerously high."""
    s, d = float(systolic), float(diastolic)

    if s >= 180 or d >= 120:
        existing = Alert.query.filter_by(
            user_id=user_id,
            alert_type="emergency",
            category="bp",
            is_dismissed=False
        ).first()

        if not existing:
            alert = Alert(
                user_id=user_id,
                alert_type="emergency",
                category="bp",
                title="🚨 BP Crisis Level Detected",
                message=(
                    f"Your BP reading of {int(s)}/{int(d)} mmHg is at crisis level "
                    f"(above 180/120). Rest immediately, take your medicine, and see a doctor today."
                ),
                action_text="Go to BP Tracker",
                action_url="/bp",
                trigger_value=s
            )
            db.session.add(alert)
            db.session.commit()

    elif s >= 160 or d >= 100:
        existing = Alert.query.filter_by(
            user_id=user_id,
            alert_type="warning",
            category="bp",
            is_dismissed=False
        ).first()

        if not existing:
            alert = Alert(
                user_id=user_id,
                alert_type="warning",
                category="bp",
                title="⚠️ High BP Detected",
                message=(
                    f"Your BP reading of {int(s)}/{int(d)} mmHg is significantly elevated. "
                    f"Review your salt intake, ensure medicine is taken, and track regularly."
                ),
                trigger_value=s
            )
            db.session.add(alert)
            db.session.commit()

# ============================================================
# BP TRACKER — MAIN PAGE
# ============================================================

@bp_bp.route("/")
@login_required
def tracker():
    today = date.today()
    user = current_user

    # ── Latest reading ────────────────────────────────────────
    latest = HealthMetric.query.filter_by(
        userid=user.id,
        metrictype="bp"
    ).order_by(HealthMetric.recordedat.desc()).first()

    latest_status = "No Reading"
    if latest:
        latest_status, _ = get_bp_status(latest.value1, latest.value2)

    # ── Morning BP (first reading today) ─────────────────────
    morning_bp = HealthMetric.query.filter(
        HealthMetric.userid == user.id,
        HealthMetric.metrictype == "bp",
        func.date(HealthMetric.recordedat) == today
    ).order_by(HealthMetric.recordedat.asc()).first()

    morning_bp_str = (
        f"{int(morning_bp.value1)}/{int(morning_bp.value2)}"
        if morning_bp and morning_bp.value1 is not None and morning_bp.value2 is not None
        else "—"
    )

    # ── Evening BP (last reading today after 3pm) ─────────────
    evening_bp = HealthMetric.query.filter(
        HealthMetric.userid == user.id,
        HealthMetric.metrictype == "bp",
        func.date(HealthMetric.recordedat) == today,
        extract("hour", HealthMetric.recordedat) >= 15
    ).order_by(HealthMetric.recordedat.desc()).first()

    evening_bp_str = (
        f"{int(evening_bp.value1)}/{int(evening_bp.value2)}"
        if evening_bp and evening_bp.value1 is not None and evening_bp.value2 is not None
        else "—"
    )

    # ── Weekly chart data ─────────────────────────────────────
    seven_days = []
    for i in range(6, -1, -1):
        day_d = today - timedelta(days=i)
        day_rdgs = HealthMetric.query.filter(
            HealthMetric.userid == user.id,
            HealthMetric.metrictype == "bp",
            func.date(HealthMetric.recordedat) == day_d
        ).all()

        sys_vals = [r.value1 for r in day_rdgs if r.value1 is not None]
        dia_vals = [r.value2 for r in day_rdgs if r.value2 is not None]
        pulse_vals = [r.value3 for r in day_rdgs if r.value3 is not None]

        if sys_vals and dia_vals:
            avg_sys = round(sum(sys_vals) / len(sys_vals), 0)
            avg_dia = round(sum(dia_vals) / len(dia_vals), 0)
            avg_pulse = round(sum(pulse_vals) / len(pulse_vals), 0) if pulse_vals else None
        else:
            avg_sys = avg_dia = avg_pulse = None

        seven_days.append({
            "day": day_d.strftime("%a"),
            "sys": avg_sys,
            "dia": avg_dia,
            "pulse": avg_pulse
        })

    # ── All readings (history) ────────────────────────────────
    readings = HealthMetric.query.filter_by(
        userid=user.id,
        metrictype="bp"
    ).order_by(HealthMetric.recordedat.desc()).limit(50).all()

    # ── Streak ────────────────────────────────────────────────
    streak = 0
    check = today

    for _ in range(365):
        exists = HealthMetric.query.filter(
            HealthMetric.userid == user.id,
            HealthMetric.metrictype == "bp",
            func.date(HealthMetric.recordedat) == check
        ).first()

        if exists:
            streak += 1
            check -= timedelta(days=1)
        else:
            break

    # ── 30-day stats ──────────────────────────────────────────
    thirty_ago = datetime.utcnow() - timedelta(days=30)
    recent_30 = HealthMetric.query.filter(
        HealthMetric.userid == user.id,
        HealthMetric.metrictype == "bp",
        HealthMetric.recordedat >= thirty_ago
    ).all()

    avg_sys_30 = avg_dia_30 = None
    days_normal = 0
    days_high = 0

    if recent_30:
        sys_vals_30 = [r.value1 for r in recent_30 if r.value1 is not None]
        dia_vals_30 = [r.value2 for r in recent_30 if r.value2 is not None]

        if sys_vals_30:
            avg_sys_30 = round(sum(sys_vals_30) / len(sys_vals_30), 0)
        if dia_vals_30:
            avg_dia_30 = round(sum(dia_vals_30) / len(dia_vals_30), 0)

        for r in recent_30:
            _, cat = get_bp_status(r.value1, r.value2)
            if cat == "normal":
                days_normal += 1
            elif cat in ("high", "critical"):
                days_high += 1

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
    systolic = request.form.get("systolic", "")
    diastolic = request.form.get("diastolic", "")
    pulse = request.form.get("pulse", "")
    notes = request.form.get("notes", "")

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

    metric = HealthMetric(
        userid=current_user.id,
        metrictype="bp",
        value1=sys_val,
        value2=dia_val,
        value3=pulse_val,
        unit="mmHg",
        notes=notes or None,
        source="manual"
    )
    db.session.add(metric)
    db.session.commit()

    check_and_create_alerts(current_user.id, sys_val, dia_val)

    status, _ = get_bp_status(sys_val, dia_val)
    flash(f"BP reading {int(sys_val)}/{int(dia_val)} saved. Status: {status}.", "success")
    return redirect(url_for("bp.tracker"))


# ============================================================
# DELETE BP READING
# ============================================================

@bp_bp.route("/delete/<int:bp_id>")
@login_required
def delete_bp(bp_id):
    metric = HealthMetric.query.filter_by(
        id=bp_id,
        userid=current_user.id,
        metrictype="bp"
    ).first_or_404()

    db.session.delete(metric)
    db.session.commit()
    flash("BP reading deleted.", "info")
    return redirect(url_for("bp.tracker"))


# ============================================================
# BP CHART DATA (AJAX — for dynamic date range)
# ============================================================

@bp_bp.route("/chart-data")
@login_required
def chart_data():
    """Return BP chart data as JSON for a given number of days."""
    days = min(int(request.args.get("days", 7)), 90)
    today = date.today()
    data = []

    for i in range(days - 1, -1, -1):
        d = today - timedelta(days=i)
        rdgs = HealthMetric.query.filter(
            HealthMetric.userid == current_user.id,
            HealthMetric.metrictype == "bp",
            func.date(HealthMetric.recordedat) == d
        ).all()

        sys_vals = [r.value1 for r in rdgs if r.value1 is not None]
        dia_vals = [r.value2 for r in rdgs if r.value2 is not None]
        pulse_vals = [r.value3 for r in rdgs if r.value3 is not None]

        if rdgs and sys_vals and dia_vals:
            data.append({
                "day": d.strftime("%d %b"),
                "sys": round(sum(sys_vals) / len(sys_vals), 0),
                "dia": round(sum(dia_vals) / len(dia_vals), 0),
                "pulse": round(sum(pulse_vals) / len(pulse_vals), 0) if pulse_vals else None,
            })
        else:
            data.append({
                "day": d.strftime("%d %b"),
                "sys": None,
                "dia": None,
                "pulse": None
            })

    return jsonify(data)


# ============================================================
# EXPORT BP HISTORY (CSV)
# ============================================================

@bp_bp.route("/export")
@login_required
def export_bp():
    """Export BP history as CSV."""
    readings = HealthMetric.query.filter_by(
        userid=current_user.id,
        metrictype="bp"
    ).order_by(HealthMetric.recordedat.desc()).all()

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["Date", "Time", "Systolic", "Diastolic", "Pulse", "Status", "Notes"])

    for r in readings:
        status, _ = get_bp_status(r.value1, r.value2)
        writer.writerow([
            r.recordedat.strftime("%d %b %Y") if r.recordedat else "",
            r.recordedat.strftime("%I:%M %p") if r.recordedat else "",
            int(r.value1) if r.value1 is not None else "",
            int(r.value2) if r.value2 is not None else "",
            int(r.value3) if r.value3 is not None else "",
            status,
            r.notes or ""
        ])

    response = make_response(output.getvalue())
    response.headers["Content-Disposition"] = "attachment; filename=bp_history.csv"
    response.headers["Content-type"] = "text/csv"
    return response