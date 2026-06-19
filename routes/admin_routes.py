# routes/admin_routes.py — Admin Panel
from flask import Blueprint, render_template, redirect, url_for, flash, request, jsonify
from flask_login import login_required, current_user
from functools import wraps
from datetime import datetime, timedelta, date
from extensions import db

admin_bp = Blueprint("admin", __name__)

def admin_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not current_user.is_authenticated or not current_user.is_admin:
            flash("Admin access required.", "danger")
            return redirect(url_for("main.dashboard"))
        return f(*args, **kwargs)
    return decorated

@admin_bp.route("/")
@login_required
@admin_required
def dashboard():
    from models import User, HealthMetric, EmailReportLog, AdminLog, Alert, Document
    from sqlalchemy import func

    total_users     = User.query.count()
    active_users    = User.query.filter_by(is_active=True).count()
    verified_users  = User.query.filter_by(is_verified=True).count()
    new_today       = User.query.filter(func.date(User.created_at) == date.today()).count()
    new_this_week   = User.query.filter(User.created_at >= datetime.utcnow() - timedelta(days=7)).count()

    total_bp        = HealthMetric.query.filter_by(metric_type="bp").count()
    total_weight    = HealthMetric.query.filter_by(metric_type="weight").count()
    total_water     = HealthMetric.query.filter_by(metric_type="water").count()
    total_docs      = Document.query.count()
    total_reports   = EmailReportLog.query.count()

    recent_users    = User.query.order_by(User.created_at.desc()).limit(10).all()
    recent_logs     = AdminLog.query.order_by(AdminLog.created_at.desc()).limit(20).all()
    recent_alerts   = Alert.query.filter_by(alert_type="emergency").order_by(Alert.created_at.desc()).limit(5).all()

    # Registrations by day (last 7 days)
    reg_chart = []
    for i in range(6, -1, -1):
        d = date.today() - timedelta(days=i)
        count = User.query.filter(func.date(User.created_at) == d).count()
        reg_chart.append({"day": d.strftime("%a"), "count": count})

    return render_template("admin/dashboard.html",
        total_users=total_users, active_users=active_users,
        verified_users=verified_users, new_today=new_today,
        new_this_week=new_this_week,
        total_bp=total_bp, total_weight=total_weight,
        total_water=total_water, total_docs=total_docs,
        total_reports=total_reports,
        recent_users=recent_users, recent_logs=recent_logs,
        recent_alerts=recent_alerts, reg_chart=reg_chart,
    )

@admin_bp.route("/users")
@login_required
@admin_required
def users():
    from models import User
    search = request.args.get("search","").strip()
    page   = int(request.args.get("page",1))
    q = User.query
    if search:
        q = q.filter(User.name.ilike(f"%{search}%") | User.email.ilike(f"%{search}%"))
    users_paged = q.order_by(User.created_at.desc()).paginate(page=page, per_page=20, error_out=False)
    return render_template("admin/users.html", users=users_paged, search=search)

@admin_bp.route("/users/<int:user_id>/toggle-active")
@login_required
@admin_required
def toggle_user_active(user_id):
    from models import User, AdminLog
    user = User.query.get_or_404(user_id)
    if user.id == current_user.id:
        flash("Cannot deactivate your own account.", "danger")
        return redirect(url_for("admin.users"))
    user.is_active = not user.is_active
    log = AdminLog(admin_id=current_user.id,
                   action=f"{'Activated' if user.is_active else 'Deactivated'} user {user.email}",
                   target_type="user", target_id=user.id,
                   ip_address=request.remote_addr)
    db.session.add(log)
    db.session.commit()
    flash(f"User {user.name} {'activated' if user.is_active else 'deactivated'}.", "success")
    return redirect(url_for("admin.users"))

@admin_bp.route("/users/<int:user_id>/make-admin")
@login_required
@admin_required
def make_admin(user_id):
    from models import User, AdminLog
    user = User.query.get_or_404(user_id)
    user.is_admin = not user.is_admin
    log = AdminLog(admin_id=current_user.id,
                   action=f"{'Granted' if user.is_admin else 'Revoked'} admin for {user.email}",
                   target_type="user", target_id=user.id,
                   ip_address=request.remote_addr)
    db.session.add(log)
    db.session.commit()
    flash(f"Admin {'granted to' if user.is_admin else 'revoked from'} {user.name}.", "success")
    return redirect(url_for("admin.users"))

@admin_bp.route("/stats")
@login_required
@admin_required
def stats():
    from models import User, HealthMetric, EmailReportLog, Document, Alert
    from sqlalchemy import func
    today = date.today()

    # Daily active users (logged in last 7 days)
    dau = User.query.filter(User.last_login >= datetime.utcnow() - timedelta(days=1)).count()
    wau = User.query.filter(User.last_login >= datetime.utcnow() - timedelta(days=7)).count()

    # Metric totals
    metrics_by_type = db.session.query(HealthMetric.metric_type, func.count(HealthMetric.id)).group_by(HealthMetric.metric_type).all()
    metrics_data    = {m: c for m, c in metrics_by_type}

    return render_template("admin/stats.html",
        dau=dau, wau=wau, metrics_data=metrics_data,
        total_alerts=Alert.query.count(),
        total_docs=Document.query.count(),
        total_reports=EmailReportLog.query.count(),
    )

@admin_bp.route("/logs")
@login_required
@admin_required
def logs():
    from models import AdminLog, EmailReportLog
    page = int(request.args.get("page",1))
    admin_logs = AdminLog.query.order_by(AdminLog.created_at.desc()).paginate(page=page, per_page=30, error_out=False)
    email_logs = EmailReportLog.query.order_by(EmailReportLog.sent_at.desc()).limit(20).all()
    return render_template("admin/logs.html", admin_logs=admin_logs, email_logs=email_logs)