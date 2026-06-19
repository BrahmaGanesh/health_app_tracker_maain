# routes/email_report_routes.py — Email Report Scheduling Website
from flask import Blueprint, render_template, redirect, url_for, flash, request
from flask_login import login_required, current_user
from extensions import db
from models import EmailReportConfig, EmailReportLog
from datetime import datetime

email_report_bp = Blueprint("email_reports", __name__)

@email_report_bp.route("/settings", methods=["GET","POST"])
@login_required
def settings():
    config = current_user.email_report_config
    if not config:
        config = EmailReportConfig(user_id=current_user.id)
        db.session.add(config)
        db.session.commit()

    if request.method == "POST":
        config.is_enabled         = bool(request.form.get("is_enabled"))
        config.frequency          = request.form.get("frequency","weekly")
        config.custom_days        = int(request.form.get("custom_days",7))
        config.send_time          = request.form.get("send_time","08:00")
        config.report_period_days = int(request.form.get("report_period_days",7))
        config.email_recipients   = request.form.get("email_recipients","")
        config.include_weight     = bool(request.form.get("include_weight"))
        config.include_bp         = bool(request.form.get("include_bp"))
        config.include_water      = bool(request.form.get("include_water"))
        config.include_sleep      = bool(request.form.get("include_sleep"))
        config.include_steps      = bool(request.form.get("include_steps"))
        config.include_exercise   = bool(request.form.get("include_exercise"))
        config.include_sugar      = bool(request.form.get("include_sugar"))
        config.include_suggestions= bool(request.form.get("include_suggestions"))
        config.include_achievements=bool(request.form.get("include_achievements"))
        if config.is_enabled:
            from utils.email_sender import _compute_next_send
            config.next_send_at = _compute_next_send(config)
        else:
            config.next_send_at = None
        db.session.commit()
        flash("✅ Email report settings saved!", "success")
        return redirect(url_for("email_reports.settings"))

    logs = EmailReportLog.query.filter_by(user_id=current_user.id).order_by(EmailReportLog.sent_at.desc()).limit(10).all()
    return render_template("reports/email_settings.html", config=config, logs=logs)

@email_report_bp.route("/send-now", methods=["POST"])
@login_required
def send_now():
    days       = int(request.form.get("days",7))
    recipients = request.form.get("recipients","").strip()
    recipient_list = [e.strip() for e in recipients.split(",") if e.strip()] if recipients else [current_user.email]
    try:
        from utils.email_sender import send_report_for_user
        success = send_report_for_user(current_user, days, recipient_list)
        if success:
            flash(f"✅ Report sent to {', '.join(recipient_list)}!", "success")
        else:
            flash("❌ Failed to send. Check your email settings.", "danger")
    except Exception as e:
        import traceback
        traceback.print_exc()
        flash(f"Error: {str(e)}", "danger")
    return redirect(url_for("email_reports.settings"))