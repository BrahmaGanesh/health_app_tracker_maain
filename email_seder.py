# ============================================================
# utils/email_sender.py — Email Report Sender
# Sends HTML email reports in your exact format
# FIXED: automatic schedule now respects send_time properly
# ============================================================

import logging
from datetime import date, timedelta, datetime

logger = logging.getLogger(__name__)


def _now():
    return datetime.now()


def _parse_send_time(send_time_str):
    try:
        value = (send_time_str or "08:00").strip()
        hour, minute = map(int, value.split(":"))
        hour = max(0, min(hour, 23))
        minute = max(0, min(minute, 59))
        return hour, minute
    except Exception:
        return 8, 0


def _compute_next_send(config, from_dt=None):
    now = from_dt or _now()
    hour, minute = _parse_send_time(config.send_time)

    base = now.replace(hour=hour, minute=minute, second=0, microsecond=0)

    frequency = (config.frequency or "weekly").lower().strip()

    if frequency == "daily":
        if base <= now:
            base += timedelta(days=1)
        return base

    elif frequency == "weekly":
        if base <= now:
            base += timedelta(days=7)
        return base

    elif frequency == "monthly":
        if base <= now:
            base += timedelta(days=30)
        return base

    elif frequency == "custom":
        days = config.custom_days or 7
        if base <= now:
            base += timedelta(days=days)
        return base

    if base <= now:
        base += timedelta(days=7)
    return base


def run_scheduled_reports():
    """Scheduler job: send email reports to users who have them enabled."""
    from app import app
    with app.app_context():
        from models import EmailReportConfig

        now = _now()

        configs = EmailReportConfig.query.filter(
            EmailReportConfig.is_enabled == True,
            EmailReportConfig.next_send_at.isnot(None),
            EmailReportConfig.next_send_at <= now
        ).all()

        for config in configs:
            try:
                user = config.user
                if not user:
                    continue

                recipients = config.recipient_list if config.recipient_list else [user.email]

                success = send_report_for_user(
                    user=user,
                    period_days=config.report_period_days or 7,
                    recipients=recipients
                )

                if success:
                    logger.info(f"Automatic report sent for user {config.user_id}")
                else:
                    logger.warning(f"Automatic report failed for user {config.user_id}")

            except Exception as e:
                logger.exception(f"Email report error user {config.user_id}: {e}")


def send_report_for_user(user, period_days=None, recipients=None):
    """Generate and send the complete health report email."""
    from flask_mail import Message
    from app import mail, db
    from models import EmailReportConfig, EmailReportLog

    config = user.email_report_config
    period_days = period_days or (config.report_period_days if config else 7)
    recipients = recipients or (config.recipient_list if config else [user.email])

    if not recipients:
        recipients = [user.email]

    today = date.today()
    period_end = today
    period_start = today - timedelta(days=period_days - 1)

    report_data = _gather_report_data(user, period_start, period_end)
    html_body = _generate_html_report(user, report_data, period_start, period_end)

    score = report_data.get("health_score", 0)
    grade = report_data.get("grade", "Good")
    subject = f"🏥 Your HealthTrack Report — {period_start.strftime('%d %b')} to {period_end.strftime('%d %b %Y')} | Score: {score}/100 ({grade})"

    try:
        gmail_sent = False

        if user.auth_provider == "google" and user.google_access_token:
            try:
                from routes.google_auth import send_email_via_gmail
                gmail_sent = send_email_via_gmail(user, subject, html_body, recipients)
            except Exception as gmail_err:
                logger.warning(f"Gmail API failed, falling back to SMTP: {gmail_err}")

        if not gmail_sent:
            msg = Message(
                subject=subject,
                recipients=recipients,
                html=html_body
            )
            mail.send(msg)

        log = EmailReportLog(
            user_id=user.id,
            recipients=", ".join(recipients),
            period_start=period_start,
            period_end=period_end,
            status="sent",
            health_score=score,
            sent_at=_now()
        )
        db.session.add(log)

        if config:
            now = _now()
            config.last_sent_at = now
            config.total_sent = (config.total_sent or 0) + 1
            config.next_send_at = _compute_next_send(config, from_dt=now)

        db.session.commit()
        logger.info(f"Report sent to {recipients} for user {user.id}")
        return True

    except Exception as e:
        log = EmailReportLog(
            user_id=user.id,
            status="failed",
            error_message=str(e),
            sent_at=_now()
        )
        db.session.add(log)
        db.session.commit()
        logger.error(f"Email report failed: {e}")
        return False


