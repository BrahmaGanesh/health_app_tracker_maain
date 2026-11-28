# routes/business_routes.py — Subscriber & Revenue Dashboard
from functools import wraps
from datetime import datetime, timedelta, date

from flask import Blueprint, render_template, redirect, url_for, make_response, jsonify
from flask_login import login_required, current_user

from models import User, now_ist, today_ist, UserSubscription

business_bp = Blueprint("business", __name__, url_prefix="/business")


# ── Admin-only guard ───────────────────────────────────────────────
def admin_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not current_user.is_authenticated or not getattr(current_user, "is_admin", False):
            return redirect(url_for("auth.login"))
        return f(*args, **kwargs)
    return decorated


def _plan(uid):
    from models import UserSubscription
    sub_list = UserSubscription.get_all(filters={"user_id": uid}, limit=1)
    sub = sub_list[0] if sub_list else None
    return sub.plan if sub and sub.is_active else "free"


def _limit(uid):
    plan = _plan(uid)
    lim  = UserSubscription.PLAN_LIMITS.get(plan, 2)
    return lim  # None = unlimited


def _can_add(uid):
    lim = _limit(uid)
    if lim is None: return True
    count = len(UserSubscription.get_all(filters={"user_id": uid, "status": "upcoming"}))
    return count < lim


def _is_family(uid):
    return _plan(uid) == "family"


# ═════════════════════════════════════════════════════════════════
# DASHBOARD
# ════════════════════════════════════════════════════════════════

business_bp = Blueprint("business", __name__, url_prefix="/business")


@business_bp.route("/")
@login_required
@admin_required
def dashboard():
    now = now_ist() if callable(now_ist) else datetime.now()
    today = today_ist()
    all_subs = UserSubscription.get_all()
    total_users = User.count()

    # Active plan counts
    premium_count = sum(1 for s in all_subs if s.plan == "premium" and s.is_active)
    family_count = sum(1 for s in all_subs if s.plan == "family" and s.is_active)
    paid_users = premium_count + family_count
    free_count = max(total_users - paid_users, 0)

    # Current MRR
    mrr = (premium_count * 199) + (family_count * 349)

    # Previous month MRR estimate
    last_month_cutoff = now - timedelta(days=30)
    last_premium = sum(
        1 for s in all_subs
        if s.plan == "premium" and s.created_at and s.created_at <= last_month_cutoff
    )
    last_family = sum(
        1 for s in all_subs
        if s.plan == "family" and s.created_at and s.created_at <= last_month_cutoff
    )
    prev_mrr = (last_premium * 199) + (last_family * 349)
    mrr_growth = round(((mrr - prev_mrr) / prev_mrr) * 100, 1) if prev_mrr > 0 else 0

    # New this month
    month_start = today.replace(day=1)
    new_this_month = sum(
        1 for s in all_subs
        if s.created_at and s.created_at.date() >= month_start
    )

    # Conversion rate
    conversion_rate = round((paid_users / total_users) * 100, 1) if total_users > 0 else 0

    # Expiring in 7 days
    in_7 = today + timedelta(days=7)
    expiring_subs = UserSubscription.get_all(
        filters={
            "plan": {"$in": ["premium", "family"]},
            "expires_at_lte": datetime.combine(today + timedelta(days=7), datetime.min.time()),
            "expires_at_gt": now,
        }
    )
    expiring_users = [s.user for s in expiring_subs if s.user]

    # Revenue trend — last 6 months
    revenue_trend = []
    current_month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

    for i in range(5, -1, -1):
        ref = current_month_start - timedelta(days=i * 30)
        month_dt = ref.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

        month_subs = [s for s in all_subs if s.created_at and s.created_at.replace(day=1, hour=0, minute=0, second=0, microsecond=0) == month_dt]
        month_mrr = sum(199 if s.plan == "premium" else 349 for s in month_subs if s.plan in ("premium", "family"))

        revenue_trend.append({
            "month": month_dt.strftime("%b %Y"),
            "mrr": month_mrr,
        })

    return render_template("business/dashboard.html",
        total_users=total_users,
        premium_count=premium_count,
        family_count=family_count,
        free_count=free_count,
        paid_users=paid_users,
        mrr=mrr,
        mrr_growth=mrr_growth,
        new_this_month=new_this_month,
        conversion_rate=conversion_rate,
        expiring_users=expiring_users,
        revenue_trend=revenue_trend,
    )


# ============================================================
# API ENDPOINTS
# ════════════════════════════════════════════════════════════════

@business_bp.route("/api/subscribers")
@login_required
@admin_required
def api_subscribers():
    """Return paginated subscriber list for admin table."""
    page = int(request.args.get("page", 1))
    per_page = 20
    all_subs = UserSubscription.get_all()

    # Build subscriber data with user info
    sub_data = []
    for s in all_subs:
        user = User.get_by_id(s.user_id) if s.user_id else None
        sub_data.append({
            "id": s.id,
            "user_id": s.user_id,
            "user_email": user.email if user else "Unknown",
            "user_name": user.name if user else "Unknown",
            "plan": s.plan,
            "status": s.status,
            "is_active": s.is_active,
            "created_at": s.created_at,
            "expires_at": s.expires_at,
            "amount": s.amount,
        })

    # Pagination
    per_page = 20
    start = (page - 1) * per_page
    end = start + per_page
    paginated = sub_data[start:end]

    return jsonify({
        "subscribers": paginated,
        "total": len(sub_data),
        "page": page,
        "per_page": per_page,
        "total_pages": (len(sub_data) + 19) // 20,
    })


@business_bp.route("/api/mrr-history")
@login_required
@admin_required
def api_mrr_history():
    """Return MRR history for charts."""
    all_subs = UserSubscription.get_all()

    # Build 12 months of history
    history = []
    now = datetime.utcnow()
    for i in range(11, -1, -1):
        ref = now - timedelta(days=30 * i)
        month_start = ref.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        month_end = (month_start + timedelta(days=32)).replace(day=1) - timedelta(seconds=1)

        month_subs = [s for s in all_subs if s.created_at and month_start <= s.created_at <= month_end]
        month_mrr = sum(199 if s.plan == "premium" else 349 for s in month_subs if s.plan in ("premium", "family"))

        history.append({
            "month": month_start.strftime("%b %Y"),
            "mrr": month_mrr,
            "subscribers": len([s for s in month_subs if s.plan in ("premium", "family")]),
        })

    return jsonify(history)


@business_bp.route("/export-subscribers")
@login_required
@admin_required
def export_subscribers():
    """Export all subscribers as CSV."""
    import csv
    import io

    all_subs = UserSubscription.get_all()
    output = io.StringIO()
    writer = csv.writer(output)

    writer.writerow(["User ID", "Email", "Name", "Plan", "Status", "Created At", "Expires At", "Amount", "Currency"])

    for s in all_subs:
        user = User.get_by_id(s.user_id) if s.user_id else None
        writer.writerow([
            s.user_id,
            user.email if user else "Unknown",
            user.name if user else "Unknown",
            s.plan,
            s.status,
            s.created_at.strftime("%Y-%m-%d") if s.created_at else "",
            s.expires_at.strftime("%Y-%m-%d") if s.expires_at else "",
            s.amount,
            s.currency,
        ])

    output.seek(0)
    response = make_response(output.getvalue())
    response.headers["Content-Disposition"] = "attachment; filename=subscribers.csv"
    response.headers["Content-type"] = "text/csv"
    return response