# routes/admin_routes.py — Admin Panel
from flask import Blueprint, render_template, redirect, url_for, flash, request, jsonify
from flask_login import login_required, current_user
from functools import wraps
from datetime import datetime, timedelta, date

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

    total_users     = User.count()
    active_users    = User.count(filters={"is_active": True})
    verified_users  = User.count(filters={"is_verified": True})

    today = date.today()
    new_today_list = User.get_all(filters={"created_at_date": today})
    new_today = len(new_today_list)

    new_this_week = len(User.get_all(filters={"created_at_gte": datetime.utcnow() - timedelta(days=7)}))

    total_bp        = HealthMetric.count(filters={"metric_type": "bp"})
    total_weight    = HealthMetric.count(filters={"metric_type": "weight"})
    total_water     = HealthMetric.count(filters={"metric_type": "water"})
    total_docs      = Document.count()
    total_reports   = EmailReportLog.count()

    recent_users    = User.get_all(order_by="-created_at", limit=10)
    recent_logs     = AdminLog.get_all(order_by="-created_at", limit=20)
    recent_alerts   = Alert.get_all(limit=10)

    # Registrations by day (last 7 days)
    reg_chart = []
    for i in range(6, -1, -1):
        d = date.today() - timedelta(days=i)
        count_list = User.get_all(filters={"created_at_date": d})
        count = len(count_list)
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

    if search:
        # Simple search - get all and filter in Python
        all_users = User.get_all()
        filtered = [u for u in all_users if search.lower() in u.name.lower() or search.lower() in u.email.lower()]
    else:
        filtered = User.get_all()

    # Simple pagination
    per_page = 20
    start = (page - 1) * per_page
    end = start + per_page
    users_page = filtered[start:end]

    # Create a simple pagination object
    class SimplePagination:
        def __init__(self, items, page, per_page, total):
            self.items = items
            self.page = page
            self.per_page = per_page
            self.total = total
            self.pages = (total + per_page - 1) // per_page

    pagination = SimplePagination(filtered[start:end], page, 20, len(filtered))

    return render_template("admin/users.html", users=pagination, search=search)

@admin_bp.route("/users/<int:user_id>/toggle-active")
@login_required
@admin_required
def toggle_user_active(user_id):
    from models import User, AdminLog
    user = User.get_by_id_or_404(user_id)
    if user.id == current_user.id:
        flash("Cannot deactivate your own account.", "danger")
        return redirect(url_for("admin.users"))
    user.is_active = not user.is_active
    user.save()
    # Log the action
    log = AdminLog(
        admin_id=current_user.id,
        action="toggle_user_active",
        target_type="user",
        target_id=user.id,
        details={"new_status": user.is_active}
    )
    log.save()
    flash(f"User {user.name} {'activated' if user.is_active else 'deactivated'}.", "success")
    return redirect(url_for("admin.users"))

@admin_bp.route("/users/<int:user_id>/toggle-verified")
@login_required
@admin_required
def toggle_user_verified(user_id):
    from models import User, AdminLog
    user = User.get_by_id_or_404(user_id)
    user.is_verified = not user.is_verified
    user.save()
    log = AdminLog(
        admin_id=current_user.id,
        action="toggle_user_verified",
        target_type="user",
        target_id=user.id,
        details={"new_status": user.is_verified}
    )
    log.save()
    flash(f"User {user.name} {'verified' if user.is_verified else 'unverified'}.", "success")
    return redirect(url_for("admin.users"))

@admin_bp.route("/users/<int:user_id>/toggle-admin")
@login_required
@admin_required
def toggle_user_admin(user_id):
    from models import User, AdminLog
    user = User.get_by_id_or_404(user_id)
    if user.id == current_user.id:
        flash("Cannot change your own admin status.", "danger")
        return redirect(url_for("admin.users"))
    user.plan = "admin" if user.plan != "admin" else "free"
    user.save()
    log = AdminLog(
        admin_id=current_user.id,
        action="toggle_user_admin",
        target_type="user",
        target_id=user.id,
        details={"new_plan": user.plan}
    )
    log.save()
    flash(f"User {user.name} admin status changed.", "success")
    return redirect(url_for("admin.users"))

@admin_bp.route("/logs")
@login_required
@admin_required
def logs():
    from models import AdminLog
    page = int(request.args.get("page", 1))
    per_page = 30
    logs = AdminLog.get_all(order_by="-created_at", limit=per_page)
    return render_template("admin/logs.html", logs=logs)

@admin_bp.route("/alerts")
@login_required
@admin_required
def alerts():
    from models import Alert
    unread = Alert.get_all(filters={"is_read": False, "is_dismissed": False}, order_by="-created_at", limit=50)
    return render_template("admin/alerts.html", unread=unread)

@admin_bp.route("/reports")
@login_required
@admin_required
def reports():
    from models import EmailReportLog
    reports = EmailReportLog.get_all(order_by="-sent_at", limit=50)
    return render_template("admin/reports.html", reports=reports)

@admin_bp.route("/stats")
@login_required
@admin_required
def stats():
    from models import User, HealthMetric, Document, EmailReportLog
    dau = len(User.get_all(filters={"last_login_gte": datetime.utcnow() - timedelta(days=1)}))
    wau = len(User.get_all(filters={"last_login_gte": datetime.utcnow() - timedelta(days=7)}))
    total_alerts = Alert.count()
    total_docs = Document.count()
    total_reports = EmailReportLog.count()

    # Registrations per day
    reg_chart = []
    for i in range(6, -1, -1):
        d = date.today() - timedelta(days=i)
        count_list = User.get_all(filters={"created_at_date": d})
        count = len(count_list)
        reg_chart.append({"day": d.strftime("%a"), "count": count})

    return jsonify({
        "dau": dau,
        "wau": wau,
        "total_alerts": total_alerts,
        "total_docs": total_docs,
        "total_reports": total_reports,
        "reg_chart": reg_chart,
    })

@admin_bp.route("/logs/page/<int:page>")
@login_required
@admin_required
def logs_paged(page):
    from models import AdminLog
    per_page = 30
    logs = AdminLog.get_all(order_by="-created_at", limit=30)
    return render_template("admin/logs.html", logs=logs)