def _gather_report_data(user, period_start, period_end):
    """Collect all health data for the report period."""
    from models import HealthMetric, SleepLog, StepLog, DailyHealthScore, ExerciseLog
    from sqlalchemy import func

    days_count = (period_end - period_start).days + 1
    all_days = [period_start + timedelta(days=i) for i in range(days_count)]
    day_data = []

    for d in all_days:
        bp = HealthMetric.query.filter(
            HealthMetric.user_id == user.id,
            HealthMetric.metric_type == "bp",
            func.date(HealthMetric.recorded_at) == d
        ).order_by(HealthMetric.recorded_at.desc()).first()

        wt = HealthMetric.query.filter(
            HealthMetric.user_id == user.id,
            HealthMetric.metric_type == "weight",
            func.date(HealthMetric.recorded_at) == d
        ).order_by(HealthMetric.recorded_at.desc()).first()

        water = HealthMetric.query.filter(
            HealthMetric.user_id == user.id,
            HealthMetric.metric_type == "water",
            func.date(HealthMetric.recorded_at) == d
        ).with_entities(func.sum(HealthMetric.value_1)).scalar() or 0

        sleep = SleepLog.query.filter_by(user_id=user.id, log_date=d).first()
        steps = StepLog.query.filter_by(user_id=user.id, log_date=d).first()

        sugar = HealthMetric.query.filter(
            HealthMetric.user_id == user.id,
            HealthMetric.metric_type == "sugar",
            func.date(HealthMetric.recorded_at) == d
        ).order_by(HealthMetric.recorded_at.desc()).first()

        score = DailyHealthScore.query.filter_by(user_id=user.id, score_date=d).first()

        day_data.append({
            "date": d,
            "day_str": d.strftime("%d %b"),
            "bp_sys": int(bp.value_1) if bp else None,
            "bp_dia": int(bp.value_2) if bp else None,
            "weight": round(wt.value_1, 1) if wt else None,
            "water": round(float(water), 1),
            "sleep": round(sleep.duration_hours, 1) if sleep and sleep.duration_hours else None,
            "steps": steps.steps if steps else None,
            "sugar_f": int(sugar.value_1) if sugar and sugar.value_1 else None,
            "score": int(score.total_score) if score else None,
        })

    def safe_avg(key):
        vals = [d[key] for d in day_data if d[key] is not None]
        return round(sum(vals) / len(vals), 1) if vals else None

    health_score = safe_avg("score") or 0
    grade = "Excellent" if health_score >= 90 else ("Good" if health_score >= 75 else ("Fair" if health_score >= 60 else "Needs Attention"))

    achievements = _compute_achievements(user, day_data, days_count)
    suggestions = _generate_suggestions(user, day_data)

    return {
        "day_data": day_data,
        "averages": {
            "bp_sys": safe_avg("bp_sys"),
            "bp_dia": safe_avg("bp_dia"),
            "weight": safe_avg("weight"),
            "water": safe_avg("water"),
            "sleep": safe_avg("sleep"),
            "steps": safe_avg("steps"),
            "score": health_score,
            "sugar_f": safe_avg("sugar_f"),
        },
        "health_score": int(health_score),
        "grade": grade,
        "achievements": achievements,
        "suggestions": suggestions,
        "days_count": days_count,
    }


def _compute_achievements(user, day_data, days_count):
    achievements = []
    target_water = user.goals.target_water_litres if user.goals else 2.5
    target_steps = user.goals.target_steps if user.goals else 8000

    water_days = sum(1 for d in day_data if d["water"] >= target_water)
    if water_days == days_count:
        achievements.append(f"🏅 {days_count}-Day Water Goal Achieved")
    elif water_days >= days_count // 2:
        achievements.append(f"💧 Water Goal Met {water_days}/{days_count} Days")

    step_days = sum(1 for d in day_data if d["steps"] and d["steps"] >= target_steps)
    if step_days == days_count:
        achievements.append(f"🏅 {days_count}-Day Step Goal Achieved")
    elif step_days > 0:
        achievements.append(f"👟 Hit Step Goal {step_days}/{days_count} Days")

    bp_days = [d for d in day_data if d["bp_sys"]]
    if len(bp_days) >= 2:
        first_bp = bp_days[0]["bp_sys"]
        last_bp = bp_days[-1]["bp_sys"]
        if last_bp < first_bp:
            achievements.append(f"📉 BP Improved by {first_bp - last_bp} mmHg")
        normal_days = sum(1 for d in bp_days if d["bp_sys"] < 130)
        if normal_days == len(bp_days):
            achievements.append("✅ BP in Healthy Range All Days")

    sleep_days = [d for d in day_data if d["sleep"]]
    if sleep_days:
        good_sleep = sum(1 for d in sleep_days if d["sleep"] >= 7)
        if good_sleep == days_count:
            achievements.append(f"🏅 Good Sleep Maintained All {days_count} Days")

    if not achievements:
        achievements.append("Keep tracking consistently to earn achievements!")

    return achievements


def _generate_suggestions(user, day_data):
    suggestions = []
    target_water = user.goals.target_water_litres if user.goals else 2.5
    target_steps = user.goals.target_steps if user.goals else 8000

    avg_water = sum(d["water"] for d in day_data) / len(day_data) if day_data else 0
    if avg_water < target_water * 0.8:
        suggestions.append(f"💧 Increase daily water intake to at least {target_water}L — it helps lower BP.")

    bp_days = [d for d in day_data if d["bp_sys"]]
    if bp_days:
        avg_sys = sum(d["bp_sys"] for d in bp_days) / len(bp_days)
        if avg_sys >= 140:
            suggestions.append("❤️ Average BP is elevated. Reduce salt intake, stress, and ensure medicine is taken daily.")
        elif avg_sys < 120:
            suggestions.append("✅ BP is in excellent range. Continue current diet and exercise routine.")
        else:
            suggestions.append("❤️ BP is improving. Continue monitoring twice daily and limit sodium to under 2g/day.")

    sleep_vals = [d["sleep"] for d in day_data if d["sleep"]]
    if sleep_vals:
        avg_sleep = sum(sleep_vals) / len(sleep_vals)
        if avg_sleep < 6:
            suggestions.append("😴 Average sleep below 6 hours. Poor sleep directly raises BP — aim for 7–8 hours.")
        elif avg_sleep >= 7.5:
            suggestions.append("✅ Excellent sleep quality. Consistent 7–8 hour sleep supports heart health.")

    step_avg = sum(d["steps"] for d in day_data if d["steps"]) / max(1, sum(1 for d in day_data if d["steps"]))
    if step_avg < target_steps * 0.5:
        suggestions.append(f"🚶 Average steps low ({int(step_avg)}/day). Add a 20-minute morning walk to significantly lower BP.")

    weights = [d["weight"] for d in day_data if d["weight"]]
    if len(weights) >= 2:
        change = weights[-1] - weights[0]
        if change < -0.5:
            suggestions.append(f"⚖️ Weight trend positive — lost {abs(change):.1f}kg this period. Maintain current routine.")
        elif change > 0.5:
            suggestions.append("⚖️ Weight slightly increased. Review calorie intake and ensure daily physical activity.")

    if not suggestions:
        suggestions.append("🌟 Great health week! Continue your current routine — consistency is the key to long-term recovery.")

    return suggestions[:5]


def _generate_html_report(user, data, period_start, period_end):
    """Generate the complete HTML email in your exact format."""
    day_data = data["day_data"]
    averages = data["averages"]
    achievements = data["achievements"]
    suggestions = data["suggestions"]
    score = data["health_score"]
    grade = data["grade"]

    score_color = "#22c55e" if score >= 75 else ("#f59e0b" if score >= 50 else "#ef4444")

    table_rows = ""
    metrics = [
        ("Weight (kg)", "weight"),
        ("BP (mmHg)", None),
        ("Water (L)", "water"),
        ("Sleep (hrs)", "sleep"),
        ("Steps", "steps"),
        ("Sugar (mg/dL)", "sugar_f"),
        ("Score", "score"),
    ]

    for label, key in metrics:
        row = f"<tr><td style='padding:8px 12px;font-weight:600;color:#142d4c;background:#f8fafc;border:1px solid #e2e8f0;'>{label}</td>"
        if key is None:
            for d in day_data:
                val = f"{d['bp_sys']}/{d['bp_dia']}" if d['bp_sys'] else '—'
                target_sys = user.goals.target_bp_systolic if user.goals else 130
                color = "#22c55e" if d["bp_sys"] and d["bp_sys"] < target_sys else ("#ef4444" if d["bp_sys"] and d["bp_sys"] >= 140 else "#1a202c")
                row += f"<td style='padding:8px 12px;text-align:center;border:1px solid #e2e8f0;color:{color};font-weight:600;'>{val}</td>"
            avg_val = f"{int(averages['bp_sys'] or 0)}/{int(averages['bp_dia'] or 0)}" if averages["bp_sys"] else "—"
            row += f"<td style='padding:8px 12px;text-align:center;border:1px solid #e2e8f0;font-weight:700;background:#eff6ff;'>{avg_val}</td>"
        else:
            for d in day_data:
                val = str(d.get(key, "—")) if d.get(key) is not None else "—"
                row += f"<td style='padding:8px 12px;text-align:center;border:1px solid #e2e8f0;'>{val}</td>"
            avg_val = str(averages.get(key, "—")) if averages.get(key) is not None else "—"
            row += f"<td style='padding:8px 12px;text-align:center;border:1px solid #e2e8f0;font-weight:700;background:#eff6ff;'>{avg_val}</td>"
        row += "</tr>"
        table_rows += row

    day_headers = "".join(
        f"<th style='padding:10px 12px;background:#142d4c;color:white;font-weight:600;border:1px solid #1e3a5f;text-align:center;'>{d['day_str']}</th>"
        for d in day_data
    )

    ach_html = "".join(
        f"<div style='padding:8px 0;font-size:14px;color:#142d4c;border-bottom:1px solid #f0f4f8;'>{a}</div>"
        for a in achievements
    )

    sug_html = "".join(
        f"<div style='padding:8px 12px;margin-bottom:8px;background:#f0fdf4;border-left:4px solid #22c55e;border-radius:6px;font-size:14px;color:#166534;'>{s}</div>"
        for s in suggestions
    )

    score_items = []
    if averages["water"] and averages["water"] >= (user.goals.target_water_litres if user.goals else 2.5):
        score_items.append("✅ Water Goal Achieved")
    if averages["bp_sys"] and averages["bp_sys"] < 130:
        score_items.append("✅ Healthy BP Range")
    if averages["sleep"] and averages["sleep"] >= 7:
        score_items.append("✅ Good Sleep Quality")
    if averages["steps"] and averages["steps"] >= (user.goals.target_steps if user.goals else 8000):
        score_items.append("✅ Step Goal Achieved")

    score_indicators_html = "".join(
        f"<div style='font-size:14px;color:#166534;padding:4px 0;'>{item}</div>"
        for item in score_items
    )

    photo_html = ""
    if user.profile_photo:
        photo_html = f"<img src='{user.profile_photo}' style='width:60px;height:60px;border-radius:50%;object-fit:cover;border:3px solid #9fd3c7;' alt='Profile'><br>"

    next_report_date = (period_end + timedelta(days=data['days_count'])).strftime("%d-%b-%Y")

    html = f"""
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>HealthTrack Report</title></head>
<body style="margin:0;padding:0;background:#f0f4f8;font-family:'Segoe UI',Arial,sans-serif;">
<div style="max-width:680px;margin:20px auto;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(20,45,76,0.12);">

  <div style="background:linear-gradient(135deg,#142d4c,#1e3f6e,#4f3b78);padding:32px;text-align:center;color:white;">
    <div style="font-size:32px;margin-bottom:8px;">🏥</div>
    <h1 style="margin:0;font-size:24px;font-weight:900;letter-spacing:1px;">HEALTH TRACKER REPORT</h1>
    <div style="margin-top:8px;opacity:0.8;font-size:14px;">Powered by HealthTrack</div>
  </div>

  <div style="height:4px;background:linear-gradient(90deg,#9fd3c7,#61b390);"></div>

  <div style="padding:24px 32px;background:#f8fafc;border-bottom:2px dashed #e2e8f0;">
    <div style="font-size:11px;font-weight:700;letter-spacing:2px;text-transform:uppercase;color:#6b839e;margin-bottom:12px;">👤 USER INFORMATION</div>
    <div style="display:flex;align-items:center;gap:16px;flex-wrap:wrap;">
      <div>{photo_html}</div>
      <div>
        <div style="font-size:20px;font-weight:700;color:#142d4c;">{user.name}</div>
        <div style="color:#6b839e;font-size:14px;">{user.email}</div>
        <div style="color:#6b839e;font-size:13px;margin-top:4px;">
          Report Period: <strong>{period_start.strftime('%d-%b-%Y')}</strong> to <strong>{period_end.strftime('%d-%b-%Y')}</strong>
          ({data['days_count']} days)
        </div>
        <div style="margin-top:6px;font-size:13px;color:#4f3b78;font-weight:600;">
          Conditions: {', '.join(user.condition_names) or 'Not specified'}
        </div>
      </div>
    </div>
  </div>

  <div style="padding:24px 32px;background:white;border-bottom:2px dashed #e2e8f0;">
    <div style="font-size:11px;font-weight:700;letter-spacing:2px;text-transform:uppercase;color:#6b839e;margin-bottom:16px;">⭐ HEALTH SCORE</div>
    <div style="display:flex;align-items:center;gap:24px;flex-wrap:wrap;">
      <div style="background:linear-gradient(135deg,#142d4c,#1e3f6e);border-radius:16px;padding:20px 28px;text-align:center;color:white;min-width:140px;">
        <div style="font-size:48px;font-weight:700;color:{score_color};font-family:monospace;">{score}</div>
        <div style="font-size:13px;opacity:0.7;">/ 100</div>
        <div style="font-size:16px;font-weight:700;color:{score_color};margin-top:4px;">{grade}</div>
      </div>
      <div style="flex:1;">{score_indicators_html}</div>
    </div>
  </div>

  <div style="padding:24px 32px;border-bottom:2px dashed #e2e8f0;overflow-x:auto;">
    <div style="font-size:11px;font-weight:700;letter-spacing:2px;text-transform:uppercase;color:#6b839e;margin-bottom:16px;">📊 HEALTH DATA TABLE</div>
    <table style="width:100%;border-collapse:collapse;font-size:13px;">
      <thead>
        <tr>
          <th style="padding:10px 12px;background:#142d4c;color:white;font-weight:600;border:1px solid #1e3a5f;text-align:left;">Metric</th>
          {day_headers}
          <th style="padding:10px 12px;background:#4f3b78;color:white;font-weight:600;border:1px solid #3d2d5f;text-align:center;">Average</th>
        </tr>
      </thead>
      <tbody>{table_rows}</tbody>
    </table>
    <div style="margin-top:8px;font-size:12px;color:#6b839e;">
      <span style="color:#22c55e;font-weight:600;">🟢 Green = Healthy/Improved</span> &nbsp;
      <span style="color:#ef4444;font-weight:600;">🔴 Red = Needs Attention</span>
    </div>
  </div>

  <div style="padding:24px 32px;background:#f0fdf4;border-bottom:2px dashed #e2e8f0;">
    <div style="font-size:11px;font-weight:700;letter-spacing:2px;text-transform:uppercase;color:#6b839e;margin-bottom:12px;">🏆 ACHIEVEMENTS</div>
    {ach_html}
  </div>

  <div style="padding:24px 32px;border-bottom:2px dashed #e2e8f0;">
    <div style="font-size:11px;font-weight:700;letter-spacing:2px;text-transform:uppercase;color:#6b839e;margin-bottom:12px;">💡 PERSONALISED SUGGESTIONS</div>
    {sug_html}
  </div>

  <div style="padding:20px 32px;background:#f8fafc;text-align:center;">
    <div style="font-size:11px;font-weight:700;letter-spacing:2px;text-transform:uppercase;color:#6b839e;margin-bottom:8px;">📅 NEXT REPORT</div>
    <div style="font-size:14px;color:#142d4c;">Next scheduled report: <strong>{next_report_date}</strong></div>
  </div>

  <div style="background:linear-gradient(135deg,#142d4c,#4f3b78);padding:20px 32px;text-align:center;color:white;">
    <div style="font-size:13px;opacity:0.8;">Generated automatically by <strong>HealthTrack</strong></div>
    <div style="font-size:11px;opacity:0.6;margin-top:4px;">Your adaptive health recovery platform</div>
  </div>

</div>
</body>
</html>
"""
    return html